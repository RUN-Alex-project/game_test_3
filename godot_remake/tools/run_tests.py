#!/usr/bin/env python3
"""Cross-platform automated test runner for the godot_remake project.

Single source of truth for test execution. Both run_tests.ps1 (Windows) and
run_tests.sh (Linux/macOS) are thin wrappers around this script.

Reads tests/test_manifest.json (the single test registry), filters scenes by
current platform, runs Godot headless per scene, applies the same failure
semantics as the historical PowerShell runner:

  FAIL conditions per automated scene:
    - Godot exit code != 0
    - any "SCRIPT ERROR:" line
    - any "^ERROR:" line  (except the known-benign
      "Failed to read the root certificate store" certificate store warning)
    - any "ObjectDB instances leaked" line
    - no "^PASS " completion marker
    - any "SKIP" / "SKIPPED" / "TEST_USER_DATA_NOT_WRITABLE" marker

  Scenes registered for other platforms are reported as NOT_APPLICABLE
  (not started, not SKIP, not counted as pass/fail).

  Main scene smoke runs last with the same error/leak checks (no PASS marker
  required, matching historical behaviour).

Uses only the Python standard library. Exits 0 only when every applicable
scene and the smoke pass.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT = TOOLS_DIR.parent                      # godot_remake/
MANIFEST_PATH = PROJECT / "tests" / "test_manifest.json"

ALLOWED_PLATFORMS = ("windows", "linux")

# Exactly one known-benign error line, filtered identically to the historical
# PowerShell runner. Precise match only - never blanket-ignore ERROR lines.
ERROR_EXCLUDE_SUBSTRINGS = ("Failed to read the root certificate store",)

SCRIPT_ERROR_RE = re.compile(r"SCRIPT ERROR:")
ERROR_LINE_RE = re.compile(r"^ERROR:", re.MULTILINE)
LEAK_RE = re.compile(r"ObjectDB instances leaked")
SKIP_RE = re.compile(r"SKIP|SKIPPED|TEST_USER_DATA_NOT_WRITABLE")
PASS_RE = re.compile(r"^PASS ", re.MULTILINE)

WALL_CLOCK_TIMEOUT_DEFAULT = 900  # seconds per scene; --quit-after is the primary bound


def detect_platform() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform.startswith("linux"):
        return "linux"
    return "unknown"


def resolve_godot(arg_godot: str | None) -> tuple[str | None, str]:
    """Resolve godot binary. Priority: --godot > GODOT_BIN > GODOT_EXE > godot4 > godot."""
    candidates: list[str] = []
    if arg_godot:
        candidates.append(("arg --godot", arg_godot))
    for env_name in ("GODOT_BIN", "GODOT_EXE"):
        value = os.environ.get(env_name)
        if value:
            candidates.append((f"env {env_name}", value))
    candidates.append(("PATH godot4", "godot4"))
    candidates.append(("PATH godot", "godot"))

    for source, candidate in candidates:
        if "/" in candidate or "\\" in candidate or os.path.isabs(candidate):
            resolved = candidate
        else:
            resolved = shutil.which(candidate)
        if resolved and os.path.isfile(resolved):
            # Windows 无执行位语义；POSIX 需真实可执行。
            if os.name == "nt" or os.access(resolved, os.X_OK):
                return resolved, source
        # fall through to next candidate
    return None, ""


def load_manifest() -> dict:
    if not MANIFEST_PATH.is_file():
        print(f"RUNNER FAIL: test manifest not found: {MANIFEST_PATH}")
        sys.exit(2)
    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"RUNNER FAIL: cannot parse test manifest: {exc}")
        sys.exit(2)
    if int(manifest.get("schema_version", 0)) != 1:
        print("RUNNER FAIL: unsupported manifest schema_version")
        sys.exit(2)
    return manifest


def read_log(log_path: Path) -> str:
    try:
        return log_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def classify_failure(exit_code: int, log_text: str) -> str | None:
    """Return a failure reason string, or None when the run is clean."""
    for line in log_text.splitlines():
        if "SCRIPT ERROR:" in line:
            return "script errors; see log"
        if line.startswith("ERROR:") and not any(x in line for x in ERROR_EXCLUDE_SUBSTRINGS):
            return "script errors; see log"
    if LEAK_RE.search(log_text):
        return "ObjectDB instances leaked at exit; see log"
    if SKIP_RE.search(log_text):
        return "SKIP/NOT_WRITABLE detected; see log"
    if exit_code != 0:
        return f"exit {exit_code}; see log"
    if not PASS_RE.search(log_text):
        return "no PASS completion marker before --quit-after; see log"
    return None


def classify_smoke_failure(exit_code: int, log_text: str) -> str | None:
    """Smoke semantics: exit code + errors + leaks only (no PASS marker), as historically."""
    for line in log_text.splitlines():
        if "SCRIPT ERROR:" in line:
            return "script errors; see log"
        if line.startswith("ERROR:") and not any(x in line for x in ERROR_EXCLUDE_SUBSTRINGS):
            return "script errors; see log"
    if LEAK_RE.search(log_text):
        return "ObjectDB instances leaked at exit; see log"
    if exit_code != 0:
        return f"exit {exit_code}; see log"
    return None


def run_scene(godot: str, scene: str, quit_after: int, timeout: int) -> tuple[bool, str, Path | None]:
    with tempfile.TemporaryDirectory(prefix="godot-remake-") as tmpdir:
        log_path = Path(tmpdir) / "godot.log"
        cmd = [
            godot, "--headless",
            "--path", str(PROJECT),
            "--scene", scene,
            "--quit-after", str(quit_after),
            "--log-file", str(log_path),
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
            exit_code = proc.returncode
        except subprocess.TimeoutExpired:
            return False, f"wall-clock timeout after {timeout}s", None
        log_text = read_log(log_path) if log_path.exists() else ""
        reason = classify_failure(exit_code, log_text)
        if reason is None:
            return True, "", None
        # preserve the log for inspection on failure
        keep = Path(tempfile.gettempdir()) / f"godot-remake-fail-{scene.rsplit('/', 1)[-1]}.log"
        try:
            keep.write_text(log_text, encoding="utf-8")
        except OSError:
            keep = None
        return False, f"{reason} ({keep})" if keep else reason, keep


def run_smoke(godot: str, quit_after: int, timeout: int) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="godot-remake-smoke-") as tmpdir:
        log_path = Path(tmpdir) / "godot.log"
        cmd = [
            godot, "--headless",
            "--path", str(PROJECT),
            "--quit-after", str(quit_after),
            "--log-file", str(log_path),
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
            exit_code = proc.returncode
        except subprocess.TimeoutExpired:
            return False, f"wall-clock timeout after {timeout}s"
        log_text = read_log(log_path) if log_path.exists() else ""
        reason = classify_smoke_failure(exit_code, log_text)
        if reason is None:
            return True, ""
        keep = Path(tempfile.gettempdir()) / "godot-remake-smoke-fail.log"
        try:
            keep.write_text(log_text, encoding="utf-8")
            reason = f"{reason} ({keep})"
        except OSError:
            pass
        return False, reason


def main() -> int:
    parser = argparse.ArgumentParser(description="godot_remake cross-platform test runner")
    parser.add_argument("--godot", help="path to the Godot 4.6 binary")
    parser.add_argument("--timeout", type=int, default=WALL_CLOCK_TIMEOUT_DEFAULT,
                        help="wall-clock timeout per scene in seconds (default 900)")
    args = parser.parse_args()

    current = detect_platform()
    if current not in ALLOWED_PLATFORMS:
        print(f"RUNNER FAIL: unsupported platform {sys.platform} (allowed: {ALLOWED_PLATFORMS})")
        return 2

    godot, source = resolve_godot(args.godot)
    if not godot:
        print("RUNNER FAIL: no usable Godot binary found.")
        print("Resolution order: --godot > GODOT_BIN > GODOT_EXE > godot4 > godot.")
        print("Fix, e.g.:   export GODOT_BIN=/usr/local/bin/godot   (Linux)")
        print("          or set GODOT_EXE / pass --godot            (Windows)")
        print("Refusing to fall back to any Windows Godot executable from Linux.")
        return 2

    manifest = load_manifest()
    scenes = manifest.get("scenes", [])
    default_quit = int(manifest.get("default_quit_after", 1200))
    smoke_quit = int(manifest.get("smoke_quit_after", 300))

    version = subprocess.run([godot, "--version"], capture_output=True, text=True)
    print(f"# platform={current} godot={godot} ({source}) version={version.stdout.strip()}")

    total_registered = len(scenes)
    applicable = not_applicable = passed = failed = 0

    for entry in scenes:
        scene = str(entry.get("path", ""))
        platforms = entry.get("platforms", list(ALLOWED_PLATFORMS))
        if current not in platforms:
            not_applicable += 1
            print(f"NOT_APPLICABLE {scene} platform={','.join(platforms)} current={current}")
            continue
        applicable += 1
        quit_after = int(entry.get("quit_after", default_quit))
        print(f"RUN {scene}")
        ok, reason, _ = run_scene(godot, scene, quit_after, args.timeout)
        if ok:
            passed += 1
        else:
            failed += 1
            print(f"FAILED {scene} ({reason})")
            return 1  # fail fast, matching historical runner behaviour

    print("RUN main scene smoke test")
    smoke_ok, smoke_reason = run_smoke(godot, smoke_quit, args.timeout)
    if not smoke_ok:
        failed += 1
        print(f"FAILED main scene smoke test ({smoke_reason})")
        return 1

    print("PASS all automated scenes and main smoke test")
    print(f"# summary: registered={total_registered} applicable={applicable} "
          f"not_applicable={not_applicable} passed={passed} failed={failed} "
          f"(platform={current})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
