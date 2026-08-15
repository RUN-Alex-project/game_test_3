# res:// 资源引用大小写审计（Linux 大小写敏感文件系统专项门禁）。
#
# 规则：
#   1. 以 git tracked 文件列表构造大小写敏感路径集合；
#   2. 扫描生产与测试代码（scripts/ scenes/ tests/ data/ *.godot/*.gd/*.tscn/*.tres/*.json）
#      中的静态 res:// 引用；
#   3. 引用必须与真实 tracked/文件系统路径大小写完全一致；
#   4. 大小写不匹配 -> ERROR（非 0 退出），输出 源文件:行号 引用路径 实际路径；
#   5. 引用不存在的路径：已知负向测试夹具（故意不存在的文件）列入允许清单；
#      其余静态可判定缺失 -> ERROR；动态拼接路径不在此工具范围（warning 不阻断）。
#
# 仅使用 Python 标准库；Windows/Linux 均可运行。
import argparse
import re
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT = TOOLS_DIR.parent                 # godot_remake/
REPO = PROJECT.parent                      # 仓库根（.git 所在）

SCAN_DIRS = ("scripts", "scenes", "tests", "data")
SCAN_EXTS = {".gd", ".tscn", ".tres", ".json", ".godot", ".cfg"}

# 负向测试夹具：代码故意引用不存在的文件来验证错误处理（逐项人工确认，禁止批量放行）
ALLOWED_MISSING = {
    "res://docs/evidence/does_not_exist.txt",
}

RES_RE = re.compile(r"res://([A-Za-z0-9_\-\./一-鿿]+)")


def git_tracked() -> set[str]:
    out = subprocess.run(
        ["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout
    return set(out.splitlines())


def build_index(tracked: set[str]) -> tuple[set[str], dict[str, list[str]]]:
    rel_prefix = PROJECT.name + "/"          # godot_remake/
    gr_tracked = {t[len(rel_prefix):]: t for t in tracked if t.startswith(rel_prefix)}
    exact = set(gr_tracked)
    lower: dict[str, list[str]] = {}
    for rel in exact:
        lower.setdefault(rel.lower(), []).append(rel)
    return exact, lower


def scan_file(path: Path) -> list[tuple[int, str]]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    hits = []
    for m in RES_RE.finditer(text):
        line_no = text[: m.start()].count("\n") + 1
        hits.append((line_no, m.group(1)))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    tracked = git_tracked()
    exact, lower = build_index(tracked)

    case_errors: list[str] = []
    missing_errors: list[str] = []
    dynamic_warn = 0
    checked = 0

    for sub in SCAN_DIRS:
        base = PROJECT / sub
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix.lower() not in SCAN_EXTS:
                continue
            checked += 1
            for line_no, ref in scan_file(p):
                res_path = "res://" + ref
                if ref in exact:
                    continue
                # 未跟踪但文件系统真实存在（大小写精确）则放行
                if (PROJECT / ref).is_file():
                    continue
                # 目录引用（DirAccess 枚举等）：大小写精确匹配即放行
                if (PROJECT / ref).is_dir():
                    continue
                if ref.lower() in lower:
                    actual = lower[ref.lower()]
                    case_errors.append(
                        f"{p.relative_to(PROJECT).as_posix()}:{line_no} "
                        f"res://{ref} -> 实际: {actual}"
                    )
                    continue
                # 大小写不敏感文件系统探测（未跟踪文件/目录；仅真实大小写差异才报错）
                fpath = PROJECT / ref
                parent, fname = fpath.parent, fpath.name
                if parent.is_dir():
                    cand = [q.name for q in parent.iterdir() if q.name.lower() == fname.lower()]
                    if len(cand) == 1 and cand[0] != fname:
                        case_errors.append(
                            f"{p.relative_to(PROJECT).as_posix()}:{line_no} "
                            f"res://{ref} -> 实际: {parent.relative_to(PROJECT).as_posix()}/{cand[0]}"
                        )
                        continue
                # 无扩展名动态解析（res://tests/foo -> foo.tscn/gd/tres）
                if any((PROJECT / (ref + ext)).is_file() for ext in (".tscn", ".gd", ".tres")):
                    dynamic_warn += 1
                    continue
                if res_path in ALLOWED_MISSING:
                    continue
                missing_errors.append(
                    f"{p.relative_to(PROJECT).as_posix()}:{line_no} res://{ref} 文件不存在"
                )

    print(f"RESOURCE_CASE checked_files={checked} case_mismatches={len(case_errors)} "
          f"missing={len(missing_errors)} dynamic_ok={dynamic_warn}")
    for e in case_errors:
        print(f"CASE_ERROR {e}")
    for e in missing_errors:
        print(f"MISSING_ERROR {e}")
    if case_errors or missing_errors:
        print("RESOURCE_CASE FAIL")
        return 1
    print("RESOURCE_CASE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
