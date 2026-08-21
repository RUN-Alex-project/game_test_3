#!/usr/bin/env python3
"""测试前置条件登记表：缺什么、在哪、怎么修的唯一来源。

有三类输入按仓库策略不入库，但部分测试与门禁需要它们：

  swf          原版 Flash 输入（.gitignore 第 23 行有意排除，见该行注释）
  release_dir  Windows 发布目录 artifacts/releases/v1.41/（.gitignore 排除生成产物）
  imported     Godot 导入缓存 .godot/（.gitignore 排除）

tests/test_manifest.json 的场景可声明 requires: ["swf"]；
tools/run_tests.py --only-available 与 tools/preflight.py 共读本模块，
不各写一份判断。

仅使用 Python 标准库。
"""
from __future__ import annotations

from godot_env import EXE_NAME, PCK_NAME, PROJECT, RELEASE_DIR, RELEASE_VERSION, swf_path

# 发布目录被视为已就绪所必需的文件（与 docs/doc_gate.py 的校验对象一致）
RELEASE_REQUIRED_FILES = (
    "build_manifest.json",
    "SHA256SUMS.txt",
    EXE_NAME,
    PCK_NAME,
)


def _swf_ok() -> bool:
    return swf_path().is_file()


def _release_dir_ok() -> bool:
    return all((RELEASE_DIR / name).is_file() for name in RELEASE_REQUIRED_FILES)


def _imported_ok() -> bool:
    return (PROJECT / ".godot").is_dir()


CHECKS = {
    "swf": _swf_ok,
    "release_dir": _release_dir_ok,
    "imported": _imported_ok,
}

TITLES = {
    "swf": "原版 SWF 输入",
    "release_dir": "Windows 发布目录 " + RELEASE_VERSION,
    "imported": "Godot 导入缓存",
}


def location(key: str) -> str:
    if key == "swf":
        return str(swf_path())
    if key == "release_dir":
        return str(RELEASE_DIR)
    if key == "imported":
        return str(PROJECT / ".godot")
    return ""


def remedy(key: str) -> str:
    if key == "swf":
        return (
            "原版 SWF 按仓库策略不入库。把它放到仓库根，或设 MOYU_SWF_PATH 指向它。"
            "只影响 test_native_timeline_registry_scene 与 "
            "test_combat_feedback_sequence_scene 两个场景。"
        )
    if key == "release_dir":
        return (
            "发布产物不入库。先跑 python work/v155/rebuild_release.py 重建 exe/pck 并刷新 "
            "build_manifest.json 与 SHA256SUMS.txt。doc_gate、release_gate 与 "
            "test_release_candidate_scene 都依赖它。"
        )
    if key == "imported":
        return "先跑一次 godot --headless --path . --import 生成导入缓存（首次克隆后必需）。"
    return ""


def is_available(key: str) -> bool:
    check = CHECKS.get(key)
    if check is None:
        # 未登记的 requires 值一律视为不满足，避免拼写错误被静默当成已就绪
        return False
    return check()


def missing_prerequisites(requires) -> list[str]:
    """返回 requires 中当前环境不满足的前置条件键，保持声明顺序。"""
    return [str(key) for key in (requires or []) if not is_available(str(key))]


def known_keys() -> tuple[str, ...]:
    return tuple(CHECKS.keys())