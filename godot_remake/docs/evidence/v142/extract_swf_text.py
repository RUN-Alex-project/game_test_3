#!/usr/bin/env python3
"""v1.42 可重跑纯文本反查：从 SWF 提取受控证据文本（不含 JRE / FFDec / 全量反编译产物）。

用途
----
对 E:\\魔域\\2.2.swf / 2.3.swf / 2.4.swf 做确定性、可终止、可记录退出码的纯文本提取。
只输出去重、排序后的候选字符串到 work/v142/text/moyu_<ver>_strings.txt；
不提交原始 SWF、FFDec 导出树、p-code、系统日志或临时目录。

证据边界（诚实口径）
--------------------
- 本脚本做"原始字节扫描"，不解析 AS2/AS3 动作码语义。因此命中 token 只证明
  "该字符串以这些字节存在于 SWF 中"，不证明其运行机制（如某按钮确实执行某跳转）。
- UTF-8 CJK 字符串可直接精确命中。GBK 字符串（若有）以二级模式输出。
- DefineText/DefineEditText 的静态字形文本依赖字体映射，纯字节扫描无法直接还原，
  记为未覆盖范围；已有 FFDec 审计显示 2.3/2.4 静态文本仅"魔域"标题。

用法
----
python extract_swf_text.py <swf_path> <out_txt> [--timeout-sec N]
  退出码：0=成功；2=输入文件不可读或非 SWF；124=超时（由外层 timeout 包装）；1=其他异常。
"""
import argparse
import sys
import zlib
from pathlib import Path

MIN_CJK_RUN_BYTES = 6      # >= 2 个三字节 UTF-8 CJK 字符
MIN_CJK_DISTINCT = 2       # 至少 2 个不同字符，过滤重复填充
MIN_ASCII_RUN = 6


def load_swf(path: Path) -> bytes:
    raw = path.read_bytes()
    if raw[:3] == b"CWS":
        return b"FWS" + raw[3:8] + zlib.decompress(raw[8:])
    if raw[:3] == b"FWS":
        return raw
    if raw[:3] == b"ZWS":
        return b"FWS" + raw[3:8] + zlib.decompress(raw[8:], -15)
    raise ValueError("unsupported SWF signature: %s" % raw[:3])


def _is_utf8_cjk_char(b0, b1, b2) -> bool:
    """UTF-8 三字节 CJK 字符：基本区 0xE4-0xE9；全角标点区 U+3000-303F（E3 80）；全角形式 U+FF01-FF5E（EF BC-BE）。"""
    if 0xE4 <= b0 <= 0xE9:
        return 0x80 <= b1 <= 0xBF and 0x80 <= b2 <= 0xBF
    if b0 == 0xE3 and b1 == 0x80:
        return 0x80 <= b2 <= 0xBF
    if b0 == 0xEF and 0xBC <= b1 <= 0xBE:
        return 0x80 <= b2 <= 0xBF
    return False


def utf8_cjk_runs(data: bytes):
    """扫描 UTF-8 三字节 CJK 连续段（基本区 0xE4-0xE9 + 全角标点区/全角形式）。"""
    out, i, n = [], 0, len(data)
    cur = bytearray()
    while i < n:
        b = data[i]
        if i + 2 < n and _is_utf8_cjk_char(b, data[i + 1], data[i + 2]):
            cur += bytes([b, data[i + 1], data[i + 2]])
            i += 3
            continue
        if len(cur) >= MIN_CJK_RUN_BYTES:
            out.append(bytes(cur))
        cur = bytearray()
        i += 1
    if len(cur) >= MIN_CJK_RUN_BYTES:
        out.append(bytes(cur))
    return out


def gbk_cjk_runs(data: bytes):
    """二级：扫描 GBK 双字节 CJK 连续段（lead 0x81-0xFE, trail 0x40-0xFE）。"""
    out, i, n = [], 0, len(data)
    cur = bytearray()
    while i + 1 < n:
        b0, b1 = data[i], data[i + 1]
        if 0x81 <= b0 <= 0xFE and 0x40 <= b1 <= 0xFE:
            cur += bytes([b0, b1])
            i += 2
            continue
        if len(cur) >= 8:  # >= 4 个 GBK 字符
            out.append(bytes(cur))
        cur = bytearray()
        i += 1
    if len(cur) >= 8:
        out.append(bytes(cur))
    return out


def ascii_runs(data: bytes):
    out, i, n = [], 0, len(data)
    cur = bytearray()
    while i < n:
        b = data[i]
        if 0x20 <= b <= 0x7E:
            cur.append(b)
            i += 1
            continue
        if len(cur) >= MIN_ASCII_RUN:
            out.append(bytes(cur))
        cur = bytearray()
        i += 1
    if len(cur) >= MIN_ASCII_RUN:
        out.append(bytes(cur))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("swf")
    ap.add_argument("out_txt")
    ap.add_argument("--label", default="")
    args = ap.parse_args()

    try:
        data = load_swf(Path(args.swf))
    except Exception as e:
        print("EXTRACT_ERROR input: %s" % e, file=sys.stderr)
        return 2

    stats = {}
    blocks = []

    # 主模式：UTF-8 CJK
    utf8_hits = utf8_cjk_runs(data)
    stats["utf8_cjk_runs"] = len(utf8_hits)
    utf8_lines = []
    for b in utf8_hits:
        try:
            s = b.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if len(set(s)) >= MIN_CJK_DISTINCT:
            utf8_lines.append(s)
    utf8_uniq = sorted(set(utf8_lines), key=lambda x: (-len(x), x))
    stats["utf8_uniq"] = len(utf8_uniq)
    blocks.append(("## MODE: utf8_cjk (primary)", utf8_uniq))

    # 二级模式：GBK CJK
    gbk_hits = gbk_cjk_runs(data)
    stats["gbk_cjk_runs"] = len(gbk_hits)
    gbk_lines = []
    for b in gbk_hits:
        try:
            s = b.decode("gbk")
        except UnicodeDecodeError:
            continue
        if len(set(s)) >= MIN_CJK_DISTINCT:
            gbk_lines.append(s)
    gbk_uniq = sorted(set(gbk_lines), key=lambda x: (-len(x), x))
    stats["gbk_uniq"] = len(gbk_uniq)
    blocks.append(("## MODE: gbk_cjk (secondary)", gbk_uniq))

    # ASCII 标识符（类名/变量/系统名/文件路径等）
    ascii_hits = ascii_runs(data)
    stats["ascii_runs"] = len(ascii_hits)
    ascii_uniq = sorted(
        set(s.decode("ascii") for s in ascii_hits if s.decode("ascii", "replace").isprintable()),
        key=lambda x: (-len(x), x),
    )
    stats["ascii_uniq"] = len(ascii_uniq)
    blocks.append(("## MODE: ascii (identifiers/paths)", ascii_uniq))

    label = args.label or Path(args.swf).stem
    out = Path(args.out_txt)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        f.write("# 受控证据文本: %s (source: %s)\n" % (label, args.swf))
        f.write("# 提取方式: 原始字节扫描(UTF-8/GBK CJK + ASCII)，去重排序；不解析动作码语义。\n")
        f.write("# 统计: %s\n" % _fmt_stats(stats))
        for header, lines in blocks:
            f.write("\n%s\n" % header)
            f.write("# count=%d\n" % len(lines))
            for s in lines:
                f.write(s + "\n")

    print("EXTRACT_OK %s utf8=%d gbk=%d ascii=%d -> %s" % (
        label, stats["utf8_uniq"], stats["gbk_uniq"], stats["ascii_uniq"], out))
    return 0


def _fmt_stats(stats) -> str:
    return "; ".join("%s=%d" % (k, v) for k, v in sorted(stats.items()))


if __name__ == "__main__":
    sys.exit(main())
