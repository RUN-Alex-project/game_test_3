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
SCENE = "res://tests/test_season_epilogue_scene.tscn"
BAK = ".v154bak"

CASES = [
    ("scripts/season_cycle_service.gd", "const CYCLE_DAYS := 14", "const CYCLE_DAYS := 13", "SEASON_PERIOD"),
    ("scripts/season_cycle_service.gd", "const ENFORCE_DAY := true", "const ENFORCE_DAY := false", "SEASON_DAY"),
    ("scripts/season_cycle_service.gd", "const SKIP_SAME_DAY := true", "const SKIP_SAME_DAY := false", "SEASON_ROLLOVER"),
    ("scripts/season_cycle_service.gd", "const USE_GAME_DAY := true", "const USE_GAME_DAY := false", "SEASON_CLOCK"),
    ("scripts/season_cycle_service.gd", "const MAX_DAILY_CONTRACTS := 3", "const MAX_DAILY_CONTRACTS := 5", "CONTRACT_CAP"),
    ("scripts/season_cycle_service.gd", "const REQUIRE_SOURCE := true", "const REQUIRE_SOURCE := false", "CONTRACT_SOURCE"),
    ("scripts/season_cycle_service.gd", "const BLOCK_TRAIN_SCORE := true", "const BLOCK_TRAIN_SCORE := false", "SEASON_TRAIN"),
    ("scripts/season_cycle_service.gd", "const SKIP_REWARD_DUP := true", "const SKIP_REWARD_DUP := false", "SEASON_REWARD"),
    ("scripts/season_cycle_service.gd", "const SKIP_REWARD_DUP := true", "const SKIP_REWARD_DUP := false", "CONTRACT_MAIL"),
    ("scripts/season_cycle_service.gd", "const SETTLE_ON_14 := true", "const SETTLE_ON_14 := false", "SEASON_SETTLE"),
    ("scripts/season_cycle_service.gd", "const NEW_SEED_NEXT := true", "const NEW_SEED_NEXT := false", "SEASON_SEED"),
    ("scripts/season_cycle_service.gd", "const HISTORY_CAP := 4", "const HISTORY_CAP := 99", "SEASON_HISTORY"),
    ("scripts/epilogue_event_service.gd", "const BLOCK_DIRECT_REL := true", "const BLOCK_DIRECT_REL := false", "EPILOGUE_REL"),
    ("scripts/epilogue_event_service.gd", "const REQUIRE_FINALE := true", "const REQUIRE_FINALE := false", "EPILOGUE_LOCK"),
    ("scripts/season_cycle_service.gd", "const REQUIRE_RANK_LIVE := true", "const REQUIRE_RANK_LIVE := false", "RANK_TEXT"),
    ("scripts/season_cycle_service.gd", "const REQUIRE_SAVE_ID := true", "const REQUIRE_SAVE_ID := false", "SAVE_SEASON"),
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
    log_path = Path(tempfile.gettempdir()) / "v154_neg.log"
    if log_path.exists():
        log_path.unlink()
    cmd = [GODOT, "--headless", "--path", str(ROOT), "--scene", SCENE, "--quit-after", "30000", "--log-file", str(log_path)]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, timeout=90)
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
                print(blob[-1500:])
                failed.append(code)
    finally:
        restore_all()
    print("NEG PASS %d/%d" % (passed, len(CASES)))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
