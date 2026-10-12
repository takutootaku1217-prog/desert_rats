#!/usr/bin/env python3
"""Run existing Godot diagnostics sequentially; preserve every attempt."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR_LINE = re.compile(r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FAIL\b|★)")


@dataclass(frozen=True)
class Check:
    id: str
    args: tuple[str, ...]
    success: str | None = None
    timeout: float = 180.0
    game_minutes: float | None = None
    repetitions: int | None = None


def diagnostic(name: str, marker: str = "== 結果: すべて成功 ==") -> Check:
    return Check(name, ("-s", f"res://tools/test_{name}.gd"), marker)


CHECKS = {c.id: c for c in [
    Check("import", ("--editor", "--import", "--quit"), timeout=120),
    *(diagnostic(n) for n in ("quarry", "gather", "cargo", "items", "crew_status", "life_actions", "tool_management", "rooms", "view", "camera", "artscale", "packed_equipment", "equipment_ui", "weapon", "weapon_ui", "cargo_accounting", "cargo_escape_ui", "progression", "clarity_ui", "inventory_discard", "save_game", "save_ui", "save_progression", "world_map", "world_flow", "world_boundaries", "world_fauna", "seed_initialization", "batch_crafting", "batch_ui", "batch_flow", "haul_support", "haul_ui", "haul_flow", "facility_packing", "packing_flow", "crew_detail", "build")),
    *(diagnostic(n, "== 結果: 0 件失敗 ==") for n in ("cargo_reservations", "consumption_loop")),
    Check("loop_vanilla", ("-s", "res://tools/test_loop.gd", "--", "32", "2", "12", "500", "0", "vanilla"),
          "== 結果: 問題なし ==", 300, 32, 2),
    Check("loop_normal", ("-s", "res://tools/test_loop.gd", "--", "28", "2", "12", "500", "0", "normal"),
          "== 結果: 問題なし ==", 300, 28, 2),
    Check("loop_manual", ("-s", "res://tools/test_loop.gd", "--", "28", "1", "12", "700", "0", "manual", "trace"),
          "== 結果: 問題なし ==", 300, 28, 1),
    Check("loop_events", ("-s", "res://tools/test_loop.gd", "--", "32", "1", "12", "500", "1", "vanilla", "trace"),
          "== 結果: 問題なし ==", 300, 32, 1),
    Check("quarry_rear", ("-s", "res://tools/test_quarry.gd", "--", "rear"), "== 結果: すべて成功 =="),
    Check("manual_repro", ("-s", "res://tools/test_loop.gd", "--", "28", "3", "12", "700", "0", "manual", "trace"), "== 結果: 問題なし ==", 400, 28, 3),
    *(Check("manual_" + mode, ("-s", "res://tools/test_loop.gd", "--", "28", "1", "12", "700", "0", "manual", "trace", mode), "== 結果: 問題なし ==", 300, 28, 1) for mode in ("legacy_inputs", "legacy_boundary", "legacy_both")),
    Check("startup", ("--quit-after", "300")),
]}
SUITES = {
    "core": ["batch_crafting", "batch_ui", "batch_flow", "haul_support", "haul_ui", "haul_flow", "facility_packing", "packing_flow", "world_map", "world_flow", "world_boundaries", "world_fauna", "save_game", "save_ui", "inventory_discard", "clarity_ui", "cargo_accounting", "cargo_escape_ui", "progression", "weapon", "weapon_ui", "equipment_ui", "packed_equipment", "quarry", "gather", "cargo", "items", "crew_status", "life_actions", "tool_management",
             "cargo_reservations", "consumption_loop", "loop_vanilla", "loop_normal", "startup"],
    "extra": ["loop_manual", "loop_events"],
    "layout": ["rooms", "view", "camera", "artscale", "quarry", "quarry_rear", "consumption_loop"],
}


def capture(argv: list[str], cwd: Path) -> dict:
    try:
        p = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding="utf-8", errors="replace", timeout=15, shell=False)
        return {"command": argv, "returncode": p.returncode, "output": p.stdout.strip()}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"command": argv, "error": str(exc)}


def git_state(root: Path) -> dict:
    fields = {key: capture(["git", "--no-optional-locks", *args], root) for key, args in {
        "head": ["rev-parse", "HEAD"], "branch": ["branch", "--show-current"],
        "status": ["status", "--porcelain=v1", "--untracked-files=all"],
    }.items()}
    changed = []
    try:
        tracked = subprocess.check_output(["git", "--no-optional-locks", "diff", "HEAD", "--name-only", "-z"], cwd=root)
        untracked = subprocess.check_output(["git", "--no-optional-locks", "ls-files", "--others", "--exclude-standard", "-z"], cwd=root)
        for raw in sorted(set((tracked + untracked).split(b"\0")) - {b""}):
            name = os.fsdecode(raw)
            p = root / name
            changed.append({"path": name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None})
    except (OSError, subprocess.CalledProcessError) as exc:
        fields["changed_files_error"] = str(exc)
    fields["changed_files"] = changed
    fields["dirty"] = bool(fields["status"].get("output")) if fields["status"].get("returncode") == 0 else None
    return fields


def save_json(path: Path, data: dict) -> None:
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def new_run(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
    return Path(tempfile.mkdtemp(prefix=stamp, dir=output))


def stop_process(process: subprocess.Popen) -> None:
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    else:
        process.kill()
    process.wait()


def run_check(check: Check, argv: list[str], root: Path, run: Path, env: dict,
              timeout: float | None = None) -> dict:
    log = run / f"{check.id}.log"
    limit = check.timeout if timeout is None else timeout
    result = {"id": check.id, "command": argv, "cwd": str(root), "log": str(log),
              "timeout_seconds": limit, "requested_game_minutes_per_run": check.game_minutes,
              "requested_repetitions": check.repetitions, "status": "running", "returncode": None}
    start = time.monotonic()
    process = None
    try:
        # stdout and stderr share one stream, preserving their observed ordering.
        with log.open("x", encoding="utf-8") as stream:
            try:
                process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                           shell=False, start_new_session=(os.name == "posix"))
                process.wait(timeout=limit)
                result["returncode"] = process.returncode
                result["status"] = "passed" if process.returncode == 0 else "failed"
            except subprocess.TimeoutExpired:
                stop_process(process)
                result.update(status="timeout", returncode=process.returncode)
            except KeyboardInterrupt:
                if process is not None:
                    stop_process(process)
                result.update(status="interrupted", returncode=process.returncode if process else None)
            except FileNotFoundError as exc:
                result.update(status="missing_executable", error=str(exc))
                stream.write(str(exc) + "\n")
            except OSError as exc:
                result.update(status="launch_error", error=str(exc))
                stream.write(str(exc) + "\n")
    finally:
        result["elapsed_wall_seconds"] = round(time.monotonic() - start, 3)
    output = log.read_text(encoding="utf-8", errors="replace")
    result["diagnostic_error_lines"] = [line for line in output.splitlines() if ERROR_LINE.search(line)]
    result["success_marker_found"] = check.success in output if check.success else None
    if result["status"] == "passed" and (result["diagnostic_error_lines"] or
                                            (check.success and not result["success_marker_found"])):
        result["status"] = "failed"
        result["reason"] = "Diagnostic error or missing completion marker despite exit 0"
    return result


def execute(checks: list[tuple[Check, list[str]]], root: Path, output: Path, env: dict,
            metadata: dict, timeout: float | None = None, import_required: bool = False) -> tuple[Path, dict]:
    if not checks:
        raise ValueError("No checks selected; an empty run cannot pass")
    run = new_run(output)
    env = env.copy()
    for key, subdir in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        path = run / "godot-user" / subdir
        path.mkdir(parents=True)
        env[key] = str(path)
    report = {"schema_version": 1, "run_directory": str(run), "started_utc": datetime.now(timezone.utc).isoformat(),
              "metadata": metadata, "scope": [c.id for c, _ in checks], "status": "running", "first_failure": None,
              "checks": [{"id": c.id, "command": argv, "status": "not_run"} for c, argv in checks]}
    save_json(run / "results.json", report)
    start = time.monotonic()
    blocked = False
    for index, (check, argv) in enumerate(checks):
        if blocked:
            result = {"id": check.id, "command": argv, "status": "not_run", "reason": "Import failed or run interrupted"}
        else:
            print(f"START {check.id} (timeout {timeout or check.timeout:g}s)", flush=True)
            result = run_check(check, argv, root, run, env, timeout)
            print(f"{result['status'].upper()} {check.id} wall={result['elapsed_wall_seconds']:.3f}s", flush=True)
        report["checks"][index] = result
        if result["status"] != "passed" and report["first_failure"] is None:
            report["first_failure"] = result.copy()
        if result["status"] == "interrupted" or (import_required and check.id == "import" and result["status"] != "passed"):
            blocked = True
        save_json(run / "results.json", report)
    report["status"] = "passed" if all(r["status"] == "passed" for r in report["checks"]) else "failed"
    report["elapsed_wall_seconds"] = round(time.monotonic() - start, 3)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    save_json(run / "results.json", report)
    return run, report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="core")
    parser.add_argument("--check", action="append", choices=CHECKS, help="Run only these checks (repeatable); import is included")
    parser.add_argument("--godot", default=shutil.which("godot") or shutil.which("godot4") or "godot")
    parser.add_argument("--output-dir", type=Path, default=Path(tempfile.gettempdir()) / "desert-rats-harness")
    parser.add_argument("--timeout", type=float, help="Override each check's wall-clock timeout in seconds")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.timeout is not None and (not 0 < args.timeout < float("inf")):
        parser.error("--timeout must be positive and finite")
    if args.list:
        print(json.dumps({"suites": SUITES, "checks": list(CHECKS)}, ensure_ascii=False, indent=2))
        return 0
    if args.output_dir.resolve().is_relative_to(ROOT):
        parser.error("--output-dir must be outside the repository to keep evidence out of source-state checks")
    selected = list(dict.fromkeys(["import", *(args.check or SUITES[args.suite])]))
    metadata = {"platform": platform.platform(), "python": sys.version, "python_executable": sys.executable,
                "runner_command": [sys.executable, *sys.argv], "root": str(ROOT), "git_before": git_state(ROOT),
                "godot_version": capture([args.godot, "--version"], ROOT), "suite": None if args.check else args.suite,
                "unverified": ["Windows / Godot 4.7.2", "OS-level input", "Audio"],
                "scope_note": "world_*, batch_*, haul_*, facility_packing, packing_flow and startup use the default map; other gameplay checks explicitly use legacy-world-test fixtures. Only selected checks; core does not cover extra or all gameplay conditions."}
    checks = []
    for name in selected:
        argv = [args.godot, "--headless", "--path", str(ROOT), "--fixed-fps", "60", *CHECKS[name].args]
        if name not in ("import", "startup", "seed_initialization", "batch_crafting", "batch_ui", "batch_flow", "haul_support", "haul_ui", "haul_flow", "facility_packing", "packing_flow") and not name.startswith("world_"):
            if "--" not in argv: argv.append("--")
            argv.append("legacy-world-test")  # Existing-loop fixtures; world_* exercise the new default map.
        checks.append((CHECKS[name], argv))
    run, report = execute(checks, ROOT, args.output_dir.resolve(), os.environ.copy(), metadata, args.timeout, True)
    report["metadata"]["git_after"] = git_state(ROOT)
    report["source_changed_during_run"] = report["metadata"]["git_after"] != metadata["git_before"]
    git_verified = all(metadata["git_before"][key].get("returncode") == 0 for key in ("head", "branch", "status"))
    git_verified = git_verified and "changed_files_error" not in metadata["git_before"]
    version_verified = metadata["godot_version"].get("returncode") == 0 and bool(metadata["godot_version"].get("output"))
    if report["source_changed_during_run"] or not git_verified or not version_verified:
        report["status"] = "failed"
        report["verification_error"] = "Source changed during run or Git/Godot metadata could not be verified"
        if report["first_failure"] is None:
            report["first_failure"] = {"id": "environment_verification", "status": "failed", "reason": report["verification_error"]}
    save_json(run / "results.json", report)
    print(f"Selected checks: {report['status']}. Results: {run / 'results.json'}", flush=True)
    print("判定は選択した診断のみです。通常セットの成功は追加セット・全条件の成功を意味しません。")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
