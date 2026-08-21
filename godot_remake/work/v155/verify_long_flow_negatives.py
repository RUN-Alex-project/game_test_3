# -*- coding: utf-8 -*-
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(r"E:\deepseek-work\TKS3_mod\godot_remake")
GODOT = os.environ.get(
    "GODOT_EXE",
    r"C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64.exe",
)
SCENE = "res://tests/test_long_flow_v155_scene.tscn"
BAK = ".v155bak"

CASES = [
    ("scripts/long_flow_service.gd", "const REQUIRE_AUDIT := true", "const REQUIRE_AUDIT := false", "BALANCE_AUDIT"),
    ("scripts/long_flow_service.gd", "const REQUIRE_FROZEN := true", "const REQUIRE_FROZEN := false", "VALUE_OVERRIDE"),
    ("scripts/long_flow_service.gd", "const BLOCK_DOUBLE := true", "const BLOCK_DOUBLE := false", "VALUE_DOUBLE"),
    ("scripts/long_flow_service.gd", "const BLOCK_OP_DUP := true", "const BLOCK_OP_DUP := false", "LEDGER_OP_DUP"),
    ("scripts/long_flow_service.gd", "const REQUIRE_LEDGER := true", "const REQUIRE_LEDGER := false", "LEDGER_DIFF"),
    ("scripts/long_flow_service.gd", "const REQUIRE_V21 := true", "const REQUIRE_V21 := false", "SAVE_V21"),
    ("scripts/long_flow_service.gd", "const REQUIRE_V22_TYPE := true", "const REQUIRE_V22_TYPE := false", "SAVE_V22_TYPE"),
    ("scripts/long_flow_service.gd", "const REJECT_FUTURE := true", "const REJECT_FUTURE := false", "SAVE_FUTURE"),
    ("scripts/long_flow_service.gd", "const REQUIRE_ATOMIC := true", "const REQUIRE_ATOMIC := false", "SAVE_ATOMIC"),
    ("scripts/long_flow_service.gd", "const REQUIRE_ALL_FLOWS := true", "const REQUIRE_ALL_FLOWS := false", "FLOW_SKIP"),
    ("scripts/long_flow_service.gd", "const BLOCK_FAKE_TERMINAL := true", "const BLOCK_FAKE_TERMINAL := false", "FLOW_FAKE"),
    ("scripts/long_flow_service.gd", "const BLOCK_SEASON_DUP := true", "const BLOCK_SEASON_DUP := false", "SEASON_DUP"),
    ("scripts/long_flow_service.gd", "const BLOCK_ARBITRAGE := true", "const BLOCK_ARBITRAGE := false", "ARBITRAGE"),
    ("scripts/long_flow_service.gd", "const REQUIRE_NO_LEAK := true", "const REQUIRE_NO_LEAK := false", "OBJECT_LEAK"),
    ("scripts/long_flow_service.gd", "const BLOCK_SKIP := true", "const BLOCK_SKIP := false", "RUNNER_SKIP"),
    ("scripts/long_flow_service.gd", "const REQUIRE_RC := true", "const REQUIRE_RC := false", "RC_HASH"),
    ("scripts/long_flow_service.gd", "const REQUIRE_APP_READY := true", "const REQUIRE_APP_READY := false", "SMOKE_READY"),
    ("scripts/long_flow_service.gd", "const REQUIRE_BASELINE := true", "const REQUIRE_BASELINE := false", "DOC_COUNT"),
    ("scripts/long_flow_service.gd", "const REQUIRE_SAVE_POINTS := true", "const REQUIRE_SAVE_POINTS := false", "FLOW_SAVE"),
    ("scripts/long_flow_service.gd", "const REQUIRE_MATRIX := true", "const REQUIRE_MATRIX := false", "FLOW_SET"),
]


def restore_all():
    for rel, _a, _b, _c in CASES:
        src = ROOT / (rel + BAK)
        dst = ROOT / rel
        if src.exists():
            shutil.copyfile(src, dst)
            src.unlink()


def backup(rel):
    src = ROOT / rel
    bak = ROOT / (rel + BAK)
    if not bak.exists():
        shutil.copyfile(src, bak)


def mutate(rel, old, new):
    p = ROOT / rel
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit("missing marker in %s: %s" % (rel, old))
    p.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def run_scene():
    log_path = Path(tempfile.gettempdir()) / "v155_neg.log"
    if log_path.exists():
        log_path.unlink()
    cmd = [GODOT, "--headless", "--path", str(ROOT), "--scene", SCENE, "--quit-after", "40000", "--log-file", str(log_path)]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, timeout=180)
    body = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    extra = (proc.stdout or b"").decode("utf-8", "replace")
    return proc.returncode, body, extra


def main():
    restore_all()
    passed = 0
    failed = []
    try:
        for rel, old, new, code in CASES:
            restore_all()
            seen = set()
            for r2, _a, _b, _c in CASES:
                if r2 not in seen:
                    backup(r2)
                    seen.add(r2)
            mutate(rel, old, new)
            rc, log, extra = run_scene()
            blob = log + "\n" + extra
            hit = code in blob
            mutated_ok = rc != 0 or "FAIL" in blob
            if hit and mutated_ok:
                print("NEG PASS", code)
                passed += 1
            else:
                print("NEG FAIL", code, "rc", rc)
                print(blob[-1800:])
                failed.append(code)
    finally:
        restore_all()
    print("NEG PASS %d/%d" % (passed, len(CASES)))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
