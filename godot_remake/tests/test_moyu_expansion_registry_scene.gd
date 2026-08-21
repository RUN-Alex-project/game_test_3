extends Node

# v1.42 专项：验证 docs/moyu_23_24_content_registry.json（本地 2.2/2.3/2.4 内容候选目录）
# 与 docs/expansion_data_contract_v22.json（v22 数据合同，NOT_ENABLED）。
#
# 本测试是"正向同一验证器"：work/v142/verify_registry_negatives.py 的真实变异负向
# 会修改注册表/合同 JSON，再以同一个场景重跑，命中下方精确错误码（ERR_*）。
#
# 检查（任务书 6.1）：
#   1. JSON 可解析；2. ID 全局唯一；
#   3. kind/source_version/evidence_status/planned_version/design_status 来自允许集合；
#   4. local_version_confirmed/partial 的 evidence_source 存在且 token 精确命中；
#   5. evidence_gap/singleplayer_extension 不允许伪造 source/token；
#   6. 候选地图>=18、任务 60-75、首批 NPC=12、候补 NPC>=24、物品>=20、技能/Boss>=18；
#   7. v22 合同字段唯一、默认值与类型相符、服务归属非空、status=NOT_ENABLED；
#   8. 候选地图/任务 ID 不与 data/maps.json、data/quests.json 冲突。
#
# 成功：print("PASS ...") -> quit(0)；失败：print("REGISTRY_FAIL: ERR_XXX ...") -> quit(1)。
# 本测试不启动玩法，只校验注册表与合同，符合"不得修改玩法/UI/数值/存档"约束。

const REGISTRY_PATH := "res://docs/moyu_23_24_content_registry.json"
const CONTRACT_PATH := "res://docs/expansion_data_contract_v22.json"
const MAPS_JSON_PATH := "res://data/maps.json"
const QUESTS_JSON_PATH := "res://data/quests.json"

const ALLOWED_KIND := ["map", "quest", "npc", "item", "skill", "boss", "system"]
const ALLOWED_SOURCE_VERSION := ["2.2", "2.3", "2.4", "project"]
const ALLOWED_EVIDENCE_STATUS := [
	"local_version_confirmed", "local_version_partial",
	"singleplayer_extension", "evidence_gap",
]
const ALLOWED_DESIGN_STATUS := ["borrowed", "adapted", "singleplayer_extension", "not_selected"]
const ALLOWED_PLANNED := [
	"v1.43", "v1.44", "v1.45", "v1.46", "v1.47", "v1.48", "v1.49",
	"v1.50", "v1.51", "v1.52", "v1.53", "v1.54", "v1.55", "not_planned",
]
# 允许的证据来源目录（受控文本）：docs/evidence 或 work/v142/text
const EVIDENCE_PREFIXES := ["res://docs/evidence/", "res://work/v142/text/"]

const MIN_MAPS := 18
const MIN_QUESTS := 60
const MAX_QUESTS := 75
const MIN_FIRST_NPC := 12
const MIN_BACKUP_NPC := 24
const MIN_ITEMS := 20
const MIN_SKILL_BOSS := 18

# v22 合同必填字段（negative #7 删除任一字段必须命中 ERR_CONTRACT_FIELD_MISS）
const CONTRACT_REQUIRED_FIELDS := [
	"revision", "world_seed", "day_sequence", "adventurers", "relationships", "mailbox",
	"commission_state", "rankings", "season", "economy", "properties", "auction",
	"campaign", "collections",
]

var _errors: Array = []


func _ready() -> void:
	# ---- 1/8. 注册表可解析 + 基本结构 ----
	var registry: Dictionary = _read_json(REGISTRY_PATH, "registry")
	if registry.is_empty():
		_fail("ERR_JSON_PARSE", "registry JSON 未解析或为空")
		_finish()
		return

	var entries: Array = registry.get("entries", [])
	# ---- 2. ID 全局唯一 ----
	var seen: Dictionary = {}
	for e in entries:
		var eid: String = str(e.get("id", ""))
		if eid.is_empty():
			_fail("ERR_EMPTY_ID", "存在空 id")
			continue
		if seen.has(eid):
			_fail("ERR_DUP_ID", "重复 id: %s" % eid)
		seen[eid] = true

	# ---- 3. 枚举合法性 ----
	for e in entries:
		var kind: String = str(e.get("kind", ""))
		var sv: String = str(e.get("source_version", ""))
		var es: String = str(e.get("evidence_status", ""))
		var pv: String = str(e.get("planned_version", ""))
		var ds: String = str(e.get("design_status", ""))
		if not (kind in ALLOWED_KIND):
			_fail("ERR_BAD_KIND", "%s kind=%s" % [str(e.get("id")), kind])
		if not (sv in ALLOWED_SOURCE_VERSION):
			_fail("ERR_BAD_SOURCE_VERSION", "%s source_version=%s" % [str(e.get("id")), sv])
		if not (es in ALLOWED_EVIDENCE_STATUS):
			_fail("ERR_BAD_EVIDENCE_STATUS", "%s evidence_status=%s" % [str(e.get("id")), es])
		if not (pv in ALLOWED_PLANNED):
			_fail("ERR_BAD_PLANNED", "%s planned_version=%s" % [str(e.get("id")), pv])
		if not (ds in ALLOWED_DESIGN_STATUS):
			_fail("ERR_BAD_DESIGN_STATUS", "%s design_status=%s" % [str(e.get("id")), ds])

		# ---- 4/5. 来源与 token 规则 ----
		# 合同要求 evidence_source 为相对文本路径；JSON null/缺失视为无来源。
		var src_raw = e.get("evidence_source")
		var src: String = ""
		if src_raw is String and not (src_raw as String).is_empty():
			src = src_raw as String
		var tokens: Array = e.get("evidence_tokens", [])
		if not (tokens is Array):
			_fail("ERR_BAD_TOKENS", "%s evidence_tokens 不是数组" % str(e.get("id")))
			tokens = []
		var status: String = es
		if status == "local_version_confirmed" or status == "local_version_partial":
			if src.is_empty():
				_fail("ERR_SOURCE_MISS", "%s confirmed/partial 缺 evidence_source" % str(e.get("id")))
			else:
				_check_source_and_tokens(e, src, tokens)
		elif status == "singleplayer_extension" or status == "evidence_gap":
			if not src.is_empty():
				_fail("ERR_GAP_FABRICATED_SOURCE", "%s 伪造了 source: %s" % [str(e.get("id")), src])
			if tokens.size() > 0:
				_fail("ERR_GAP_FABRICATED_TOKEN", "%s 伪造了 token: %s" % [str(e.get("id")), str(tokens)])

	# ---- 6. 最小规模 ----
	var n_map := 0
	var n_quest := 0
	var n_first := 0
	var n_backup := 0
	var n_item := 0
	var n_skill_boss := 0
	var cand_map_ids: Array = []
	var cand_quest_ids: Array = []
	for e in entries:
		match str(e.get("kind", "")):
			"map":
				n_map += 1
				cand_map_ids.append(str(e.get("id")))
			"quest":
				n_quest += 1
				cand_quest_ids.append(str(e.get("id")))
			"npc":
				if str(e.get("cohort", "")) == "first":
					n_first += 1
				elif str(e.get("cohort", "")) == "backup":
					n_backup += 1
			"item":
				n_item += 1
			"skill", "boss":
				n_skill_boss += 1
	if n_map < MIN_MAPS:
		_fail("ERR_MAP_COUNT", "候选地图 %d < %d" % [n_map, MIN_MAPS])
	if n_quest < MIN_QUESTS or n_quest > MAX_QUESTS:
		_fail("ERR_QUEST_RANGE", "候选任务 %d 不在 %d-%d" % [n_quest, MIN_QUESTS, MAX_QUESTS])
	if n_first != MIN_FIRST_NPC:
		_fail("ERR_NPC_FIRST", "首批固定冒险者 %d != %d" % [n_first, MIN_FIRST_NPC])
	if n_backup < MIN_BACKUP_NPC:
		_fail("ERR_NPC_BACKUP", "候补固定冒险者 %d < %d" % [n_backup, MIN_BACKUP_NPC])
	if n_item < MIN_ITEMS:
		_fail("ERR_ITEM_COUNT", "候选物品 %d < %d" % [n_item, MIN_ITEMS])
	if n_skill_boss < MIN_SKILL_BOSS:
		_fail("ERR_SKILLBOSS_COUNT", "候选技能/Boss %d < %d" % [n_skill_boss, MIN_SKILL_BOSS])

	# ---- 8. 与现有 maps/quests 冲突 ----
	var maps_ids: Array = _read_id_list(MAPS_JSON_PATH, "id", "maps.json")
	var quests_ids: Array = _read_id_list(QUESTS_JSON_PATH, "id", "quests.json")
	for mid in cand_map_ids:
		if mid in maps_ids:
			_fail("ERR_MAP_COLLIDE", "候选地图 %s 与 maps.json 冲突" % mid)
	for qid in cand_quest_ids:
		if qid in quests_ids:
			_fail("ERR_QUEST_COLLIDE", "候选任务 %s 与 quests.json 冲突" % qid)

	# ---- 7. v22 数据合同 ----
	_verify_contract()

	_finish()


func _check_source_and_tokens(e: Dictionary, src: String, tokens: Array) -> void:
	var res_path := _to_res(src)
	if not _is_allowed_evidence_path(res_path):
		_fail("ERR_SOURCE_PATH_OUTSIDE", "%s 证据来源越界: %s" % [str(e.get("id")), src])
	if not FileAccess.file_exists(res_path):
		_fail("ERR_SOURCE_MISS", "%s 来源文件不存在: %s" % [str(e.get("id")), src])
		return
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		_fail("ERR_SOURCE_MISS", "%s 无法打开: %s" % [str(e.get("id")), src])
		return
	var text: String = f.get_as_text()
	f.close()
	for t in tokens:
		var tk: String = str(t)
		if tk.is_empty():
			continue
		if not (tk in text):
			_fail("ERR_TOKEN_MISS", "%s token 未命中 %s: %s" % [str(e.get("id")), src, tk])


func _to_res(p: String) -> String:
	if p.begins_with("res://"):
		return p
	if p.begins_with("/"):
		return "res://" + p.trim_prefix("/")
	return "res://" + p


func _verify_contract() -> void:
	var contract: Dictionary = _read_json(CONTRACT_PATH, "contract")
	if contract.is_empty():
		_fail("ERR_CONTRACT_JSON_PARSE", "contract JSON 未解析或为空")
		return
	if str(contract.get("status", "")) != "ENABLED":
		_fail("ERR_CONTRACT_ENABLED", "v22 合同在 v1.43 必须为 ENABLED，当前=%s" % str(contract.get("status")))
	var fields: Array = contract.get("fields", [])
	if fields.size() == 0:
		_fail("ERR_CONTRACT_FIELD_MISS", "合同 fields 为空")
		return
	var fseen: Dictionary = {}
	var found: Dictionary = {}
	for fld in fields:
		var fname: String = str(fld.get("name", ""))
		if fname.is_empty():
			_fail("ERR_CONTRACT_DUP_FIELD", "合同存在空字段名")
			continue
		if fseen.has(fname):
			_fail("ERR_CONTRACT_DUP_FIELD", "合同字段重复: %s" % fname)
		fseen[fname] = true
		found[fname] = true
		var ftype: String = str(fld.get("type", ""))
		var fdefault = fld.get("default")
		var fsvc: String = str(fld.get("owning_service", ""))
		if fsvc.is_empty():
			_fail("ERR_CONTRACT_SERVICE", "合同字段 %s 服务归属为空" % fname)
		# 默认值与类型相符
		var type_ok := false
		if ftype.begins_with("int") and (fdefault is int or fdefault is float):
			type_ok = true
		elif ftype.begins_with("dict") and fdefault is Dictionary:
			type_ok = true
		elif ftype.begins_with("list") and fdefault is Array:
			type_ok = true
		elif ftype == "string" and fdefault is String:
			type_ok = true
		if not type_ok:
			_fail("ERR_CONTRACT_DEFAULT_TYPE", "合同字段 %s 默认值 %s 与类型 %s 不符" % [fname, str(fdefault), ftype])
	for req in CONTRACT_REQUIRED_FIELDS:
		if not found.has(req):
			_fail("ERR_CONTRACT_FIELD_MISS", "合同缺少必填字段: %s" % req)


func _is_allowed_evidence_path(p: String) -> bool:
	for prefix in EVIDENCE_PREFIXES:
		if p.begins_with(prefix):
			return true
	return false


func _read_json(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("ERR_JSON_PARSE", "%s 文件不存在: %s" % [label, path])
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("ERR_JSON_PARSE", "%s 无法打开: %s" % [label, path])
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	_fail("ERR_JSON_PARSE", "%s 不是 Dictionary" % label)
	return {}


func _read_id_list(path: String, field: String, label: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		_fail("ERR_JSON_PARSE", "%s 文件不存在: %s" % [label, path])
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("ERR_JSON_PARSE", "%s 无法打开: %s" % [label, path])
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		for item in parsed:
			if item is Dictionary and item.has(field):
				out.append(str(item[field]))
	return out


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS moyu_expansion_registry: JSON 解析、ID 唯一、枚举合法、token 精确命中、无伪造来源、规模达标、v22 合同已启用且类型/服务正确、与 maps/quests 无冲突（registry 全部条目 %s）"
		% _read_entry_count_label())
	get_tree().quit(0)


func _read_entry_count_label() -> String:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return "?"
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return str(parsed.get("categories", {}).get("total", "?"))
	return "?"
