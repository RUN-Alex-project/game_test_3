# -*- coding: utf-8 -*-
"""重建 Windows 发布产物：导出 exe/pck，然后刷新 build_manifest.json 与 SHA256SUMS.txt。

发布目录里的三份文档（最终交付报告 / 已知问题 / 试玩验收清单）是内容，已入库；
exe、pck、build_manifest.json、SHA256SUMS.txt 是派生产物，不入库，由本脚本生成。
因此在干净克隆上本脚本必须能从零创建 build_manifest.json，而不是只刷新已有文件。
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from datetime import date

ROOT = Path(__file__).resolve().parents[2]      # godot_remake/
sys.path.insert(0, str(ROOT / "tools"))
from godot_env import EXE_NAME, PCK_NAME, RELEASE_VERSION, resolve_godot  # noqa: E402

REL = ROOT / "artifacts" / "releases" / RELEASE_VERSION
EXE = REL / EXE_NAME
PCK = REL / PCK_NAME

GODOT, _GODOT_SOURCE = resolve_godot()
if not GODOT:
    raise SystemExit(
        "no usable Godot binary found. Resolution order: GODOT_BIN > GODOT_EXE > godot4 > godot"
    )

# 发布目录里已入库的内容文档；缺任何一份都说明克隆不完整，不能靠本脚本生成。
CONTENT_DOCS = (
    "已知问题_" + RELEASE_VERSION + ".md",
    "最终交付报告_" + RELEASE_VERSION + ".md",
    "试玩验收清单_" + RELEASE_VERSION + ".md",
)

# build_manifest.json 的静态骨架；哈希/尺寸/日期由 refresh_hashes 填。
MANIFEST_SKELETON = {
    "release": RELEASE_VERSION,
    "godot_version": "",
    "build_date": "",
    "main_scene": "res://scenes/main.tscn",
    "executable": EXE_NAME,
    "executable_built": True,
    "executable_stale": False,
    "executable_reason": "local rebuild via work/v155/rebuild_release.py",
    "artifacts": [
        "build_manifest.json",
        CONTENT_DOCS[0],
        CONTENT_DOCS[1],
        CONTENT_DOCS[2],
        EXE_NAME,
        PCK_NAME,
    ],
    "excluded": [
        "savegame.json",
        "测试临时存档",
        "私有日志",
        "开发缓存",
    ],
    "executable_hash_sha256": "",
    "executable_size_bytes": 0,
    "pck": {
        "file": PCK_NAME,
        "size_bytes": 0,
        "sha256": "",
        "embedded": False,
    },
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def release_file_names() -> list[str]:
    """发布目录实际文件名（SHA256SUMS.txt 自身不登记自己）。"""
    return sorted(f.name for f in REL.iterdir() if f.is_file() and f.name != "SHA256SUMS.txt")


def check_content_docs() -> None:
    missing = [name for name in CONTENT_DOCS if not (REL / name).is_file()]
    if missing:
        raise SystemExit(
            "发布目录缺少已入库的内容文档 %s；请确认克隆完整（这些文件不由本脚本生成）"
            % ", ".join(missing)
        )


def godot_version_string() -> str:
    proc = subprocess.run([GODOT, "--version"], capture_output=True, text=True, timeout=60)
    return (proc.stdout or "").strip()


def export_release() -> None:
    REL.mkdir(parents=True, exist_ok=True)
    cmd = [GODOT, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop", str(EXE)]
    print("export", cmd)
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, timeout=1800)
    log = (proc.stdout or b"").decode("utf-8", "replace") + "\n" + (proc.stderr or b"").decode("utf-8", "replace")
    print(log[-3000:] if len(log) > 3000 else log)
    if proc.returncode != 0:
        raise SystemExit("export failed rc=%s" % proc.returncode)
    if not EXE.is_file() or not PCK.is_file():
        raise SystemExit("missing exe/pck after export")


def refresh_hashes() -> None:
    mf_path = REL / "build_manifest.json"
    if mf_path.is_file():
        mf = json.loads(mf_path.read_text(encoding="utf-8"))
    else:
        print("build_manifest.json 不存在，按骨架新建")
        mf = json.loads(json.dumps(MANIFEST_SKELETON))
    mf["godot_version"] = godot_version_string()
    mf["build_date"] = date.today().isoformat()
    mf["executable_built"] = True
    mf["executable_stale"] = False
    mf["executable_hash_sha256"] = sha256(EXE)
    mf["executable_size_bytes"] = EXE.stat().st_size
    mf["pck"]["sha256"] = sha256(PCK)
    mf["pck"]["size_bytes"] = PCK.stat().st_size

    # artifacts 必须与目录实际文件集双向相等（docs/doc_gate.py 会校验）。
    # 先写一次让 build_manifest.json 自身存在，再按实际目录重算 artifacts 写第二次——
    # 否则首次在空目录上重建时，artifacts 会漏掉 build_manifest.json 自己。
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    mf["artifacts"] = release_file_names()
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # SHA256SUMS 必须在 manifest 定稿之后再写，否则 manifest 自身的哈希会过期。
    names = release_file_names()
    lines = []
    hashes = {}
    for name in names:
        digest = sha256(REL / name)
        hashes[name] = digest
        lines.append("%s  %s" % (digest, name))
    (REL / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    rc_path = ROOT / "docs" / "release_candidate_manifest_v155.json"
    if rc_path.is_file():
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
    check_content_docs()
    export_release()
    refresh_hashes()
    print("rebuild ok")