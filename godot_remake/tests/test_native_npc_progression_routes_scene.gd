extends Node

# v1.34 专项：原版 NPC 入口流程校正。
# 验证元帅/首相/公主/日常官/研究所的原版 NPC 对话入口不再路由到 progression 聚合窗，
# 专属 action 能完成军功查询/捐献/赠礼/交付/研究所，且全程不打开 progression_panel。

const REGISTRY_PATH := "res://docs/npc_progression_flow_registry.json"


func _press_choice(main: Node, label: String) -> bool:
	for child in main.dialogue_panel.choices.get_children():
		if child is Button and child.text == label:
			child.emit_signal("pressed")
			return true
	return false


func _ready() -> void:
	# 周日，便于军饷与周日礼物；首日 loaded
	GameState.current_day = 7
	GameState.gold = 5000000
	GameState.magic_stones = 1000000
	GameState.military_merit = 1000
	GameState.add_item("rose", 200)
	GameState.add_item("magic_soul_crystal", 3)
	GameState.add_item("soul_king", 1)
	GameState.research = {"technology_level": 20.0, "production_rate": 2, "stock": 3, "vip_level": 0}

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.progression_panel.hide()
	assert(not main.progression_panel.visible, "progression_panel should start hidden")

	# --- 元帅：军功查询不打开聚合窗 ---
	main._open_actor_dialogue("marshal")
	assert(_press_choice(main, "战功查询"), "marshal dialogue missing 战功查询 choice")
	assert(not main.progression_panel.visible, "military_status opened the progression panel")
	assert(main.dialogue_panel.visible and "战功" in main.dialogue_panel.body_label.text, "military_status did not show military merit text")

	# 军饷：周日成功一次，第二次失败且不重复加魔石
	var stones_before := GameState.magic_stones
	main._handle_dialogue_action("military_salary")
	assert(GameState.magic_stones == stones_before + 999999999, "military salary did not grant the configured magic stones")
	main._handle_dialogue_action("military_salary")
	assert(GameState.magic_stones == stones_before + 999999999, "military salary was granted twice")
	assert(not main.progression_panel.visible, "military salary opened the progression panel")

	# --- 首相：捐献成功扣金币加功勋；金币不足不变；不打开聚合窗 ---
	main._open_actor_dialogue("prime_minister")
	assert(_press_choice(main, "捐献金币"), "prime minister missing 捐献金币 choice")
	assert(not main.progression_panel.visible, "prime donate opened the progression panel")
	var gold_before := GameState.gold
	var merit_before := GameState.nobility_merit
	assert(_press_choice(main, "捐献750,000金币"), "prime donate missing 750000 tier")
	assert(GameState.gold == gold_before - 750000 and GameState.nobility_merit == merit_before + 1, "prime donation did not settle correctly")
	assert(not main.progression_panel.visible, "donate_gold opened the progression panel")
	# 金币不足：清空金币后捐献失败，两字段不变
	GameState.gold = 100
	var gold_low := GameState.gold
	var merit_low := GameState.nobility_merit
	main._handle_dialogue_action("donate_gold:750000")
	assert(GameState.gold == gold_low and GameState.nobility_merit == merit_low, "donate_gold with insufficient gold changed state")
	assert(not main.progression_panel.visible, "failed donate opened the progression panel")
	GameState.gold = 5000000

	# --- 公主：赠礼成功消耗玫瑰加好感；玫瑰不足不变；不打开聚合窗 ---
	main._open_actor_dialogue("princess")
	assert(_press_choice(main, "送礼"), "princess missing 送礼 choice")
	assert(not main.progression_panel.visible, "princess gift opened the progression panel")
	var rose_before := GameState.count_item("rose")
	var aff_before := GameState.affection
	assert(_press_choice(main, "送99朵白玫瑰"), "princess gift missing 99-rose tier")
	assert(GameState.count_item("rose") == rose_before - 99 and GameState.affection == aff_before + 50, "give_roses 99 did not settle correctly")
	assert(not main.progression_panel.visible, "give_roses opened the progression panel")
	# 玫瑰不足：清空玫瑰后赠礼失败，好感不变
	GameState.consume_item("rose", GameState.count_item("rose"))
	var rose_zero := GameState.count_item("rose")
	var aff_low := GameState.affection
	main._handle_dialogue_action("give_roses:999")
	assert(GameState.count_item("rose") == rose_zero and GameState.affection == aff_low, "give_roses with no roses changed state")
	assert(not main.progression_panel.visible, "failed give_roses opened the progression panel")

	# --- 公主周日礼物：物品数量+1，重复不变 ---
	GameState.current_day = 7
	GameState.affection = 10
	GameState.last_princess_gift_day = 0
	var gift_id: String = str(GameState.princess_sunday_gift_item_id())
	var gift_before := GameState.count_item(gift_id)
	main._open_actor_dialogue("princess")
	assert(_press_choice(main, "星期天礼物"), "princess missing 星期天礼物 choice")
	assert(GameState.last_princess_gift_day == 7, "princess sunday gift did not record claim day")
	assert(GameState.count_item(gift_id) == gift_before + 1, "princess sunday gift did not add exactly one item")
	assert(not main.progression_panel.visible, "princess sunday gift opened progression panel")
	main._open_actor_dialogue("princess")
	_press_choice(main, "星期天礼物")
	assert(GameState.count_item(gift_id) == gift_before + 1, "princess sunday gift granted twice")
	assert(GameState.last_princess_gift_day == 7, "princess sunday gift day changed on repeat")
	assert(not main.progression_panel.visible, "princess sunday gift re-opened progression panel")

	# --- 日常官：周一交付魔魂晶石（按钮）；周二交付灵魂王（按钮）；重复/材料不足不扣 ---
	GameState.current_day = 1
	GameState.add_item("magic_soul_crystal", 3)
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "交付宝石"), "daily officer Mon missing 交付宝石 choice")
	assert(not main.progression_panel.visible, "daily deliver opened the progression panel")
	var ms_before := GameState.count_item("magic_soul_crystal")
	var dmerit_before := GameState.nobility_merit
	assert(_press_choice(main, "交付魔魂晶石"), "daily deliver missing magic_soul tier")
	assert(GameState.count_item("magic_soul_crystal") == ms_before - 1 and GameState.nobility_merit == dmerit_before + 500, "Mon magic_soul deliver did not settle")
	# 重复交付失败不扣（按钮触发）
	var ms_after := GameState.count_item("magic_soul_crystal")
	var dmerit_after := GameState.nobility_merit
	main._open_actor_dialogue("daily_officer")
	_press_choice(main, "交付宝石")
	_press_choice(main, "交付魔魂晶石")
	assert(GameState.count_item("magic_soul_crystal") == ms_after and GameState.nobility_merit == dmerit_after, "repeated Mon deliver changed state")
	# 周二：清理灵魂王完成标记后，从NPC入口交付灵魂王
	GameState.current_day = 2
	GameState.completed_daily_tasks.erase("collect_soul_king")
	GameState.add_item("soul_king", 2)
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "交付宝石"), "daily officer Tue missing 交付宝石 choice")
	var sk_before := GameState.count_item("soul_king")
	var dmerit_tue := GameState.nobility_merit
	assert(_press_choice(main, "交付灵魂王"), "daily deliver missing soul_king tier")
	assert(GameState.count_item("soul_king") == sk_before - 1 and GameState.nobility_merit == dmerit_tue + 2000, "Tue soul_king deliver did not settle")
	# 材料不足：清空灵魂王后从NPC入口交付失败不扣
	GameState.consume_item("soul_king", GameState.count_item("soul_king"))
	GameState.completed_daily_tasks.erase("collect_soul_king")
	var sk_zero := GameState.count_item("soul_king")
	var dmerit_low := GameState.nobility_merit
	main._open_actor_dialogue("daily_officer")
	_press_choice(main, "交付宝石")
	_press_choice(main, "交付灵魂王")
	assert(GameState.count_item("soul_king") == sk_zero and GameState.nobility_merit == dmerit_low, "daily deliver with no soul_king changed state")
	assert(not main.progression_panel.visible, "failed daily deliver opened the progression panel")

	# --- 日常官周三/周四幻兽入口可达 ---
	GameState.current_day = 3
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "查看幻兽"), "daily officer Wed/Thu missing 查看幻兽 choice")
	assert(main.pet_panel.visible, "daily officer Wed/Thu did not open pet panel")
	main.pet_panel.hide()

	# --- 日常官周五/六/日入口可达（选项存在）---
	GameState.current_day = 5
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "接受任务") or _has_choice(main, "接受任务"), "daily officer Fri missing quest choice")
	GameState.current_day = 6
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "前往皇宫"), "daily officer Sat missing travel choice")
	GameState.current_day = 7
	main._open_actor_dialogue("daily_officer")
	assert(_press_choice(main, "进入地下城"), "daily officer Sun missing dungeon choice")
	assert(not main.progression_panel.visible, "daily officer routes opened the progression panel")

	# --- 研究所：NPC四选项端到端 + 窗口资源扣除 ---
	GameState.research = {"technology_level": 20.0, "production_rate": 2, "stock": 3, "vip_level": 0}
	GameState.magic_stones = 100000
	GameState.add_item("soul_king", 5)
	var research_cfg: Dictionary = GameState.pet_service.config.get("research", {})
	# NPC 四选项存在
	main._open_actor_dialogue("research")
	assert(_has_choice(main, "进入"), "research NPC missing 进入 choice")
	assert(_has_choice(main, "研究所的当前信息"), "research NPC missing 当前信息 choice")
	assert(_has_choice(main, "关于2008奥运使者"), "research NPC missing 2008 choice")
	assert(_has_choice(main, "提高产量任务"), "research NPC missing 提高产量任务 choice")
	assert(not main.progression_panel.visible, "research NPC opened progression panel")
	# 当前信息：只读，不改状态
	var r_tech_snap := float(GameState.research.technology_level)
	var r_stones_snap := GameState.magic_stones
	_press_choice(main, "研究所的当前信息")
	assert(float(GameState.research.technology_level) == r_tech_snap and GameState.magic_stones == r_stones_snap, "research_info changed state")
	assert(not main.progression_panel.visible, "research_info opened progression panel")
	# 2008奥运使者：三状态只读（未完成/待交付/已领取），不改 VIP/魔石/fuwa_event
	var r_vip_snap := int(GameState.research.get("vip_level", 0))
	# 未完成
	GameState.fuwa_event = GameState.default_fuwa_event()
	var fe_snap := GameState.fuwa_event.duplicate(true)
	main._open_actor_dialogue("research")
	_press_choice(main, "关于2008奥运使者")
	assert("打听" in main.dialogue_panel.body_label.text, "olympic_info uncompleted missing 打听 text")
	assert(GameState.fuwa_event == fe_snap and int(GameState.research.get("vip_level", 0)) == r_vip_snap and GameState.magic_stones == r_stones_snap, "olympic_info uncompleted changed state")
	assert(not main.progression_panel.visible, "olympic_info opened progression panel")
	# 已找齐但未最终交付（显式 beast_defeated=false，证明不再依赖错误字段）
	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.fuwa_event.found_count = GameState.FUWA_NAMES.size()
	GameState.fuwa_event.completion_claimed = false
	GameState.fuwa_event.beast_defeated = false
	var fe_pending := GameState.fuwa_event.duplicate(true)
	main._open_actor_dialogue("research")
	_press_choice(main, "关于2008奥运使者")
	assert("最终交付" in main.dialogue_panel.body_label.text, "olympic_info pending missing 最终交付 text")
	assert(not ("打听" in main.dialogue_panel.body_label.text), "olympic_info pending wrongly shows uncompleted text")
	assert(GameState.fuwa_event == fe_pending and int(GameState.research.get("vip_level", 0)) == r_vip_snap and GameState.magic_stones == r_stones_snap, "olympic_info pending changed state")
	assert(not main.progression_panel.visible, "olympic_info pending opened progression panel")
	# 已完成并领取
	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.fuwa_event.found_count = GameState.FUWA_NAMES.size()
	GameState.fuwa_event.completion_claimed = true
	var fe_done := GameState.fuwa_event.duplicate(true)
	main._open_actor_dialogue("research")
	_press_choice(main, "关于2008奥运使者")
	assert("感谢" in main.dialogue_panel.body_label.text and "300" in main.dialogue_panel.body_label.text, "olympic_info done missing 感谢/300 text")
	assert(GameState.fuwa_event == fe_done and int(GameState.research.get("vip_level", 0)) == r_vip_snap and GameState.magic_stones == r_stones_snap, "olympic_info done changed state")
	assert(not main.progression_panel.visible, "olympic_info done opened progression panel")
	# 提高产量任务：成功消耗灵魂王(production_task_cost)+产量+2
	main._open_actor_dialogue("research")
	var ptask_cost := int(GameState.pet_service.production_task_cost(GameState.research))
	var sk_before_task := GameState.count_item("soul_king")
	var rate_before_task := int(GameState.research.production_rate)
	_press_choice(main, "提高产量任务")
	assert(GameState.count_item("soul_king") == sk_before_task - ptask_cost, "research production task did not consume soul_king by production_task_cost")
	assert(int(GameState.research.production_rate) == rate_before_task + 2, "research production task did not +2")
	assert(not main.progression_panel.visible, "research production task opened progression panel")
	# 提高产量任务：缺材料不扣
	GameState.consume_item("soul_king", GameState.count_item("soul_king"))
	var sk_none := GameState.count_item("soul_king")
	var rate_none := int(GameState.research.production_rate)
	main._open_actor_dialogue("research")
	_press_choice(main, "提高产量任务")
	assert(GameState.count_item("soul_king") == sk_none and int(GameState.research.production_rate) == rate_none, "research production task with no soul_king changed state")
	# 提高产量任务：达上限不扣
	GameState.research.production_rate = 6
	GameState.add_item("soul_king", 3)
	var sk_cap := GameState.count_item("soul_king")
	var rate_cap := int(GameState.research.production_rate)
	main._open_actor_dialogue("research")
	_press_choice(main, "提高产量任务")
	assert(GameState.count_item("soul_king") == sk_cap and int(GameState.research.production_rate) == rate_cap, "research production task at cap changed state")
	# 进入：打开 ResearchPanel，资助/购买资源扣除
	GameState.research = {"technology_level": 20.0, "production_rate": 2, "stock": 3, "vip_level": 0}
	GameState.magic_stones = 100000
	GameState.add_item("soul_king", 3)
	main._open_actor_dialogue("research")
	assert(_press_choice(main, "进入"), "research NPC 进入 did not open panel")
	assert(main.research_panel.visible, "research NPC did not open ResearchPanel")
	assert(not main.progression_panel.visible, "research 进入 opened progression panel")
	var rpanel = main.research_panel
	# 资助：技术+1，魔石按 funding_magic_stones_per_level 扣
	var fund_cost := int(research_cfg.get("funding_magic_stones_per_level", 10000))
	var r_tech_before := float(GameState.research.technology_level)
	var r_stones_before_fund := GameState.magic_stones
	rpanel._fund()
	assert(float(GameState.research.technology_level) == r_tech_before + 1.0, "research fund did not raise tech level")
	assert(GameState.magic_stones == r_stones_before_fund - fund_cost, "research fund did not deduct funding_magic_stones_per_level")
	# 购买：库存-1，幻兽+1，魔石按 research_pet_price 扣
	var buy_price := int(GameState.pet_service.research_pet_price(GameState.research))
	var r_stock_before := int(GameState.research.stock)
	var r_pet_before := GameState.pets.size()
	var r_stones_before_buy := GameState.magic_stones
	rpanel._buy_pet()
	assert(int(GameState.research.stock) == r_stock_before - 1 and GameState.pets.size() == r_pet_before + 1, "research buy did not settle")
	assert(GameState.magic_stones == r_stones_before_buy - buy_price, "research buy did not deduct research_pet_price")
	# 无库存失败：库存/魔石/幻兽不变
	GameState.research.stock = 0
	var r_no_stock_stones := GameState.magic_stones
	var r_pet_fail := GameState.pets.size()
	rpanel._buy_pet()
	assert(int(GameState.research.stock) == 0 and GameState.magic_stones == r_no_stock_stones and GameState.pets.size() == r_pet_fail, "research buy with no stock changed state")
	assert(not main.progression_panel.visible, "research ops opened progression panel")
	rpanel.hide()

	# --- 注册表：结构 + classification + 独立SWF证据 + 缺口 + PM决定分类 ---
	assert(FileAccess.file_exists(REGISTRY_PATH), "npc progression flow registry missing")
	var rf := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	var reg: Dictionary = JSON.parse_string(rf.get_as_text())
	rf.close()
	assert(reg.has("npcs") and reg["npcs"].size() == 5, "registry must have 5 npc groups")
	var all_opts: Array = []
	for npc in reg["npcs"]:
		assert(npc.has("npc_id") and npc.has("options"), "npc entry missing id/options")
		for opt in npc["options"]:
			all_opts.append(opt)
	assert(all_opts.size() == 22, "registry must have 22 options, got %d" % all_opts.size())
	# research 恰 4 个原版选项
	var research_opts: Array = []
	for npc in reg["npcs"]:
		if str(npc.get("npc_id", "")) == "research":
			research_opts = npc["options"]
	assert(research_opts.size() == 4, "research must have 4 options, got %d" % research_opts.size())
	var research_actions: Array = []
	for ro in research_opts:
		research_actions.append(str(ro.get("action_id", "")))
	assert("research" in research_actions and "research_info" in research_actions and "research_olympic_info" in research_actions and "research_production_task" in research_actions, "research missing one of 4 native actions")
	for opt in all_opts:
		assert(opt.has("classification"), "option missing classification: " + str(opt.get("action_id")))
		assert(opt.has("evidence_source") and opt.has("evidence_tokens"), "option missing evidence fields")
		var es: String = str(opt["evidence_source"])
		assert(es.begins_with("res://") and FileAccess.file_exists(es), "evidence_source path missing: " + es)
		var ef := FileAccess.open(es, FileAccess.READ)
		var etext: String = ef.get_as_text()
		ef.close()
		for tok in opt["evidence_tokens"]:
			assert(str(tok) in etext, "evidence_token %s not in %s" % [str(tok), es])
		# native_confirmed: evidence_source 文件部分 != implementation_path 文件部分（禁止循环自证）
		if str(opt["classification"]) == "native_confirmed":
			var impl_file: String = str(opt.get("implementation_path", "")).split("#")[0].get_file()
			assert(es.get_file() != impl_file, "native_confirmed evidence_source equals implementation_path (circular): " + str(opt.get("action_id")))
		# implementation_path 文件存在 + action token 命中
		var impl_path: String = str(opt.get("implementation_path", "")).split("#")[0]
		if not impl_path.is_empty():
			assert(FileAccess.file_exists(impl_path), "implementation_path missing: " + impl_path)
			var ipf := FileAccess.open(impl_path, FileAccess.READ)
			var itext: String = ipf.get_as_text()
			ipf.close()
			var action_tok: String = str(opt["action_id"]).split(":")[0]
			assert(action_tok in itext, "action token %s not in implementation %s" % [action_tok, impl_path])
	# evidence_gaps 含军情查询 + 关于军衔
	var gaps_text := JSON.stringify(reg.get("evidence_gaps", []))
	assert("军情查询" in gaps_text and "关于军衔" in gaps_text, "evidence_gaps missing 军情查询/关于军衔")
	# 75M 便捷档 + 日常官差异分类
	assert("convenience_override" in JSON.stringify(reg.get("convenience_overrides", [])), "missing 75M convenience_override")
	assert("intentional_divergence" in JSON.stringify(reg.get("intentional_divergences", [])), "missing daily officer intentional_divergence")
	# 证据文件：元帅少尉至上尉（非少尉至上校）；sprite1174 NPC + sprite827 窗口区分
	var ev_file := FileAccess.open("res://docs/evidence/npc_progression_actions_v103_v9.txt", FileAccess.READ)
	var ev_text: String = ev_file.get_as_text()
	ev_file.close()
	assert("少尉至上尉" in ev_text, "evidence file missing 少尉至上尉")
	assert(not ("少尉至上校军衔每级要1000战功" in ev_text), "evidence file still contains wrong 少尉至上校 text")
	assert("sprite 1174" in ev_text, "evidence file missing sprite 1174 NPC section")
	assert("专属窗口" in ev_text, "evidence file missing sprite 827 window clarification")
	# research 4 项 evidence_tokens 须命中 sprite1174 NPC token（证明证据来自NPC对话而非窗口）
	for t in ["进入", "研究所的当前信息", "关于2008奥运使者", "提高产量任务"]:
		assert(t in ev_text, "evidence file missing research NPC token %s" % t)
	# 注册表 JSON：含少尉至上尉，不含少尉至上校1000战功
	var reg_json := JSON.stringify(reg)
	assert("少尉至上尉" in reg_json, "registry json missing 少尉至上尉")
	assert(not ("少尉至上校1000战功" in reg_json), "registry json still contains 少尉至上校1000战功")

	print("PASS native NPC progression routes: marshal/prime/princess/daily/research exclusive actions, no progression_panel, registry verified")
	get_tree().quit(0)


func _has_choice(main: Node, label: String) -> bool:
	for child in main.dialogue_panel.choices.get_children():
		if child is Button and child.text == label:
			return true
	return false
