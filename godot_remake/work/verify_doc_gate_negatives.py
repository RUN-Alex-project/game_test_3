#!/usr/bin/env python3
"""PM 第三轮拒签修复：doc_gate 数量负向验证（编码兼容 + try/finally 异常清理）。

在未设置 PYTHONIOENCODING 的默认 Windows 环境中可直接运行并输出 NEG_ALL_PASS：
- run_gate(): 子进程显式 PYTHONIOENCODING=utf-8 + PYTHONUTF8=1（不依赖父进程编码），
  capture 输出按 utf-8 + errors="replace" 容错解码；
- mutate_negative(): 每个变异（N1/N2/N3a/N3b）用 try/finally 恢复原文件，
  即使门禁进程异常/编码异常也必然恢复；
- 末尾断言：无 .bak、无变异标记、runner 数量=65、README 恢复、doc_gate PASS。
"""
import subprocess, sys, os, io, re, glob, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)


def run_gate():
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    r = subprocess.run(
        [sys.executable, "docs/doc_gate.py"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
    )
    return r.returncode, r.stdout


def mutate_negative(path, mutate, expect_substr, label):
    """备份 -> 变异 -> 门禁必须 FAIL 且命中 expect_substr -> finally 恢复原文件。"""
    bak = path + ".bak"
    ok = False
    try:
        shutil.copyfile(path, bak)
        s = io.open(path, encoding="utf-8").read()
        mutated = mutate(s)
        io.open(path, "w", encoding="utf-8").write(mutated)
        rc, out = run_gate()
        intercepted = (rc != 0) and (expect_substr in out)
        if intercepted:
            hit = [l for l in out.splitlines() if expect_substr in l][:1]
            print(f"{label} OK: 被拦截 -> {hit}")
            ok = True
        else:
            print(f"{label} FAIL: 未被拦截 (rc={rc} out={out[:120]!r})")
    except Exception as e:
        print(f"{label} ERROR: {type(e).__name__}: {e}")
    finally:
        if os.path.exists(bak):
            shutil.copyfile(bak, path)
            os.remove(bak)
    return ok


failures = 0

# N1: README 把总数误写为旧总数 66（错误口径，当前应为 67）→ 必须失败
if not mutate_negative(
        "README.md",
        lambda s: s.replace("共 67 RUN", "共 66 RUN"),
        "旧总数 66", "N1"):
    failures += 1

# N2: README 缺 "66 个自动化场景"（当前口径）→ 必须失败
if not mutate_negative(
        "README.md",
        lambda s: s.replace("66 个自动化场景", "六十六个自动化场景"),
        "缺少当前测试口径", "N2"):
    failures += 1

# N3a: runner 场景数 67（插入假场景）→ 必须失败
if not mutate_negative(
        "run_tests.ps1",
        lambda s: s.replace(
            '    "res://tests/test_release_candidate_scene.tscn",',
            '    "res://tests/test_release_candidate_scene.tscn",\n    "res://tests/ZZZ_FAKE_SCENE.tscn",'),
        "实际 67 个", "N3a"):
    failures += 1

# N3b: runner 场景数 65（删除一个场景）→ 必须失败
if not mutate_negative(
        "run_tests.ps1",
        lambda s: s.replace('    "res://tests/ui_audit/test_ui_panel_bounds_scene.tscn",\n', ''),
        "实际 65 个", "N3b"):
    failures += 1

# ---- 末尾断言：无 .bak / 变异文件 / 临时目录残留 ----
def _scan_temp_dirs():
    """真实扫描本仓库相关临时目录：项目根 + 系统 TEMP + Godot user://rc_tmp。"""
    found = []
    # 1) 项目根：.gate_tmp* / rc_tmp* / smoke-tmp-* 等目录（防御模式）
    for pat in [".gate_tmp*", "rc_tmp*", "smoke-tmp-*", "*_tmp_*"]:
        found += [p for p in glob.glob(os.path.join(ROOT, pat)) if os.path.isdir(p)]
    # 2) 系统 TEMP：smoke-tmp-* / gate_tmp* / rc_tmp* 目录（只扫目录，不扫按设计保留的冒烟日志文件）
    tmp = os.environ.get("TEMP") or os.environ.get("TMP")
    if tmp:
        for pat in ["smoke-tmp-*", "gate_tmp*", "rc_tmp*"]:
            found += [p for p in glob.glob(os.path.join(tmp, pat)) if os.path.isdir(p)]
    # 3) Godot user://rc_tmp（本项目的用户数据目录）
    ud = os.environ.get("APPDATA")
    if ud:
        rc = os.path.join(ud, "Godot", "app_userdata", "魔域 1.03 Godot 重制", "rc_tmp")
        if os.path.exists(rc):
            found.append(rc)
    return sorted(set(found))

residue = []
for b in sorted(glob.glob("*.bak") + glob.glob("**/*.bak", recursive=True)):
    residue.append(b)
residue += _scan_temp_dirs()
runner = io.open("run_tests.ps1", encoding="utf-8").read()
if "ZZZ_FAKE" in runner:
    residue.append("ZZZ_FAKE in runner")
m = re.search(r"\$scenes = @\((.*?)\)", runner, re.S)
count = len(re.findall(r'res://tests', m.group(1) if m else ""))
if count != 66:
    residue.append(f"runner count {count} != 66")
if "共 67 RUN" not in io.open("README.md", encoding="utf-8").read():
    residue.append("README not restored")
if residue:
    print("RESIDUE:", residue)
    failures += 1
else:
    print("RESIDUE OK: 无 .bak / 变异文件 / 临时目录残留（已实际扫描 .gate_tmp*、rc_tmp*、smoke-tmp-*：项目根 + 系统 TEMP + Godot user://rc_tmp）")

rc, out = run_gate()
if rc != 0:
    print("FINAL_GATE FAIL:", out[:200])
    failures += 1
else:
    print("FINAL_GATE OK: doc_gate PASS after cleanup")

if failures:
    print(f"NEG_TOTAL_FAILURES={failures}")
    sys.exit(1)
print("NEG_ALL_PASS: 旧总数 66 / 缺 66 自动化场景 / runner 65 / runner 67 全部被拦截；编码兼容 + try/finally 清理；无残留；恢复后 PASS")
