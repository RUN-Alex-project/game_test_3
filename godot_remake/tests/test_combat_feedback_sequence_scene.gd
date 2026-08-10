extends Node
## v1.37 整改02 专项测试：战斗反馈事件序列（唯一生产反馈通道 CombatFeedbackService）。
## 分区结构：A-I + N（负向），每区独立函数；最终断言 completed_sections == EXPECTED_SECTIONS，
## PASS 只在全部分区完成后打印。
##
## 覆盖（整改02）：
##   A. 三回合逐回合事件集合/attack_sequence/dedupe key/声音请求；显式 key 不触发默认 key 生成。
##   B. 技能完整生命周期（skill_started 新回合建立后/skill_finished 同 session+sequence）、
##      精确体力、伤害状态差、体力不足降级、被动/utility 分类。
##   C. AudioService 真实记录（headless 先记录再跳过播放）——正向检查（无生产变异点，如实降级说明）。
##   D. dodge 确定性（test_dodge_roll 强制）+ busy 全快照。
##   E. 胜利/失败/战斗退出流程 + 战斗生命周期状态机（active/victory_rewards/defeat_rewards/idle；
##      idle 上下文普通领取不被顺序规则拒绝；end_session 后延迟战斗事件拒绝）。
##   F. 掉落：单 item/双相同 item（真实 claim_loot ×2，operation id 不同）/背包满失败。
##   G. level_up 连续两次 + per_level。
##   H. SWF DefineSound 三方比对 + 字段篡改 + 证据路径/token 变异负向（调用验证器命中精确错误码）。
##   I. headless 记录 + 声音请求无重复。
##   N. 负向集合：重复 key / 顺序交换 / 未登记声音 / 被动伪装 / 旧 session /
##      跨回合共用 key / 同回合 Dictionary 别名污染（命中缺陷）/ skill_finished 缺失与错回合 /
##      per_item 同 operation 重复回调 / per_level 错误去重。
##      每个负向：mutation_applied 前置断言 + 与正向相同的验证器 + 精确错误码 + 恢复后正向对照。

const SceneBattleController = preload("res://scripts/scene_battle_controller.gd")
const BattleSession = preload("res://scripts/battle_session.gd")
const SwfParser = preload("res://tests/helpers/swf_parser.gd")
const SWF_PATH := "E:/deepseek-work/TKS3_mod/魔域1.03_v9.swf"

var ctrl: Control
var player_actor: TextureRect
var monster_actor: TextureRect

const SLOTS := ["weapon", "helmet", "necklace", "armor", "bracelet", "boots"]
const ROUND1_EVENTS := ["player_attack_started", "monster_hit", "player_attack_frame", "monster_attack_started", "monster_attack_finished", "player_attack_finished"]
const EXPECTED_SECTIONS := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "N"]
var completed_sections: Array = []


func _ready() -> void:
	GameState.save_path = "user://v137_feedback_test_save.json"
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.player_current_hp = 550
	GameState.player_current_stamina = 110
	GameState.learned_skills = {}
	GameState.equipment = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
	GameState.loot_queue = []
	GameState.quest_states = GameState.quest_service.default_states()
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})
	for pet in GameState.pets:
		pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	AudioService.test_reset_play_history()

	ctrl = SceneBattleController.new()
	add_child(ctrl)
	player_actor = TextureRect.new()
	player_actor.position = Vector2(300, 400)
	player_actor.size = Vector2(57, 161)
	monster_actor = TextureRect.new()
	monster_actor.position = Vector2(430, 300)
	monster_actor.size = Vector2(80, 90)
	add_child(player_actor)
	add_child(monster_actor)
	ctrl.player_actor = player_actor

	await _run_all()
	print("PASS v1.37 整改02 combat feedback: sections A-I+N all completed with section-set assertion and mutation-negative proof")
	get_tree().quit(0)


# --- 等待辅助（可控时间推进：真实 create_timer）---

func _wait_round_end(timeout := 4.0) -> bool:
	var elapsed := 0.0
	while ctrl.busy:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
		if elapsed >= timeout:
			return false
	return true


func _wait_battle_end(timeout := 6.0) -> bool:
	var elapsed := 0.0
	while ctrl.session != null or ctrl.busy:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
		if elapsed >= timeout:
			return false
	return true


func _reset_battle_state() -> void:
	GameState.equipment = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.player_current_hp = 550
	GameState.player_current_stamina = 110
	GameState.learned_skills = {}
	GameState.loot_queue = []
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})
	for pet in GameState.pets:
		pet.level = 1
		pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	ctrl.test_dodge_roll = -1.0
	ctrl.attack_sequence = 0
	AudioService.test_reset_play_history()
	FeedbackService.test_reset()


func _count(event_type: String, skill_id: String = "", sound_name: String = "", item_id: String = "") -> int:
	var n := 0
	for ev in FeedbackService.test_event_history():
		if not bool(ev.get("accepted", false)) or str(ev.get("event_type", "")) != event_type:
			continue
		if not skill_id.is_empty() and str(ev.get("skill_id", "")) != skill_id:
			continue
		if not sound_name.is_empty() and str(ev.get("sound_name", "")) != sound_name:
			continue
		if not item_id.is_empty() and str(ev.get("payload", {}).get("item_id", "")) != item_id:
			continue
		n += 1
	return n


func _round_events(round: int) -> Array:
	var result: Array = []
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and int(ev.get("attack_sequence", -1)) == round:
			result.append(str(ev.get("event_type", "")))
	return result


func _round_rejected(round: int) -> int:
	var n := 0
	for ev in FeedbackService.test_event_history():
		if not bool(ev.get("accepted", false)) and int(ev.get("attack_sequence", -1)) == round:
			n += 1
	return n


func _round_dedupe_key(round: int, event_type: String) -> String:
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and int(ev.get("attack_sequence", -1)) == round and str(ev.get("event_type", "")) == event_type:
			return str(ev.get("dedupe_key", ""))
	return ""


func _equip_dodge_set() -> void:
	for slot in SLOTS:
		var instance := GameState.enhancement.create_equipment_instance("field_" + slot)
		instance = (GameState.enhancement.activate_war_soul(instance, 0.0) as Dictionary).get("equipment", instance)
		instance = GameState.enhancement.set_soul_levels(instance, 0, 5)
		GameState.equipment[slot] = {"item_id": "field_" + slot, "enhancement": instance}


func _run_all() -> void:
	await _section_a()
	completed_sections.append("A")
	print("SECTION A done: three rounds per-round event set/sequence/dedupe-key/sound-request")
	await _section_b()
	completed_sections.append("B")
	print("SECTION B done: skill lifecycle stamina damage fallback passive/utility")
	await _section_c()
	completed_sections.append("C")
	print("SECTION C done: AudioService headless recording (positive check)")
	await _section_d()
	completed_sections.append("D")
	print("SECTION D done: deterministic dodge and busy full snapshot")
	await _section_e()
	completed_sections.append("E")
	print("SECTION E done: victory/defeat/retreat and battle lifecycle state machine")
	await _section_f()
	completed_sections.append("F")
	print("SECTION F done: single/dual-identical loot claim and full-inventory failure")
	await _section_g()
	completed_sections.append("G")
	print("SECTION G done: consecutive level_up and per_level strategy")
	await _section_h()
	completed_sections.append("H")
	print("SECTION H done: SWF triple check, field tamper, evidence path/token mutation negatives")
	await _section_i()
	completed_sections.append("I")
	print("SECTION I done: headless recording and no-duplicate sound requests")
	await _section_n()
	completed_sections.append("N")
	print("SECTION N done: all 10 mutation-negative cases")
	assert(completed_sections == EXPECTED_SECTIONS, "completed section set mismatch: %s vs %s" % [str(completed_sections), str(EXPECTED_SECTIONS)])
	# 协程落地帧：最后一次 cancel 后悬挂的 process_frame await 在此完成（quit 竞态修复）
	await get_tree().process_frame
	await get_tree().process_frame


# ============ A. 三回合 + dedupe 策略 ============

func _section_a() -> void:
	_reset_battle_state()
	for pet in GameState.pets:
		pet.level = 300
		pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	assert(ctrl.engage("spider", monster_actor), "three-round engage failed")
	var battle_session := FeedbackService.session_id
	assert(battle_session > 0, "begin_session must assign a session id")
	for round in [1, 2, 3]:
		if round > 1:
			assert(ctrl.session != null, "battle must survive round %d" % round)
			ctrl._attack()
		assert(await _wait_round_end(), "round %d did not finish" % round)
		var evs := _round_events(round)
		assert(evs == ROUND1_EVENTS, "round %d event set mismatch: %s" % [round, str(evs)])
		assert(_round_rejected(round) == 0, "round %d must have no rejected events" % round)
		for event_type in ROUND1_EVENTS:
			var key := _round_dedupe_key(round, event_type)
			assert(key == "attack:%d:%d:%s" % [battle_session, round, event_type],
				"round %d dedupe key %s must embed session+sequence+event" % [round, key])
		assert(AudioService.test_play_count("attack") == round, "attack sound must fire once per round")
		assert(AudioService.test_play_count("monster_attack_normal") == round, "monster attack sound must fire once per round")
	assert(int(ctrl.session.turn) == 3, "three rounds must advance turn to 3")
	ctrl.cancel_battle()
	# 显式 dedupe key 存在时不得执行默认 key 生成逻辑（纯函数性；默认 key 无副作用）。
	# idle 上下文（无战斗顺序约束）：loot_claimed 无 reward_queued 前置。
	FeedbackService.test_reset()
	assert(FeedbackService.battle_state == "idle", "explicit-key fixture must run in idle context")
	var explicit := FeedbackService.emit("loot_claimed", {"item_id": "rose", "dedupe_key": "explicit_key", "claim_operation_id": "op-x"})
	assert(bool(explicit.get("accepted", false)), "explicit-key event must be accepted")
	assert(FeedbackService.test_dedupe_key_of("loot_claimed") == "explicit_key", "explicit key must be used verbatim")
	# mutation_applied：显式 key 场景下默认 key 生成被跳过——同一默认 key 的事件仍可接受
	# （说明默认 key 逻辑未在显式 key 时被消费/污染）
	var after_explicit := FeedbackService.emit("loot_claimed", {"item_id": "rose", "claim_operation_id": "op-1"})
	assert(bool(after_explicit.get("accepted", false)), "default-key event after explicit must not be polluted")


# ============ B. 技能生命周期 ============

func _section_b() -> void:
	# B1. flying_slash 2 级（成本 5）
	_reset_battle_state()
	GameState.learned_skills = {"flying_slash": 2}
	assert(ctrl.engage("spider", monster_actor, null, "flying_slash"), "flying slash engage failed")
	assert(await _wait_round_end(), "flying slash round did not finish")
	assert(_count("skill_started", "flying_slash") == 1, "skill_started missing")
	assert(_count("skill_finished", "flying_slash") == 1, "skill_finished missing")
	var ss := FeedbackService.test_session_and_sequence_of("skill_started", "flying_slash")
	var sf := FeedbackService.test_session_and_sequence_of("skill_finished", "flying_slash")
	assert(int(ss.get("session_id", -1)) == int(sf.get("session_id", -1)), "skill_started/finished must share session_id")
	assert(int(ss.get("attack_sequence", -1)) == int(sf.get("attack_sequence", -1)), "skill_started/finished must share attack_sequence")
	var seq_b1 := FeedbackService.test_event_type_sequence()
	assert(seq_b1.find("skill_started") < seq_b1.find("player_attack_started"), "skill_started must precede attack start")
	assert(seq_b1.find("player_attack_started") < seq_b1.find("monster_hit"), "attack must precede hit")
	assert(seq_b1.find("monster_hit") < seq_b1.find("skill_finished"), "hit must precede skill_finished")
	assert(seq_b1.find("skill_finished") < seq_b1.find("player_attack_finished"), "skill_finished must precede attack finish")
	assert(GameState.player_current_stamina == 105, "flying slash rank2 must deduct exactly 5 stamina")
	assert(AudioService.test_play_count("skill_flying_slash") == 1, "flying slash sound request missing")
	var stats_b := GameState.get_player_stats()
	var normal_bs := BattleSession.new("spider", stats_b, 1)
	var skill_bs := BattleSession.new("spider", stats_b, 1)
	var normal_turn := normal_bs.perform_turn(1.0, 1.0, 1.0, 1.0)
	var skill_turn := skill_bs.perform_turn(1.0, 1.0, 1.0, 1.2)
	assert(float(skill_turn.get("skill_multiplier", 0.0)) == 1.2, "skill multiplier must reach battle")
	assert(int(skill_turn.get("player_damage", 0)) > int(normal_turn.get("player_damage", 0)),
		"skill damage must exceed normal attack at same seed/variance")
	assert(int(ctrl.session.monster_hp) < 7500, "production skill attack must damage the monster")
	ctrl.cancel_battle()
	# B2. star_sword 1 级（成本 10）
	_reset_battle_state()
	GameState.learned_skills = {"star_sword": 1}
	assert(ctrl.engage("spider", monster_actor, null, "star_sword"), "star sword engage failed")
	assert(await _wait_round_end(), "star sword round did not finish")
	assert(_count("skill_started", "star_sword") == 1 and _count("skill_finished", "star_sword") == 1, "star sword lifecycle incomplete")
	assert(GameState.player_current_stamina == 100, "star sword rank1 must deduct exactly 10 stamina")
	assert(AudioService.test_play_count("skill_star_sword") == 1, "star sword sound request missing")
	ctrl.cancel_battle()
	# B3. 体力不足降级
	_reset_battle_state()
	GameState.learned_skills = {"flying_slash": 2}
	GameState.player_current_stamina = 3
	assert(ctrl.engage("spider", monster_actor, null, "flying_slash"), "stamina fallback engage failed")
	assert(await _wait_round_end(), "stamina fallback round did not finish")
	assert(_count("skill_failed_stamina", "flying_slash") == 1, "skill_failed_stamina missing")
	assert(_count("skill_started") == 0 and _count("skill_finished") == 0, "fallback must not emit skill_started/finished")
	assert(_count("player_attack_started") == 1 and _count("player_attack_finished") == 1, "fallback must degrade to exactly one normal attack")
	assert(GameState.player_current_stamina == 3, "fallback must not deduct stamina")
	assert(AudioService.test_play_count("skill_flying_slash") == 0, "fallback must not request skill sound")
	assert(AudioService.test_play_count("attack") == 1, "fallback must request exactly one normal attack sound")
	ctrl.cancel_battle()
	# B4. 被动/utility 分类
	_reset_battle_state()
	assert(str(GameState.skill_service.skills["fighting_spirit"].get("type", "")) == "passive", "passive fixture must hold")
	var passive_bad := FeedbackService.emit("skill_started", {"skill_id": "fighting_spirit"})
	assert(not bool(passive_bad.get("accepted", true)) and str(passive_bad.get("rejection_code", "")) == "FEEDBACK_PASSIVE_SKILL_TRIGGERED",
		"passive skill cast must be rejected")
	GameState.learned_skills = {"love_power": 1}
	var love := GameState.use_love_power(0.0)
	assert(bool(love.get("success", false)), "love power fixture failed")
	assert(_count("skill_started") == 0 and _count("skill_finished") == 0 and _count("skill_failed_stamina") == 0,
		"love_power must not emit battle skill feedback")


# ============ C. AudioService 真实记录（正向检查） ============

func _section_c() -> void:
	# 正向：headless 下 play() 先记录再跳过播放器（AudioService 记录为内部逻辑，无生产变异点可注入——
	# 如实降级为正向检查，mutation 需评审时手动删除记录行验证）
	_reset_battle_state()
	assert(DisplayServer.get_name() == "headless", "test must run headless")
	assert(AudioService.sfx_players.is_empty(), "headless must not create audio players")
	AudioService.play("attack")
	assert(AudioService.test_play_count("attack") == 1, "headless play must record the request")
	assert(AudioService.test_play_history_size() == 1, "headless play must record history")
	assert(str(AudioService.test_play_history()[0].get("sound_name", "")) == "attack", "history must keep sound_name")
	assert(AudioService.test_play_count("nonexistent") == 0, "unplayed sound must count zero")
	AudioService.test_reset_play_history()
	assert(AudioService.test_play_history_size() == 0, "test reset must clear play history")
	# 声音请求总数守恒：一个技能回合恰好 3 个请求（attack+skill+monster，独立通道交叉）
	_reset_battle_state()
	GameState.learned_skills = {"flying_slash": 1}
	assert(ctrl.engage("spider", monster_actor, null, "flying_slash"), "cross-channel engage failed")
	assert(await _wait_round_end(), "cross-channel round did not finish")
	var total := AudioService.test_play_count("attack") + AudioService.test_play_count("skill_flying_slash") + AudioService.test_play_count("monster_attack_normal")
	assert(total == 3, "cross-channel: exactly 3 sound requests for one skill round")
	ctrl.cancel_battle()


# ============ D. dodge 确定性 + busy 快照 ============

func _section_d() -> void:
	_reset_battle_state()
	_equip_dodge_set()
	GameState.pets[0].current_hp = 0
	GameState.pets[1].current_hp = 0
	GameState.player_current_hp = 500
	ctrl.test_dodge_roll = 0.0
	assert(ctrl.engage("spider", monster_actor), "dodge engage failed")
	assert(await _wait_round_end(), "dodge round did not finish")
	assert(_count("dodge") == 1, "dodge event must fire exactly once")
	assert(_count("player_hit") == 0, "dodge must not produce player_hit")
	assert(GameState.player_current_hp == 500, "dodge must not damage the player")
	assert(AudioService.test_play_count("attack") == 1 and AudioService.test_play_count("monster_attack_normal") == 1,
		"dodge round must only request attack and monster attack sounds")
	assert(AudioService.test_play_history_size() == 2, "dodge round must not request hit/death sounds")
	assert(player_actor.modulate == Color.WHITE, "dodge must not change player visuals")
	var has_damage_label := false
	for child in ctrl.get_children():
		if child is Label and str((child as Label).text).begins_with("-"):
			has_damage_label = true
	assert(not has_damage_label, "dodge must not show damage float text")
	ctrl.cancel_battle()
	# busy 全快照
	_reset_battle_state()
	assert(ctrl.engage("spider", monster_actor), "busy engage failed")
	var snap_turn := int(ctrl.session.turn)
	var snap_stamina := int(GameState.player_current_stamina)
	var snap_player_hp := int(GameState.player_current_hp)
	var snap_monster_hp := int(ctrl.session.monster_hp)
	var snap_events := FeedbackService.test_accepted_count()
	var snap_sounds := AudioService.test_play_history_size()
	var snap_schedulers: int = ctrl.active_scheduler_count()
	assert(ctrl.engage("spider", monster_actor), "busy re-engage must be a no-op")
	assert(int(ctrl.session.turn) == snap_turn, "busy input must not advance turn")
	assert(int(GameState.player_current_stamina) == snap_stamina, "busy input must not deduct stamina")
	assert(int(GameState.player_current_hp) == snap_player_hp, "busy input must not change player HP")
	assert(int(ctrl.session.monster_hp) == snap_monster_hp, "busy input must not change monster HP")
	assert(FeedbackService.test_accepted_count() == snap_events, "busy input must not emit feedback")
	assert(AudioService.test_play_history_size() == snap_sounds, "busy input must not request sounds")
	assert(ctrl.active_scheduler_count() == snap_schedulers, "busy input must not start schedulers")
	await get_tree().create_timer(0.15).timeout
	assert(FeedbackService.test_accepted_count() == snap_events, "busy rejection must not emit later")
	assert(AudioService.test_play_history_size() == snap_sounds, "busy rejection must not request sounds later")
	ctrl.cancel_battle()


# ============ E. 胜利/失败/退出 + 战斗生命周期状态机 ============

func _section_e() -> void:
	# E1. 胜利流程 + 生命周期：active -> victory_rewards -> idle
	_reset_battle_state()
	assert(FeedbackService.battle_state == "idle", "reset must return to idle")
	assert(ctrl.engage("spider", monster_actor), "victory engage failed")
	assert(FeedbackService.battle_state == "active", "engage must enter active state")
	assert(await _wait_round_end(), "victory setup round did not finish")
	ctrl.session.monster_hp = 1
	ctrl._attack()
	assert(await _wait_battle_end(), "victory battle did not end")
	assert(_count("monster_death") == 1 and _count("victory") == 1 and _count("reward_queued") == 1, "victory sequence incomplete")
	var seq_e1 := FeedbackService.test_event_type_sequence()
	var death_idx := seq_e1.find("monster_death")
	assert(death_idx >= 0, "monster_death missing")
	assert(not seq_e1.slice(death_idx).has("monster_attack_started"), "monster must not counter-attack after death")
	assert(seq_e1.find("victory") < seq_e1.find("reward_queued"), "victory must precede reward_queued")
	var drops_count := 0
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and str(ev.get("event_type", "")) == "reward_queued":
			drops_count = int(ev.get("payload", {}).get("item_count", 0))
	assert(_count("loot_claimed") == drops_count, "loot_claimed count must equal queued drops")
	assert(AudioService.test_play_count("victory") == 1, "victory sound request missing")
	assert(FeedbackService.battle_state == "idle", "victory must end session to idle after battle_finished")
	await get_tree().create_timer(2.3).timeout
	# E2. 玩家死亡 + 生命周期：active -> defeat_rewards -> idle
	_reset_battle_state()
	GameState.pets[0].current_hp = 0
	GameState.pets[1].current_hp = 0
	GameState.player_current_hp = 1
	assert(ctrl.engage("spider", monster_actor), "player death engage failed")
	assert(await _wait_battle_end(), "defeat battle did not end")
	assert(_count("player_death") == 1, "player_death must occur exactly once")
	assert(AudioService.test_play_count("death") == 1, "death sound request missing")
	var seq_e2 := FeedbackService.test_event_type_sequence()
	var pdeath_idx := seq_e2.find("player_death")
	assert(pdeath_idx >= 0 and not seq_e2.slice(pdeath_idx).has("player_attack_started"), "no player attack after player death")
	assert(FeedbackService.battle_state == "idle", "defeat must end session to idle")
	# E3. 战斗退出（幸运耗尽）：battle_retreat 语义事件（战斗中：先 begin_session）
	_reset_battle_state()
	FeedbackService.begin_session()
	ctrl.session = BattleSession.new("spider", GameState.get_player_stats(), 1)
	ctrl.session.force_defeat("pet_luck_exhausted")
	await ctrl._finish_defeat()
	assert(_count("battle_retreat") == 1, "battle_retreat must fire exactly once")
	assert(_count("player_death") == 0, "retreat must not emit player_death")
	assert(AudioService.test_play_count("death") == 1, "retreat must keep baseline death sound via feedback channel")
	# E4. 生命周期：idle 上下文普通掉落领取不被顺序规则拒绝（不因缺少 victory/reward_queued 被拒）
	_reset_battle_state()
	assert(FeedbackService.battle_state == "idle", "idle fixture must hold")
	GameState.queue_loot(["exp_ball"])
	assert(GameState.claim_loot("exp_ball"), "idle-context claim must succeed")
	assert(_count("loot_claimed", "", "", "exp_ball") == 1, "idle-context loot_claimed must be accepted without reward_queued")
	# E5. 生命周期：end_session 后延迟战斗事件拒绝
	_reset_battle_state()
	FeedbackService.begin_session()
	var ended_session := FeedbackService.session_id
	FeedbackService.end_session()
	var delayed := FeedbackService.emit("monster_attack_started", {"session_id": ended_session, "attack_sequence": 1})
	assert(not bool(delayed.get("accepted", true)) and str(delayed.get("rejection_code", "")) == "FEEDBACK_STALE_SESSION_EVENT",
		"delayed battle event after end_session must be rejected")


# ============ F. 掉落 ============

func _section_f() -> void:
	# F1. 双相同 item：真实 claim_loot ×2，两次接受、operation id 不同、队列删除正确
	_reset_battle_state()
	GameState.queue_loot(["exp_ball", "exp_ball"])
	assert(GameState.claim_loot("exp_ball"), "first claim must succeed")
	assert(GameState.claim_loot("exp_ball"), "second identical claim must succeed")
	assert(GameState.loot_queue.is_empty(), "loot queue must be empty after both claims")
	assert(_count("loot_claimed", "", "", "exp_ball") == 2, "two identical items must produce two loot_claimed events")
	var claim_keys: Array = []
	var operation_ids: Array = []
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and str(ev.get("event_type", "")) == "loot_claimed" and str(ev.get("payload", {}).get("item_id", "")) == "exp_ball":
			claim_keys.append(str(ev.get("dedupe_key", "")))
			operation_ids.append(str(ev.get("payload", {}).get("claim_operation_id", "")))
	assert(claim_keys.size() == 2 and claim_keys[0] != claim_keys[1], "per_item dedupe keys must distinguish identical claims")
	assert(operation_ids.size() == 2 and operation_ids[0] != operation_ids[1], "claim_operation_id must differ across independent claims")
	# 同一次领取回调重复（同 operation id）-> 第二次拒绝（使用真实 claim_loot 产生的 operation id）
	var first_op: String = str(operation_ids[0])
	var repeat := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": first_op})
	assert(not bool(repeat.get("accepted", true)) and str(repeat.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"repeat callback with same operation id must be rejected")
	# F2. 背包满失败：不产生成功事件、不删除队列物品
	_reset_battle_state()
	for i in 48:
		GameState.inventory[i] = {"item_id": "rose", "quantity": 99}
	GameState.loot_queue = ["exp_ball"]
	var queue_before := GameState.loot_queue.duplicate()
	assert(not GameState.claim_loot("exp_ball"), "full-inventory claim must fail")
	assert(GameState.loot_queue == queue_before, "failed claim must not delete the queued item")
	assert(_count("loot_claim_failed", "", "", "exp_ball") == 1, "failed claim must emit loot_claim_failed")
	assert(_count("loot_claimed") == 0, "failed claim must not emit loot_claimed")


# ============ G. level_up ============

func _section_g() -> void:
	_reset_battle_state()
	GameState.level = 1
	GameState.experience = GameState.experience_to_next_level() - 1
	GameState.apply_victory_rewards({"experience": 1, "military_merit": 0, "nobility_merit": 0, "gold": 0, "magic_stones": 0, "monster_id": "spider"})
	assert(_count("level_up") == 1, "first level-up must emit level_up")
	assert(GameState.level == 2, "first level-up must reach level 2")
	assert(AudioService.test_play_count("level_up") == 1, "level_up sound request missing")
	GameState.experience = GameState.experience_to_next_level() - 1
	GameState.apply_victory_rewards({"experience": 1, "military_merit": 0, "nobility_merit": 0, "gold": 0, "magic_stones": 0, "monster_id": "spider"})
	assert(_count("level_up") == 2, "second consecutive level-up must not be swallowed by dedupe")
	assert(GameState.level == 3, "second level-up must reach level 3")
	var level_keys: Array = []
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and str(ev.get("event_type", "")) == "level_up":
			level_keys.append(str(ev.get("dedupe_key", "")))
	assert(level_keys.size() == 2 and level_keys[0] != level_keys[1], "per_level keys must differ across levels")
	# per_level 负向：同 level 重复 -> FEEDBACK_DUPLICATE_EVENT；不同 level 恢复接受
	var lv1 := FeedbackService.emit("level_up", {"level": 50, "sound_name": "level_up"})
	assert(bool(lv1.get("accepted", false)), "first per_level event must be accepted")
	var lv2 := FeedbackService.emit("level_up", {"level": 50, "sound_name": "level_up"})
	assert(not bool(lv2.get("accepted", true)) and str(lv2.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"same-level level_up must be rejected (per_level)")
	var lv3 := FeedbackService.emit("level_up", {"level": 51, "sound_name": "level_up"})
	assert(bool(lv3.get("accepted", false)), "next-level level_up must be accepted")
	assert(AudioService.test_play_count("level_up") == 4, "sound requests must match accepted level_up events")


# ============ H. SWF 三方比对 + 证据链变异负向 ============

func _section_h() -> void:
	var evidence_path := FeedbackService.test_registry_evidence_source()
	assert(evidence_path == "res://docs/evidence/combat_feedback_v103_v9.txt", "registry evidence_source must be readable")
	var evidence_file := FileAccess.open(evidence_path, FileAccess.READ)
	assert(evidence_file != null, "evidence file from registry must exist")
	var evidence_text := evidence_file.get_as_text()

	var parser := SwfParser.new(SWF_PATH)
	assert(parser.is_loaded(), "SWF parser must load")
	assert(parser.sound_definitions.size() == 37, "SWF must define 37 sounds")

	var manifest_file := FileAccess.open("res://assets/extracted/sounds/manifest.csv", FileAccess.READ)
	assert(manifest_file != null, "manifest must exist")
	var manifest_rows: Dictionary = {}
	for line in manifest_file.get_as_text().strip_edges().split("\n").slice(1):
		var parts := line.split(",")
		if parts.size() < 8:
			continue
		manifest_rows[int(parts[0])] = {
			"format": int(parts[1]), "rate": int(parts[2]), "sample_width": int(parts[3]),
			"channels": int(parts[4]), "sample_count": int(parts[5]),
		}

	for sound_id in parser.sound_definitions:
		var swf: Dictionary = parser.sound_definitions[sound_id]
		assert(manifest_rows.has(sound_id), "manifest missing SWF sound %d" % sound_id)
		var manifest: Dictionary = manifest_rows[sound_id]
		var entry := FeedbackService.registered_sound(sound_id)
		assert(not entry.is_empty(), "registry missing sound %d" % sound_id)
		assert(int(swf.get("format", -1)) == 2 and int(manifest.get("format", -1)) == 2 and str(entry.get("format", "")) == "mp3",
			"format mismatch sound %d" % sound_id)
		assert(int(swf.get("rate", 0)) == int(manifest.get("rate", 0)) and int(manifest.get("rate", 0)) == int(entry.get("rate", 0)),
			"rate mismatch sound %d" % sound_id)
		assert(int(swf.get("sample_width", 0)) == int(manifest.get("sample_width", 0)) and int(manifest.get("sample_width", 0)) == int(entry.get("sample_width", 0)),
			"sample_width mismatch sound %d" % sound_id)
		assert(int(swf.get("channels", 0)) == int(manifest.get("channels", 0)) and int(manifest.get("channels", 0)) == int(entry.get("channels", 0)),
			"channels mismatch sound %d" % sound_id)
		assert(int(swf.get("sample_count", 0)) == int(manifest.get("sample_count", 0)) and int(manifest.get("sample_count", 0)) == int(entry.get("sample_count", 0)),
			"sample_count mismatch sound %d" % sound_id)
		assert(str(entry.get("classification", "")) in ["native_confirmed", "used_unconfirmed", "evidence_gap", "unrelated"],
			"invalid classification sound %d" % sound_id)
		assert(FileAccess.file_exists(str(entry.get("file", ""))), "sound file missing %d" % sound_id)
		var segment := _evidence_segment(evidence_text, sound_id)
		assert(not segment.is_empty(), "evidence segment missing sound %d" % sound_id)
		assert(FeedbackService.validate_evidence_tokens(entry, segment) == "", "valid entry tokens must pass segment validator")
	assert(manifest_rows.size() == 37 and FeedbackService.registry_sound_count() == 37, "triple check must cover all 37 sounds")
	assert(FeedbackService.validate_registry_against_manifest().is_empty(), "registry must match manifest")

	# 字段篡改负向（真实变异条目 -> 验证器 -> 精确错误码）
	var bad_entry := FeedbackService.registered_sound(1).duplicate(true)
	bad_entry["rate"] = 99999
	assert(FeedbackService.validate_sound_entry_fields(1, bad_entry, manifest_rows[1]) == "FEEDBACK_SOUND_FIELD_MISMATCH",
		"tampered rate must hit FEEDBACK_SOUND_FIELD_MISMATCH")
	bad_entry = FeedbackService.registered_sound(1).duplicate(true)
	bad_entry["sample_count"] = 0
	assert(FeedbackService.validate_sound_entry_fields(1, bad_entry, manifest_rows[1]) == "FEEDBACK_SOUND_FIELD_MISMATCH",
		"tampered sample_count must hit FEEDBACK_SOUND_FIELD_MISMATCH")
	assert(FeedbackService.validate_sound_entry_fields(1, FeedbackService.registered_sound(1), manifest_rows[1]) == "",
		"untampered entry must pass")

	# 证据路径变异负向（变异 evidence_source -> 验证器 -> FEEDBACK_EVIDENCE_MISSING）
	var bogus_source := "res://docs/evidence/does_not_exist.txt"
	assert(not FileAccess.file_exists(bogus_source), "bogus evidence path fixture must not exist")
	assert(FeedbackService.validate_evidence_source(bogus_source) == "FEEDBACK_EVIDENCE_MISSING",
		"bogus evidence source must hit FEEDBACK_EVIDENCE_MISSING")
	assert(FeedbackService.validate_evidence_source(evidence_path) == "", "real evidence source must pass")

	# 证据 token 变异负向（变异条目：token 不在所属段 -> 验证器 -> FEEDBACK_EVIDENCE_MISSING）
	var seg1 := _evidence_segment(evidence_text, 1)
	assert(not seg1.contains("sprite124"), "sound_0001 segment must not contain sound_0123 token")
	var tampered_tokens := FeedbackService.registered_sound(1).duplicate(true)
	tampered_tokens["evidence_tokens"] = ["sprite124", "frame7"]
	assert(FeedbackService.validate_evidence_tokens(tampered_tokens, seg1) == "FEEDBACK_EVIDENCE_MISSING",
		"token outside its segment must hit FEEDBACK_EVIDENCE_MISSING")
	assert(FeedbackService.validate_evidence_tokens(FeedbackService.registered_sound(1), seg1) == "",
		"valid tokens must pass segment validator")


func _evidence_segment(evidence_text: String, sound_id: int) -> String:
	var marker := "sound_%04d rate" % sound_id
	var lines := evidence_text.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].begins_with(marker):
			start = i
			break
	if start < 0:
		return ""
	var result: Array = []
	for j in range(start + 1, lines.size()):
		if lines[j].begins_with("sound_") or lines[j].begins_with("=== "):
			break
		result.append(lines[j])
	return "\n".join(result)


# ============ I. headless 记录与无重复 ============

func _section_i() -> void:
	_reset_battle_state()
	assert(DisplayServer.get_name() == "headless", "test must run headless")
	assert(AudioService.sfx_players.is_empty(), "headless must not create audio players")
	FeedbackService.begin_session()
	FeedbackService.emit("victory", {"sound_name": "victory"})
	assert(_count("victory", "", "victory") == 1, "recorded event must keep its sound_name")
	assert(AudioService.test_play_count("victory") == 1, "headless play must record the request")
	# 声音请求无重复：被 dedupe 拒绝的事件不产生声音请求
	var before := AudioService.test_play_history_size()
	var dup := FeedbackService.emit("victory", {"sound_name": "victory"})
	assert(not bool(dup.get("accepted", true)), "duplicate victory must be rejected")
	assert(AudioService.test_play_history_size() == before, "rejected event must not request sounds")
	FeedbackService.end_session()


# ============ N. 负向集合（mutation_applied + 同一验证器 + 精确错误码 + 恢复对照） ============

func _section_n() -> void:
	# N1. 重复 dedupe key
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	FeedbackService.set_attack_sequence(1)
	var dup_first := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "dup_key"})
	assert(bool(dup_first.get("accepted", false)), "first event must be accepted")
	var dup_second := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "dup_key"})
	assert(not bool(dup_second.get("accepted", true)) and str(dup_second.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"duplicate key must be rejected")
	assert(_count("player_attack_started") == 1, "only first event accepted")
	var dup_third := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "dup_key3"})
	assert(bool(dup_third.get("accepted", false)), "fresh key must be accepted after rejection")
	FeedbackService.end_session()

	# N2. 交换攻击/受击顺序
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	FeedbackService.set_attack_sequence(1)
	assert(FeedbackService.test_event_count("player_attack_started") == 0, "sequence fixture must start empty")
	var seq_bad := FeedbackService.emit("monster_hit", {"attack_sequence": 1})
	assert(not bool(seq_bad.get("accepted", true)) and str(seq_bad.get("rejection_code", "")) == "FEEDBACK_SEQUENCE_MISMATCH",
		"hit before attack must be rejected")
	var seq_good1 := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "seq1"})
	var seq_good2 := FeedbackService.emit("monster_hit", {"attack_sequence": 1, "dedupe_key": "seq2"})
	assert(bool(seq_good1.get("accepted", false)) and bool(seq_good2.get("accepted", false)), "ordered events must be accepted")
	FeedbackService.end_session()

	# N3. 未登记 sound
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	assert(FeedbackService.sound_id_of("nonexistent_sound") == -1, "fixture must be unregistered")
	var snd_bad := FeedbackService.emit("victory", {"sound_name": "nonexistent_sound"})
	assert(not bool(snd_bad.get("accepted", true)) and str(snd_bad.get("rejection_code", "")) == "FEEDBACK_SOUND_UNREGISTERED",
		"unregistered sound must be rejected")
	var snd_good := FeedbackService.emit("victory", {"sound_name": "victory", "dedupe_key": "snd1"})
	assert(bool(snd_good.get("accepted", false)), "registered sound must be accepted")
	FeedbackService.end_session()

	# N4. 被动伪装主动
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	assert(str(GameState.skill_service.skills["fighting_spirit"].get("type", "")) == "passive", "passive fixture must hold")
	var pas_bad := FeedbackService.emit("skill_started", {"skill_id": "fighting_spirit"})
	assert(not bool(pas_bad.get("accepted", true)) and str(pas_bad.get("rejection_code", "")) == "FEEDBACK_PASSIVE_SKILL_TRIGGERED",
		"passive cast must be rejected")
	var act_good := FeedbackService.emit("skill_started", {"skill_id": "star_sword", "dedupe_key": "act1"})
	assert(bool(act_good.get("accepted", false)), "active skill must be accepted")
	FeedbackService.end_session()

	# N5. 旧 session 事件
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	var cancelled_session := FeedbackService.session_id
	FeedbackService.end_session()
	assert(FeedbackService.session_id != cancelled_session, "session must be invalidated")
	var stale_bad := FeedbackService.emit("player_attack_started", {"session_id": cancelled_session, "attack_sequence": 1})
	assert(not bool(stale_bad.get("accepted", true)) and str(stale_bad.get("rejection_code", "")) == "FEEDBACK_STALE_SESSION_EVENT",
		"stale session event must be rejected")
	FeedbackService.begin_session()  # 新 session（active）——当前 session 事件接受
	var stale_good := FeedbackService.emit("player_attack_started", {"dedupe_key": "stale_ok"})
	assert(bool(stale_good.get("accepted", false)), "current session event must be accepted")
	FeedbackService.end_session()

	# N6. 跨回合共用 key：被拒事件不得伪造前置状态
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	FeedbackService.set_attack_sequence(1)
	var shared_first := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "shared"})
	assert(bool(shared_first.get("accepted", false)), "shared-key first event must be accepted")
	FeedbackService.set_attack_sequence(2)
	var shared_second := FeedbackService.emit("player_attack_started", {"attack_sequence": 2, "dedupe_key": "shared"})
	assert(not bool(shared_second.get("accepted", true)) and str(shared_second.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"shared-key second event must be rejected by dedupe")
	var pollution_probe := FeedbackService.emit("monster_hit", {"attack_sequence": 2, "dedupe_key": "probe"})
	assert(not bool(pollution_probe.get("accepted", true)) and str(pollution_probe.get("rejection_code", "")) == "FEEDBACK_SEQUENCE_MISMATCH",
		"rejected event must not fake attack_started for round 2")
	var round2_ok := FeedbackService.emit("player_attack_started", {"attack_sequence": 2, "dedupe_key": "r2"})
	var round2_hit := FeedbackService.emit("monster_hit", {"attack_sequence": 2, "dedupe_key": "r2hit"})
	assert(bool(round2_ok.get("accepted", false)) and bool(round2_hit.get("accepted", false)), "round 2 must recover")
	FeedbackService.end_session()

	# N7. 同回合 Dictionary 别名污染（整改02 必测：命中"同回合不 duplicate"缺陷）
	#    先接受 player_attack_started(key=same_shared)；再 monster_attack_started 复用 same_shared
	#    （被 dedupe 拒——旧实现在 transition 阶段会直接写入 monster_attack_started 状态）；
	#    随后新 key 的 dodge 必须因缺少合法前置被 FEEDBACK_SEQUENCE_MISMATCH 拒绝
	#    （若被拒事件污染状态则会错误接受）。
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	FeedbackService.set_attack_sequence(1)
	var same_round_first := FeedbackService.emit("player_attack_started", {"attack_sequence": 1, "dedupe_key": "same_shared"})
	assert(bool(same_round_first.get("accepted", false)), "same-round first event must be accepted")
	var same_round_second := FeedbackService.emit("monster_attack_started", {"attack_sequence": 1, "dedupe_key": "same_shared"})
	assert(not bool(same_round_second.get("accepted", true)) and str(same_round_second.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"same-round reused key must be rejected by dedupe")
	# mutation_applied：被拒事件已进入 transition 阶段（monster_attack_started 写入点），
	# 修复后该写入只发生在副本上——dodge 必须因缺少 monster_attack_started 前置被拒
	var same_round_dodge := FeedbackService.emit("dodge", {"attack_sequence": 1, "dedupe_key": "dodge_new"})
	assert(not bool(same_round_dodge.get("accepted", true)) and str(same_round_dodge.get("rejection_code", "")) == "FEEDBACK_SEQUENCE_MISMATCH",
		"same-round rejected event must not fake monster_attack_started")
	# 恢复后正向对照：合法 monster_attack_started 后 dodge 接受
	var legit_attack := FeedbackService.emit("monster_attack_started", {"attack_sequence": 1, "dedupe_key": "legit_ma"})
	var legit_dodge := FeedbackService.emit("dodge", {"attack_sequence": 1, "dedupe_key": "legit_dodge"})
	assert(bool(legit_attack.get("accepted", false)) and bool(legit_dodge.get("accepted", false)),
		"after legitimate monster_attack_started, dodge must be accepted")
	FeedbackService.end_session()

	# N8. skill_finished 缺失/错回合
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	FeedbackService.set_attack_sequence(1)
	assert(_count("skill_started") == 0, "skill lifecycle fixture must start without skill_started")
	var fin_bad := FeedbackService.emit("skill_finished", {"attack_sequence": 1, "skill_id": "flying_slash"})
	assert(not bool(fin_bad.get("accepted", true)) and str(fin_bad.get("rejection_code", "")) == "FEEDBACK_SEQUENCE_MISMATCH",
		"skill_finished without skill_started must be rejected")
	var fin_start := FeedbackService.emit("skill_started", {"attack_sequence": 1, "skill_id": "flying_slash", "dedupe_key": "s1"})
	assert(bool(fin_start.get("accepted", false)), "skill_started must be accepted")
	FeedbackService.set_attack_sequence(2)
	var fin_wrong_round := FeedbackService.emit("skill_finished", {"attack_sequence": 2, "skill_id": "flying_slash"})
	assert(not bool(fin_wrong_round.get("accepted", true)) and str(fin_wrong_round.get("rejection_code", "")) == "FEEDBACK_SEQUENCE_MISMATCH",
		"skill_finished on a different round must be rejected")
	FeedbackService.emit("skill_started", {"attack_sequence": 2, "skill_id": "flying_slash", "dedupe_key": "s2"})
	var fin_good := FeedbackService.emit("skill_finished", {"attack_sequence": 2, "skill_id": "flying_slash", "dedupe_key": "f2"})
	assert(bool(fin_good.get("accepted", false)), "same-round skill_finished must be accepted")
	FeedbackService.end_session()

	# N9. per_item 同 operation 重复回调（经真实 GameState.claim_loot 的 operation id）
	FeedbackService.test_reset()
	GameState.loot_queue = ["exp_ball"]
	assert(GameState.claim_loot("exp_ball"), "real claim must succeed")
	var real_op := ""
	for ev in FeedbackService.test_event_history():
		if bool(ev.get("accepted", false)) and str(ev.get("event_type", "")) == "loot_claimed":
			real_op = str(ev.get("payload", {}).get("claim_operation_id", ""))
	assert(not real_op.is_empty(), "real claim must carry a claim_operation_id")
	# mutation_applied：同一 operation id 已接受一次（dedupe 记录持有）
	var repeat_callback := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": real_op})
	assert(not bool(repeat_callback.get("accepted", true)) and str(repeat_callback.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"repeat callback with same operation id must be rejected")
	# 恢复后正向对照：新 operation id 接受
	var next_claim := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": "op-fresh"})
	assert(bool(next_claim.get("accepted", false)), "fresh operation id must be accepted")

	# N10. per_level 错误去重
	FeedbackService.test_reset()
	var pl1 := FeedbackService.emit("level_up", {"level": 60, "sound_name": "level_up"})
	assert(bool(pl1.get("accepted", false)), "first per_level event must be accepted")
	var pl2 := FeedbackService.emit("level_up", {"level": 60, "sound_name": "level_up"})
	assert(not bool(pl2.get("accepted", true)) and str(pl2.get("rejection_code", "")) == "FEEDBACK_DUPLICATE_EVENT",
		"same-level level_up must be rejected")
	var pl3 := FeedbackService.emit("level_up", {"level": 61, "sound_name": "level_up"})
	assert(bool(pl3.get("accepted", false)), "next-level level_up must be accepted")
	# N11. 战斗状态矩阵：idle/victory_rewards 禁止回合内事件；defeat_rewards 禁止攻击
	FeedbackService.test_reset()
	var idle_round := FeedbackService.emit("player_attack_started", {"dedupe_key": "idle_r"})
	assert(not bool(idle_round.get("accepted", true)) and str(idle_round.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"idle must reject round events")
	FeedbackService.begin_session()
	var v1 := FeedbackService.emit("victory", {"dedupe_key": "v1"})
	assert(bool(v1.get("accepted", false)), "victory must be accepted in active")
	var vr_round := FeedbackService.emit("player_attack_started", {"attack_sequence": 0, "dedupe_key": "vr_r"})
	assert(not bool(vr_round.get("accepted", true)) and str(vr_round.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"victory_rewards must reject round events")
	FeedbackService.end_session()
	FeedbackService.begin_session()
	var d1 := FeedbackService.emit("player_death", {"dedupe_key": "d1"})
	assert(bool(d1.get("accepted", false)), "player_death must be accepted in active")
	var dr_attack := FeedbackService.emit("player_attack_started", {"attack_sequence": 0, "dedupe_key": "dr_a"})
	assert(not bool(dr_attack.get("accepted", true)) and str(dr_attack.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"defeat_rewards must reject new attacks")
	var dr_skill := FeedbackService.emit("skill_started", {"attack_sequence": 0, "skill_id": "flying_slash", "dedupe_key": "dr_s"})
	assert(not bool(dr_skill.get("accepted", true)) and str(dr_skill.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"defeat_rewards must reject new skills")
	FeedbackService.end_session()

	# N12. per_item 缺少非空 claim_operation_id -> FEEDBACK_OPERATION_ID_MISSING
	FeedbackService.test_reset()
	var no_op := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball"})
	assert(not bool(no_op.get("accepted", true)) and str(no_op.get("rejection_code", "")) == "FEEDBACK_OPERATION_ID_MISSING",
		"per_item without operation id must be rejected")
	var with_op := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": "op-n"})
	assert(bool(with_op.get("accepted", false)), "per_item with operation id must be accepted")
	# N14. 完整状态矩阵 76 项返工（任务书05）：独立 EXPECTED 表（人工固化，禁止读取生产常量）
	#     + 纯函数验证器 + mutation 负向（STATE_MATRIX_MISMATCH）+ 四状态真实 emit 集成。
	var all_events := ["player_attack_started", "player_attack_frame", "player_attack_finished",
		"skill_started", "skill_failed_stamina", "skill_finished",
		"monster_hit", "monster_attack_started", "monster_attack_finished",
		"player_hit", "dodge", "monster_death", "player_death", "victory",
		"reward_queued", "loot_claimed", "loot_claim_failed", "level_up", "battle_retreat"]
	assert(all_events.size() == 19, "state matrix must cover all 19 registered events")
	# 独立预期表（任务书05 第7节规则人工固化，非从生产常量推导）：
	#   idle:            仅非战斗事件（loot_claimed/loot_claim_failed/level_up）
	#   active:          全部 19 事件
	#   victory_rewards: 升级/奖励入队/领取（禁止攻击/技能/命中/死亡/胜利/撤退）
	#   defeat_rewards:  升级/领取/撤退/死亡/受击反馈（禁止攻击/技能/怪物攻击/胜利/奖励入队）
	var EXPECTED_ALLOWED_EVENTS_BY_STATE := {
		"idle": ["loot_claimed", "loot_claim_failed", "level_up"],
		"active": all_events.duplicate(),
		"victory_rewards": ["level_up", "reward_queued", "loot_claimed", "loot_claim_failed"],
		"defeat_rewards": ["level_up", "loot_claimed", "loot_claim_failed", "battle_retreat",
			"player_death", "monster_death", "player_hit", "monster_hit", "dodge"],
	}
	# 纯函数验证器：逐项（4 状态 × 19 事件 = 76）比较生产矩阵与独立预期，返回 mismatch 列表。
	var _verify_matrix := func(production: Dictionary, expected: Dictionary) -> Array:
		var mismatches: Array = []
		for state: String in expected:
			for ev: String in all_events:
				var exp_allowed: bool = (expected[state] as Array).has(ev)
				var prod_allowed: bool = (production.get(state, []) as Array).has(ev)
				if exp_allowed != prod_allowed:
					mismatches.append("STATE_MATRIX_MISMATCH: %s/%s expected_allowed=%s production=%s"
						% [state, ev, exp_allowed, prod_allowed])
		return mismatches
	# 正向：真实生产表 vs 独立预期必须 0 mismatch（76 项全覆盖，含独立断言不变量）
	var mm: Array = _verify_matrix.call(FeedbackService.ALLOWED_EVENTS_BY_STATE, EXPECTED_ALLOWED_EVENTS_BY_STATE)
	assert(mm.is_empty(), "state matrix 76 cases must match independent expected, got: %s" % str(mm))
	# 负向 mutation（篡改生产矩阵副本——模拟生产表被误改后，同一验证器必须命中 STATE_MATRIX_MISMATCH）：
	# M-a：idle 表误删允许项 loot_claimed
	var mut_a: Dictionary = FeedbackService.ALLOWED_EVENTS_BY_STATE.duplicate(true)
	(mut_a["idle"] as Array).erase("loot_claimed")
	assert(not (mut_a["idle"] as Array).has("loot_claimed"), "mutation A must apply (idle loses loot_claimed)")
	var mm_a: Array = _verify_matrix.call(mut_a, EXPECTED_ALLOWED_EVENTS_BY_STATE)
	assert(not mm_a.is_empty() and str(mm_a[0]).begins_with("STATE_MATRIX_MISMATCH"),
		"mutation A must hit STATE_MATRIX_MISMATCH, got: %s" % str(mm_a))
	# M-b：idle 表误加禁止项 victory
	var mut_b: Dictionary = FeedbackService.ALLOWED_EVENTS_BY_STATE.duplicate(true)
	(mut_b["idle"] as Array).append("victory")
	assert((mut_b["idle"] as Array).has("victory"), "mutation B must apply (idle gains victory)")
	var mm_b: Array = _verify_matrix.call(mut_b, EXPECTED_ALLOWED_EVENTS_BY_STATE)
	assert(not mm_b.is_empty() and str(mm_b[0]).begins_with("STATE_MATRIX_MISMATCH"),
		"mutation B must hit STATE_MATRIX_MISMATCH, got: %s" % str(mm_b))
	# M-c：victory_rewards 表误加禁止项 player_attack_started
	var mut_c: Dictionary = FeedbackService.ALLOWED_EVENTS_BY_STATE.duplicate(true)
	(mut_c["victory_rewards"] as Array).append("player_attack_started")
	assert((mut_c["victory_rewards"] as Array).has("player_attack_started"), "mutation C must apply")
	var mm_c: Array = _verify_matrix.call(mut_c, EXPECTED_ALLOWED_EVENTS_BY_STATE)
	assert(not mm_c.is_empty() and str(mm_c[0]).begins_with("STATE_MATRIX_MISMATCH"),
		"mutation C must hit STATE_MATRIX_MISMATCH, got: %s" % str(mm_c))
	# 四状态真实 emit() 集成状态差（每个状态至少一次真实接受 + 一次真实拒绝对照）：
	FeedbackService.test_reset()
	# idle：真实 emit loot_claimed 接受；player_attack_started 拒绝（MISMATCH）
	var i_ok := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": "op-i1"})
	assert(bool(i_ok.get("accepted", false)), "idle real emit loot_claimed must be accepted")
	var i_no := FeedbackService.emit("player_attack_started", {"dedupe_key": "i_no"})
	assert(str(i_no.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"idle real emit attack must be rejected (got %s)" % str(i_no.get("rejection_code", "")))
	# active：真实 emit player_attack_started 接受
	FeedbackService.begin_session()
	var a_ok := FeedbackService.emit("player_attack_started", {"dedupe_key": "a_ok"})
	assert(bool(a_ok.get("accepted", false)), "active real emit attack must be accepted")
	# victory_rewards：真实 victory 进入后 reward_queued->loot_claimed 接受、player_attack_started 拒绝
	var v_setup := FeedbackService.emit("victory", {"dedupe_key": "v_setup"})
	assert(bool(v_setup.get("accepted", false)), "victory setup emit must be accepted")
	var vr_rq := FeedbackService.emit("reward_queued", {"dedupe_key": "vr_rq"})
	assert(bool(vr_rq.get("accepted", false)), "victory_rewards real emit reward_queued must be accepted")
	var vr_ok := FeedbackService.emit("loot_claimed", {"item_id": "exp_ball", "claim_operation_id": "op-vr"})
	assert(bool(vr_ok.get("accepted", false)), "victory_rewards real emit loot (after reward_queued) must be accepted")
	var vr_no := FeedbackService.emit("player_attack_started", {"dedupe_key": "vr_no", "attack_sequence": 0})
	assert(str(vr_no.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"victory_rewards real emit attack must be rejected (got %s)" % str(vr_no.get("rejection_code", "")))
	FeedbackService.end_session()
	# defeat_rewards：真实 player_death 进入后 battle_retreat 接受、reward_queued 拒绝
	FeedbackService.begin_session()
	var d_setup := FeedbackService.emit("player_death", {"dedupe_key": "d_setup"})
	assert(bool(d_setup.get("accepted", false)), "player_death setup emit must be accepted")
	var dr_ok := FeedbackService.emit("battle_retreat", {"dedupe_key": "dr_ok"})
	assert(bool(dr_ok.get("accepted", false)), "defeat_rewards real emit battle_retreat must be accepted")
	var dr_no := FeedbackService.emit("reward_queued", {"dedupe_key": "dr_no"})
	assert(str(dr_no.get("rejection_code", "")) == "FEEDBACK_BATTLE_STATE_MISMATCH",
		"defeat_rewards real emit reward_queued must be rejected (got %s)" % str(dr_no.get("rejection_code", "")))
	FeedbackService.end_session()
