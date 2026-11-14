"""Model-free safety checks; all remotes, worktrees and workers are disposable."""
import copy
import concurrent.futures
import ctypes
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import shutil
import signal
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

MODULE = Path(__file__).with_name("cloud_handoff.py")
if MODULE.exists():
    spec = importlib.util.spec_from_file_location("cloud_handoff", MODULE)
    handoff = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(handoff)
else:
    handoff = None


def evidence(now=1000):
    return {"source": "simulation", "observed_at": now, "warning": False,
            "rejected": False, "windows": {
                "primary": {"remaining": 80, "reset_at": now + 3600},
                "secondary": {"remaining": 50, "reset_at": now + 7200}}}


class QuotaTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(handoff, "quota gate implementation is missing")

    def test_all_windows_must_be_fresh_finite_and_above_ten(self):
        # Catches a permissive boundary, NaN comparison, or stale/reset evidence.
        handoff.quota_gate(evidence(), now=1000, probe=True)
        for value in (10, 0, -1, 101, math.nan, math.inf, None, True, "80"):
            with self.subTest(remaining=value):
                item = evidence()
                item["windows"]["secondary"]["remaining"] = value
                with self.assertRaises(handoff.Blocked):
                    handoff.quota_gate(item, now=1000, probe=True)
        for stamp in (879, 1001, math.nan, None):
            item = evidence()
            item["observed_at"] = stamp
            with self.subTest(observed_at=stamp), self.assertRaises(handoff.Blocked):
                handoff.quota_gate(item, now=1000, probe=True)
        item = evidence(880)
        handoff.quota_gate(item, now=1000, probe=True)
        item["windows"]["secondary"]["reset_at"] = 1000
        with self.assertRaises(handoff.Blocked):
            handoff.quota_gate(item, now=1000, probe=True)

    def test_unknown_missing_warning_and_simulation_for_real_are_blocked(self):
        for field, value in (("warning", True), ("rejected", True),
                             ("source", "unknown"), ("warning", None)):
            item = evidence()
            item[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(handoff.Blocked):
                handoff.quota_gate(item, now=1000, probe=True)
        for item in ({}, {**evidence(), "windows": {"primary": evidence()["windows"]["primary"]}}):
            with self.assertRaises(handoff.Blocked):
                handoff.quota_gate(item, now=1000, probe=True)
        with self.assertRaises(handoff.Blocked):
            handoff.quota_gate(evidence(), now=1000)

    def test_official_payload_normalizers_keep_missing_windows_blocked(self):
        codex = handoff.normalize_codex({"ordinaryUsageAllowed": True, "rateLimits": {
            "primary": {"usedPercent": 20, "resetsAt": 2000},
            "secondary": {"usedPercent": 30, "resetsAt": 3000}}}, observed_at=1000)
        self.assertEqual(codex.get("ordinary_usage_allowed"), True,
                         "normalizer must read the official TOP LEVEL field")
        handoff.quota_gate(codex, now=1000)
        self.assertEqual(codex["windows"]["primary"]["remaining"], 80)
        claude = handoff.normalize_claude({"rate_limits": {
            "five_hour": {"used_percentage": 15, "resets_at": 2000},
            "seven_day": {"used_percentage": 25, "resets_at": 3000}}}, observed_at=1000)
        handoff.quota_gate(claude, now=1000, required=("five_hour", "seven_day"))
        handoff.quota_gate(claude, now=1000)
        missing = handoff.normalize_codex({"rateLimits": {"primary": {
            "usedPercent": 20, "resetsAt": 2000}}}, observed_at=1000)
        with self.assertRaises(handoff.Blocked):
            handoff.quota_gate(missing, now=1000)
        for allowed in (False, None):
            denied = copy.deepcopy(codex)
            denied["ordinary_usage_allowed"] = allowed
            with self.assertRaises(handoff.Blocked):
                handoff.quota_gate(denied, now=1000)

    def test_codex_top_level_denials_and_incomplete_extra_buckets_block(self):
        raw = {"ordinaryUsageAllowed": True, "rateLimits": {
            "primary": {"usedPercent": 5, "resetsAt": 2000},
            "secondary": {"usedPercent": 10, "resetsAt": 3000}}}
        normalized = handoff.normalize_codex(raw, observed_at=1000)
        self.assertEqual(normalized.get("ordinary_usage_allowed"), True,
                         "normalizer must read the official TOP LEVEL field")
        handoff.quota_gate(normalized, now=1000)
        for extra in ({"ordinaryUsageAllowed": False}, {"ordinaryUsageAllowed": None},
                      {"rateLimitReachedType": "primary"}, {"spendControlReached": True},
                      {"rateLimitsByLimitId": {"other": {"primary": raw["rateLimits"]["primary"]}}}):
            with self.subTest(extra=extra), self.assertRaises(handoff.Blocked):
                handoff.quota_gate(handoff.normalize_codex({**raw, **extra}, observed_at=1000), now=1000)

    def test_arbitrary_private_fields_cannot_enter_normalized_public_quota(self):
        for location in ("root", "window"):
            item = evidence()
            target = item if location == "root" else item["windows"]["primary"]
            target["auth_token"] = "FAKE-test-marker-not-a-secret"
            with self.subTest(location=location), self.assertRaises(handoff.Blocked):
                handoff.quota_gate(item, now=1000, probe=True)


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          text=True, capture_output=True).stdout.strip()


class GitTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(handoff is not None and hasattr(handoff, "Coordinator"),
                        "durable Git coordinator implementation is missing")
        self.tmp = tempfile.TemporaryDirectory(prefix="handoff-test-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.remote, self.a, self.b = root / "remote.git", root / "a", root / "b"
        subprocess.run(["git", "init", "--bare", str(self.remote)], check=True, capture_output=True)
        subprocess.run(["git", "clone", str(self.remote), str(self.a)], check=True, capture_output=True)
        git(self.a, "config", "user.name", "Test")
        git(self.a, "config", "user.email", "test@example.invalid")
        git(self.a, "checkout", "-b", "source")
        (self.a / "game").mkdir()
        (self.a / "game/project.godot").write_text("config_version=5\n")
        (self.a / "tools").mkdir()
        shutil.copyfile(MODULE, self.a / "tools/cloud_handoff.py")
        git(self.a, "add", "game/project.godot", "tools/cloud_handoff.py")
        git(self.a, "commit", "-m", "fixture source")
        self.source = git(self.a, "rev-parse", "HEAD")
        git(self.a, "push", "origin", "source")
        subprocess.run(["git", "clone", "--branch", "source", str(self.remote), str(self.b)],
                       check=True, capture_output=True)
        self.ca, self.cb = handoff.Coordinator(self.a), handoff.Coordinator(self.b)

    def initialize(self):
        return self.ca.initialize(task_id="fixture", source_branch="source",
                                  source_sha=self.source, project_path="game/project.godot")

    def claim(self, coordinator, commit, owner="gpt-mock", source=None):
        return coordinator.claim(expected=commit, source_sha=source or self.source,
                                 owner=owner, quota=evidence(time.time()), probe=True)

    def test_two_real_remote_competitors_only_one_can_claim(self):
        initial = self.initialize()
        barrier = threading.Barrier(2)
        class Rival(handoff.Coordinator):
            def publish(self, state, parent=None):
                barrier.wait(timeout=10)  # Both finish validation before EITHER pushes.
                return super().publish(state, parent)
        # Both commits descend from the SAME expected SHA; a FF push chooses one.
        def attempt(coordinator):
            try:
                return self.claim(coordinator, initial["commit"])
            except handoff.Blocked:
                return None
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, (Rival(self.a), Rival(self.b))))
        self.assertEqual(sum(result is not None for result in results), 1)
        final = self.cb.inspect()
        self.assertEqual(final["state"]["phase"], "claimed")
        self.assertEqual(final["state"]["owner"], "gpt-mock")
        self.assertEqual(git(self.remote, "rev-parse", "source"), self.source)
        self.assertEqual(git(self.remote, "ls-tree", "--name-only", final["commit"]), "state.json")
        self.assertEqual(git(self.remote, "rev-parse", final["commit"] + "^"), initial["commit"])
        self.assertEqual(git(self.remote, "show", "-s", "--format=%an|%ae|%cn|%ce", final["commit"]),
                         "Cloud Handoff|cloud-handoff@users.noreply.github.com|Cloud Handoff|cloud-handoff@users.noreply.github.com")

    def test_wrong_owner_source_stale_state_and_missing_stop_receipt_block(self):
        initial = self.initialize()
        for owner, source in (("claude-mock", self.source), ("gpt-mock", "a" * 40)):
            with self.assertRaises(handoff.Blocked):
                self.claim(self.cb, initial["commit"], owner, source)
        held = self.claim(self.ca, initial["commit"])
        with self.assertRaises(handoff.Blocked):
            self.claim(self.cb, initial["commit"])
        # A dead/old claimant is never recovered merely because time passed.
        for owner in ("gpt-mock", "claude-mock"):
            with self.assertRaises(handoff.Blocked):
                self.claim(self.cb, held["commit"], owner)
        self.assertEqual(self.ca.inspect()["commit"], held["commit"])

    def test_dirty_untracked_or_unpushed_game_source_is_refused(self):
        initial = self.initialize()
        project = self.a / "game/project.godot"
        project.write_text("changed\n")
        with self.assertRaises(handoff.Blocked):
            self.claim(self.ca, initial["commit"])
        git(self.a, "add", "game/project.godot")
        git(self.a, "commit", "-m", "unshared game change")
        with self.assertRaises(handoff.Blocked):
            self.claim(self.ca, initial["commit"])
        (self.b / "game/new-save.dat").write_text("untracked\n")
        with self.assertRaises(handoff.Blocked):
            self.claim(self.cb, initial["commit"])
        self.assertEqual(self.ca.inspect()["commit"], initial["commit"])

    def test_coordination_never_stages_unrelated_work_or_reinitializes(self):
        initial = self.initialize()
        (self.a / "private-local.txt").write_text("fixture only\n")
        git(self.a, "add", "private-local.txt")
        held = self.claim(self.ca, initial["commit"])
        self.assertEqual(git(self.a, "diff", "--cached", "--name-only"), "private-local.txt")
        self.assertEqual(git(self.remote, "ls-tree", "--name-only", held["commit"]), "state.json")
        with self.assertRaises(handoff.Blocked):
            self.initialize()

    def test_wrong_head_and_modified_saved_controller_block_even_with_unchanged_game(self):
        runner = self.a / "tools/cloud_handoff.py"
        initial = self.initialize()
        runner.write_text("# unsafe modified controller fixture\n")
        with self.assertRaises(handoff.Blocked):
            self.claim(self.ca, initial["commit"])
        git(self.a, "add", "tools/cloud_handoff.py")
        git(self.a, "commit", "-m", "unshared controller fixture")
        with self.assertRaises(handoff.Blocked):
            self.claim(self.ca, initial["commit"])

    def test_source_without_saved_controller_cannot_initialize(self):
        git(self.a, "rm", "tools/cloud_handoff.py")
        git(self.a, "commit", "-m", "fixture omits controller")
        git(self.a, "push", "origin", "source")
        self.source = git(self.a, "rev-parse", "HEAD")
        with self.assertRaises(handoff.Blocked):
            self.initialize()

    def test_executing_controller_must_match_saved_blob(self):
        (self.a / "tools/cloud_handoff.py").write_text("# different saved controller fixture\n")
        git(self.a, "add", "tools/cloud_handoff.py")
        git(self.a, "commit", "-m", "fixture has other controller bytes")
        git(self.a, "push", "origin", "source")
        self.source = git(self.a, "rev-parse", "HEAD")
        with self.assertRaises(handoff.Blocked):
            self.initialize()

    def test_push_accepted_but_ack_lost_retains_claim_and_blocks_successor(self):
        initial = self.initialize()
        wrappers = Path(self.tmp.name) / "bin"
        wrappers.mkdir()
        wrapper = wrappers / "git"
        wrapper.write_text("#!" + sys.executable + "\nimport subprocess,sys\n"
                           "result=subprocess.run([" + repr(shutil.which("git")) + ",*sys.argv[1:]])\n"
                           "sys.exit(72 if 'push' in sys.argv and result.returncode == 0 else result.returncode)\n")
        wrapper.chmod(0o755)
        with patch.dict(os.environ, {"PATH": str(wrappers) + os.pathsep + os.environ["PATH"]}):
            with self.assertRaises(handoff.Blocked):
                self.ca.probe(expected=initial["commit"], source_sha=self.source,
                              owner="gpt-mock", next_owner="claude-mock")
        held = self.cb.inspect()
        self.assertNotEqual(held["commit"], initial["commit"])
        self.assertEqual(held["state"]["phase"], "claimed")
        self.assertIsNone(held["state"]["previous_stopped"])
        for owner in ("gpt-mock", "claude-mock"):
            with self.assertRaises(handoff.Blocked):
                self.claim(self.cb, held["commit"], owner)

    def test_private_or_oversized_state_is_rejected_before_publication(self):
        initial = self.initialize()
        quota = evidence(time.time())
        quota["auth_token"] = "FAKE-test-marker-not-a-secret"
        with self.assertRaises(handoff.Blocked):
            self.ca.claim(expected=initial["commit"], source_sha=self.source,
                          owner="gpt-mock", quota=quota, probe=True)
        oversized = copy.deepcopy(initial["state"])
        oversized["summary"] = "x" * 17000
        with self.assertRaises(handoff.Blocked):
            self.ca.publish(oversized, initial["commit"])
        self.assertEqual(self.cb.inspect()["commit"], initial["commit"])
        self.assertNotIn("FAKE-test-marker", git(self.remote, "log", "-p", "--all"))

    def test_unknown_state_fields_or_forged_stopped_phase_cannot_be_published(self):
        initial = self.initialize()
        for location in ("root", "checkpoint", "stopped-without-receipt"):
            item = copy.deepcopy(initial["state"])
            if location == "stopped-without-receipt":
                item.update(phase="stopped", owner="gpt-mock", run_id="f" * 32)
            else:
                target = item if location == "root" else item["checkpoint"]
                target["auth_output"] = "FAKE-test-marker-not-a-secret"
            with self.subTest(location=location), self.assertRaises(handoff.Blocked):
                self.ca.publish(item, initial["commit"])
        self.assertEqual(self.cb.inspect()["commit"], initial["commit"])

    def test_external_malformed_stopped_state_blocks_inspection_and_claim(self):
        initial = self.initialize()
        invalid = copy.deepcopy(initial["state"])
        invalid.update(phase="stopped", owner="gpt-mock", run_id="f" * 32)
        blob = self.ca.git("hash-object", "-w", "--stdin", data=json.dumps(invalid))
        tree = self.ca.git("mktree", data="100644 blob " + blob + "\tstate.json\n")
        corrupt = self.ca.git("commit-tree", tree, "-p", initial["commit"], "-m", "malformed fixture", identity=True)
        self.ca.git("push", "origin", corrupt + ":" + self.ca.ref)
        with self.assertRaises(handoff.Blocked):
            self.cb.inspect()
        with self.assertRaises(handoff.Blocked):
            self.claim(self.cb, corrupt)
        self.assertEqual(self.cb.remote_sha(self.cb.ref), corrupt)

    def test_model_free_worker_reaped_before_successor_starts(self):
        initial = self.initialize()
        self.assertTrue(hasattr(self.ca, "probe"), "supervised probe is missing")
        first = self.ca.probe(expected=initial["commit"], source_sha=self.source,
                              owner="gpt-mock", next_owner="claude-mock", stop="interruption")
        stopped = first["state"]["previous_stopped"]
        self.assertTrue(stopped["reaped"])
        self.assertEqual(stopped["returncode"], 0)
        with self.assertRaises(ChildProcessError):
            os.waitpid(stopped["pid"], os.WNOHANG)
        self.assertGreater(first["state"]["checkpoint"]["completed_units"], 0)
        second = self.cb.probe(expected=first["commit"], source_sha=self.source,
                               owner="claude-mock", complete=True)
        self.assertEqual(second["state"]["phase"], "completed")
        self.assertGreater(second["state"]["previous_stopped"]["started_at"], stopped["stopped_at"])
        self.assertEqual(second["state"]["source_sha"], self.source)
        self.assertEqual(second["state"]["mode"], "mock")

    def test_second_cli_cannot_start_while_first_real_process_is_running(self):
        initial = self.initialize()
        self.assertTrue(hasattr(self.ca, "probe"), "supervised CLI is missing")
        command = [sys.executable, str(MODULE), "--repo", str(self.a), "probe", "--expected",
                   initial["commit"], "--source-sha", self.source, "--owner", "gpt-mock",
                   "--next-owner", "claude-mock", "--units", "20", "--delay", "0.05"]
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        deadline = time.monotonic() + 10
        running = None
        while time.monotonic() < deadline and proc.poll() is None:
            snapshot = self.cb.inspect()
            if snapshot["state"]["phase"] == "running":
                running = snapshot
                break
            time.sleep(0.02)
        self.assertIsNotNone(running, "first process never entered its durable running state")
        self.assertIsNone(proc.poll(), "first supervisor must still be alive during the attempted claim")
        with self.assertRaises(handoff.Blocked):
            self.cb.probe(expected=running["commit"], source_sha=self.source,
                          owner="claude-mock", complete=True)
        stdout, stderr = proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 0, stderr)
        self.assertEqual(json.loads(stdout)["state"]["phase"], "stopped")

    @unittest.skipUnless(sys.platform.startswith("linux"), "real orphan adoption uses Linux prctl")
    def test_supervisor_death_with_live_child_never_unlocks_ownership(self):
        initial = self.initialize()
        libc = ctypes.CDLL(None)
        self.assertEqual(libc.prctl(36, 1, 0, 0, 0), 0)  # Adopt and reap our orphan only.
        supervisor = subprocess.Popen([sys.executable, str(MODULE), "--repo", str(self.a), "probe",
            "--expected", initial["commit"], "--source-sha", self.source, "--owner", "gpt-mock",
            "--next-owner", "claude-mock", "--units", "100", "--delay", "0.1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        child, folder = None, None
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                current = self.cb.inspect()
                if current["state"]["phase"] == "running":
                    self.assertIsNone(supervisor.poll(), "supervisor unexpectedly exited")
                    children = []
                    for candidate in Path("/proc").iterdir():
                        if not candidate.name.isdigit():
                            continue
                        try:
                            status = (candidate / "status").read_text().splitlines()
                        except (FileNotFoundError, ProcessLookupError):
                            continue
                        if f"PPid:\t{supervisor.pid}" in status:
                            children.append(candidate.name)
                    for candidate in children:
                        try:
                            argv = Path(f"/proc/{candidate}/cmdline").read_bytes().split(b"\0")
                        except FileNotFoundError:
                            continue  # A Git subprocess can finish during inspection.
                        if len(argv) > 3 and argv[1] == b"-c":
                            child = int(candidate)
                            folder = Path(os.fsdecode(argv[3]))
                            break
                    if child is not None:
                        break
                time.sleep(0.02)
            self.assertIsNotNone(child, "supervised child was never running")
            supervisor.kill()
            supervisor.wait(timeout=5)
            os.kill(child, 0)  # The old worker is genuinely still alive.
            held = self.cb.inspect()
            self.assertEqual(held["state"]["phase"], "running")
            self.assertIsNone(held["state"]["previous_stopped"])
            with self.assertRaises(handoff.Blocked):
                self.claim(self.cb, held["commit"], "claude-mock")
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
                supervisor.wait(timeout=5)
            if child is not None:
                os.kill(child, signal.SIGTERM)
                os.waitpid(child, 0)
            libc.prctl(36, 0, 0, 0, 0)
            if folder is not None:
                shutil.rmtree(folder)


if __name__ == "__main__":
    unittest.main()
