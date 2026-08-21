#!/usr/bin/env python3
"""工程根定位与 Godot 可执行文件解析的唯一来源。

tools/run_tests.py、tools/preflight.py 与 work/ 下的门禁脚本共用本模块。
在此之前 work/ 下 5 个已入库脚本各自写死开发机绝对路径，
克隆到其它路径后会去操作原开发机路径而不是当前工作树。

仅使用 Python 标准库。
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT = TOOLS_DIR.parent                 # godot_remake/
REPO = PROJECT.parent                      # 仓库根（原版 SWF 所在层级）

RELEASE_VERSION = "v1.41"
RELEASE_DIR = PROJECT / "artifacts" / "releases" / RELEASE_VERSION

# 原版 SWF 文件名。MOYU_SWF_PATH 优先，否则取仓库根同名文件，与
# test_native_timeline_registry_scene / test_combat_feedback_sequence_scene
# 的 _swf_path() 同口径。
SWF_NAME = "魔域1.03_v9.swf"

EXE_NAME = "魔域1.03_v1.41.exe"
PCK_NAME = "魔域1.03_v1.41.pck"

ALLOWED_PLATFORMS = ("windows", "linux")


def detect_platform() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform.startswith("linux"):
        return "linux"
    return "unknown"


def resolve_godot(arg_godot: str | None = None) -> tuple[str | None, str]:
    """解析 godot 可执行文件。优先级：--godot > GODOT_BIN > GODOT_EXE > godot4 > godot。

    返回 (路径, 来源说明)；找不到时返回 (None, "")。
    不做版本校验：校验属于 tools/preflight.py 的职责。
    """
    candidates: list[tuple[str, str]] = []
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


def godot_version(godot: str, timeout: int = 60) -> str | None:
    """返回 `godot --version` 的版本串；无法执行或输出为空时返回 None。

    0 字节的包管理器符号链接能通过 isfile 检查却跑不出版本，
    必须真实执行一次才能识别。
    """
    try:
        proc = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    version = (proc.stdout or "").strip()
    return version or None


def swf_path() -> Path:
    env_path = os.environ.get("MOYU_SWF_PATH")
    if env_path:
        return Path(env_path)
    return REPO / SWF_NAME