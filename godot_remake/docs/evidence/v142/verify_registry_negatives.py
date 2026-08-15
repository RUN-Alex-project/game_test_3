#!/usr/bin/env python3
"""v1.42 注册表真实变异负向验证（任务书 6.2：至少八项，先断言变异生效，再调用正向同一验证器命中精确错误码）。

流程（每项）：
1. 备份目标 JSON；
2. 变异并写回；
3. 重新读取并断言"变异已生效"（前后差异），否则该项 FAIL；
4. 调用正向同一验证器 = tests/test_moyu_expansion_registry_scene.tscn（与 run_tests.ps1 相同场景），
   断言退出码非 0 且输出含精确错误码 ERR_*；
5. try/finally 无条件恢复备份并删除 .bak；
6. 末尾断言：无 .bak、注册表/合同文件已恢复（正向 PASS）。

负向清单（10 项）：
  N1  confirmed token -> 不存在 token            -> ERR_TOKEN_MISS
  N2  confirmed source -> 不存在文件              -> ERR_SOURCE_MISS
  N3  复制一个已有 ID                             -> ERR_DUP_ID
  N4  evidence_status -> 非法值                   -> ERR_BAD_EVIDENCE_STATUS
  N5  source_version -> 不允许值                  -> ERR_BAD_SOURCE_VERSION
  N6  planned_version -> 不存在版本               -> ERR_BAD_PLANNED
  N7  删除 v22 必填字段                           -> ERR_CONTRACT_FIELD_MISS
  N8  候选地图 ID -> 现有 maps.json 已有 ID       -> ERR_MAP_COLLIDE
  N9  候选任务 ID -> 现有 quests.json 已有 ID     -> ERR_QUEST_COLLIDE
  N10 singleplayer_extension 非法加 token         -> ERR_GAP_FABRICATED_TOKEN
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
os.chdir(ROOT)

REGISTRY = ROOT / "docs" / "moyu_23_24_content_registry.json"
CONTRACT = ROOT / "docs" / "expansion_data_contract_v22.json"
MAPS = ROOT / "data" / "maps.json"
QUESTS = ROOT / "data" / "quests.json"
SCENE = "res://tests/test_moyu_expansion_registry_scene.tscn"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def run_positive_verifier():
    """调用正向同一验证器（与 run_tests.ps1 相同的 godot 场景）。"""
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    godot = os.environ.get("GODOT_EXE") or "godot"
    r = subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "--scene", SCENE, "--quit-after", "300"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        env=env, timeout=180,
    )
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def mutate_negative(path: Path, mutate, expect_code: str, label: str, seed: str):
    """备份 -> 变异 -> 断言变异生效 -> 正向同一验证器命中精确错误码 -> finally 恢复。"""
    bak = str(path) + ".bak"
    ok = False
    try:
        shutil.copyfile(path, bak)
        before = path.read_text(encoding="utf-8")
        data = load_json(path)
        mutate(data, seed)
        dump_json(path, data)
        after = path.read_text(encoding="utf-8")
        if after == before:
            print(f"{label} FAIL: 变异未生效（文件无变化）")
            return False
        # 变异生效的第二层断言：重新加载并按 seed 校验特征
        reloaded = load_json(path)
        if not mutation_effective(reloaded, label, seed):
            print(f"{label} FAIL: 变异未生效（语义断言失败）")
            return False
        rc, out = run_positive_verifier()
        intercepted = (rc != 0) and (expect_code in out)
        if intercepted:
            hit = [l for l in out.splitlines() if expect_code in l][:1]
            print(f"{label} OK: 变异生效且被拦截 -> {hit}")
            ok = True
        else:
            print(f"{label} FAIL: 未被拦截 (rc={rc} expect={expect_code})")
            tail = [l for l in out.splitlines() if "REGISTRY" in l or "PASS" in l or "ERROR" in l][:5]
            for t in tail:
                print("   out:", t[:200])
    except Exception as e:
        print(f"{label} ERROR: {type(e).__name__}: {e}")
    finally:
        if os.path.exists(bak):
            shutil.copyfile(bak, path)
            os.remove(bak)
    return ok


def mutation_effective(data, label: str, seed: str) -> bool:
    """按负向语义断言变异已在文件中生效。"""
    entries = data.get("entries", [])
    if label == "N1":
        return any("ZZZ_NO_SUCH_TOKEN_ANYWHERE" in str(t) for e in entries for t in e.get("evidence_tokens", []))
    if label == "N2":
        return any(str(e.get("evidence_source", "")).endswith("ZZZ_NO_SUCH_FILE.txt") for e in entries)
    if label == "N3":
        ids = [str(e["id"]) for e in entries]
        return ids.count("map_treeheart_road") >= 2
    if label == "N4":
        return any(str(e.get("evidence_status", "")) == "not_a_real_status" for e in entries)
    if label == "N5":
        return any(str(e.get("source_version", "")) == "3.0" for e in entries)
    if label == "N6":
        return any(str(e.get("planned_version", "")) == "v9.99" for e in entries)
    if label == "N7":
        names = [str(f.get("name", "")) for f in data.get("fields", [])]
        return "rankings" not in names
    if label == "N8":
        return any(str(e["id"]) == "cassano_city" and e.get("kind") == "map" for e in entries)
    if label == "N9":
        return any(str(e["id"]) == "border_raid" and e.get("kind") == "quest" for e in entries)
    if label == "N10":
        return any(
            e.get("evidence_status") == "singleplayer_extension" and e.get("evidence_tokens")
            for e in entries
        )
    return False


def mut_N1(data, _seed):
    for e in data["entries"]:
        if e.get("evidence_status") == "local_version_confirmed" and e.get("evidence_tokens"):
            e["evidence_tokens"][0] = "ZZZ_NO_SUCH_TOKEN_ANYWHERE"
            return


def mut_N2(data, _seed):
    for e in data["entries"]:
        if e.get("evidence_status") == "local_version_confirmed" and e.get("evidence_source"):
            e["evidence_source"] = "work/v142/text/ZZZ_NO_SUCH_FILE.txt"
            return


def mut_N3(data, _seed):
    # 复制第一个 map 条目，追加一个同 id 副本
    first_map = next(e for e in data["entries"] if e["kind"] == "map")
    dup = dict(first_map)
    data["entries"].append(dup)


def mut_N4(data, _seed):
    data["entries"][0]["evidence_status"] = "not_a_real_status"


def mut_N5(data, _seed):
    data["entries"][0]["source_version"] = "3.0"


def mut_N6(data, _seed):
    data["entries"][0]["planned_version"] = "v9.99"


def mut_N7(data, _seed):
    data["fields"] = [f for f in data["fields"] if str(f.get("name", "")) != "rankings"]


def mut_N8(data, _seed):
    target = next(e for e in data["entries"] if e["kind"] == "map")
    target["id"] = "cassano_city"  # 现有 maps.json 已存在 ID


def mut_N9(data, _seed):
    target = next(e for e in data["entries"] if e["kind"] == "quest")
    target["id"] = "border_raid"   # 现有 quests.json 已存在 ID


def mut_N10(data, _seed):
    for e in data["entries"]:
        if e.get("evidence_status") == "singleplayer_extension":
            e["evidence_source"] = "work/v142/text/moyu_2.4_strings.txt"
            e["evidence_tokens"] = ["伪造的token"]
            return


def main() -> int:
    failures = 0
    cases = [
        (REGISTRY, mut_N1, "ERR_TOKEN_MISS", "N1"),
        (REGISTRY, mut_N2, "ERR_SOURCE_MISS", "N2"),
        (REGISTRY, mut_N3, "ERR_DUP_ID", "N3"),
        (REGISTRY, mut_N4, "ERR_BAD_EVIDENCE_STATUS", "N4"),
        (REGISTRY, mut_N5, "ERR_BAD_SOURCE_VERSION", "N5"),
        (REGISTRY, mut_N6, "ERR_BAD_PLANNED", "N6"),
        (CONTRACT, mut_N7, "ERR_CONTRACT_FIELD_MISS", "N7"),
        (REGISTRY, mut_N8, "ERR_MAP_COLLIDE", "N8"),
        (REGISTRY, mut_N9, "ERR_QUEST_COLLIDE", "N9"),
        (REGISTRY, mut_N10, "ERR_GAP_FABRICATED_TOKEN", "N10"),
    ]
    for path, mut, code, label in cases:
        if not mutate_negative(path, mut, code, label, label):
            failures += 1

    # 末尾：无 .bak、恢复后正向 PASS
    residue = []
    for b in sorted(glob_any("**/*.bak")):
        residue.append(str(b))
    for p in [REGISTRY, CONTRACT]:
        if not p.exists():
            residue.append("missing %s" % p.name)
    if residue:
        print("RESIDUE:", residue)
        failures += 1
    rc, out = run_positive_verifier()
    if rc != 0 or "PASS moyu_expansion_registry" not in out:
        print("FINAL_POSITIVE FAIL: rc=%d" % rc)
        for l in out.splitlines()[:6]:
            print("  ", l[:200])
        failures += 1
    else:
        print("FINAL_POSITIVE OK: 恢复后同验证器 PASS")

    if failures:
        print(f"NEG_TOTAL_FAILURES={failures}")
        return 1
    print("NEG_ALL_PASS: 10 项真实变异全部先证明生效、再由正向同一验证器命中精确错误码；无残留；恢复后 PASS")
    return 0


def glob_any(pattern):
    import glob
    return glob.glob(str(ROOT / pattern), recursive=True)


if __name__ == "__main__":
    sys.exit(main())
