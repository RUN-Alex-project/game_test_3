#!/usr/bin/env python3
"""P1-4 文档门禁（拒签整改重写）：
1. 真实文件 SHA256：对发布目录每个实际文件计算哈希，与 SHA256SUMS.txt 每条逐一比较（双向）；
2. 文件集合双向相等：manifest.artifacts == 实际目录文件集（除 SHA256SUMS）== SHA256SUMS 文件集；
3. manifest 内部一致性（exe/pck 哈希、stale=false）；
4. 状态文本一致性：所有状态文档（版本改动/开发进度/综合整改报告/最终交付报告/已知问题）统一，
   "待复验/拒签" 与 "可试玩" 冲突、拒签状态下的 "阻断：无" 冲突、机械替换损坏（嵌套"待复验/不待复验/禁止试玩"）检测；
5. 控制字符（U+0000-001F 除 \\t\\n\\r）扫描全部状态文档；
6. 测试数量统一（66）。
"""
import sys, re, hashlib, json
from pathlib import Path

PROJECT = Path(__file__).parent.parent
RELEASE = PROJECT / "artifacts" / "releases" / "v1.41"
errors = []

# ---- 1/2. 真实文件 SHA256 双向 + 文件集合双向相等 ----
sha_file = RELEASE / "SHA256SUMS.txt"
manifest_file = RELEASE / "build_manifest.json"
if not sha_file.exists():
    errors.append("SHA256SUMS.txt 不存在")
else:
    sha_map = {}
    seen_sha_names = set()
    for l in sha_file.read_text(encoding="utf-8").strip().split("\n"):
        if not l.strip():
            continue
        parts = l.split("  ")
        if len(parts) != 2:
            errors.append(f"SHA256SUMS 行格式非法: {l}")
            continue
        if parts[1] in seen_sha_names:
            # 第三轮拒签整改：同文件名重复行 / 同名哈希冲突，不转 set 丢重复
            errors.append(f"SHA256SUMS 同文件名重复: {parts[1]}")
            continue
        seen_sha_names.add(parts[1])
        sha_map[parts[1]] = parts[0].lower()
    # 每个实际文件逐一计算 SHA256 并与记录比较（SHA256SUMS.txt 自身不登记自己）
    for f in sorted(RELEASE.iterdir()):
        if not f.is_file() or f.name == "SHA256SUMS.txt":
            continue
        actual_hash = hashlib.sha256(f.read_bytes()).hexdigest()
        if f.name in sha_map:
            if sha_map[f.name] != actual_hash:
                errors.append(f"SHA256SUMS {f.name}: 记录 {sha_map[f.name]} != 实际文件 {actual_hash}")
        else:
            errors.append(f"SHA256SUMS 缺失记录: {f.name}")
    # SHA256SUMS 记录的每个文件必须实际存在
    for name in sha_map:
        if not (RELEASE / name).is_file():
            errors.append(f"SHA256SUMS 记录的文件不存在: {name}")
    # 文件集合双向相等：manifest.artifacts == 实际 == SHA256SUMS
    actual_files = {f.name for f in RELEASE.iterdir() if f.is_file() and f.name != "SHA256SUMS.txt"}
    if manifest_file.exists():
        m = json.loads(manifest_file.read_text(encoding="utf-8"))
        art_list = list(m.get("artifacts", []))
        if len(art_list) != len(set(art_list)):
            # 第三轮拒签整改：manifest.artifacts 重复项
            errors.append("manifest.artifacts 含重复项")
        manifest_arts = set(art_list)
        if len(art_list) != len(actual_files):
            errors.append(f"manifest.artifacts 数量 {len(art_list)} != 实际目录 {len(actual_files)}")
        if manifest_arts != actual_files:
            diff = sorted(manifest_arts ^ actual_files)
            errors.append(f"manifest.artifacts != 实际目录文件集（差异: {diff}）")
        # 三方数量多重集：SHA 记录数 == 实际文件数 == manifest artifacts 数
        if len(seen_sha_names) != len(actual_files):
            errors.append(f"SHA256SUMS 记录数 {len(seen_sha_names)} != 实际目录 {len(actual_files)}")
        if set(sha_map.keys()) != actual_files:
            diff = sorted(set(sha_map.keys()) ^ actual_files)
            errors.append(f"SHA256SUMS 文件集 != 实际目录文件集（差异: {diff}）")
        if m.get("executable_stale", True):
            errors.append("manifest: exe 标记为 stale，不得发布")
        if str(m.get("executable_hash_sha256", "")).lower() != sha_map.get("魔域1.03_v1.41.exe", ""):
            errors.append("manifest exe 哈希 != SHA256SUMS")
        if str(m.get("pck", {}).get("sha256", "")).lower() != sha_map.get("魔域1.03_v1.41.pck", ""):
            errors.append("manifest pck 哈希 != SHA256SUMS")
    else:
        errors.append("build_manifest.json 不存在")

# ---- 4. 状态文本一致性 ----
STATUS_DOCS = [
    "版本改动.md", "开发进度.md",
    "docs/综合整改报告.md",
    "artifacts/releases/v1.41/最终交付报告_v1.41.md",
    "artifacts/releases/v1.41/已知问题_v1.41.md",
]
for md in STATUS_DOCS:
    p = PROJECT / md
    if not p.exists():
        errors.append(f"状态文档缺失: {md}")
        continue
    t = p.read_text(encoding="utf-8")
    # 状态冲突只检查"状态声明行"（引用块 / 当前状态·结论节 / 阻断行），
    # 报告正文中对历史指摘或门禁规则的引用（如"待复验（不待复验（禁止试玩））"）不算当前状态。
    def _strip_inline_code(s: str) -> str:
        # 行内代码引用（如 `待复验（不待复验（禁止试玩））`）是对历史损坏文本的引用，不是当前状态声明
        return re.sub(r"`[^`]*`", "", s)

    def _state_lines(text: str):
        lines = text.split("\n")
        out = []
        in_state_section = False
        for i, line in enumerate(lines):
            s = line.strip()
            if s.startswith("## 当前状态") or s.startswith("## 结论") or s.startswith("## 状态"):
                in_state_section = True
            elif s.startswith("## ") or s.startswith("# "):
                if not (s.startswith("## 当前状态") or s.startswith("## 结论") or s.startswith("## 状态")):
                    in_state_section = False
            # 状态声明行：引用块 / 状态节 / 阻断判断行（"阻断"裸词会误捕正文引用，改用冒号形式）
            if s.startswith("> ") or in_state_section or "阻断：" in s or "阻断判断" in s:
                out.append(_strip_inline_code(s))
        return out

    state_lines = _state_lines(t)
    state_text = "\n".join(state_lines)
    has_revoked = any(("REVOKED" in s) or ("待复验" in s) or ("拒签" in s) or ("整改中" in s) for s in state_lines)
    # 可试玩作为状态声明的模式（"可试玩"裸词描述句如"冲突已消除"不误报）
    has_playable = any(
        ("可进入用户试玩" in s) or ("标记为可试玩" in s) or ("可试玩状态" in s)
        or ("可试玩基线" in s) or ("可以开始试玩" in s) or ("允许用户试玩" in s)
        for s in state_lines
    )
    if has_revoked and has_playable:
        errors.append(f"{md}: 待复验/拒签 与 可试玩 并存（状态冲突）")
    # 机械替换损坏：嵌套"待复验（…待复验…）" / "待复验（…不待复验…）"（单层"待复验（禁止试玩）"是合法历史表述）
    for s in state_lines:
        if re.search(r"待复验[（(][^）)]*(待复验|不待复验)", s):
            errors.append(f"{md}: 机械替换损坏文本（嵌套'待复验/不待复验'）: {s[:60]}")
    # 状态为待复验/拒签/整改中时，状态声明行不得写"阻断：无"
    if has_revoked:
        for s in state_lines:
            if "阻断：无" in s:
                errors.append(f"{md}: 状态为待复验/拒签/整改中但写了'阻断：无'（状态冲突）: {s[:60]}")

# ---- 5. 控制字符 ----
CONTROL_DOCS = STATUS_DOCS + ["artifacts/releases/v1.41/试玩验收清单_v1.41.md"]
for md in CONTROL_DOCS:
    p = PROJECT / md
    if p.exists():
        bad = [c for c in p.read_bytes() if c < 0x20 and c not in (0x09, 0x0A, 0x0D)]
        if bad:
            errors.append(f"控制字符存在: {md} {[hex(b) for b in bad[:5]]}")

# ---- 6. 测试数量统一（P1-4 拒签整改：机械读取 run_tests.ps1 的 $scenes 数组）----
runner_path = PROJECT / "run_tests.ps1"
if not runner_path.exists():
    errors.append("run_tests.ps1 不存在")
else:
    runner_text = runner_path.read_text(encoding="utf-8")
    scenes_block = re.search(r"\$scenes = @\((.*?)\)\s*\n", runner_text, re.S)
    if scenes_block is None:
        errors.append("run_tests.ps1: 找不到 $scenes 数组块")
        runner_count = -1
    else:
        scene_lines = re.findall(r'"res://tests/[^"]+\.tscn"', scenes_block.group(1))
        runner_count = len(scene_lines)
    EXPECTED_SCENES = 65
    if runner_count != EXPECTED_SCENES:
        errors.append(f"run_tests.ps1 场景数组实际 {runner_count} 个（口径应为 {EXPECTED_SCENES} 个自动化场景 + 主场景冒烟 = 66 RUN；负向：runner 数量 64 或 66 均必须失败）")
# 数量口径统一：所有状态/交付文档必须采用"65 个自动化场景 + 主场景冒烟，共 66 RUN"
# 负向规则（PM 第二轮拒签）：
#   - 文档写成 "65 RUN"（错误口径，应为 66 RUN）→ 必须失败；
#   - 文档写成 "66 RUN" 但缺少 "65 个自动化场景" → 必须失败；
#   - 旧口径（52/51/58/59/60）→ 必须失败。
COUNT_DOCS = [
    "README.md",
    "开发进度.md",
    "docs/综合整改报告.md",
    "docs/v1.37-v1.41_全版本复验文档.md",
    "artifacts/releases/v1.41/最终交付报告_v1.41.md",
    "artifacts/releases/v1.41/已知问题_v1.41.md",
]
for md in COUNT_DOCS:
    p = PROJECT / md
    if not p.exists():
        continue
    t = p.read_text(encoding="utf-8")
    if "52 个自动化" in t or "51 个测试场景" in t or "58 场景" in t or "59 个自动化" in t or "59场景" in t or "59 场景" in t:
        errors.append(f"{md}: 场景数表述为旧口径（52/51/58/59），应为 65 个自动化场景")
    if "60 场景 + 冒烟" in t or "60 个场景" in t or "60 RUN" in t:
        errors.append(f"{md}: 表述为旧口径 60 RUN，应为'65 个自动化场景 + 主场景冒烟，共 66 RUN'")
    if "65 RUN" in t:
        errors.append(f"{md}: 表述写成 65 RUN（错误口径，正确为 66 RUN；65 个自动化场景 + 冒烟 = 66 RUN）")
    if "66 RUN" in t and "65 个自动化" not in t and "65个自动化" not in t and "65 自动化" not in t:
        errors.append(f"{md}: 提到 66 RUN 必须伴随'65 个自动化场景'口径")

if errors:
    print("DOC_GATE FAIL:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
print("DOC_GATE PASS: 真实文件 SHA256 双向一致、文件集合双向相等、manifest 内部一致、状态文本一致、无控制字符、数量统一、stale=false")
