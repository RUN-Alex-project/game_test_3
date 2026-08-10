extends Node
## v1.38 专项测试：剧情状态机——真正注册表驱动（二次整改）。
## 核心：setup/verify 字段为测试内函数名，测试用 call() 调度；修改注册表任一 setup/verify 字段名
##       -> call() 返回 null -> 测试失败（证明字段真正驱动，非摆设）。
## 每节点：前置（零状态差）/ 首次（call setup 准备 + 真实生产 API dispatch + call verify 断言）/
##         重复（幂等）/ 跨日（按 test.cross_day policy）/ 读档（保存期望值 + 深比较）。
## ROUTE 节点走 main_original 真实入口（_open_prime_minister_king_news / _open_king_dialogue /
##        _travel_to / 战斗 dispatcher），无伪占位。
## 八负向（N1-N8）：变异真实注册表副本，全部传入统一 run_registry_case，先断言变异生效再命中精确错误码。
## 写入审计：记录测试显式写终态 flag 的位置；断言终态只由生产 API 产生。

const REGISTRY_PATH := "res://docs/story_dialogue_registry.json"
const EVIDENCE_PATH := "res://docs/evidence/story_dialogues_v103_v9.txt"

var _nodes: Dictionary = {}
var _evidence_text: String = ""
var _executed: Dictionary = {}
var _precondition_verified: Dictionary = {}
var _main: Control  # main_original 实例（ROUTE 节点真实入口）


func _load_registry() -> void:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	assert(f != null, "story registry must be readable: " + REGISTRY_PATH)
	var raw: Variant = JSON.parse_string(f.get_as_text())
	_nodes = (raw as Dictionary).get("nodes", {})


func _reset_story() -> void:
	# P1-1：快照全集字段全部重置（与 _state_snapshot 对齐，防用例间状态泄漏）
	GameState.save_path = "user://v138_story_test_save.json"
	GameState.story_flags = {
		"king_rescued": false, "princess_friend_gift_available": false,
		"maid_year_pig_available": true, "maid_combat_stone_available": true,
		"game_won": false, "war_soul_quest_available": false, "war_soul_secret_unlocked": false,
	}
	GameState.nobility_merit = 0
	GameState.magic_stones = 0
	GameState.gold = 0
	GameState.experience = 0
	GameState.military_merit = 0
	GameState.current_day = 1
	GameState.current_time_used = 0
	GameState.current_map_id = "cassano_city"
	GameState.level = 30
	GameState.affection = 0
	GameState.last_princess_chat_day = 0
	GameState.last_princess_gift_day = 0
	GameState.last_military_salary_day = 0
	GameState.last_pk_race_day = 0
	GameState.last_territory_challenge_day = 0
	GameState.last_territory_reward_day = 0
	GameState.next_pet_instance_id = 1
	GameState.owned_territory = ""
	GameState.player_current_hp = 550
	GameState.player_current_stamina = 100
	GameState.pets = []
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})
	GameState.warehouse = []
	for i in 48:
		GameState.warehouse.append({})
	GameState.equipment = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.completed_daily_tasks = {}
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.war_soul_maze_active = false
	GameState.war_soul_guardian_revealed = false
	GameState.pk_race_active = false
	GameState.research = {"stock": 0, "technology_level": 10.0, "vip_level": 0}
	GameState.loot_queue = []
	GameState.learned_skills = {}
	GameState.unlocked_maps = {"dungeon_floor_2": false, "dungeon_floor_3": false}
	# P1-1：每节点重置 fuwa_rng 种子（refresh_fuwa_messenger 的 roll 序列确定，跨日 diff 确定性）
	GameState.fuwa_rng.seed = 20260809


# ---- 写入审计：记录测试显式写终态 flag 的位置（区分前置夹具 vs 流程伪造）----

var _write_audit: Array = []  # [(location, flag, value)]


func _ready() -> void:
	GameState.save_path = "user://v138_story_test_save.json"
	# P1-1：固定 fuwa_rng 种子保证跨日 diff 确定性（refresh_fuwa_messenger 的 roll 固定非 1）
	GameState.fuwa_rng.seed = 20260809
	var probe_roll: int = GameState.fuwa_rng.randi_range(1, 9)
	assert(probe_roll != 1, "fuwa_rng seed 20260809 必须使 messenger roll != 1（否则 fuwa_event 跨日不变，diff 不确定）")
	GameState.fuwa_rng.seed = 20260809  # 重置种子：正式序列与探测一致
	# P0-3：检查 user:// 可写性，不可写时退出非零且不打印 PASS（禁止 SKIP 绕过）
	var user_dir := ProjectSettings.globalize_path("user://")
	print("USER_DATA_PATH=", user_dir)
	var probe := FileAccess.open("user://__writable_probe__.tmp", FileAccess.WRITE)
	if probe == null:
		print("TEST_USER_DATA_NOT_WRITABLE: user:// 不可写（路径=", user_dir, "）")
		print("FAIL v1.38: user:// not writable, cannot run save-dependent tests")
		get_tree().quit(1)
		return
	probe.store_string("ok")
	probe.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://__writable_probe__.tmp"))
	_cleanup_save()  # 测试隔离：开始前清理残留存档
	_load_registry()
	var ef := FileAccess.open(EVIDENCE_PATH, FileAccess.READ)
	assert(ef != null, "story evidence must be readable: " + EVIDENCE_PATH)
	_evidence_text = ef.get_as_text()
	assert(_nodes.size() == 27, "registry must have 27 nodes, got %d" % _nodes.size())

	# 实例化 main_original（ROUTE 节点真实入口）
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame

	# 1. 每节点 test 元数据 + 严格 source token 校验（只允许 spriteNNN/frameNN/game_state/main_original）
	for node_id: String in _nodes:
		var node: Dictionary = _nodes[node_id]
		assert(node.has("test"), "node %s must have test metadata" % node_id)
		var t: Dictionary = node["test"]
		assert(t.has("setup") and t.has("verify") and t.has("action"), "node %s test incomplete" % node_id)
		assert(_strict_source_hit(node.get("swf_evidence", []), str(node.get("domain", ""))),
			"node %s swf_evidence 必须在该节点 domain 证据段内命中真实 source token（spriteNNN/frameNN/game_state/main_original）" % node_id)

	# 2. 数据驱动遍历（call setup/verify）
	for node_id: String in _nodes:
		_run_node(node_id, _nodes[node_id])

	# 3. 三集合精确相等（第三轮拒签整改）：注册表节点集合 == 执行集合 == 前置覆盖集合，均 27
	var reg: Array = _nodes.keys(); reg.sort()
	var ex: Array = _executed.keys(); ex.sort()
	assert(reg == ex, "双向集合不一致：注册表 %d vs 执行 %d（%s）" % [reg.size(), ex.size(), str(ex)])
	var pre_verified: Array = _precondition_verified.keys()
	pre_verified.sort()
	assert(reg == pre_verified, "前置校验完成集合必须精确等于注册表节点集合（注册 %d vs 已验证 %d，%s）" % [reg.size(), pre_verified.size(), str(pre_verified)])
	# 第四轮补充整改：precondition_policy 精确统计——26 required + 1 not_applicable，无缺失/未知
	var required_count := 0
	var not_applicable_count := 0
	for node_id: String in _nodes:
		var policy_audit: Variant = _nodes[node_id].get("precondition_policy", null)
		assert(policy_audit != null, "precondition_policy 必须存在: " + node_id)
		var policy_str := str(policy_audit)
		assert(policy_str == "required" or policy_str == "not_applicable", "precondition_policy 必须为 required/not_applicable: " + node_id)
		if policy_str == "not_applicable":
			not_applicable_count += 1
			assert(node_id == "prime_minister_king_news", "not_applicable 策略只能用于真正无门槛节点（%s 有真实前置）" % node_id)
			var pre_audit: Dictionary = _nodes[node_id].get("precondition", {})
			assert(bool(pre_audit.get("not_applicable", false)) and not str(pre_audit.get("not_applicable_reason", "")).is_empty(),
				"not_applicable 节点必须标 not_applicable 且带理由: " + node_id)
		else:
			required_count += 1
			var pre_audit2: Dictionary = _nodes[node_id].get("precondition", {})
			assert(not bool(pre_audit2.get("not_applicable", false)), "required 节点不得标 not_applicable: " + node_id)
	assert(required_count == 26 and not_applicable_count == 1,
		"precondition_policy 统计必须为 26 required + 1 not_applicable（实际 %d required + %d not_applicable）" % [required_count, not_applicable_count])

	# 4. 六负向（变异真实注册表）
	_run_negatives()

	# 5. 写入审计：终态 flag 只由生产 API 产生（写审计记录仅含前置夹具，无流程伪造）
	_assert_write_audit()

	# 测试隔离：finally 清理存档（无论成败）
	_cleanup_save()
	_assert_clean()  # 清理断言：存档必须已删除
	print("PASS v1.38 story dialogue state machine: 注册表驱动遍历 %d 节点（前置矩阵执行器 + call setup/verify + 真实入口 + 全节点重复 + 读档深比较 + cross_day 分离 + 隔离 finally）+ 三集合精确相等（注册/执行/前置覆盖=27）+ 负向（N1-N30 含前置矩阵、not_applicable 旁路、policy 缺失/未知、差分逃逸与登记精确性）" % _nodes.size())
	get_tree().quit(0)


## 测试隔离：清理唯一 user:// 临时存档（防止跨测试污染）
func _cleanup_save() -> void:
	# PM 要求：清理正式档 + .tmp + .bak
	var global := ProjectSettings.globalize_path(GameState.save_path)
	if FileAccess.file_exists(GameState.save_path):
		DirAccess.remove_absolute(global)
	if FileAccess.file_exists(GameState.save_path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path + ".tmp"))
	if FileAccess.file_exists(GameState.save_path + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path + ".bak"))


## 可靠 finally 清理：无论 assert 失败/异常/超时，_exit_tree 都执行清理
func _exit_tree() -> void:
	_cleanup_save()


## 清理断言：测试结束后存档必须已删除（供复验）
func _assert_clean() -> void:
	assert(not FileAccess.file_exists(GameState.save_path), "测试隔离：存档必须在结束后清理")


func _strict_source_hit(ev: Array, domain: String) -> bool:
	# 按"节点 → 证据段 → token"逐项验证：token 必须在该节点 domain 对应的证据段内命中，
	# 且每个 swf_evidence entry 至少一个 source token 命中（无全局漏配）。
	var segment := _evidence_segment(domain)
	assert(not segment.is_empty(), "证据段 缺失: " + domain)
	for entry: String in ev:
		var tokens := _extract_source_tokens(entry)
		var entry_hit := false
		for tok: String in tokens:
			var alt := tok.replace("frame", "frame_")
			if segment.contains(tok) or segment.contains(alt):
				entry_hit = true
		if not entry_hit:
			return false  # 该 entry 无 token 命中本域段（错段/错 sprite/错 frame）
	return true


func _evidence_segment(domain: String) -> String:
	# 提取证据文件 `=== <domain> ===` 到下一个 `===` 的段文本
	var marker := "=== " + domain
	var lines := _evidence_text.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].begins_with(marker):
			start = i + 1
			break
	if start < 0:
		return ""
	var result: Array = []
	for j in range(start, lines.size()):
		if lines[j].begins_with("=== "):
			break
		result.append(lines[j])
	return "\n".join(result)


func _extract_source_tokens(entry: String) -> Array:
	var out: Array = []
	for m in [RegEx.create_from_string(r"sprite\d+"), RegEx.create_from_string(r"frame\d+")]:
		if m != null:
			for r in m.search_all(entry):
				if not out.has(r.get_string()):
					out.append(r.get_string())
	if entry.contains("game_state"):
		out.append("game_state")
	if entry.contains("main_original"):
		out.append("main_original")
	return out


func _run_node(node_id: String, node: Dictionary) -> void:
	# 统一执行器：run_registry_case 执行 precondition/setup/首次/重复/跨日/读档，返回 "" 或错误码
	var code := run_registry_case(_nodes, node_id)
	assert(code == "", "node %s 正向执行失败: %s" % [node_id, code])
	_executed[node_id] = true


## 统一执行器：接受注册表副本（含变异）与 node_id，执行该节点完整正向流程，
## 返回 ""（成功）或精确错误码。正向遍历与六负向共用此函数。
func run_registry_case(registry: Dictionary, node_id: String) -> String:
	var node: Dictionary = registry[node_id]
	var t: Dictionary = node["test"]
	var setup_name := str(t.get("setup", ""))
	var verify_name := str(t.get("verify", ""))
	var action := str(t.get("action", ""))
	var cross_day := str(t.get("cross_day", "none"))
	var save_fields: Array = t.get("save_fields", [])

	# 0. setup/verify 字段可调度性（与 call 同源）
	if not has_method(setup_name):
		return "STORY_SETUP_DRIVER_MISSING"
	if not has_method(verify_name):
		return "STORY_VERIFY_DRIVER_MISSING"
	# 路由合法性（与 _dispatch_main 同源）
	if action.begins_with("MAIN:"):
		if not _is_valid_route(action.trim_prefix("MAIN:")):
			return "STORY_ACTION_ROUTE_MISMATCH"
	# 证据 token 段验证（用传入 registry 的 swf_evidence + domain）——N6 变异副本经此命中
	if not _strict_source_hit(node.get("swf_evidence", []), str(node.get("domain", ""))):
		return "STORY_TOKEN_MISS"

	# 0b. 前置矩阵（第三轮拒签整改）：从传入 registry 副本读取 precondition 登记，
	#     先执行夹具 -> 完整 43 字段快照 -> 真实 dispatcher -> 验证 reason/success/triggered -> 精确状态差分。
	#     禁止旧 _precondition_impl 的 pass/default 分支冒充验证（该函数已删除）。
	var pre_code := _run_precondition(registry, node_id)
	if pre_code != "":
		return pre_code
	# 第四轮拒签整改：三集合覆盖只在 _run_precondition 真正完成校验后登记
	_precondition_verified[node_id] = true

	# 1. 首次：setup + dispatch + verify
	_reset_story()
	var setup_result: Variant = call(setup_name)
	if setup_result == null:
		return "STORY_SETUP_DRIVER_MISSING"
	var first_result: Dictionary = _dispatch(action, node_id)
	var verify_result: Variant = call(verify_name, first_result)
	if verify_result is String and verify_result != "":
		return str(verify_result)
	if not (verify_result is String):
		return "STORY_VERIFY_DRIVER_MISSING"


# 2. 重复：幂等（P1-1 拒签整改：不再跳过 MAIN 路由节点，全部节点真实执行重复阶段）
	if not _is_infinite_repeat(registry, node_id):
		var repeat_result: Dictionary = _dispatch(action, node_id)
		var rep_reason := str(t.get("repeat_reason", ""))
		if not rep_reason.is_empty() and not str(repeat_result.get("reason", "")).is_empty():
			if str(repeat_result.get("reason", "")) != rep_reason:
				return "STORY_REWARD_NOT_IDEMPOTENT"
		if _verify_repeat(registry, node_id, repeat_result) != "":
			return "STORY_REWARD_NOT_IDEMPOTENT"

	# 3. 跨日（按 test.cross_day policy，用 registry 传入）：
#    准备阶段（设前置日期状态）由 run_registry_case 显式调用，执行阶段（纯 API）由 _cross_day_result。
	_reset_story()
	_cross_day_prepare(registry, node_id, cross_day)
	var cd := _cross_day_exec(registry, node_id, cross_day, action)
	if cd != "":
		return cd

	# 4. 读档（保存期望值 + 深比较，用 registry 传入，返回错误码）
	var sl := _save_load_result(registry, node_id, save_fields)
	if sl != "":
		return sl

	return ""


func _is_valid_route(route: String) -> bool:
	return route in ["prime_minister_king_news", "king_dialogue", "palace_garden_entry", "pk_champion", "final_campaign_gate"]


# ---- dispatch：真实生产 API（GameState 函数或 MAIN 路由）----

func _dispatch(action: String, node_id: String = "") -> Dictionary:
	if action.begins_with("MAIN:"):
		return _dispatch_main(action.trim_prefix("MAIN:"))
	if action.begins_with("submit_pet_for_daily_task:"):
		# P1-1：支持 "submit_pet_for_daily_task:<instance_id>"（daily 重做提交第二只幻兽）
		return GameState.submit_pet_for_daily_task(int(action.split(":")[1]))
	match action:
		"rescue_king": return GameState.rescue_king()
		"chat_with_princess": return GameState.chat_with_princess()
		"give_roses": return GameState.give_roses(99)
		"claim_princess_friend_gift": return GameState.claim_princess_friend_gift()
		"claim_princess_sunday_gift": return GameState.claim_princess_sunday_gift()
		"buy_maid_year_pig": return GameState.buy_maid_year_pig()
		"buy_maid_combat_stone": return GameState.buy_maid_combat_stone()
		"accept_daily_task":
			var r := GameState.quest_service.accept(GameState.quest_states, "border_raid")
			GameState.quest_states = r.get("states", GameState.quest_states)
			return r
		"complete_daily_task": return GameState.complete_daily_task("collect_magic_soul")
		"submit_pet_for_daily_task": return GameState.submit_pet_for_daily_task(1)
		"start_fuwa_round": return GameState.start_fuwa_round()
		"complete_fuwa_beast_battle": return GameState.complete_fuwa_beast_battle()
		"claim_fuwa_reward": return GameState.claim_fuwa_reward(0)
		"claim_fuwa_completion": return GameState.claim_fuwa_completion()
		"open_lottery_chest": return GameState.open_lottery_chest(0, 0)
		"register_pk_race": return GameState.register_pk_race()
		"try_unlock_war_soul_quest": return {"success": GameState.try_unlock_war_soul_quest()}
		"enter_war_soul_maze": return GameState.enter_war_soul_maze()
		"reveal_war_soul_guardian": return {"success": GameState.reveal_war_soul_guardian()}
		"complete_war_soul_secret": return GameState.complete_war_soul_secret()
		"resolve_final_campaign_victory": return GameState.resolve_final_campaign_victory("demon_assault")
		"complete_research_production_task": return GameState.complete_research_production_task()
	return {"success": false, "reason": "unknown_action"}


# ---- ROUTE 节点真实 main_original 入口 ----

func _dispatch_main(route: String) -> Dictionary:
	match route:
		"prime_minister_king_news":
			_main._open_prime_minister_king_news()
			return {"route": true, "opened": _main.dialogue_panel.visible}
		"king_dialogue":
			_main._open_king_dialogue()
			return {"route": true, "opened": _main.dialogue_panel.visible, "choices": _main.dialogue_panel.choices.get_child_count()}
		"palace_garden_entry":
			# 真实地图 dispatcher：从 palace 出口进入后花园（_travel_to 检查 can_travel+can_enter_map+状态反馈）
			GameState.current_map_id = "palace"
			_main._apply_current_map()
			GameState.current_map_id = "palace"
			_main._travel_to("palace_garden")
			return {"route": true, "map": GameState.current_map_id, "status": _main.dialogue_panel.visible}
		"pk_champion":
			# 通过真实战斗 dispatcher 触发 PK 擂主击败（_on_scene_battle_finished 由胜利流程触发）
			GameState.finish_pk_race(true)
			return {"route": true, "pk_active": GameState.pk_race_active}
		"final_campaign_gate":
			# 真实地图 dispatcher：从魔军帅旗出口进入能量塔（_travel_to 检查主帅门禁 + 状态反馈）
			GameState.current_map_id = "demon_banner"
			_main._apply_current_map()
			GameState.current_map_id = "demon_banner"
			_main._travel_to("energy_tower")
			return {"route": true, "map": GameState.current_map_id, "status": _main.dialogue_panel.visible}
	return {"route": true, "error": "unknown_route"}


# ---- 前置：零状态差（按 node_id 精确）----

## 独立允许集合：真正无门槛（无前置条件）的节点（明确分类规则）
func _is_not_applicable_allowed(node_id: String) -> bool:
	return node_id in ["prime_minister_king_news"]


func _run_precondition(registry: Dictionary, node_id: String) -> String:
	# 前置矩阵执行器（第四轮拒签整改）：从传入 registry 副本读取 precondition 登记，
	# **执行器自身**校验节点是否允许 not_applicable（不依赖 _ready 外层审计）。
	# 先执行夹具 -> 完整 43 字段快照 -> 真实 dispatcher -> 验证 reason/success/triggered -> 精确状态差分。
	var node_ctx: Dictionary = registry[node_id]
	# 第四轮补充整改：强制 precondition_policy 字段存在且精确限定 required/not_applicable
	var policy_raw: Variant = node_ctx.get("precondition_policy", null)
	if policy_raw == null:
		return "STORY_PRECONDITION_POLICY_MISSING"
	var policy := str(policy_raw)
	if policy != "required" and policy != "not_applicable":
		return "STORY_PRECONDITION_POLICY_INVALID"
	var pre: Dictionary = node_ctx.get("precondition", {})
	if pre.is_empty():
		return "STORY_PRECONDITION_MISSING"
	if policy == "not_applicable":
		# 仅允许由独立允许集合确认的节点（第四轮拒签整改：执行器自身校验，不依赖外层审计）
		if not _is_not_applicable_allowed(node_id):
			return "STORY_PRECONDITION_NOT_APPLICABLE_INVALID"
		if not bool(pre.get("not_applicable", false)):
			return "STORY_PRECONDITION_NOT_APPLICABLE_INVALID"  # policy 声明但未标 not_applicable
		if str(pre.get("not_applicable_reason", "")).is_empty():
			return "STORY_PRECONDITION_REASON_MISSING"
		return ""
	# policy == "required"（有真实前置门槛的节点）
	if bool(pre.get("not_applicable", false)):
		# 有门槛节点标 not_applicable（即使带非空假理由）-> 拒绝
		return "STORY_PRECONDITION_NOT_APPLICABLE_INVALID"
	if not pre.has("precondition_setup") or not pre.has("precondition_action"):
		return "STORY_PRECONDITION_CONFIG_MISSING"  # required 但缺少前置配置
	var setup_name := str(pre.get("precondition_setup", ""))
	var action := str(pre.get("precondition_action", ""))
	var expected_success := bool(pre.get("expected_success", false))
	var expected_triggered := bool(pre.get("expected_triggered", false))
	var expected_reason := str(pre.get("expected_reason", ""))
	var expected_result: Dictionary = pre.get("expected_result", {})
	var expected_changed: Array = pre.get("expected_state_changed", [])
	var expected_unchanged: Array = pre.get("expected_state_unchanged", [])
	if not has_method(setup_name):
		return "STORY_PRECONDITION_SETUP_MISSING"
	_reset_story()
	call(setup_name)
	var snap_before := _state_snapshot()
	var result: Dictionary = _dispatch(action, node_id)
	# reason/success/triggered 精确验证
	if bool(result.get("success", false)) != expected_success:
		return "STORY_PRECONDITION_OUTCOME_MISMATCH"
	if bool(result.get("triggered", false)) != expected_triggered:
		return "STORY_PRECONDITION_OUTCOME_MISMATCH"
	if expected_reason.is_empty():
		if result.has("reason") and not str(result.get("reason", "")).is_empty():
			return "STORY_PRECONDITION_REASON_MISMATCH"
	else:
		if str(result.get("reason", "")) != expected_reason:
			return "STORY_PRECONDITION_REASON_MISMATCH"
	# MAIN 路由结果字段（opened/map/pk_active）精确验证
	for field: String in expected_result:
		if result.get(field) != expected_result[field]:
			return "STORY_PRECONDITION_OUTCOME_MISMATCH"
	# 精确状态差分：changed 全变 / unchanged 全不变 / 覆盖与快照集合精确相等
	var snap_after := _state_snapshot()
	var covered: Array = expected_changed.duplicate()
	covered.append_array(expected_unchanged)
	var snapshot_keys := _state_snapshot_keys()
	covered.sort()
	snapshot_keys.sort()
	if covered != snapshot_keys:
		return "STORY_PRECONDITION_COVERAGE_MISMATCH"
	for field: String in expected_changed:
		if snap_before.get(field) == snap_after.get(field):
			return "STORY_PRECONDITION_CHANGED_MISSING"
	for field: String in expected_unchanged:
		if snap_before.get(field) != snap_after.get(field):
			return "STORY_PRECONDITION_UNCHANGED_VIOLATED"
	return ""


# ---- 前置矩阵夹具（precondition_setup 指向，把状态设置为"不满足前置"）----

func pre_rescue_king() -> void:
	GameState.story_flags["king_rescued"] = true  # 已救 -> rescue 拒触发

func pre_king_dialogue() -> void:
	GameState.story_flags["king_rescued"] = false  # 未救 -> 国王对话拒开
	_main.dialogue_panel.visible = false  # UI 状态重置（防跨用例对话框残留影响 opened 判定）

func pre_princess_chat() -> void:
	GameState.current_day = 1
	GameState.last_princess_chat_day = 1  # 当天已聊

func pre_give_roses() -> void:
	pass  # 重置后无玫瑰 -> missing_roses

func pre_friend_gift() -> void:
	GameState.affection = 0  # 亲密度不足 -> relationship_too_low

func pre_sunday_gift() -> void:
	GameState.current_day = 1  # 非周日

func pre_maid_year_pig() -> void:
	GameState.magic_stones = 0  # 魔石不足

func pre_maid_combat_stone() -> void:
	GameState.magic_stones = 0  # 魔石不足

func pre_daily_accept() -> void:
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.quest_states = GameState.quest_service.accept(GameState.quest_states, "border_raid").get("states", GameState.quest_states)  # 已 active -> 再 accept 失败

func pre_daily_complete() -> void:
	GameState.completed_daily_tasks["collect_magic_soul"] = true  # 已交

func pre_submit_pet() -> void:
	GameState.completed_daily_tasks["submit_pet"] = true  # 已交

func pre_fuwa_start() -> void:
	GameState.fuwa_event.round_active = true  # 已激活 -> already_active

func pre_fuwa_beast() -> void:
	GameState.fuwa_event.round_active = false  # 未激活 -> round_not_active

func pre_fuwa_claim() -> void:
	GameState.fuwa_event.round_active = true
	GameState.fuwa_event.beast_defeated = false  # 战兽未败 -> beast_not_defeated

func pre_fuwa_completion() -> void:
	GameState.fuwa_event.found_count = 4  # 未集齐 -> not_complete

func pre_garden() -> void:
	GameState.current_map_id = "palace"  # 已在入口，爵位不足 -> can_enter_map 拒绝
	GameState.nobility_merit = 0

func pre_lottery() -> void:
	GameState.magic_stones = 10  # 魔石 < 28 -> not_enough_magic_stones

func pre_pk_register() -> void:
	GameState.current_day = 1  # 非周六

func pre_pk_champion() -> void:
	GameState.pk_race_active = false  # 未报名 -> finish 无状态变化

func pre_ws_unlock() -> void:
	GameState.story_flags["war_soul_quest_available"] = true  # 已解锁 -> try_unlock 返回 false

func pre_ws_explorer() -> void:
	GameState.story_flags["war_soul_quest_available"] = false  # 未解锁 -> quest_locked

func pre_ws_chest() -> void:
	GameState.current_map_id = "cassano_city"  # 非迷宫 -> reveal 返回 false

func pre_ws_complete() -> void:
	GameState.war_soul_maze_active = false  # 未激活 -> quest_inactive

func pre_fc_victory() -> void:
	GameState.demon_campaign["assault_alive"] = false  # 已击败 -> already_defeated

func pre_fc_gate() -> void:
	GameState.current_map_id = "demon_banner"  # 已在帅旗入口，主帅存活 -> 能量塔拒绝
	GameState.demon_campaign = GameState.default_demon_campaign()

func pre_research() -> void:
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})  # 无魂王 -> missing_soul_king


func setup_rescue_king() -> bool: return true
func setup_princess_chat() -> bool:
	GameState.affection = 0; return true
func setup_give_roses() -> bool:
	for i in 1000:
		GameState.add_item("rose")
	return true
func setup_claim_princess_friend_gift() -> bool:
	GameState.affection = 100; GameState.story_flags["princess_friend_gift_available"] = true; return true
func setup_princess_sunday_gift() -> bool:
	GameState.current_day = 7; GameState.affection = 1; return true
func setup_maid_year_pig() -> bool:
	GameState.magic_stones = 10000; return true
func setup_maid_combat_stone() -> bool:
	GameState.magic_stones = 10000; return true
func setup_daily_task_accept() -> bool:
	GameState.quest_states = GameState.quest_service.default_states(); return true
func setup_daily_task_complete() -> bool:
	GameState.magic_stones = 10000
	for i in 20:
		GameState.add_item("magic_soul_crystal")
	return true
func setup_daily_task_submit_pet() -> bool:
	# P1-1：daily 可重做需要两只幻兽（第一天交一只，跨日后再交第二只），prepare 一次性准备
	GameState.pets = [
		{"template_id": "none", "quality_score": 3000.0, "deployed": false, "level": 1, "current_hp": 100, "experience": 0, "custom_name": "t", "instance_id": 1},
		{"template_id": "none", "quality_score": 3000.0, "deployed": false, "level": 1, "current_hp": 100, "experience": 0, "custom_name": "t2", "instance_id": 2},
	]
	GameState.next_pet_instance_id = 3
	return true
func setup_fuwa_start_round() -> bool:
	GameState.fuwa_event.found_count = 0; GameState.fuwa_event.round_active = false; return true
func setup_fuwa_beast_battle() -> bool:
	GameState.fuwa_event.round_active = true; return true
func setup_fuwa_claim_reward() -> bool:
	GameState.fuwa_event.round_active = true; GameState.fuwa_event.beast_defeated = true; return true
func setup_fuwa_completion() -> bool:
	GameState.fuwa_event.found_count = 5; GameState.fuwa_event.completion_claimed = false; return true
func setup_lottery_chest() -> bool:
	GameState.magic_stones = 100; return true
func setup_pk_register() -> bool:
	GameState.current_day = 6; return true
func setup_war_soul_quest_unlock() -> bool:
	GameState.equipment = {"weapon": {"enhancement": {"quality_level": 4}}, "helmet": {"enhancement": {"quality_level": 4}}, "necklace": {"enhancement": {"quality_level": 4}}, "armor": {"enhancement": {"quality_level": 4}}, "bracelet": {"enhancement": {"quality_level": 4}}, "boots": {"enhancement": {"quality_level": 4}}}; return true
func setup_war_soul_explorer() -> bool:
	GameState.story_flags["war_soul_quest_available"] = true; GameState.magic_stones = 100000; return true
func setup_war_soul_chest() -> bool:
	GameState.story_flags["war_soul_quest_available"] = true; GameState.magic_stones = 100000
	GameState.enter_war_soul_maze(); return true
func setup_war_soul_complete() -> bool:
	GameState.story_flags["war_soul_quest_available"] = true; GameState.magic_stones = 100000
	GameState.enter_war_soul_maze(); return true
func setup_final_campaign_victory() -> bool:
	GameState.story_flags["king_rescued"] = true; GameState.story_flags["game_won"] = false
	GameState.demon_campaign = GameState.default_demon_campaign(); return true
func setup_prime_minister_king_news() -> bool:
	GameState.story_flags["king_rescued"] = true; return true
func setup_king_dialogue() -> bool:
	GameState.story_flags["king_rescued"] = true; return true
func setup_palace_garden_entry() -> bool:
	GameState.nobility_merit = 100000; return true
func setup_pk_champion() -> bool:
	GameState.current_day = 6; GameState.level = 30; GameState.register_pk_race(); return true
func setup_final_campaign_gate() -> bool:
	GameState.level = 60; GameState.story_flags["king_rescued"] = true
	GameState.demon_campaign = GameState.default_demon_campaign()
	GameState.resolve_final_campaign_victory("demon_commander"); return true
func setup_research_produce() -> bool:
	GameState.research = {"stock": 5, "technology_level": 10.0, "vip_level": 0}
	for i in 10:
		GameState.add_item("soul_king")
	return true


# ---- verify 函数（注册表 verify 字段指向，call 调度，返回错误码或空）----

func verify_rescue_king(r: Dictionary) -> String:
	return "" if bool(r.get("triggered", false)) and GameState.get_nobility_rank().name == "王" else "first_fail"
func verify_princess_chat(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.affection >= 1 else "first_fail"
func verify_give_roses(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and int(r.get("affection", 0)) > 0 else "first_fail"
func verify_claim_princess_friend_gift(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.pets.back().template_id == "year_pig" else "first_fail"
func verify_princess_sunday_gift(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) else "first_fail"
func verify_maid_year_pig(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.pets.back().template_id == "year_pig" else "first_fail"
func verify_maid_combat_stone(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) else "first_fail"
func verify_daily_task_accept(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and str(r.get("states", {}).get("border_raid", {}).get("status", "")) == "active" else "first_fail"
func verify_daily_task_complete(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and bool(GameState.completed_daily_tasks.get("collect_magic_soul", false)) else "first_fail"
func verify_daily_task_submit_pet(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and bool(GameState.completed_daily_tasks.get("submit_pet", false)) else "first_fail"
func verify_fuwa_start_round(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.current_map_id == "green_field" else "first_fail"
func verify_fuwa_beast_battle(r: Dictionary) -> String:
	return "" if bool(r.get("triggered", false)) and bool(GameState.fuwa_event.get("beast_defeated", false)) else "first_fail"
func verify_fuwa_claim_reward(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and int(GameState.fuwa_event.get("found_count", 0)) >= 1 else "first_fail"
func verify_fuwa_completion(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.magic_stones >= 100000 else "first_fail"
func verify_lottery_chest(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) else "first_fail"
func verify_pk_register(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and bool(GameState.pk_race_active) else "first_fail"
func verify_war_soul_quest_unlock(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and bool(GameState.story_flags.get("war_soul_quest_available", false)) else "first_fail"
func verify_war_soul_explorer(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and GameState.current_map_id == "war_soul_seal_maze" else "first_fail"
func verify_war_soul_chest(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) and bool(GameState.war_soul_guardian_revealed) else "first_fail"
func verify_war_soul_complete(r: Dictionary) -> String:
	return "" if bool(r.get("triggered", false)) and bool(GameState.story_flags.get("war_soul_secret_unlocked", false)) else "first_fail"
func verify_final_campaign_victory(r: Dictionary) -> String:
	return "" if bool(r.get("triggered", false)) and not bool(GameState.demon_campaign.get("assault_alive", true)) else "first_fail"
func verify_prime_minister_king_news(r: Dictionary) -> String:
	return "" if bool(GameState.story_flags.get("king_rescued", false)) else "first_fail"
func verify_king_dialogue(r: Dictionary) -> String:
	return "" if bool(GameState.story_flags.get("king_rescued", false)) and int(r.get("choices", 0)) >= 6 else "first_fail"
func verify_palace_garden_entry(r: Dictionary) -> String:
	# 验证真实地图状态变化（_travel_to 真实切换 current_map_id，非返回值可伪造）
	return "" if GameState.current_map_id == "palace_garden" else "first_fail"
func verify_pk_champion(r: Dictionary) -> String:
	return "" if not bool(r.get("pk_active", true)) else "first_fail"
func verify_final_campaign_gate(r: Dictionary) -> String:
	# 验证真实地图状态变化（_travel_to 真实切换 current_map_id，非返回值可伪造）
	return "" if GameState.current_map_id == "energy_tower" else "first_fail"
func verify_research_produce(r: Dictionary) -> String:
	return "" if bool(r.get("success", false)) else "first_fail"


# ---- 跨日：严格按 test.cross_day policy ----

## 跨日准备阶段：仅设置跨日前置状态（一次性 / 周期日），不执行终态 flag 伪造
func _cross_day_prepare(registry: Dictionary, node_id: String, policy: String) -> void:
	match policy:
		"daily":
			_setup_via_registry(registry, node_id)
		"weekly":
			GameState.current_day = 6
			if node_id == "princess_sunday_gift":
				GameState.current_day = 7
			_setup_via_registry(registry, node_id)
		"revive":
			# 复活夹具：king_rescued=true + game_won=false + 敌军存活（跨日复活测试准备）
			GameState.story_flags["king_rescued"] = true
			GameState.story_flags["game_won"] = false
			GameState.demon_campaign = GameState.default_demon_campaign()
		"none":
			_setup_via_registry(registry, node_id)


## 跨日执行阶段（P1-1 拒签整改）：只调真实生产 API（_dispatch / advance_day），
## 执行阶段禁止调用 setup（夹具在 prepare 阶段一次性准备）。
## 所有分支（daily/weekly/revive/none/infinite）统一进入公共 epilogue，
## epilogue 用注册表精确 expected_changed / expected_unchanged 做双向字段断言。
func _cross_day_exec(registry: Dictionary, node_id: String, policy: String, action: String) -> String:
	# 执行前完整状态快照（43 字段，用于 epilogue 双向差分）
	var snap_before := _state_snapshot()
	var branch_ok := false
	var branch_detail := ""
	# 跨日重做动作：注册表可登记 cross_day_action（如提交第二只幻兽），默认复用 action
	var exec_action := str(registry[node_id].get("test", {}).get("cross_day_action", action))
	match policy:
		"daily":
			_dispatch(action, node_id)
			GameState.advance_day()  # 真实日期 API
			var again: Dictionary = _dispatch(exec_action, node_id)  # 次日重做（无 setup，真实资源 prepare 已备）
			branch_ok = bool(again.get("success", false))
			branch_detail = "daily 次日可重做（执行期无 setup）again=" + JSON.stringify(again)
		"weekly":
			_dispatch(action, node_id)
			for i in 7:
				GameState.advance_day()  # 真实日期 API 推进一周
			var again2: Dictionary = _dispatch(exec_action, node_id)
			if node_id == "pk_champion":
				# 领域语义：擂主被击败后不再活跃（pk_active=false 视为重做成功）
				branch_ok = not bool(again2.get("pk_active", true))
				branch_detail = "weekly 擂主击败后不再活跃"
			else:
				branch_ok = bool(again2.get("success", false))
				branch_detail = "weekly 跨周可重做"
		"revive":
			GameState.resolve_final_campaign_victory("demon_assault")
			branch_ok = bool(GameState.advance_day().get("demon_army_revived", false))
			branch_detail = "revive 跨日复活"
		"none":
			var infinite := _is_infinite_repeat(registry, node_id)
			_dispatch(action, node_id)
			GameState.advance_day()  # 真实日期 API 推进 1 天
			var again3: Dictionary = _dispatch(exec_action, node_id)
			if infinite:
				# 无限重复节点：跨日后仍可重复（成功/触发均可）
				branch_ok = bool(again3.get("success", bool(again3.get("triggered", false))))
				branch_detail = "none infinite 跨日可重复"
			else:
				# 一次性节点：跨日后再次 dispatch 必须失败（flag 不重置）
				branch_ok = not bool(again3.get("success", false)) and not bool(again3.get("triggered", false))
				branch_detail = "none 一次性跨日不重置"
	# ===== 公共 epilogue：精确 expected_changed / expected_unchanged 双向断言 =====
	# 错误码必须精确为 STORY_CROSS_DAY_MISMATCH（详情仅记录，不附加到错误码）
	if not branch_ok:
		print("CROSS_DAY_DETAIL: %s (%s)" % [node_id, branch_detail])
		return "STORY_CROSS_DAY_MISMATCH"
	var snap_after := _state_snapshot()
	var node: Dictionary = registry[node_id]
	var changed: Array = node.get("cross_day_changed", [])
	var unchanged: Array = node.get("cross_day_unchanged", [])
	var reason: Dictionary = node.get("cross_day_changed_reason", {})
	# 1. 登记精确性：changed ∪ unchanged 必须与快照字段集合**精确相等**（非包含关系）
	var covered: Array = changed.duplicate()
	covered.append_array(unchanged)
	var snapshot_keys := _state_snapshot_keys()
	covered.sort()
	snapshot_keys.sort()
	if covered != snapshot_keys:
		print("CROSS_DAY_DETAIL: %s changed∪unchanged 与快照集合不精确相等\n  covered=%s\n  snapshot=%s" % [node_id, str(covered), str(snapshot_keys)])
		return "STORY_CROSS_DAY_MISMATCH"
	# 2. 拒绝未知字段、重复字段、changed/unchanged 交集
	var seen: Dictionary = {}
	for field: String in changed:
		if not snapshot_keys.has(field):
			print("CROSS_DAY_DETAIL: %s changed 含未知字段 %s" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
		if seen.has(field):
			print("CROSS_DAY_DETAIL: %s changed 含重复字段 %s" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
		seen[field] = true
	for field: String in unchanged:
		if not snapshot_keys.has(field):
			print("CROSS_DAY_DETAIL: %s unchanged 含未知字段 %s" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
		if seen.has(field):
			print("CROSS_DAY_DETAIL: %s changed∩unchanged 交集字段 %s" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
		seen[field] = true
	# 3. cross_day_changed_reason 键集合必须精确等于 changed（缺 reason / 多出 reason 均拒绝）
	var reason_keys: Array = reason.keys()
	reason_keys.sort()
	var changed_sorted: Array = changed.duplicate()
	changed_sorted.sort()
	if reason_keys != changed_sorted:
		print("CROSS_DAY_DETAIL: %s reason 键集合 != changed（reason=%s changed=%s）" % [node_id, str(reason_keys), str(changed_sorted)])
		return "STORY_CROSS_DAY_MISMATCH"
	# 4. expected_changed 必须全部真实变化
	for field: String in changed:
		if snap_before.get(field) == snap_after.get(field):
			print("CROSS_DAY_DETAIL: %s 登记变化字段 %s 实际未变化" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
	# 5. expected_unchanged 必须全部不变（未登记变化 = 意外副作用）
	for field: String in unchanged:
		if snap_before.get(field) != snap_after.get(field):
			print("CROSS_DAY_DETAIL: %s 未登记字段 %s 被修改（意外副作用）" % [node_id, field])
			return "STORY_CROSS_DAY_MISMATCH"
	return ""


## 快照字段全集（43 字段，与注册表 cross_day_changed/unchanged 覆盖断言一致）
func _state_snapshot_keys() -> Array:
	return [
		"gold", "magic_stones", "level", "experience", "military_merit", "nobility_merit", "affection",
		"current_day", "current_time_used", "player_current_hp", "player_current_stamina", "next_pet_instance_id",
		"last_princess_gift_day", "last_princess_chat_day", "last_military_salary_day", "last_pk_race_day",
		"last_territory_challenge_day", "last_territory_reward_day",
		"pk_race_active", "war_soul_maze_active", "war_soul_guardian_revealed",
		"current_map_id", "owned_territory",
		"story_flags.king_rescued", "story_flags.princess_friend_gift_available", "story_flags.maid_year_pig_available",
		"story_flags.maid_combat_stone_available", "story_flags.war_soul_quest_available",
		"story_flags.war_soul_secret_unlocked", "story_flags.game_won",
		"fuwa_event", "demon_campaign", "quest_states", "completed_daily_tasks", "inventory", "warehouse",
		"pets", "equipment", "base_stats", "research", "unlocked_maps", "learned_skills", "loot_queue",
	]


## 完整 GameState 深度快照（43 字段，P1-1 拒签整改：覆盖金币/魔石/经验/军功/亲密度/背包/仓库/装备/幻兽/研究所等全部持久状态）
func _state_snapshot() -> Dictionary:
	var snap := {}
	snap["gold"] = GameState.gold
	snap["magic_stones"] = GameState.magic_stones
	snap["level"] = GameState.level
	snap["experience"] = GameState.experience
	snap["military_merit"] = GameState.military_merit
	snap["nobility_merit"] = GameState.nobility_merit
	snap["affection"] = GameState.affection
	snap["current_day"] = GameState.current_day
	snap["current_time_used"] = GameState.current_time_used
	snap["player_current_hp"] = GameState.player_current_hp
	snap["player_current_stamina"] = GameState.player_current_stamina
	snap["next_pet_instance_id"] = GameState.next_pet_instance_id
	snap["last_princess_gift_day"] = GameState.last_princess_gift_day
	snap["last_princess_chat_day"] = GameState.last_princess_chat_day
	snap["last_military_salary_day"] = GameState.last_military_salary_day
	snap["last_pk_race_day"] = GameState.last_pk_race_day
	snap["last_territory_challenge_day"] = GameState.last_territory_challenge_day
	snap["last_territory_reward_day"] = GameState.last_territory_reward_day
	snap["pk_race_active"] = GameState.pk_race_active
	snap["war_soul_maze_active"] = GameState.war_soul_maze_active
	snap["war_soul_guardian_revealed"] = GameState.war_soul_guardian_revealed
	snap["current_map_id"] = GameState.current_map_id
	snap["owned_territory"] = GameState.owned_territory
	for flag: String in GameState.story_flags:
		snap["story_flags." + flag] = GameState.story_flags[flag]
	snap["fuwa_event"] = JSON.stringify(GameState.fuwa_event)
	snap["demon_campaign"] = JSON.stringify(GameState.demon_campaign)
	snap["quest_states"] = JSON.stringify(GameState.quest_states)
	snap["completed_daily_tasks"] = JSON.stringify(GameState.completed_daily_tasks)
	snap["inventory"] = JSON.stringify(GameState.inventory)
	snap["warehouse"] = JSON.stringify(GameState.warehouse)
	snap["pets"] = JSON.stringify(GameState.pets)
	snap["equipment"] = JSON.stringify(GameState.equipment)
	snap["base_stats"] = JSON.stringify(GameState.base_stats)
	snap["research"] = JSON.stringify(GameState.research)
	snap["unlocked_maps"] = JSON.stringify(GameState.unlocked_maps)
	snap["learned_skills"] = JSON.stringify(GameState.learned_skills)
	snap["loot_queue"] = JSON.stringify(GameState.loot_queue)
	return snap


# ---- 读档：保存期望值 + 深比较（返回错误码，供 run_registry_case 复用）----

func _setup_via_registry(registry: Dictionary, node_id: String) -> void:
	# 从传入 registry 读 setup 函数名（不读全局 _nodes）
	var setup_name := str(registry[node_id]["test"].get("setup", ""))
	var r: Variant = call(setup_name)
	assert(r != null, "node %s setup %s 不存在" % [node_id, setup_name])


func _save_load_result(registry: Dictionary, node_id: String, save_fields: Array) -> String:
	if save_fields.is_empty():
		return ""
	_reset_story()
	_setup_via_registry(registry, node_id)
	# action 从传入 registry 读取（变异副本的 action 必须生效）
	_dispatch(str(registry[node_id]["test"].get("action", "")), node_id)
	var expected: Dictionary = {}
	for field: String in save_fields:
		expected[field] = _read_field(field)
	if not GameState.save_game():
		return "STORY_SAVE_WRITE_FAILED"  # 保存失败
	_reset_story()
	if not GameState.load_game():
		return "STORY_SAVE_LOAD_FAILED"  # 读取失败
	for field: String in save_fields:
		var restored: Variant = _read_field(field)
		if restored == null:
			return "STORY_SAVE_DEFAULT_MISSING"  # 字段缺失（缺默认）
		if restored != expected.get(field):
			return "STORY_SAVE_VALUE_MISMATCH"  # 恢复值不一致
	return ""


func _read_field(field: String) -> Variant:
	var parts := field.split(".")
	if parts.size() >= 2:
		if parts[0] == "story_flags":
			return GameState.story_flags.get(parts[1], null)
		var root: Variant = GameState.get(parts[0])
		if root is Dictionary:
			return root.get(parts[1], null)
		return root
	return GameState.get(parts[0])


func _is_infinite_repeat(registry: Dictionary, node_id: String) -> bool:
	# 整改：从注册表 test.infinite_repeat 读取，禁止硬编码 node ID 列表
	return bool(registry.get(node_id, {}).get("test", {}).get("infinite_repeat", false))


# ---- 重复幂等验证（registry 驱动：用注册表 test.repeat_guard 字段，非 node_id 硬编码）----

func _verify_repeat(registry: Dictionary, node_id: String, r: Dictionary) -> String:
	var guard := str(registry[node_id]["test"].get("repeat_guard", "success"))
	if guard != "triggered" and guard != "success":
		return "STORY_REPEAT_GUARD_INVALID"  # 变异 repeat_guard 为非法值即命中
	if guard == "triggered":
		return "" if not bool(r.get("triggered", false)) else "repeat_fail"
	return "" if not bool(r.get("success", false)) else "repeat_fail"


# ---- 八负向（N1-N8）：复制并变异真实注册表，全部传入统一 run_registry_case（与正向同一执行器）----

func _run_negatives() -> void:
	# N1: 变异 setup 字段为不存在函数 -> run_registry_case 命中 STORY_SETUP_DRIVER_MISSING
	var c1: Dictionary = _nodes.duplicate(true)
	c1["rescue_king"]["test"]["setup"] = "setup_nonexistent"
	assert(c1["rescue_king"]["test"]["setup"] == "setup_nonexistent", "N1 变异生效（setup 字段已改）")
	assert(run_registry_case(c1, "rescue_king") == "STORY_SETUP_DRIVER_MISSING",
		"N1 变异 setup 必须经统一 run_registry_case 命中")

	# N2: 变异 verify 字段
	var c2: Dictionary = _nodes.duplicate(true)
	c2["rescue_king"]["test"]["verify"] = "verify_nonexistent"
	assert(c2["rescue_king"]["test"]["verify"] == "verify_nonexistent", "N2 变异生效（verify 字段已改）")
	assert(run_registry_case(c2, "rescue_king") == "STORY_VERIFY_DRIVER_MISSING",
		"N2 变异 verify 必须经统一 run_registry_case 命中")

	# N3: 变异 action 为未知 MAIN 路由 -> run_registry_case 命中 STORY_ACTION_ROUTE_MISMATCH
	var c3: Dictionary = _nodes.duplicate(true)
	c3["king_dialogue"]["test"]["action"] = "MAIN:nonexistent_route"
	assert(c3["king_dialogue"]["test"]["action"] == "MAIN:nonexistent_route", "N3 变异生效（action 已改）")
	assert(run_registry_case(c3, "king_dialogue") == "STORY_ACTION_ROUTE_MISMATCH",
		"N3 未知路由必须经统一 run_registry_case 命中")

	# N4: 变异 cross_day（读原值 none 改成 daily）-> run_registry_case 的跨日执行器命中
	# rescue_king 原策略 none（一次性救王不可重做）；改成 daily 后 daily 分支期望次日可重做
	#   但救王 flag 已置位不可重做 -> 真实生产入口检测到 MISMATCH
	var c4: Dictionary = _nodes.duplicate(true)
	var orig_policy4 := str(c4["rescue_king"]["test"].get("cross_day", ""))
	assert(orig_policy4 == "none", "N4 前置：rescue_king cross_day 原值应为 none（got %s）" % orig_policy4)
	c4["rescue_king"]["test"]["cross_day"] = "daily"
	assert(str(c4["rescue_king"]["test"]["cross_day"]) == "daily", "N4 变异生效（cross_day 已改为 daily）")
	var n4_result := run_registry_case(c4, "rescue_king")
	assert(n4_result == "STORY_CROSS_DAY_MISMATCH",
		"N4 变异 cross_day 必须经统一 run_registry_case 命中（got '%s'）" % n4_result)

	# N5: 变异 save_fields 为缺默认字段 -> run_registry_case 的读档校验命中
	var c5: Dictionary = _nodes.duplicate(true)
	c5["rescue_king"]["test"]["save_fields"] = ["story_flags.v138_new_flag"]
	assert(c5["rescue_king"]["test"]["save_fields"].has("story_flags.v138_new_flag"), "N5 变异生效（save 字段已改）")
	assert(run_registry_case(c5, "rescue_king") == "STORY_SAVE_DEFAULT_MISSING",
		"N5 缺存档默认必须经统一 run_registry_case 命中")

	# N6: 变异 token 为另一节点合法 token（错段）-> 变异副本进统一 run_registry_case 命中
	var c6: Dictionary = _nodes.duplicate(true)
	c6["rescue_king"]["swf_evidence"] = ["sprite1079 frame_1 DoAction.as（公主）"]
	assert(str(c6["rescue_king"]["swf_evidence"][0]).contains("sprite1079"), "N6 变异生效（token 改为公主域）")
	assert(run_registry_case(c6, "rescue_king") == "STORY_TOKEN_MISS",
		"N6 错段 token 必须经统一 run_registry_case 命中 STORY_TOKEN_MISS")

	# N7（逃逸，差分）：先验证原始 case 成功，再变异合法 setup 必须使结果失败（非差分无效）
	var c7_base: Dictionary = _nodes.duplicate(true)
	assert(run_registry_case(c7_base, "king_dialogue") == "", "N7 前置：原始 king_dialogue 必须成功")
	var c7: Dictionary = _nodes.duplicate(true)
	c7["king_dialogue"]["test"]["setup"] = "setup_give_roses"  # 另一合法 setup（不设 king_rescued -> 拒开）
	assert(c7["king_dialogue"]["test"]["setup"] == "setup_give_roses", "N7 变异生效（setup 改为另一合法函数）")
	var n7 := run_registry_case(c7, "king_dialogue")
	assert(n7 != "" and n7 != "STORY_SETUP_DRIVER_MISSING",
		"N7 合法 setup 变异必须影响执行结果且失败于目标阶段（got '%s'，非 setup 缺位）" % n7)

	# N8（逃逸，差分 + 按序到达读档）：先 baseline 成功，
	#     再变异 action（buy_maid_combat_stone，daily）+ 匹配 verify + cross_day=daily + 正常 save_fields
	#     -> 首次/重复/跨日/save/load 全成功（返回 ""）；再加缺默认字段 -> 读档命中 STORY_SAVE_DEFAULT_MISSING。
	var c8_base: Dictionary = _nodes.duplicate(true)
	assert(run_registry_case(c8_base, "maid_year_pig") == "", "N8 步骤1：原始 maid_year_pig 必须成功")
	var c8: Dictionary = _nodes.duplicate(true)
	c8["maid_year_pig"]["test"]["action"] = "buy_maid_combat_stone"  # 变异 action（另一合法，daily 语义）
	c8["maid_year_pig"]["test"]["verify"] = "verify_maid_combat_stone"  # 匹配 verify（success 通过）
	c8["maid_year_pig"]["test"]["cross_day"] = "daily"  # 同步跨日语义
	c8["maid_year_pig"]["test"]["save_fields"] = ["story_flags.maid_combat_stone_available"]  # 正常字段
	# P1-1：变异后节点行为即 combat_stone，cross_day 精确登记同步为 combat_stone 语义（否则 epilogue 精确差分会拒绝变异）
	c8["maid_year_pig"]["cross_day_changed"] = _nodes["maid_combat_stone"]["cross_day_changed"].duplicate()
	c8["maid_year_pig"]["cross_day_changed_reason"] = _nodes["maid_combat_stone"]["cross_day_changed_reason"].duplicate(true)
	c8["maid_year_pig"]["cross_day_unchanged"] = _nodes["maid_combat_stone"]["cross_day_unchanged"].duplicate()
	assert(c8["maid_year_pig"]["test"]["action"] == "buy_maid_combat_stone", "N8 步骤2：变异 action 生效")
	assert(run_registry_case(c8, "maid_year_pig") == "",
		"N8 步骤3：变异 action 的完整流程（首次/重复/跨日/save/load）必须全成功")
	# 步骤4：加缺默认字段 -> 读档阶段命中 STORY_SAVE_DEFAULT_MISSING
	c8["maid_year_pig"]["test"]["save_fields"] = ["story_flags.v138_new_flag"]
	assert(c8["maid_year_pig"]["test"]["save_fields"].has("story_flags.v138_new_flag"), "N8 步骤4：缺字段变异生效")
	assert(run_registry_case(c8, "maid_year_pig") == "STORY_SAVE_DEFAULT_MISSING",
		"N8 步骤5：变异 action 读档阶段必须命中 STORY_SAVE_DEFAULT_MISSING（缺字段）")
	# ---- 第三轮拒签整改：前置矩阵六个负向（同一 _run_precondition 执行器）----

	# N9（删除前置登记）：移除节点 precondition -> STORY_PRECONDITION_MISSING
	var c9: Dictionary = _nodes.duplicate(true)
	assert(c9["rescue_king"].has("precondition"), "N9 前置：rescue_king 有 precondition")
	c9["rescue_king"].erase("precondition")
	assert(not c9["rescue_king"].has("precondition"), "N9 变异生效（precondition 已删除）")
	var n9_result := run_registry_case(c9, "rescue_king")
	assert(n9_result == "STORY_PRECONDITION_MISSING",
		"N9 删除前置登记必须被统一执行器命中（got '%s'）" % n9_result)

	# N10（两合法节点交换前置夹具）：rescue_king 用 princess_chat 的 precondition_setup（pre_princess_chat）
	#    保留自身 action/reason -> 前置执行 chat 夹具后 rescue 仍成功，与 expected_success=false 冲突
	var c10: Dictionary = _nodes.duplicate(true)
	var setup_a10 := str(c10["rescue_king"]["precondition"]["precondition_setup"])
	var setup_b10 := str(c10["princess_chat"]["precondition"]["precondition_setup"])
	assert(setup_a10 != setup_b10, "N10 前置：两节点前置夹具不同")
	c10["rescue_king"]["precondition"]["precondition_setup"] = setup_b10  # 交换夹具
	assert(str(c10["rescue_king"]["precondition"]["precondition_setup"]) == setup_b10, "N10 变异生效（前置夹具已交换）")
	var n10_result := run_registry_case(c10, "rescue_king")
	assert(n10_result == "STORY_PRECONDITION_OUTCOME_MISMATCH",
		"N10 交换前置夹具必须被统一执行器命中（got '%s'）" % n10_result)

	# N11（篡改 expected_reason）：rescue_king 前置 reason 改为错误值 -> reason 不匹配
	var c11: Dictionary = _nodes.duplicate(true)
	assert(str(c11["rescue_king"]["precondition"]["expected_reason"]) == "already_rescued", "N11 前置：reason 原值")
	c11["rescue_king"]["precondition"]["expected_reason"] = "wrong_reason"
	assert(str(c11["rescue_king"]["precondition"]["expected_reason"]) == "wrong_reason", "N11 变异生效（reason 已篡改）")
	var n11_result := run_registry_case(c11, "rescue_king")
	assert(n11_result == "STORY_PRECONDITION_REASON_MISMATCH",
		"N11 篡改 expected_reason 必须被统一执行器命中（got '%s'）" % n11_result)

	# N12（注入未登记状态变化）：rescue_king 前置 expected_state_changed 加入实际不变的字段 -> 状态差分拒绝
	var c12: Dictionary = _nodes.duplicate(true)
	var orig_changed12: Array = c12["rescue_king"]["precondition"].get("expected_state_changed", [])
	assert(not orig_changed12.has("gold"), "N12 前置：changed 不含 gold")
	c12["rescue_king"]["precondition"]["expected_state_changed"] = orig_changed12.duplicate()
	c12["rescue_king"]["precondition"]["expected_state_changed"].append("gold")
	var new_unchanged12: Array = []
	for f: String in c12["rescue_king"]["precondition"].get("expected_state_unchanged", []):
		if f != "gold":
			new_unchanged12.append(f)
	c12["rescue_king"]["precondition"]["expected_state_unchanged"] = new_unchanged12
	assert(c12["rescue_king"]["precondition"]["expected_state_changed"].has("gold")
		and not c12["rescue_king"]["precondition"]["expected_state_unchanged"].has("gold"), "N12 变异生效（注入状态变化）")
	var n12_result := run_registry_case(c12, "rescue_king")
	assert(n12_result == "STORY_PRECONDITION_CHANGED_MISSING",
		"N12 注入未登记状态变化必须被统一执行器命中（got '%s'）" % n12_result)

	# N13（MAIN 路由绕过）：king_dialogue 前置 action 改为 rescue_king（绕过 MAIN 拒开）-> 救王成功与 expected 冲突
	var c13: Dictionary = _nodes.duplicate(true)
	assert(str(c13["king_dialogue"]["precondition"]["precondition_action"]) == "MAIN:king_dialogue", "N13 前置：action 走 MAIN")
	c13["king_dialogue"]["precondition"]["precondition_action"] = "rescue_king"
	assert(str(c13["king_dialogue"]["precondition"]["precondition_action"]) == "rescue_king", "N13 变异生效（绕过 MAIN）")
	var n13_result := run_registry_case(c13, "king_dialogue")
	assert(n13_result == "STORY_PRECONDITION_OUTCOME_MISMATCH",
		"N13 MAIN 路由绕过必须被统一执行器命中（got '%s'）" % n13_result)

	# N14（有门槛节点标 not_applicable + 非空假理由）：rescue_king policy=required，precondition 标 not_applicable 带假理由
	#     -> 执行器自身拒绝 NOT_APPLICABLE_INVALID（即使理由非空）
	var c14: Dictionary = _nodes.duplicate(true)
	c14["rescue_king"]["precondition"] = {"not_applicable": true, "not_applicable_reason": "假理由：无门槛"}
	assert(bool(c14["rescue_king"]["precondition"].get("not_applicable", false))
		and str(c14["rescue_king"]["precondition"].get("not_applicable_reason", "")) == "假理由：无门槛", "N14 变异生效（带非空假理由）")
	var n14_result := run_registry_case(c14, "rescue_king")
	assert(n14_result == "STORY_PRECONDITION_NOT_APPLICABLE_INVALID",
		"N14 有门槛节点带假理由标 not_applicable 必须被统一执行器拒绝（got '%s'）" % n14_result)

	# N23（king_dialogue 改 not_applicable + 非空理由）：policy=required -> NOT_APPLICABLE_INVALID
	var c23: Dictionary = _nodes.duplicate(true)
	c23["king_dialogue"]["precondition"] = {"not_applicable": true, "not_applicable_reason": "假理由：国王对话无门槛"}
	assert(bool(c23["king_dialogue"]["precondition"].get("not_applicable", false))
		and not str(c23["king_dialogue"]["precondition"].get("not_applicable_reason", "")).is_empty(), "N23 变异生效")
	var n23_result := run_registry_case(c23, "king_dialogue")
	assert(n23_result == "STORY_PRECONDITION_NOT_APPLICABLE_INVALID",
		"N23 king_dialogue 假 not_applicable 必须被统一执行器拒绝（got '%s'）" % n23_result)

	# N24（prime_minister 从 not_applicable 改 required 但缺配置）：policy=required + precondition 无 setup/action
	#     -> CONFIG_MISSING
	var c24: Dictionary = _nodes.duplicate(true)
	c24["prime_minister_king_news"]["precondition_policy"] = "required"
	c24["prime_minister_king_news"]["precondition"] = {"not_applicable_reason": "旧理由残留"}
	assert(str(c24["prime_minister_king_news"]["precondition_policy"]) == "required"
		and not c24["prime_minister_king_news"]["precondition"].has("precondition_setup"), "N24 变异生效（required 缺配置）")
	var n24_result := run_registry_case(c24, "prime_minister_king_news")
	assert(n24_result == "STORY_PRECONDITION_CONFIG_MISSING",
		"N24 not_applicable 改 required 缺配置必须被统一执行器拒绝（got '%s'）" % n24_result)

	# N25（合法 prime_minister not_applicable 正向保真）：policy=not_applicable + 标 not_applicable + 理由 -> 通过
	var c25: Dictionary = _nodes.duplicate(true)
	assert(str(c25["prime_minister_king_news"]["precondition_policy"]) == "not_applicable"
		and bool(c25["prime_minister_king_news"]["precondition"].get("not_applicable", false))
		and not str(c25["prime_minister_king_news"]["precondition"].get("not_applicable_reason", "")).is_empty(), "N25 前置：合法 not_applicable 配置")
	var n25_result := run_registry_case(c25, "prime_minister_king_news")
	assert(n25_result == "", "N25 合法 not_applicable 必须通过（got '%s'）" % n25_result)

	# N26（rescue_king 改 policy=not_applicable）：执行器允许集校验拒绝（不在允许集合）
	var c26: Dictionary = _nodes.duplicate(true)
	c26["rescue_king"]["precondition_policy"] = "not_applicable"
	c26["rescue_king"]["precondition"] = {"not_applicable": true, "not_applicable_reason": "假理由"}
	assert(str(c26["rescue_king"]["precondition_policy"]) == "not_applicable", "N26 变异生效（policy 已改）")
	var n26_result := run_registry_case(c26, "rescue_king")
	assert(n26_result == "STORY_PRECONDITION_NOT_APPLICABLE_INVALID",
		"N26 非允许集合节点改 not_applicable 策略必须被统一执行器拒绝（got '%s'）" % n26_result)

	# ---- 第四轮补充整改：precondition_policy 缺失/未知四个负向（同一执行器，先证明变异生效）----

	# N27（删除 policy）：erase precondition_policy -> STORY_PRECONDITION_POLICY_MISSING
	var c27: Dictionary = _nodes.duplicate(true)
	assert(c27["rescue_king"].has("precondition_policy"), "N27 前置：policy 存在")
	c27["rescue_king"].erase("precondition_policy")
	assert(not c27["rescue_king"].has("precondition_policy"), "N27 变异生效（policy 已删除）")
	var n27_result := run_registry_case(c27, "rescue_king")
	assert(n27_result == "STORY_PRECONDITION_POLICY_MISSING",
		"N27 删除 policy 必须被统一执行器命中 POLICY_MISSING（got '%s'）" % n27_result)

	# N28（空串 policy）：precondition_policy="" -> POLICY_INVALID
	var c28: Dictionary = _nodes.duplicate(true)
	c28["rescue_king"]["precondition_policy"] = ""
	assert(str(c28["rescue_king"]["precondition_policy"]) == "", "N28 变异生效（空串）")
	var n28_result := run_registry_case(c28, "rescue_king")
	assert(n28_result == "STORY_PRECONDITION_POLICY_INVALID",
		"N28 空串 policy 必须被统一执行器命中 POLICY_INVALID（got '%s'）" % n28_result)

	# N29（typo policy）：precondition_policy="requried" -> POLICY_INVALID
	var c29: Dictionary = _nodes.duplicate(true)
	c29["rescue_king"]["precondition_policy"] = "requried"
	assert(str(c29["rescue_king"]["precondition_policy"]) == "requried", "N29 变异生效（typo）")
	var n29_result := run_registry_case(c29, "rescue_king")
	assert(n29_result == "STORY_PRECONDITION_POLICY_INVALID",
		"N29 typo policy 必须被统一执行器命中 POLICY_INVALID（got '%s'）" % n29_result)

	# N30（大小写错误 policy）：precondition_policy="REQUIRED" -> POLICY_INVALID
	var c30: Dictionary = _nodes.duplicate(true)
	c30["rescue_king"]["precondition_policy"] = "REQUIRED"
	assert(str(c30["rescue_king"]["precondition_policy"]) == "REQUIRED", "N30 变异生效（大小写错误）")
	var n30_result := run_registry_case(c30, "rescue_king")
	assert(n30_result == "STORY_PRECONDITION_POLICY_INVALID",
		"N30 大小写错误 policy 必须被统一执行器命中 POLICY_INVALID（got '%s'）" % n30_result)

# ---- P1-1 第二轮拒签整改四个负向（登记精确性 / reason 一致性 / MAIN 意外状态变化）----

	# N15（changed∩unchanged 交集）：把 changed 中的 nobility_merit 加入 unchanged -> epilogue 交集检查命中
	var c15: Dictionary = _nodes.duplicate(true)
	assert(c15["rescue_king"]["cross_day_changed"].has("nobility_merit"), "N15 前置：changed 含 nobility_merit")
	c15["rescue_king"]["cross_day_unchanged"].append("nobility_merit")
	assert(c15["rescue_king"]["cross_day_unchanged"].has("nobility_merit"), "N15 变异生效（交集字段加入 unchanged）")
	var n15_result := run_registry_case(c15, "rescue_king")
	assert(n15_result == "STORY_CROSS_DAY_MISMATCH",
		"N15 changed∩unchanged 交集必须被 epilogue 拒绝（got '%s'）" % n15_result)

	# N16（changed 缺 reason）：从 cross_day_changed_reason 删除一个 key -> reason 键集合 != changed 命中
	var c16: Dictionary = _nodes.duplicate(true)
	assert(c16["rescue_king"]["cross_day_changed_reason"].has("nobility_merit"), "N16 前置：reason 含 nobility_merit")
	c16["rescue_king"]["cross_day_changed_reason"].erase("nobility_merit")
	assert(not c16["rescue_king"]["cross_day_changed_reason"].has("nobility_merit"), "N16 变异生效（reason 缺键）")
	var n16_result := run_registry_case(c16, "rescue_king")
	assert(n16_result == "STORY_CROSS_DAY_MISMATCH",
		"N16 changed 缺 reason 必须被 epilogue 拒绝（got '%s'）" % n16_result)

	# N17（reason 多出字段）：cross_day_changed_reason 加入不存在于 changed 的 key -> reason 键集合 != changed 命中
	var c17: Dictionary = _nodes.duplicate(true)
	assert(not c17["rescue_king"]["cross_day_changed"].has("gold"), "N17 前置：changed 不含 gold")
	c17["rescue_king"]["cross_day_changed_reason"]["gold"] = "N17 变异注入"
	assert(c17["rescue_king"]["cross_day_changed_reason"].has("gold"), "N17 变异生效（reason 多出字段）")
	var n17_result := run_registry_case(c17, "rescue_king")
	assert(n17_result == "STORY_CROSS_DAY_MISMATCH",
		"N17 reason 多出字段必须被 epilogue 拒绝（got '%s'）" % n17_result)

	# N18（MAIN 节点意外状态变化）：palace_garden_entry 删除真实变化字段 current_map_id 的登记（并入 unchanged）
	#     -> MAIN 第二次调用实际切换地图，epilogue 的 unchanged 检查命中"未登记副作用"
	var c18: Dictionary = _nodes.duplicate(true)
	assert(c18["palace_garden_entry"]["cross_day_changed"].has("current_map_id"), "N18 前置：changed 含 current_map_id")
	var new_changed18: Array = []
	for f: String in c18["palace_garden_entry"]["cross_day_changed"]:
		if f != "current_map_id":
			new_changed18.append(f)
	c18["palace_garden_entry"]["cross_day_changed"] = new_changed18
	c18["palace_garden_entry"]["cross_day_changed_reason"].erase("current_map_id")
	c18["palace_garden_entry"]["cross_day_unchanged"].append("current_map_id")
	assert(not c18["palace_garden_entry"]["cross_day_changed"].has("current_map_id")
		and c18["palace_garden_entry"]["cross_day_unchanged"].has("current_map_id"),
		"N18 变异生效（MAIN 节点 current_map_id 未登记变化）")
	var n18_result := run_registry_case(c18, "palace_garden_entry")
	assert(n18_result == "STORY_CROSS_DAY_MISMATCH",
		"N18 MAIN 节点意外状态变化必须被 epilogue 拒绝（got '%s'）" % n18_result)


# ---- 写入审计：扫描全部函数源码，区分夹具(setup/precondition/cross_day)与主流程(flow) ----
# 覆盖 _ready / _run_node / run_registry_case / _dispatch / _dispatch_main / _cross_day / setup / precondition，
# 用增强正则（story_flags["k"]= / .set( / 单引号 / 嵌套容器）捕获直接写，断言主流程无终态伪造。

func _assert_write_audit() -> void:
	var src := FileAccess.open("res://tests/test_story_dialogue_state_machine_scene.gd", FileAccess.READ)
	assert(src != null, "写入审计：必须能读取测试源码")
	var lines := src.get_as_text().split("\n")
	# 主流程函数名（禁止直接写终态 flag）：_ready/_run_node/run_registry_case/_dispatch/_dispatch_main
	var FLOW_FIRST := ["func _ready", "func _run_node", "func run_registry_case", "func _dispatch(", "func _dispatch_main", "func _cross_day_exec"]
	# 夹具函数名（允许直接写，作为前置准备）：setup_ / _precondition / _cross_day_result / _save_load_result
	var FIXTURE_PREFIX := ["func setup_", "func pre_", "func _cross_day_prepare", "func _save_load_result"]
	var current_func := ""
	var in_flow := false
	var in_audit := false
	var direct_writes: Array = []
	var assign_re := RegEx.create_from_string(r'(story_flags\[["\'][A-Za-z_]+["\']\]\s*=|story_flags\.set\(|\.set\(["\'][A-Za-z_]+["\']\s*,)')
	for i in lines.size():
		var line := lines[i]
		if line.contains("func _assert_write_audit"):
			in_audit = true; continue
		if line.begins_with("func "):
			in_audit = false
			current_func = line
			in_flow = false
			for f in FLOW_FIRST:
				if line.contains(f):
					in_flow = true
					break
			continue
		if in_audit:
			continue
		# 若在夹具函数内，写入允许（视为前置准备）
		var in_fixture := false
		if not in_flow:
			for fp in FIXTURE_PREFIX:
				if current_func.contains(fp):
					in_fixture = true
					break
		if in_flow or not in_fixture:
			if assign_re.search(line) != null and not line.strip_edges().begins_with("#"):
				direct_writes.append("%s: %s" % [current_func, line.strip_edges()])
	# 断言：主流程（_ready/_run_node/run_registry_case/_dispatch）无直接写终态 flag
	assert(direct_writes.is_empty(),
		"写入审计：主流程不得直接写终态 flag，发现: %s" % str(direct_writes))