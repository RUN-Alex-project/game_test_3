# -*- coding: utf-8 -*-
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]      # godot_remake/
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import resolve_godot  # noqa: E402

GODOT, _GODOT_SOURCE = resolve_godot()
if not GODOT:
    raise SystemExit(
        "no usable Godot binary found. Resolution order: GODOT_BIN > GODOT_EXE > godot4 > godot"
    )
SCENE = "res://tests/test_pet_endgame_scene.tscn"
BAK = ".v153bak"

CASES = [
    ("scripts/pet_collection_service.gd", "const VALIDATE_CATALOG := true", "const VALIDATE_CATALOG := false", "PET_COLLECTION_DUP"),
    ("scripts/pet_collection_service.gd", "if not by_id.has(collection_id):", "if false and not by_id.has(collection_id):", "PET_COLLECTION_UNKNOWN"),
    ("scripts/pet_collection_service.gd", "const REQUIRE_REAL_OWNED := true", "const REQUIRE_REAL_OWNED := false", "PET_COLLECTION_FAKE"),
    ("scripts/pet_collection_service.gd", "const SKIP_REWARD_DUP := true", "const SKIP_REWARD_DUP := false", "PET_COLLECTION_REWARD_DUP"),
    ("scripts/pet_support_service.gd", "const REQUIRE_OWNED := true", "const REQUIRE_OWNED := false", "PET_SUPPORT_OWNED"),
    ("scripts/pet_support_service.gd", "const BLOCK_DEPLOYED := true", "const BLOCK_DEPLOYED := false", "PET_SUPPORT_DEPLOYED"),
    ("scripts/pet_support_service.gd", "const REQUIRE_ONE_SLOT := true", "const REQUIRE_ONE_SLOT := false", "PET_SUPPORT_SECOND"),
    ("scripts/pet_support_service.gd", "const APPLY_ONLY_TRIAL := true", "const APPLY_ONLY_TRIAL := false", "PET_SUPPORT_SCENE"),
    ("scripts/pet_support_service.gd", "const REQUIRE_SNAPSHOT := true", "const REQUIRE_SNAPSHOT := false", "PET_SUPPORT_SNAPSHOT"),
    ("scripts/pet_trial_service.gd", "const REQUIRE_VICTORY := true", "const REQUIRE_VICTORY := false", "PET_TRIAL_CANCEL"),
    ("scripts/pet_trial_service.gd", "const SKIP_WEEKLY_DUP := true", "const SKIP_WEEKLY_DUP := false", "PET_TRIAL_WEEKLY_DUP"),
    ("scripts/pet_trial_service.gd", "const REQUIRE_PREREQ := true", "const REQUIRE_PREREQ := false", "PET_TRIAL_KING"),
    ("scripts/research_contract_service.gd", "const REQUIRE_COST := true", "const REQUIRE_COST := false", "RESEARCH_CONTRACT_COST"),
    ("scripts/pet_support_service.gd", "const REQUIRE_SAVE_ID := true", "const REQUIRE_SAVE_ID := false", "SAVE_PET_ID"),
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
    log_path = Path(tempfile.gettempdir()) / "v153_neg.log"
    if log_path.exists():
        log_path.unlink()
    cmd = [GODOT, "--headless", "--path", str(ROOT), "--scene", SCENE, "--quit-after", "20000", "--log-file", str(log_path)]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=120)
    body = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return proc.returncode, body, proc.stdout + proc.stderr


def main():
    restore_all()
    for rel, _a, _b, _c in CASES:
        backup(rel)
    passed = 0
    failed = []
    try:
        for rel, old, new, code in CASES:
            restore_all()
            for r2, _a, _b, _c in CASES:
                backup(r2)
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
                print(blob[-2000:])
                failed.append(code)
    finally:
        restore_all()
    print("NEG PASS %d/%d" % (passed, len(CASES)))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
