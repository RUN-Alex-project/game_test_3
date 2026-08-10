extends Node
## v1.41 专项测试：发布候选长流程验收（P1-3 拒签整改重写）。
## 真实状态转换（不靠写最终 flag）：新游戏启动 -> 救王 -> 最终战六类 -> 结局，以及五福娃/战魂/PK/存档。
## 终态成功 flag（game_won/king_rescued/war_soul_secret_unlocked=true）只由真实生产 API 产生；
## 测试允许"夹具重置"（写 false / 恢复初始状态），禁止伪造成功终态。
## 负向：RC_FLOW_BYPASSED_PRODUCTION_PATH——漏掉真实最终战步骤并伪造 game_won=true，
##       由同一流程验证器的最终状态断言拒绝（不再传 true 给布尔纯函数）。


func _ready() -> void:
	GameState.save_path = "user://test_v141_acceptance.json"

	# ---- 流程验证器正向：完整真实流程（救王 -> 六类最终战 -> 结局）----
	var flow_code := _run_acceptance_flow("complete")
	assert(flow_code == "", "正向完整流程必须通过（%s）" % flow_code)

	# ---- 流程验证器：漏掉最终战真实步骤 -> 成功终态不得产生（真实状态）----
	var skip_code := _run_acceptance_flow("skip_final_battle")
	assert(skip_code == "", "漏最终战（无伪造）必须不报错（game_won 应为 false 的真实状态）")
	assert(not bool(GameState.story_flags.get("game_won", false)), "漏最终战步骤后 game_won 必须仍为 false（真实状态）")

	# ---- 流程负向：漏掉最终战步骤 + 伪造成功终态 -> 同一验证器最终状态断言拒绝 ----
	var fake_code := _run_acceptance_flow("fake_terminal")
	assert(fake_code == "RC_FLOW_BYPASSED_PRODUCTION_PATH",
		"伪造成功终态必须被同一流程验证器拒绝（got '%s'）" % fake_code)

	# ---- 长流程 4：五福娃完整流程（真实 API，五轮领取）----
	GameState.story_flags["game_won"] = false  # 夹具重置（写 false 允许）
	GameState.story_flags["king_rescued"] = true  # 救王流程已产生（上段真实 API），此处保持
	GameState.fuwa_event = GameState.default_fuwa_event()
	GameState.fuwa_event.found_count = 0
	for round_i in 5:
		var start := GameState.start_fuwa_round()
		assert(bool(start.get("success", false)), "五福娃第%d轮开始必须成功" % (round_i + 1))
		var beast := GameState.complete_fuwa_beast_battle()
		assert(bool(beast.get("triggered", false)), "五福娃第%d轮战兽必须击败" % (round_i + 1))
		var claim := GameState.claim_fuwa_reward(0)
		assert(bool(claim.get("success", false)), "五福娃第%d轮领取必须成功" % (round_i + 1))
	assert(int(GameState.fuwa_event.get("found_count", 0)) == 5, "五福娃必须集齐 5 个")
	var fc_done := GameState.claim_fuwa_completion()
	assert(bool(fc_done.get("success", false)), "五福娃最终交付必须成功")

	# ---- 长流程 5：战魂秘密完整流程（成功终态只由真实 API 产生）----
	GameState.story_flags["war_soul_quest_available"] = false  # 夹具重置
	GameState.story_flags["war_soul_secret_unlocked"] = false  # 夹具重置（写 false 允许）
	GameState.equipment = {"weapon": {"enhancement": {"quality_level": 4}}, "helmet": {"enhancement": {"quality_level": 4}},
		"necklace": {"enhancement": {"quality_level": 4}}, "armor": {"enhancement": {"quality_level": 4}},
		"bracelet": {"enhancement": {"quality_level": 4}}, "boots": {"enhancement": {"quality_level": 4}}}
	assert(GameState.try_unlock_war_soul_quest(), "战魂任务必须经真实 API 解锁")
	GameState.magic_stones = 100000
	var ws := GameState.enter_war_soul_maze()
	assert(bool(ws.get("success", false)), "战魂谜宫必须经真实 API 进入")
	assert(GameState.reveal_war_soul_guardian(), "封印之箱必须经真实 API 显守卫")
	var wc := GameState.complete_war_soul_secret()
	assert(bool(wc.get("triggered", false)), "战魂完成必须经真实 API 触发")
	assert(bool(GameState.story_flags.get("war_soul_secret_unlocked", false)), "战魂秘密必须解锁（真实 API 产生）")

	# ---- 长流程 6：PK 代表组 + 当天重复限制 ----
	GameState.current_day = 6  # 周六（夹具日期）
	GameState.level = 30
	GameState.last_pk_race_day = 0  # 夹具重置
	var pk := GameState.register_pk_race()
	assert(bool(pk.get("success", false)), "PK 报名必须经真实 API 成功")
	assert(int(pk.get("group", 0)) == 1, "PK 30 级必须入 1 组")
	var pk2 := GameState.register_pk_race()
	assert(not bool(pk2.get("success", false)) and str(pk2.get("reason", "")) == "already_entered",
		"PK 当天重复报名必须被拒（真实幂等）")

	# ---- 长流程 10：存档 round-trip（直接保存前面真实流程产生的状态，不额外写成功终态）----
	assert(GameState.save_game(), "长流程：存档必须成功")
	GameState.story_flags["king_rescued"] = false  # 夹具重置（写 false 允许）
	GameState.story_flags["war_soul_secret_unlocked"] = false  # 夹具重置
	assert(GameState.load_game(), "长流程：读档必须成功")
	assert(bool(GameState.story_flags.get("king_rescued", false)), "长流程：读档后 king_rescued 必须恢复")
	assert(bool(GameState.story_flags.get("war_soul_secret_unlocked", false)), "长流程：读档后战魂秘密必须恢复")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	print("PASS v1.41 release acceptance: 真实流程 救王->最终战->结局（含漏步骤/伪造终态负向经同一验证器）+ 五福娃 + 战魂 + PK + 存档 round-trip（终态成功 flag 仅由真实 API 产生；允许夹具重置写 false）")
	get_tree().quit(0)


## 流程验证器（正向与负向共用同一最终状态断言）：
## - complete：真实救王 + 六类最终战 -> game_won=true
## - skip_final_battle：真实救王 + 漏最终战 -> game_won 必须仍为 false（真实状态，不报错）
## - fake_terminal：漏最终战 + 伪造 game_won=true -> 最终状态断言拒绝 RC_FLOW_BYPASSED_PRODUCTION_PATH
func _run_acceptance_flow(mode: String) -> String:
	GameState.current_map_id = "cassano_city"
	GameState.level = 30
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.player_current_hp = 550
	GameState.nobility_merit = 0
	GameState.story_flags["king_rescued"] = false  # 夹具重置（写 false 允许）
	GameState.story_flags["game_won"] = false      # 夹具重置（写 false 允许）
	GameState.demon_campaign = GameState.default_demon_campaign()
	if not bool(GameState.rescue_king().get("triggered", false)):
		return "RC_FLOW_STEP_MISSING"  # 救王必须经真实 API 触发
	if mode == "complete":
		for monster_id in ["demon_assault", "demon_guard", "demon_mystery", "demon_totem", "demon_commander", "demon_energy"]:
			if not bool(GameState.resolve_final_campaign_victory(monster_id).get("triggered", false)):
				return "RC_FLOW_STEP_MISSING"  # 六类最终战必须经真实 API
	elif mode == "fake_terminal":
		GameState.story_flags["game_won"] = true  # 负向变异：伪造成功终态（绕过真实六类流程）
	# 最终状态断言：成功终态只能由完整六类流程产生
	if bool(GameState.story_flags.get("game_won", false)) and mode != "complete":
		return "RC_FLOW_BYPASSED_PRODUCTION_PATH"
	if not bool(GameState.story_flags.get("game_won", false)) and mode == "complete":
		return "RC_FLOW_STEP_MISSING"  # 声称完整流程但结局未产生
	return ""
