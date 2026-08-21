# -*- coding: utf-8 -*-
"""Rebuild Windows release exe/pck then refresh SHA256SUMS + build_manifest hashes."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from datetime import date

ROOT = Path(r"E:\deepseek-work\TKS3_mod\godot_remake")
REL = ROOT / "artifacts" / "releases" / "v1.41"
GODOT = os.environ.get(
    "GODOT_EXE",
    r"C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64.exe",
)
EXE_NAME = "\u9b54\u57df1.03_v1.41.exe"
PCK_NAME = "\u9b54\u57df1.03_v1.41.pck"
EXE = REL / EXE_NAME
PCK = REL / PCK_NAME


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def export_release() -> None:
    out = str(EXE)
    cmd = [GODOT, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop", out]
    print("export", cmd)
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, timeout=600)
    log = (proc.stdout or b"").decode("utf-8", "replace") + "\n" + (proc.stderr or b"").decode("utf-8", "replace")
    print(log[-3000:] if len(log) > 3000 else log)
    if proc.returncode != 0:
        raise SystemExit("export failed rc=%s" % proc.returncode)
    if not EXE.is_file() or not PCK.is_file():
        raise SystemExit("missing exe/pck after export")


def refresh_hashes() -> None:
    mf_path = REL / "build_manifest.json"
    mf = json.loads(mf_path.read_text(encoding="utf-8"))
    mf["godot_version"] = "4.6.3.stable.official.7d41c59c4"
    mf["build_date"] = date.today().isoformat()
    mf["executable_built"] = True
    mf["executable_stale"] = False
    mf["executable_reason"] = "v1.55 balance/long-flow release candidate rebuild"
    mf["executable_hash_sha256"] = sha256(EXE)
    mf["executable_size_bytes"] = EXE.stat().st_size
    mf["pck"]["sha256"] = sha256(PCK)
    mf["pck"]["size_bytes"] = PCK.stat().st_size
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    names = []
    for f in sorted(REL.iterdir()):
        if f.is_file() and f.name != "SHA256SUMS.txt":
            names.append(f.name)
    lines = []
    hashes = {}
    for name in names:
        digest = sha256(REL / name)
        hashes[name] = digest
        lines.append("%s  %s" % (digest, name))
    (REL / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    rc_path = ROOT / "docs" / "release_candidate_manifest_v155.json"
    rc = json.loads(rc_path.read_text(encoding="utf-8"))
    rc["build_date"] = date.today().isoformat()
    rc["executable"] = EXE_NAME
    rc["executable_sha256"] = hashes[EXE_NAME]
    rc["pck_sha256"] = hashes[PCK_NAME]
    rc["executable_size_bytes"] = EXE.stat().st_size
    rc["pck_size_bytes"] = PCK.stat().st_size
    rc_path.write_text(json.dumps(rc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("exe", hashes[EXE_NAME], EXE.stat().st_size)
    print("pck", hashes[PCK_NAME], PCK.stat().st_size)


if __name__ == "__main__":
    export_release()
    refresh_hashes()
    print("rebuild ok")
