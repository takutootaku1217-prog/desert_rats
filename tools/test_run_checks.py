"""Small subprocess fixtures for the runner itself; no Godot required."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

import run_checks as runner


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="desert runner test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def execute(self, plans, **kwargs):
        return runner.execute(plans, self.root, self.root / "runs", os.environ.copy(), {"test_fixture": True}, **kwargs)

    def command(self, code):
        return [sys.executable, "-c", code]

    def test_success_and_literal_arguments(self):
        # Quotes, spaces, shell substitution syntax remain one literal argument.
        value = "a space; $(touch SHOULD_NOT_EXIST)"
        run, report = self.execute([(runner.Check("success", (), "DONE"),
                                   self.command("import sys; print(sys.argv[1]); print('DONE')") + [value])])
        self.assertEqual(report["status"], "passed")
        self.assertIn(value, (run / "success.log").read_text())
        self.assertFalse((self.root / "SHOULD_NOT_EXIST").exists())
        self.assertEqual(json.loads((run / "results.json").read_text())["checks"][0]["returncode"], 0)

    def test_failures_preserve_stdout_stderr_and_first_failure(self):
        run, report = self.execute([
            (runner.Check("first", ()), self.command("import sys; print('out', flush=True); print('err', file=sys.stderr); sys.exit(3)")),
            (runner.Check("second", ()), self.command("raise SystemExit(4)")),
            (runner.Check("last", (), "DONE"), self.command("print('DONE')")),
        ])
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["first_failure"]["id"], "first")
        self.assertEqual([r["returncode"] for r in report["checks"]], [3, 4, 0])
        self.assertIn("out\nerr", (run / "first.log").read_text())

    def test_timeout_retains_partial_log_and_continues(self):
        run, report = self.execute([
            (runner.Check("slow", (), timeout=0.3), self.command("import time; print('started', flush=True); time.sleep(30)")),
            (runner.Check("after", ()), self.command("print('after')")),
        ])
        self.assertEqual(report["checks"][0]["status"], "timeout")
        self.assertEqual(report["checks"][1]["status"], "passed")
        self.assertEqual(report["status"], "failed")
        self.assertIn("started", (run / "slow.log").read_text())
        self.assertLess(report["elapsed_wall_seconds"], 10)

    def test_missing_executable_blocks_dependents(self):
        _, report = self.execute([
            (runner.Check("import", ()), [str(self.root / "nonexistent executable")]),
            (runner.Check("dependent", ()), self.command("print('should not execute')")),
        ], import_required=True)
        self.assertEqual(report["checks"][0]["status"], "missing_executable")
        self.assertEqual(report["checks"][1]["status"], "not_run")
        self.assertEqual(report["status"], "failed")

    def test_exit_zero_is_not_enough(self):
        _, report = self.execute([
            (runner.Check("no_marker", (), "DONE"), self.command("print('unfinished')")),
            (runner.Check("engine_error", (), "DONE"), self.command("print('SCRIPT ERROR: example'); print('DONE')")),
        ])
        self.assertTrue(all(r["status"] == "failed" for r in report["checks"]))

    def test_rerun_does_not_replace_failure(self):
        old_run, _ = self.execute([(runner.Check("sample", ()), self.command("raise SystemExit(9)"))])
        old_json = (old_run / "results.json").read_bytes()
        old_log = (old_run / "sample.log").read_bytes()
        new_run, result = self.execute([(runner.Check("sample", ()), self.command("print('fixed')"))])
        self.assertNotEqual(old_run, new_run)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(old_json, (old_run / "results.json").read_bytes())
        self.assertEqual(old_log, (old_run / "sample.log").read_bytes())

    def test_empty_run_cannot_pass(self):
        with self.assertRaises(ValueError):
            self.execute([])

    def test_catalog_uses_existing_scripts_and_keeps_extra_separate(self):
        for check in runner.CHECKS.values():
            if "-s" in check.args:
                script = check.args[check.args.index("-s") + 1]
                self.assertTrue((runner.ROOT / script.removeprefix("res://")).is_file())
        self.assertFalse(set(runner.SUITES["core"]) & set(runner.SUITES["extra"]))


if __name__ == "__main__":
    unittest.main()
