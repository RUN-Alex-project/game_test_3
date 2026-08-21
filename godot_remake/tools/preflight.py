#!/usr/bin/env python3
"""克隆后的环境前置检查：明确报出缺什么、在哪、怎么补、能跑到什么程度。

背景：仓库按策略不入库三类输入（原版 SWF、Windows 发布产物、Godot 导入缓存），
直接在干净克隆上跑 tools/run_tests.py 或 docs/doc_gate.py 会以
"No loader found for resource" / "SHA256SUMS.txt 不存在" 这类难以定位的错误失败。
本工具把这些前置一次性讲清楚。

退出码：
  0  默认模式下全部前置齐全（可跑完整门禁）；--for-available 模式下可跑部分场景
  1  前置缺失
  2  环境不可用（平台不支持 / 找不到 Godot / Godot 跑不出版本）

仅使用 Python 标准库。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from godot_env import (  # noqa: E402
    ALLOWED_PLATFORMS,
    PROJECT,
    detect_platform,
    godot_version,
    resolve_godot,
)
from prereqs import (  # noqa: E402
    TITLES,
    is_available,
    known_keys,
    location,
    missing_prerequisites,
    remedy,
)

MANIFEST_PATH = PROJECT / "tests" / "test_manifest.json"
BASELINE_PATH = PROJECT / "docs" / "current_test_baseline.json"

# 工程要求 Godot 4.6.x（docs/linux_wsl_port.md 第 4 节）
EXPECTED_GODOT_PREFIX = "4.6."

# 完整门禁需要的前置（部分运行只需要 imported）
FULL_GATE_KEYS = ("imported", "swf", "release_dir")
AVAILABLE_RUN_KEYS = ("imported",)


def line(status: str, title: str, detail: str = "") -> None:
    print(f"[{status}] {title}" + (f"  {detail}" if detail else ""))


def check_python() -> bool:
    ok = sys.version_info >= (3, 10)
    line("PASS" if ok else "FAIL", "Python", sys.version.split()[0])
    if not ok:
        print("       修法：需要 Python 3.10+（runner 与工具仅用标准库，无 pip 依赖）。")
    return ok


def check_godot(arg_godot: str | None) -> tuple[bool, str | None]:
    godot, source = resolve_godot(arg_godot)
    if not godot:
        line("FAIL", "Godot", "未找到")
        print("       解析顺序：--godot > GODOT_BIN > GODOT_EXE > godot4 > godot")
        print("       修法：Windows 设 GODOT_EXE 指向真实 exe；Linux 设 GODOT_BIN。")
        return False, None
    version = godot_version(godot)
    if not version:
        line("FAIL", "Godot", f"{godot}（{source}）跑不出版本")
        print("       修法：该路径可能是 0 字节符号链接或快捷方式，请指向真实可执行文件。")
        return False, godot
    ok = version.startswith(EXPECTED_GODOT_PREFIX)
    line("PASS" if ok else "WARN", "Godot", f"{version}（{source}）")
    print(f"       {godot}")
    if not ok:
        print(f"       注意：工程要求 {EXPECTED_GODOT_PREFIX}x，当前 {version}。")
    return True, godot


def check_prereqs() -> dict:
    results = {}
    for key in known_keys():
        available = is_available(key)
        results[key] = available
        line("PASS" if available else "FAIL", TITLES[key], location(key))
        if not available:
            print(f"       修法：{remedy(key)}")
    return results


def report_affected_scenes() -> int:
    if not MANIFEST_PATH.is_file():
        line("FAIL", "测试清单", f"{MANIFEST_PATH} 不存在")
        return -1
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    scenes = manifest.get("scenes", [])
    current = detect_platform()
    blocked = []
    for entry in scenes:
        path = str(entry.get("path", ""))
        platforms = entry.get("platforms", list(ALLOWED_PLATFORMS))
        if current not in platforms:
            continue
        missing = missing_prerequisites(entry.get("requires", []))
        if missing:
            blocked.append((path, missing))
    print()
    if blocked:
        print(f"因前置缺失而无法运行的场景（{len(blocked)} 个）：")
        for path, missing in blocked:
            print(f"  {path}  缺 {','.join(missing)}")
    else:
        print("所有本平台场景的前置均已满足。")
    return len(blocked)


def main() -> int:
    parser = argparse.ArgumentParser(description="godot_remake 环境前置检查")
    parser.add_argument("--godot", help="Godot 4.6 可执行文件路径")
    parser.add_argument("--for-available", action="store_true",
                        help="只要求能跑 run_tests.py --only-available 的前置"
                             "（不要求原版 SWF 与发布目录）")
    args = parser.parse_args()

    current = detect_platform()
    print(f"PREFLIGHT {PROJECT}  platform={current}")
    print()

    if current not in ALLOWED_PLATFORMS:
        line("FAIL", "平台", f"{sys.platform} 不受支持（允许 {ALLOWED_PLATFORMS}）")
        return 2

    python_ok = check_python()
    godot_ok, _ = check_godot(args.godot)
    print()
    prereqs = check_prereqs()
    blocked = report_affected_scenes()

    required_keys = AVAILABLE_RUN_KEYS if args.for_available else FULL_GATE_KEYS
    missing = [k for k in required_keys if not prereqs.get(k, False)]

    print()
    if not python_ok or not godot_ok:
        print("PREFLIGHT FAIL: Python 或 Godot 不可用，先解决上面标 FAIL 的项。")
        return 2
    if missing:
        mode = "部分运行（--only-available）" if args.for_available else "完整门禁"
        print(f"PREFLIGHT FAIL: {mode} 缺 {','.join(missing)}。")
        if not args.for_available:
            print("           想先跑能跑的部分：python tools/preflight.py --for-available")
            print("           然后：python tools/run_tests.py --only-available")
        return 1
    if args.for_available:
        note = f"（{blocked} 个场景会被 PREREQ_MISSING 跳过）" if blocked > 0 else "（无场景被跳过）"
        print(f"PREFLIGHT PASS: 可运行 python tools/run_tests.py --only-available {note}")
        return 0
    print("PREFLIGHT PASS: 可运行完整门禁 —— python tools/run_tests.py、"
          "python docs/doc_gate.py、work/run_release_gate.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())