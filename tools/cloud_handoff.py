#!/usr/bin/env python3
"""Cooperative Git ownership and bounded model-free probes. No model dispatch."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import time
import uuid


class Blocked(RuntimeError):
    """Evidence is insufficient; leave any existing ownership in place."""


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def public_quota(item):
    """Reject arbitrary fields before normalized evidence can reach public Git."""
    keys = {"source", "observed_at", "warning", "rejected", "windows"}
    require(isinstance(item, dict) and keys <= item.keys() and
            item.keys() <= keys | {"ordinary_usage_allowed"}, "unexpected or missing quota fields")
    require(item["source"] in ("codex-app-server", "claude-statusline", "claude-sdk", "simulation"),
            "unknown quota source")
    require(number(item["observed_at"]) and type(item["warning"]) is bool and
            type(item["rejected"]) is bool, "unknown quota observation or status")
    windows = item["windows"]
    require(isinstance(windows, dict) and 1 <= len(windows) <= 32, "unknown quota windows")
    for key, window in windows.items():
        require(isinstance(key, str) and re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", key), "invalid quota window name")
        require(isinstance(window, dict) and set(window) == {"remaining", "reset_at"} and
                number(window["remaining"]) and number(window["reset_at"]), "unexpected or invalid quota window fields")
    require(item.get("ordinary_usage_allowed") in (None, True, False) and
            ("ordinary_usage_allowed" not in item or type(item["ordinary_usage_allowed"]) in (bool, type(None))),
            "unknown ordinary usage status")
    return json.loads(json.dumps(item, allow_nan=False))


def quota_gate(item, *, now=None, probe=False, required=None):
    """Require all applicable windows, a fresh observation and >10% remaining."""
    now = time.time() if now is None else now
    item = public_quota(item)
    require(number(now), "unknown current time")
    source = item.get("source")
    if source not in ("codex-app-server", "claude-statusline", "claude-sdk", "simulation"):
        raise Blocked("unknown quota source")
    if source == "simulation" and not probe:
        raise Blocked("simulation can authorize only a model-free probe")
    if source == "codex-app-server" and item.get("ordinary_usage_allowed") is not True:
        raise Blocked("ordinary Codex usage is denied or unknown")
    observed = item.get("observed_at")
    if not number(observed) or not 0 <= now - observed <= 120:
        raise Blocked("quota observation is stale, future or unknown")
    if item.get("warning") is not False or item.get("rejected") is not False:
        raise Blocked("quota warning, rejection or unknown status")
    windows = item.get("windows")
    if required is None:
        required = ("five_hour", "seven_day") if source.startswith("claude-") else ("primary", "secondary")
    if not isinstance(windows, dict) or not windows or not set(required).issubset(windows):
        raise Blocked("missing required quota windows")
    for window in windows.values():
        if not isinstance(window, dict):
            raise Blocked("unknown quota window")
        remaining, reset = window.get("remaining"), window.get("reset_at")
        if not number(remaining) or not 10 < remaining <= 100:
            raise Blocked("remaining quota must be finite and above ten percent")
        if not number(reset) or reset <= now:
            raise Blocked("quota reset passed or is unknown; fetch fresh evidence")
    return item


def normalize_codex(payload, *, observed_at):
    """Normalize a documented account/rateLimits/read result; never fetch it."""
    require(isinstance(payload, dict), "invalid Codex result")
    raw = payload.get("rateLimits") or {}
    result = {"source": "codex-app-server", "observed_at": observed_at,
              "warning": payload.get("spendControlReached", False) is not False,
              "rejected": payload.get("rateLimitReachedType") is not None, "windows": {},
              "ordinary_usage_allowed": payload.get("ordinaryUsageAllowed")}
    snapshots = [("", raw)]
    snapshots.extend((str(key) + ".", value) for key, value in
                     (payload.get("rateLimitsByLimitId") or {}).items())
    for prefix, snapshot in snapshots:
        if not isinstance(snapshot, dict):
            result["warning"] = True
            continue
        if prefix and any(snapshot.get(key) is None for key in ("primary", "secondary")):
            result["warning"] = True
        for key in ("primary", "secondary"):
            window = snapshot.get(key)
            if window is not None:
                used = window.get("usedPercent") if isinstance(window, dict) else None
                result["windows"][prefix + key] = {
                    "remaining": 100 - used if number(used) else None,
                    "reset_at": window.get("resetsAt") if isinstance(window, dict) else None}
    return result


def normalize_claude(payload, *, observed_at):
    """Normalize documented Claude statusline rate_limits, without auth output."""
    result = {"source": "claude-statusline", "observed_at": observed_at,
              "warning": False, "rejected": False, "windows": {}}
    for key, window in (payload.get("rate_limits") or {}).items():
        if not isinstance(window, dict):
            result["warning"] = True
            continue
        used = window.get("used_percentage")
        result["windows"][key] = {"remaining": 100 - used if number(used) else None,
                                  "reset_at": window.get("resets_at")}
    return result


OWNERS = ("gpt-mock", "claude-mock")
SHA = re.compile(r"[0-9a-f]{40}")


def require(condition, message):
    if not condition:
        raise Blocked(message)


def validate_state(state):
    keys = {"schema", "task_id", "source_branch", "source_sha", "project_path", "mode", "phase",
            "owner", "next_owner", "run_id", "checkpoint", "summary", "previous_stopped", "quota", "event_id"}
    require(isinstance(state, dict) and set(state) == keys and type(state["schema"]) is int and
            state["schema"] == 1 and state["mode"] == "mock", "unknown coordination fields or schema")
    require(isinstance(state["task_id"], str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", state["task_id"]),
            "invalid saved task")
    require(isinstance(state["source_sha"], str) and SHA.fullmatch(state["source_sha"]), "invalid saved source SHA")
    require(isinstance(state["source_branch"], str) and 1 <= len(state["source_branch"]) <= 200,
            "invalid saved source branch")
    require(isinstance(state["project_path"], str) and len(state["project_path"]) <= 200, "invalid saved project")
    project = PurePosixPath(state["project_path"])
    require(not project.is_absolute() and ".." not in project.parts and len(project.parts) >= 2 and
            project.name == "project.godot", "invalid saved project")
    require(isinstance(state["event_id"], str) and re.fullmatch(r"[0-9a-f]{32}", state["event_id"]), "invalid generation")
    require(state["phase"] in ("ready", "claimed", "running", "stopped", "completed") and
            state["owner"] in (*OWNERS, None) and state["next_owner"] in (*OWNERS, None), "unknown ownership phase")
    require(state["summary"] in ("Initialized; bounded model-free probes only.",
            "Exclusive mock claim; no successor until supervised stop.",
            "Bounded deterministic Python worker is supervised.", "Mock progress saved; worker stopped and reaped."),
            "unknown public summary")
    checkpoint = state["checkpoint"]
    require(isinstance(checkpoint, dict) and set(checkpoint) == {"completed_units", "digest"} and
            type(checkpoint["completed_units"]) is int and 0 <= checkpoint["completed_units"] <= 10**9 and
            isinstance(checkpoint["digest"], str) and re.fullmatch(r"[0-9a-f]{64}", checkpoint["digest"]), "invalid checkpoint")
    receipt = state["previous_stopped"]
    if receipt is not None:
        require(isinstance(receipt, dict) and set(receipt) == {"owner", "run_id", "pid", "started_at", "stopped_at",
                "reaped", "returncode", "reason"} and receipt["owner"] in OWNERS and
                isinstance(receipt["run_id"], str) and re.fullmatch(r"[0-9a-f]{32}", receipt["run_id"]) and
                type(receipt["pid"]) is int and receipt["pid"] > 0 and receipt["reaped"] is True and
                type(receipt["returncode"]) is int and receipt["returncode"] == 0 and
                number(receipt["started_at"]) and number(receipt["stopped_at"]) and
                receipt["stopped_at"] >= receipt["started_at"] and
                receipt["reason"] in ("bounded-completion", "simulated-warning", "simulated-interruption"),
                "invalid stop receipt")
    if state["phase"] == "ready":
        require(state["owner"] is None and state["run_id"] is None and receipt is None and
                state["next_owner"] in OWNERS and state["quota"] is None, "invalid initial ownership")
    else:
        require(state["owner"] in OWNERS and isinstance(state["run_id"], str) and
                re.fullmatch(r"[0-9a-f]{32}", state["run_id"]), "missing ownership generation")
        public_quota(state["quota"])
        if state["phase"] in ("claimed", "running", "completed"):
            require(state["next_owner"] is None, "successor offered before stop")
        if state["phase"] in ("stopped", "completed"):
            require(receipt is not None and receipt["run_id"] == state["run_id"] and
                    receipt["owner"] == state["owner"], "missing verified stop receipt")
        if state["phase"] == "stopped":
            require(state["next_owner"] in OWNERS and state["next_owner"] != state["owner"], "missing successor")


class Coordinator:
    """Only state.json is committed, on a separate append-only Git branch."""
    def __init__(self, repo, remote="origin", state_branch="cloud/handoff-state-20261114"):
        self.repo, self.remote = Path(repo), remote
        require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", remote)), "invalid remote name")
        require(state_branch.startswith("cloud/handoff-state-"), "coordination branch must use its reserved prefix")
        self.ref = "refs/heads/" + state_branch
        self.git("check-ref-format", self.ref)

    def git(self, *args, data=None, identity=False):
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"
        if identity:
            for prefix in ("GIT_AUTHOR", "GIT_COMMITTER"):
                env[prefix + "_NAME"] = "Cloud Handoff"
                env[prefix + "_EMAIL"] = "cloud-handoff@users.noreply.github.com"
        try:
            result = subprocess.run(["git", "-C", str(self.repo), *args], input=data,
                                    capture_output=True, text=True, env=env, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Blocked("Git operation unavailable; inspect ownership before retrying") from exc
        require(result.returncode == 0, "Git operation rejected; ownership may be held; inspect before retrying")
        return result.stdout.strip()

    def remote_sha(self, ref):
        output = self.git("ls-remote", "--refs", self.remote, ref)
        rows = [line.split() for line in output.splitlines() if line.split()[-1] == ref]
        require(len(rows) <= 1, "ambiguous remote reference")
        return rows[0][0] if rows else None

    def source_check(self, state, source_sha):
        require(isinstance(source_sha, str) and SHA.fullmatch(source_sha), "full source SHA required")
        require(source_sha == state["source_sha"], "source SHA differs from saved source")
        require(self.git("rev-parse", "HEAD") == source_sha, "checkout HEAD is not the exact saved source")
        branch = "refs/heads/" + state["source_branch"]
        self.git("check-ref-format", branch)
        require(branch != self.ref, "source and coordination branches must differ")
        require(self.remote_sha(branch) == source_sha, "saved source branch is missing or has moved")
        project = PurePosixPath(state["project_path"])
        require(not project.is_absolute() and ".." not in project.parts and
                len(project.parts) >= 2 and project.name == "project.godot", "invalid relative project path")
        tree = self.git("ls-tree", source_sha, "--", str(project))
        require(tree.startswith(("100644 blob ", "100755 blob ")), "source project is not a saved regular file")
        scope = str(project.parent)
        require(not self.git("status", "--porcelain", "--untracked-files=all", "--", scope),
                "game project has local changes or untracked files")
        self.git("diff", "--exit-code", source_sha, "--", scope)
        saved_controller = self.git("ls-tree", source_sha, "--", "tools/cloud_handoff.py")
        require(saved_controller.startswith(("100644 blob ", "100755 blob ")),
                "saved source is missing its regular controller file")
        saved_blob = saved_controller.split()[2]
        running_blob = self.git("hash-object", "--no-filters", str(Path(__file__).resolve()))
        require(running_blob == saved_blob, "executing controller differs from saved source blob")
        require(not self.git("status", "--porcelain", "--untracked-files=all", "--", "tools/cloud_handoff.py"),
                "controller differs from saved source")

    def inspect(self):
        commit = self.remote_sha(self.ref)
        require(commit is not None, "coordination state is not initialized")
        self.git("fetch", "--quiet", "--no-tags", "--no-write-fetch-head", self.remote, self.ref)
        require(self.git("ls-tree", "--name-only", commit) == "state.json", "unexpected coordination files")
        raw = self.git("show", commit + ":state.json")
        require(len(raw) <= 16384, "coordination state is oversized")
        try:
            state = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        except (ValueError, TypeError) as exc:
            raise Blocked("invalid coordination JSON") from exc
        validate_state(state)
        return {"commit": commit, "state": state}

    def publish(self, state, parent=None):
        raw = json.dumps(state, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"
        require(len(raw.encode("utf-8")) <= 16384, "coordination state exceeds public byte budget")
        validate_state(state)
        blob = self.git("hash-object", "-w", "--stdin", data=raw)
        tree = self.git("mktree", data="100644 blob " + blob + "\tstate.json\n")
        args = ["commit-tree", tree, "-m", "Record model-free handoff state"]
        if parent:
            args.extend(("-p", parent))
        commit = self.git(*args, identity=True)
        # A normal push rejects a competing sibling. No force, leases or unlock.
        self.git("push", "--porcelain", self.remote, commit + ":" + self.ref)
        return {"commit": commit, "state": state}

    def initialize(self, *, task_id, source_branch, source_sha, project_path, next_owner="gpt-mock"):
        require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", task_id)), "invalid task id")
        require(next_owner in OWNERS, "only mock owners are enabled")
        require(self.remote_sha(self.ref) is None, "coordination state already exists")
        state = {"schema": 1, "task_id": task_id, "source_branch": source_branch,
                 "source_sha": source_sha, "project_path": project_path, "mode": "mock",
                 "phase": "ready", "owner": None, "next_owner": next_owner, "run_id": None,
                 "checkpoint": {"completed_units": 0, "digest": hashlib.sha256(b"").hexdigest()},
                 "summary": "Initialized; bounded model-free probes only.", "previous_stopped": None,
                 "quota": None, "event_id": uuid.uuid4().hex}
        self.source_check(state, source_sha)
        return self.publish(state)

    def expected(self, expected, source_sha):
        require(isinstance(expected, str) and SHA.fullmatch(expected), "full expected state SHA required")
        snapshot = self.inspect()
        require(snapshot["commit"] == expected, "stale expected state SHA")
        self.source_check(snapshot["state"], source_sha)
        return snapshot["state"]

    def claim(self, *, expected, source_sha, owner, quota, probe=False):
        quota = quota_gate(quota, probe=probe)
        require(owner in OWNERS, "real model dispatch is disabled")
        state = self.expected(expected, source_sha)
        require(state["phase"] in ("ready", "stopped"), "owner may still be running; no automatic takeover")
        require(state["next_owner"] == owner, "claimant is not the saved next owner")
        state.update(phase="claimed", owner=owner, next_owner=None, run_id=uuid.uuid4().hex,
                     quota=quota, summary="Exclusive mock claim; no successor until supervised stop.")
        return self.publish(state, expected)

    def probe(self, *, expected, source_sha, owner, next_owner=None, complete=False,
              stop="warning", units=6, delay=0.03):
        require(isinstance(units, int) and not isinstance(units, bool) and 2 <= units <= 100,
                "probe units must be between 2 and 100")
        require(number(delay) and 0.01 <= delay <= 0.1, "probe delay must be between 0.01 and 0.1")
        require(stop in ("warning", "interruption"), "unknown controlled stop")
        require((complete and next_owner is None) or (not complete and next_owner in OWNERS and next_owner != owner),
                "choose completion or a different mock successor")
        now = time.time()
        quota = {"source": "simulation", "observed_at": now, "warning": False, "rejected": False,
                 "windows": {key: {"remaining": 80, "reset_at": now + 3600}
                             for key in ("primary", "secondary")}}
        held = self.claim(expected=expected, source_sha=source_sha, owner=owner, quota=quota, probe=True)
        state = held["state"]
        with tempfile.TemporaryDirectory(prefix="cloud-handoff-probe-") as directory:
            folder = Path(directory)
            process = subprocess.Popen([sys.executable, "-c", WORKER, directory, str(units), str(delay),
                                        json.dumps(state["checkpoint"])], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                state.update(phase="running", summary="Bounded deterministic Python worker is supervised.")
                held = self.publish(state, held["commit"])
                (folder / "start").touch()
                target = state["checkpoint"]["completed_units"] + (units if complete else units // 2)
                deadline = time.monotonic() + 15
                checkpoint = None
                while time.monotonic() < deadline:
                    path = folder / "progress.json"
                    if path.exists():
                        checkpoint = json.loads(path.read_text())
                        if checkpoint["completed_units"] >= target:
                            break
                    require(process.poll() is None, "worker exited without reaching its checkpoint; ownership retained")
                    time.sleep(0.01)
                require(checkpoint is not None and checkpoint["completed_units"] >= target,
                        "worker checkpoint timed out; ownership retained")
                state["checkpoint"] = {key: checkpoint[key] for key in ("completed_units", "digest")}
                held = self.publish(state, held["commit"])
                if not complete:
                    if stop == "interruption":
                        process.terminate()
                    else:
                        (folder / "stop").touch()
                require(process.wait(timeout=5) == 0, "worker did not stop cleanly; ownership retained")
                final = json.loads((folder / "stopped.json").read_text())
                state["checkpoint"] = {key: final[key] for key in ("completed_units", "digest")}
                receipt = {"owner": owner, "run_id": state["run_id"], "pid": process.pid,
                           "started_at": final["started_at"], "stopped_at": time.time(),
                           "reaped": True, "returncode": process.returncode,
                           "reason": "bounded-completion" if complete else "simulated-" + stop}
                # Recheck our exact ownership AND source after wait(), before releasing.
                current = self.expected(held["commit"], source_sha)
                require(current["run_id"] == state["run_id"] and current["owner"] == owner,
                        "ownership changed; transfer blocked")
                state.update(phase="completed" if complete else "stopped", next_owner=next_owner,
                             previous_stopped=receipt, summary="Mock progress saved; worker stopped and reaped.")
                if not complete and stop == "warning":
                    state["quota"]["warning"] = True
                return self.publish(state, held["commit"])
            finally:
                if process.poll() is None:
                    (folder / "stop").touch()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)


WORKER = r'''
import hashlib, json, os, signal, sys, time
from pathlib import Path
folder, units, delay, initial = Path(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), json.loads(sys.argv[4])
stopping = False
def stop(signum, frame):
    global stopping
    stopping = True
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
deadline = time.monotonic() + 45
while not (folder / "start").exists():
    if stopping or (folder / "stop").exists() or time.monotonic() >= deadline:
        sys.exit(2)
    time.sleep(0.01)
checkpoint = dict(initial, started_at=time.time())
def save(name):
    temporary = folder / (name + ".tmp")
    temporary.write_text(json.dumps(checkpoint))
    os.replace(temporary, folder / name)
for _ in range(units):
    if stopping or (folder / "stop").exists():
        break
    checkpoint["completed_units"] += 1
    checkpoint["digest"] = hashlib.sha256((checkpoint["digest"] + ":" + str(checkpoint["completed_units"])).encode()).hexdigest()
    save("progress.json")
    time.sleep(delay)
save("stopped.json")
'''


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, epilog="Only mock owners are enabled. No automatic unlock or real model launch.")
    parser.add_argument("--repo", default=".", help="saved source checkout; game project must be clean")
    parser.add_argument("--remote", default="origin")
    parser.add_argument("--state-branch", default="cloud/handoff-state-20261114")
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="initialize a NEW coordination branch tied to an exact pushed source")
    init.add_argument("--task-id", required=True)
    init.add_argument("--source-branch", required=True)
    init.add_argument("--source-sha", required=True)
    init.add_argument("--project-path", default="cloud_snapshot/project.godot")
    init.add_argument("--next-owner", choices=OWNERS, default="gpt-mock")
    commands.add_parser("inspect", help="print remote commit and compact state as JSON")
    for name in ("claim", "probe"):
        command = commands.add_parser(name, help="hold ownership" if name == "claim" else "claim, run bounded mock, reap, and hand off")
        command.add_argument("--expected", required=True, help="exact remote state commit printed by inspect")
        command.add_argument("--source-sha", required=True)
        command.add_argument("--owner", choices=OWNERS, required=True)
        if name == "claim":
            command.add_argument("--quota-file", required=True, help="normalized evidence JSON; no raw provider/auth logs")
            command.add_argument("--probe", action="store_true", help="permit simulation evidence; still no worker is started")
        else:
            command.add_argument("--next-owner", choices=OWNERS)
            command.add_argument("--complete", action="store_true")
            command.add_argument("--stop", choices=("warning", "interruption"), default="warning")
            command.add_argument("--units", type=int, default=6)
            command.add_argument("--delay", type=float, default=0.03)
    options = vars(parser.parse_args(argv))
    command = options.pop("command")
    coordinator = Coordinator(options.pop("repo"), options.pop("remote"), options.pop("state_branch"))
    try:
        if command == "claim":
            options["quota"] = json.loads(Path(options.pop("quota_file")).read_text())
        result = getattr(coordinator, "initialize" if command == "init" else command)(**options)
        print(json.dumps(result, sort_keys=True, allow_nan=False))
        return 0
    except (Blocked, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as exc:
        print("Blocked: " + str(exc) if isinstance(exc, Blocked) else "Blocked: incomplete evidence or worker failure; ownership retained", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
