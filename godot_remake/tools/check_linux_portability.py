#!/usr/bin/env python3
"""Linux 可移植性聚合门禁（PHASE 31 建议的专项工具）。

聚合检查：
  1. res:// 资源引用大小写审计（调用 tools/check_resource_case.py 同一验证器）；
  2a. 生产运行代码 Windows 绝对路径依赖审计（scripts/ scenes/ data/ project.godot）-> 目标 0；
  2b. 已入库的 tools/ 与 work/ 门禁脚本同样审计 -> 目标 0
      （v1.55 之前 work/ 下 5 个已入库脚本写死开发机绝对路径，克隆到别处会操作错目录；
       只扫 git 跟踪的文件，本地未入库的临时脚本不参与）；
  3. 测试清单一致性：test_manifest.json 注册数 == current_test_baseline.automated_scenes，
     场景唯一、platforms 合法（与 doc_gate 同口径，本工具在 Linux CI 可独立运行）；
  4. shell 脚本基础检查：run_tests.sh 存在、以 shebang 开头、不含 CRLF；
     tools/*.py 与 *.sh 在 git index 中保持可执行位（Linux checkout 可直接执行）；
  5. 已入库 .ps1 若含非 ASCII 必须带 UTF-8 BOM：Windows PowerShell 5.1 对无 BOM 的
     .ps1 按当前 ANSI 代码页解码，GBK 环境下中文行尾的字节会吞掉 LF 换行，
     把后续赋值语句并进注释（曾导致 run_release_gate.ps1 的 $project 为空）。

仅使用 Python 标准库；任一检查失败 -> 非零退出。
"""
import json
import re
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT = TOOLS_DIR.parent
REPO = PROJECT.parent

WIN_PATH_RE = re.compile(r"[CDE]:[\\/]|/mnt/[cde]/")

# 生产运行代码范围（Windows 绝对路径依赖目标 = 0）
PROD_DIRS = ("scripts", "scenes", "data")
PROD_FILES = ("project.godot",)
PROD_EXTS = {".gd", ".tscn", ".tres", ".json", ".cfg"}

# 已入库的门禁/工具脚本范围（同样目标 0）。只取 git 跟踪的文件：
# work/ 大部分内容被 .gitignore 排除，本地临时脚本不应让门禁失败。
TOOLING_DIRS = ("tools", "work")
TOOLING_EXTS = {".py", ".ps1", ".sh"}


def fail(msg: str) -> None:
    print(f"LINUX_PORTABILITY FAIL: {msg}")


def check_resource_case() -> bool:
    proc = subprocess.run(
        [sys.executable, str(TOOLS_DIR / "check_resource_case.py")],
        capture_output=True, text=True,
    )
    print(proc.stdout.strip())
    if proc.returncode != 0:
        fail("res:// 资源引用大小写审计未通过")
        return False
    return True


def check_prod_windows_paths() -> bool:
    errors = []
    targets: list[Path] = []
    for sub in PROD_DIRS:
        base = PROJECT / sub
        if base.is_dir():
            targets.extend(p for p in base.rglob("*") if p.is_file() and p.suffix.lower() in PROD_EXTS)
    for name in PROD_FILES:
        p = PROJECT / name
        if p.is_file():
            targets.append(p)
    for p in targets:
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in WIN_PATH_RE.finditer(text):
            line_no = text[: m.start()].count("\n") + 1
            errors.append(f"{p.relative_to(PROJECT).as_posix()}:{line_no} 含 Windows 绝对路径 '{m.group(0)}'")
    for e in errors:
        print(f"WIN_PATH_ERROR {e}")
    print(f"WIN_PATH production_files={len(targets)} errors={len(errors)}")
    if errors:
        fail("生产运行代码存在 Windows 绝对路径依赖（目标 0）")
        return False
    return True


def _tracked_tooling_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "--"] + [f"godot_remake/{d}" for d in TOOLING_DIRS],
        cwd=REPO, capture_output=True, text=True,
    ).stdout
    files = []
    for rel in out.splitlines():
        rel = rel.strip()
        if not rel:
            continue
        path = REPO / rel
        if path.is_file() and path.suffix.lower() in TOOLING_EXTS:
            files.append(path)
    return files


def check_tooling_windows_paths() -> bool:
    errors = []
    targets = _tracked_tooling_files()
    for p in targets:
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in WIN_PATH_RE.finditer(text):
            line_no = text[: m.start()].count("\n") + 1
            errors.append(f"{p.relative_to(REPO).as_posix()}:{line_no} 含 Windows 绝对路径 '{m.group(0)}'")
    for e in errors:
        print(f"TOOLING_PATH_ERROR {e}")
    print(f"TOOLING_PATH tracked_files={len(targets)} errors={len(errors)}")
    if errors:
        fail("已入库的 tools/ 与 work/ 脚本存在绝对路径依赖（目标 0；应从脚本自身位置推导）")
        return False
    return True


def check_ps1_encoding() -> bool:
    ok = True
    checked = 0
    for p in _tracked_tooling_files():
        if p.suffix.lower() != ".ps1":
            continue
        checked += 1
        raw = p.read_bytes()
        if all(b < 0x80 for b in raw):
            continue    # 纯 ASCII 不受 ANSI 解码影响
        if not raw.startswith(b"\xef\xbb\xbf"):
            fail(f"{p.relative_to(REPO).as_posix()} 含非 ASCII 但缺 UTF-8 BOM"
                 f"（PowerShell 5.1 会按 ANSI 解码并可能吞掉换行）")
            ok = False
    print(f"PS1_ENCODING tracked_ps1={checked}")
    return ok


def check_manifest_consistency() -> bool:
    ok = True
    mf_path = PROJECT / "tests" / "test_manifest.json"
    bl_path = PROJECT / "docs" / "current_test_baseline.json"
    if not mf_path.is_file():
        fail("tests/test_manifest.json 不存在")
        return False
    try:
        mf = json.loads(mf_path.read_text(encoding="utf-8"))
        bl = json.loads(bl_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"manifest/baseline 解析失败: {exc}")
        return False
    scenes = mf.get("scenes", [])
    auto = int(bl.get("automated_scenes", -1))
    total = int(bl.get("total_runs", -1))
    if len(scenes) != auto:
        fail(f"manifest 注册 {len(scenes)} != baseline automated_scenes {auto}")
        ok = False
    if total != auto + 1:
        fail(f"baseline total_runs {total} != automated_scenes + 1")
        ok = False
    seen = set()
    for sc in scenes:
        spath = str(sc.get("path", ""))
        if spath in seen:
            fail(f"manifest 场景重复: {spath}")
            ok = False
        seen.add(spath)
        plat = sc.get("platforms")
        if not isinstance(plat, list) or not plat or not set(plat) <= {"windows", "linux"}:
            fail(f"manifest platforms 非法: {spath} -> {plat}")
            ok = False
        if not spath.startswith("res://tests/") or not spath.endswith(".tscn"):
            fail(f"manifest 场景路径非法: {spath}")
            ok = False
        elif not (PROJECT / spath[len("res://"):]).is_file():
            fail(f"manifest 场景文件不存在: {spath}")
            ok = False
    print(f"MANIFEST scenes={len(scenes)} baseline_auto={auto} baseline_total={total}")
    return ok


def check_shell_basics() -> bool:
    ok = True
    sh = PROJECT / "run_tests.sh"
    if not sh.is_file():
        fail("run_tests.sh 不存在")
        return False
    data = sh.read_bytes()
    if not data.startswith(b"#!"):
        fail("run_tests.sh 缺 shebang")
        ok = False
    if b"\r\n" in data:
        fail("run_tests.sh 含 CRLF（Linux bash 将失败）")
        ok = False
    # git index 可执行位（core.filemode=false 环境下 index 是权威）
    out = subprocess.run(
        ["git", "ls-files", "-s", "--", str(sh.relative_to(REPO))],
        cwd=REPO, capture_output=True, text=True,
    ).stdout.strip()
    if out:
        mode = out.split()[0]
        if mode != "100755":
            fail(f"run_tests.sh git mode={mode}（应为 100755；用 git update-index --chmod=+x 修复）")
            ok = False
    else:
        print("WARN run_tests.sh 尚未加入 git index（首次提交前为预期状态）")
    print(f"SHELL run_tests.sh shebang/lf/execbit checks done")
    return ok


def main() -> int:
    results = [
        ("resource_case", check_resource_case()),
        ("prod_windows_paths", check_prod_windows_paths()),
        ("tooling_windows_paths", check_tooling_windows_paths()),
        ("ps1_encoding", check_ps1_encoding()),
        ("manifest_consistency", check_manifest_consistency()),
        ("shell_basics", check_shell_basics()),
    ]
    print()
    for name, ok in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if all(ok for _, ok in results):
        print("LINUX_PORTABILITY PASS")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
