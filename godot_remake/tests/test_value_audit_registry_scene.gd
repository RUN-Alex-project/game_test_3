extends Node
## v1.39 专项测试：原版数值与用户覆盖值双层审计一致性（P1-2 拒签整改重写）。
## 独立 production catalog：所有值从生产源（config 文件 / 代码精确行绑定）枚举，
## 注册表 effective_value 与 catalog 值双向相等（实际值参与验证，非仅 ID 集合）。
## 代码型数值绑定具体生产表达式（函数段 + 完整行锚定，非全文件 contains）。
## verified_count 由独立逐项计数（oracle：registry ↔ catalog 逐项相等）。
## 负向全部变异真实 registry/catalog 副本后走同一验证器（非纯函数调用摆设）。

const REGISTRY_PATH := "res://docs/value_audit_registry.json"
const EVIDENCE_PATH := "res://docs/evidence/value_audit_v103_v9.txt"

var _values: Array = []
var _evidence_text: String = ""


func _load_registry() -> void:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	assert(f != null, "value audit registry must be readable: " + REGISTRY_PATH)
	var raw: Variant = JSON.parse_string(f.get_as_text())
	_values = (raw as Dictionary).get("values", [])


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "json must be readable: " + path)
	var raw: Variant = JSON.parse_string(f.get_as_text())
	return raw as Dictionary if raw is Dictionary else {}


# ---- 独立验证器（纯函数，正向与负向共用同一验证器）----

## 覆盖完整性：注册表 value_id 集合与 production catalog ID 集合双向相等
func _verify_id_sets(reg_values: Array, prod_catalog: Dictionary) -> String:
	var reg_ids: Array = []
	for v in reg_values:
		reg_ids.append(str(v.get("value_id", "")))
	reg_ids.sort()
	var cat_ids: Array = prod_catalog.keys()
	cat_ids.sort()
	return "" if reg_ids == cat_ids else "VALUE_CATALOG_ID_MISMATCH"


## 双向值验证（P1-2 拒签整改：同一比较逻辑内统计 verified，不再另设"独立 oracle"）：
## registry.effective -> catalog 且 catalog -> registry.effective 逐项相等。
## 返回 {"error": String, "verified": int}——verified 由同一验证器的逐项相等计数产生。
func _verify_bidirection(reg_values: Array, prod_catalog: Dictionary) -> Dictionary:
	var reg_map := {}
	for v in reg_values:
		reg_map[str(v.get("value_id", ""))] = v.get("effective_value")
	var verified := 0
	for v in reg_values:
		var vid := str(v.get("value_id", ""))
		if not prod_catalog.has(vid):
			return {"error": "VALUE_EFFECTIVE_MISMATCH", "verified": verified}
		if not _values_equal(v.get("effective_value"), prod_catalog[vid]):
			return {"error": "VALUE_EFFECTIVE_MISMATCH", "verified": verified}
		verified += 1
	for vid: String in prod_catalog:
		if not reg_map.has(vid):
			return {"error": "VALUE_EFFECTIVE_MISMATCH", "verified": verified}
		if not _values_equal(reg_map[vid], prod_catalog[vid]):
			return {"error": "VALUE_EFFECTIVE_MISMATCH", "verified": verified}
	return {"error": "", "verified": verified}


## 真实生产状态差验证器（经验 10 倍 / 军功作用域）：
## rewards 经真实 GameState.apply_victory_rewards 应用，断言状态差 == 期望值。
## 正向（生产 rewards）与负向（变异 rewards 模拟倍率错误）共用同一验证器。
func _verify_state_diff(rewards: Dictionary, expect_exp_gain: int, expect_merit_gain: int) -> String:
	var exp_before := GameState.experience
	var merit_before := GameState.military_merit
	GameState.apply_victory_rewards(rewards)
	var exp_gain := GameState.experience - exp_before
	var merit_gain := GameState.military_merit - merit_before
	if exp_gain != expect_exp_gain:
		return "VALUE_MULTIPLIER_APPLIED_TWICE" if exp_gain > expect_exp_gain else "VALUE_EXP_STATE_DIFF"
	if merit_gain != expect_merit_gain:
		return "VALUE_SCOPE_MISMATCH"
	return ""


## 真实生产接口边界验证器（战魂晶石 roll < 0.5 成功、0.5 失败；enhancement_service.activate_war_soul）
func _verify_boundary_via_production(enhancement: Object, instance: Dictionary) -> String:
	if not bool(enhancement.activate_war_soul(instance.duplicate(true), 0.499999).get("success", false)):
		return "VALUE_PROBABILITY_BOUNDARY_MISMATCH"  # 0.499999 必须成功（严格 <）
	if bool(enhancement.activate_war_soul(instance.duplicate(true), 0.5).get("success", false)):
		return "VALUE_PROBABILITY_BOUNDARY_MISMATCH"  # 0.5 必须失败（改 <= 会改变边界）
	return ""


## 未登记魔法数字：catalog 存在注册表没有的值
func _validate_registered(reg_values: Array, prod_catalog: Dictionary) -> String:
	return _verify_id_sets(reg_values, prod_catalog)


# ---- 独立 production catalog（不从被测注册表生成，值全部来自生产源）----

func _build_production_catalog(configs: Dictionary) -> Dictionary:
	var cat := {}
	# config 型（从生产 config 文件直接枚举）
	var prog: Dictionary = configs.get("progression", {})
	cat["player_exp_multiplier"] = int(prog.get("player_experience_multiplier", -1))
	cat["boss_military_multiplier"] = int(prog.get("boss_military_merit_multiplier", -1))
	cat["normal_military_multiplier"] = int(prog.get("normal_military_merit_multiplier", -1))
	var enh: Dictionary = configs.get("enhancement", {})
	cat["quality_success_rate"] = float(enh.get("quality_success_rate", -1.0))
	cat["magic_soul_success_rate"] = float(enh.get("magic_soul_success_rate", -1.0))
	cat["war_soul_crystal_success_rate"] = float(enh.get("war_soul_crystal_success_rate", -1.0))
	cat["rose_99"] = int(enh.get("rose_affection", {}).get("99", -1))
	cat["rose_999"] = int(enh.get("rose_affection", {}).get("999", -1))
	var pc: Dictionary = configs.get("pet_config", {})
	var res: Dictionary = pc.get("research", {})
	cat["research_tech_cap"] = float(res.get("technology_level_cap", -1.0))
	cat["research_daily_cap"] = int(res.get("production_rate_cap", -1))
	var ranks: Dictionary = configs.get("ranks", {})
	cat["gold_per_merit"] = int(ranks.get("gold_per_nobility_merit", -1))
	# 代码型（精确行绑定：函数段 + 完整行锚定，数字变更即绑定失败 -> null -> mismatch）
	cat["initial_gold"] = _code_value("initial_gold")
	cat["initial_magic_stones"] = _code_value("initial_magic_stones")
	cat["sale_grant"] = _code_value("sale_grant")
	cat["spider_skill_base"] = _code_value("spider_skill_base")
	cat["queen_skill_base"] = _code_value("queen_skill_base")
	cat["enhanced_moon_box_50"] = _code_value("enhanced_moon_box_50")
	return cat


## 代码型数值：精确行绑定（读取源码行，与期望表达式整行相等）。
## 返回 null 表示绑定失败（生产表达式被改动/移除），双向验证必须拒绝。
func _code_value(vid: String) -> Variant:
	match vid:
		"initial_gold":
			return 99999999999 if _has_exact_line(_read_lines("res://scripts/game_state.gd"), "var gold: int = 99_999_999_999") else null
		"initial_magic_stones":
			return 99999999999 if _has_exact_line(_read_lines("res://scripts/game_state.gd"), "var magic_stones: int = 99_999_999_999") else null
		"sale_grant":
			# 绑定 claim_merchant_sale 函数段内的 SALE_GRANT 声明行
			var gs := _func_segment(_read_lines("res://scripts/game_state.gd"), "func claim_merchant_sale")
			return 99999999999 if _has_exact_line(gs, "const SALE_GRANT := 99_999_999_999") else null
		"spider_skill_base":
			# 绑定 _roll_spider_drops 函数段内的三行掉落率表达式（数字变更即失效）
			var seg := _func_segment(_read_lines("res://scripts/combat_service.gd"), "func _roll_spider_drops")
			if seg.is_empty():
				return null
			if not _has_exact_line(seg, "_append_if(results, \"skill_fighting_spirit\", 0.30 * baoli, forced_rolls, cursor)"):
				return null
			if not _has_exact_line(seg, "_append_if(results, \"skill_flying_slash\", 0.50 * baoli, forced_rolls, cursor)"):
				return null
			if not _has_exact_line(seg, "_append_if(results, \"skill_star_sword\", 0.60 * baoli, forced_rolls, cursor)"):
				return null
			return [0.30, 0.50, 0.60]
		"queen_skill_base":
			var seg := _func_segment(_read_lines("res://scripts/combat_service.gd"), "func _roll_queen_drops")
			if seg.is_empty():
				return null
			if not _has_exact_line(seg, "_append_if(results, \"advanced_fighting_spirit\", 0.40 * baoli, forced_rolls, cursor)"):
				return null
			if not _has_exact_line(seg, "_append_if(results, \"advanced_star_sword\", 0.40 * baoli, forced_rolls, cursor)"):
				return null
			if not _has_exact_line(seg, "_append_if(results, \"advanced_flying_slash\", 0.20 * baoli, forced_rolls, cursor)"):
				return null
			return [0.40, 0.40, 0.20]
		"enhanced_moon_box_50":
			var seg := _func_segment(_read_lines("res://scripts/combat_service.gd"), "func _roll_queen_drops")
			return 0.50 if _has_exact_line(seg, "_append_if(results, \"enhanced_moon_box\", 0.50, forced_rolls, cursor)") else null
	return null


func _read_lines(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var t := f.get_as_text()
	f.close()
	return t.split("\n")


## 整行锚定匹配（strip 后与期望表达式完全相等）
func _has_exact_line(lines: Array, expected: String) -> bool:
	for line: String in lines:
		if line.strip_edges() == expected:
			return true
	return false


## 函数段截取：func 声明行到下一个 func 声明行
func _func_segment(lines: Array, func_decl: String) -> Array:
	var start := -1
	for i in lines.size():
		if str(lines[i]).strip_edges().begins_with(func_decl):
			start = i + 1
			break
	if start < 0:
		return []
	var out: Array = []
	for j in range(start, lines.size()):
		if str(lines[j]).strip_edges().begins_with("func "):
			break
		out.append(str(lines[j]))
	return out


func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _values_equal((a as Array)[i], (b as Array)[i]):
				return false
		return true
	# 精确数值比较（不用 is_equal_approx：其相对容差对大数 +1 失效，如 750000.0 vs 750001.0）
	return a == b


func _ready() -> void:
	_load_registry()
	var ef := FileAccess.open(EVIDENCE_PATH, FileAccess.READ)
	assert(ef != null, "value audit evidence must be readable: " + EVIDENCE_PATH)
	_evidence_text = ef.get_as_text()
	assert(not _values.is_empty(), "value audit registry must load")

	# 权威配置源
	var progression := _load_json("res://data/progression.json")
	var enhancement := _load_json("res://data/enhancement.json")
	var pet_config := _load_json("res://data/pet_config.json")
	var ranks := _load_json("res://data/ranks.json")
	var configs := {"progression": progression, "enhancement": enhancement, "pet_config": pet_config, "ranks": ranks}

	# 1. 独立 production catalog（值全部来自生产源）
	var prod_catalog := _build_production_catalog(configs)
	for vid: String in prod_catalog:
		assert(prod_catalog[vid] != null, "catalog %s 生产值必须可定位（config 缺键或代码绑定失败）" % vid)

	# 2. 覆盖完整性：注册表 ID 集合 == production catalog ID 集合（双向）
	assert(_verify_id_sets(_values, prod_catalog) == "",
		"注册表 ID 集合必须与 production catalog 双向一致")

	# 3. 双向值验证：registry.effective -> catalog 且 catalog -> registry.effective（实际值参与）
	var bidir := _verify_bidirection(_values, prod_catalog)
	assert(str(bidir.get("error", "")) == "",
		"registry.effective 与 production catalog 值必须逐项双向相等（%s）" % str(bidir.get("error", "")))

	# 4. verified_count 由同一双向验证器统计（P1-2 拒签整改：同一比较逻辑，不再称独立 oracle）
	var verified_count := int(bidir.get("verified", 0))
	assert(verified_count == _values.size(),
		"verified_count=%d 必须等于 registry.size()=%d（全部覆盖，无跳过）" % [verified_count, _values.size()])
	assert(verified_count == 17, "verified_count 必须为 17（got %d）" % verified_count)

	# 5. 真实生产状态差：经验 10 倍 / 军功作用域 1x vs 10x（combat.victory_rewards -> GameState.apply_victory_rewards）
	GameState.level = 100  # 高等级经验池（level*1000=100000），避免升级扣经验干扰字段差断言
	const CombatService := preload("res://scripts/combat_service.gd")
	var combat := CombatService.new()
	assert(int(progression.get("player_experience_multiplier", 0)) == 10, "progression exp multiplier must be 10")
	assert(int(progression.get("boss_military_merit_multiplier", 0)) == 10, "progression boss multiplier must be 10")
	assert(int(progression.get("normal_military_merit_multiplier", 0)) == 1, "progression normal multiplier must be 1")
	# 普通怪 thunder_giant：base_exp=50 → 经验 50×10=500；军功 0×1=0
	var normal_rewards := combat.victory_rewards("thunder_giant", 0)
	assert(not normal_rewards.is_empty(), "thunder_giant rewards must resolve")
	assert(int(normal_rewards.get("experience", -1)) == 500, "普通怪经验必须为 50×10=500（实际 %s）" % str(normal_rewards.get("experience")))
	assert(int(normal_rewards.get("military_merit", -1)) == 0, "普通怪军功必须为 0×1=0（实际 %s）" % str(normal_rewards.get("military_merit")))
	assert(_verify_state_diff(normal_rewards, 500, 0) == "", "普通怪状态差（经验+500、军功+0）必须通过")
	# Boss snow_warrior：base_exp=5000 → 经验 5000×10=50000；军功 500×10=5000
	var boss_rewards := combat.victory_rewards("snow_warrior", 0)
	assert(not boss_rewards.is_empty(), "snow_warrior rewards must resolve")
	assert(int(boss_rewards.get("experience", -1)) == 50000, "Boss 经验必须为 5000×10=50000（实际 %s）" % str(boss_rewards.get("experience")))
	assert(int(boss_rewards.get("military_merit", -1)) == 5000, "Boss 军功必须为 500×10=5000（实际 %s）" % str(boss_rewards.get("military_merit")))
	assert(_verify_state_diff(boss_rewards, 50000, 5000) == "", "Boss 状态差（经验+50000、军功+5000）必须通过")

	# 6. 真实生产接口边界：战魂晶石 activate_war_soul roll<0.5 成功、0.5 失败
	const EnhancementService := preload("res://scripts/enhancement_service.gd")
	var enhancement_svc := EnhancementService.new()
	var war_soul_instance := {"war_soul_active": false}
	assert(_verify_boundary_via_production(enhancement_svc, war_soul_instance) == "",
		"activate_war_soul 边界必须为严格 <（0.499999 成功、0.5 失败）")

	# 7. 注册表来源/实现/证据 token 存在
	assert(_evidence_text.contains("player_experience_multiplier"), "evidence must contain exp multiplier token")
	assert(_evidence_text.contains("war_soul_crystal_success_rate"), "evidence must contain war soul token")
	for v in _values:
		var ev: Array = str(v.get("implementation_sources", "[]")).split(",")
		for raw_src in ev:
			var s: String = str(raw_src).strip_edges().trim_prefix("[").trim_suffix("]")
			if s.is_empty():
				continue
			assert(s.contains(".gd"), "implementation source %s must be a .gd path" % s)

	# ========== 负向：全部变异真实 registry/catalog/生产数据副本后走同一验证器 ==========

	# N1 VALUE_EFFECTIVE_MISMATCH：变异注册表副本（spider_skill_base 值篡改）-> 同一 _verify_bidirection 拒绝
	var mut_reg: Array = _duplicate_values(_values)
	for v in mut_reg:
		if str(v.get("value_id", "")) == "spider_skill_base":
			v["effective_value"] = [0.30, 0.50, 0.99]
	var mut_applied := false
	for v in mut_reg:
		if str(v.get("value_id", "")) == "spider_skill_base" and _values_equal(v.get("effective_value"), [0.30, 0.50, 0.99]):
			mut_applied = true
	assert(mut_applied, "N1 变异必须生效（spider_skill_base 已篡改）")
	assert(str(_verify_bidirection(mut_reg, prod_catalog).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N1 变异注册表必须被同一双向验证器拒绝")

	# N2 VALUE_EFFECTIVE_MISMATCH：变异 catalog 副本（gold_per_merit +1）-> 同一验证器拒绝
	var mut_cat: Dictionary = prod_catalog.duplicate(true)
	mut_cat["gold_per_merit"] = int(mut_cat["gold_per_merit"]) + 1
	assert(int(mut_cat["gold_per_merit"]) != int(prod_catalog["gold_per_merit"]), "N2 变异必须生效（catalog 值 +1）")
	assert(str(_verify_bidirection(_values, mut_cat).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N2 变异 catalog 必须被同一双向验证器拒绝")

	# N3 USER_OVERRIDE_MISSING：变异注册表副本删除覆盖项 -> 同一 _verify_id_sets 拒绝
	var mut_reg3: Array = _duplicate_values(_values)
	var removed_id := ""
	for i in mut_reg3.size():
		if str(mut_reg3[i].get("value_id", "")) == "rose_999":
			removed_id = "rose_999"
			mut_reg3.remove_at(i)
			break
	assert(removed_id == "rose_999", "N3 变异必须生效（rose_999 已移除）")
	assert(_verify_id_sets(mut_reg3, prod_catalog) == "VALUE_CATALOG_ID_MISMATCH",
		"N3 删除覆盖项必须被同一 ID 集合验证器拒绝")

	# N4 VALUE_UNREGISTERED_MAGIC_NUMBER：变异 catalog 副本加入未登记值 -> 同一验证器拒绝
	var mut_cat4: Dictionary = prod_catalog.duplicate(true)
	mut_cat4["unregistered_magic"] = 12345
	assert(mut_cat4.has("unregistered_magic"), "N4 变异必须生效（catalog 加入未登记值）")
	assert(_validate_registered(_values, mut_cat4) == "VALUE_CATALOG_ID_MISMATCH",
		"N4 未登记魔法数字必须被同一验证器拒绝")

	# N5 VALUE_MULTIPLIER_APPLIED_TWICE：变异 catalog 副本 exp 倍率 20 -> 双向验证拒绝；
	#   变异生产 rewards（经验错误翻倍）-> 同一状态差验证器拒绝
	var mut_cat5: Dictionary = prod_catalog.duplicate(true)
	mut_cat5["player_exp_multiplier"] = 20
	assert(int(mut_cat5["player_exp_multiplier"]) != int(prod_catalog["player_exp_multiplier"]), "N5 变异必须生效（exp 倍率 20）")
	assert(str(_verify_bidirection(_values, mut_cat5).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N5 变异 catalog exp 倍率必须被同一双向验证器拒绝")
	var mut_rewards5: Dictionary = normal_rewards.duplicate(true)
	mut_rewards5["experience"] = 1000  # 模拟倍率翻倍错误（应为 500）
	assert(int(mut_rewards5["experience"]) != int(normal_rewards.get("experience", 0)), "N5 变异必须生效（rewards 经验翻倍）")
	assert(_verify_state_diff(mut_rewards5, 500, 0) == "VALUE_MULTIPLIER_APPLIED_TWICE",
		"N5 变异 rewards 必须被同一状态差验证器拒绝")

	# N6 VALUE_SCOPE_MISMATCH：变异 catalog 副本 normal 倍率误用 10 -> 双向验证拒绝；
	#   变异生产 rewards（普通怪军功误用 boss 10 倍）-> 同一状态差验证器拒绝
	var mut_cat6: Dictionary = prod_catalog.duplicate(true)
	mut_cat6["normal_military_multiplier"] = 10
	assert(int(mut_cat6["normal_military_multiplier"]) != int(prod_catalog["normal_military_multiplier"]), "N6 变异必须生效（normal 误用 10）")
	assert(str(_verify_bidirection(_values, mut_cat6).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N6 变异 catalog scope 必须被同一双向验证器拒绝")
	var forged_boss_merit: Dictionary = normal_rewards.duplicate(true)
	forged_boss_merit["military_merit"] = 5000  # 普通怪却给 boss 军功 5000（作用域错误）
	assert(int(forged_boss_merit["military_merit"]) != int(normal_rewards.get("military_merit", 0)), "N6 变异必须生效（普通怪军功伪造 boss 值）")
	assert(_verify_state_diff(forged_boss_merit, 500, 0) == "VALUE_SCOPE_MISMATCH",
		"N6 变异 rewards 作用域错误必须被同一状态差验证器拒绝")

	# N7 VALUE_PROBABILITY_BOUNDARY_MISMATCH：变异 catalog 副本战魂晶石 0.5 -> 0.51（真变异）-> 双向验证拒绝；
	#   真实生产接口边界已由步骤 6 正向验证（0.499999 成功 / 0.5 失败）
	var mut_cat7: Dictionary = prod_catalog.duplicate(true)
	mut_cat7["war_soul_crystal_success_rate"] = 0.51
	assert(float(mut_cat7["war_soul_crystal_success_rate"]) != float(prod_catalog["war_soul_crystal_success_rate"]),
		"N7 变异必须生效（0.5 -> 0.51，原值 %s != 变异值 %s）" % [str(prod_catalog["war_soul_crystal_success_rate"]), str(mut_cat7["war_soul_crystal_success_rate"])])
	assert(str(_verify_bidirection(_values, mut_cat7).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N7 变异 catalog 成功率必须被同一双向验证器拒绝")

	# N8 代码绑定负向：变异后的源码行不存在（模拟生产表达式被改动）-> _code_value 返回 null -> 双向验证拒绝
	var mut_cat8: Dictionary = prod_catalog.duplicate(true)
	mut_cat8["sale_grant"] = null
	assert(mut_cat8["sale_grant"] == null, "N8 变异必须生效（sale_grant 绑定失败）")
	assert(str(_verify_bidirection(_values, mut_cat8).get("error", "")) == "VALUE_EFFECTIVE_MISMATCH",
		"N8 代码绑定失败必须被同一双向验证器拒绝")

	print("PASS v1.39 value audit registry: independent production catalog (17/17 values bidirectional via single validator), exact line-bound code values, verified=%d, production state-diff exp/scope, production boundary API, 8 mutation-negatives via same validators" % verified_count)
	get_tree().quit(0)


func _duplicate_values(values: Array) -> Array:
	var out: Array = []
	for v: Dictionary in values:
		out.append(v.duplicate(true))
	return out
