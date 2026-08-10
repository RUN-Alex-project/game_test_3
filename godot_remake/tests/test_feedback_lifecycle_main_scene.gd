extends Node
var _reenter_count: int = 0
var _reenter_ok: bool = true
var _reenter_defeat: bool = false
## v1.37 整改03：主场景真实集成——战斗反馈生命周期（end_session 幂等、状态矩阵）。
## 场景：普通胜利、玩家死亡回城、战斗中切图/取消、battle_finished 后重建。
## 断言：session 只结束一次（end_session 幂等）、最终 battle_state=idle、无新 session 被旧流程误结束。


func _left_click(main: Control, action_id: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, action_id)


func _wait_until(pred: Callable, timeout := 8.0) -> bool:
	var elapsed := 0.0
	while not pred.call():
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
		if elapsed >= timeout:
			return false
	return true


func _ready() -> void:
	GameState.save_path = "user://v137_lifecycle_test_save.json"
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.player_current_hp = 550
	GameState.player_current_stamina = 110
	GameState.learned_skills = {}
	GameState.equipment = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
	GameState.loot_queue = []
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})
	for pet in GameState.pets:
		pet.current_hp = int(GameState.pet_service.get_stats(pet).max_hp)
	FeedbackService.test_reset()
	AudioService.test_reset_play_history()

	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ctrl: Control = main.scene_battle_controller
	var monster_actor_fixture: TextureRect = main.interactive_actors["battle:spider"]

	# 场景 1：普通胜利——session 只结束一次（end_session 幂等），最终 idle
	assert(FeedbackService.battle_state == "idle", "initial state must be idle")
	_left_click(main, "battle:spider")
	assert(await _wait_until(func() -> bool: return ctrl.session != null), "battle must start")
	var sid_1 := FeedbackService.session_id
	assert(FeedbackService.battle_state == "active", "engage must enter active")
	await _wait_until(func() -> bool: return not ctrl.busy)
	ctrl.session.monster_hp = 1
	ctrl._attack()
	assert(await _wait_until(func() -> bool: return ctrl.session == null, 10.0), "victory must close battle")
	await get_tree().create_timer(2.4).timeout
	assert(FeedbackService.battle_state == "idle", "victory must end session to idle")
	# end_session 幂等：再次调用不递增（旧流程可能重复 end）
	FeedbackService.end_session(sid_1)
	assert(FeedbackService.session_id == sid_1 + 1, "idempotent end_session must not increment twice")

	# 场景 2：玩家死亡回城——player_death 事件一次、idle
	GameState.pets[0].current_hp = 0
	GameState.pets[1].current_hp = 0
	GameState.player_current_hp = 1
	_left_click(main, "battle:spider")
	assert(await _wait_until(func() -> bool: return ctrl.session == null, 10.0), "defeat must close battle")
	assert(FeedbackService.test_event_count("player_death") == 1, "player_death must fire once")
	assert(FeedbackService.battle_state == "idle", "defeat must end session to idle")

	# 场景 3：战斗中切图/取消——旧 session 失效、idle
	GameState.pets[0].current_hp = int(GameState.pet_service.get_stats(GameState.pets[0]).max_hp)
	GameState.pets[1].current_hp = int(GameState.pet_service.get_stats(GameState.pets[1]).max_hp)
	GameState.player_current_hp = 550
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	_left_click(main, "battle:spider")
	assert(await _wait_until(func() -> bool: return ctrl.session != null), "battle 3 must start")
	var sid_3 := FeedbackService.session_id
	ctrl.cancel_battle()
	assert(FeedbackService.battle_state == "idle", "cancel must end session to idle")
	FeedbackService.end_session(sid_3)
	assert(FeedbackService.session_id == sid_3 + 1, "cancel + idempotent end must increment once")

	# 场景 4：battle_finished 监听器重建——新 session 不被旧 expected 误结束
	FeedbackService.test_reset()
	FeedbackService.begin_session()
	var sid_new := FeedbackService.session_id
	var old_sid := sid_new - 1
	FeedbackService.end_session(old_sid)  # 旧 expected：不结束新 session
	assert(FeedbackService.session_id == sid_new and FeedbackService.battle_state == "active",
		"stale expected_session_id must not end the new session")
	FeedbackService.end_session(sid_new)
	assert(FeedbackService.battle_state == "idle", "matching end must reach idle")

	await get_tree().process_frame
	await get_tree().process_frame

	# 场景 5：battle_finished 同步重入——监听器内立即开始新战斗；旧流程不得结束新 session
	FeedbackService.test_reset()
	_reenter_count = 0
	_reenter_ok = true
	var scene5_handler := func(_monster_id: String, _victory: bool) -> void:
		_reenter_count += 1
		if _reenter_count > 1:
			return
		# 监听器内立即开始新战斗（同步重入）——重新获取 actor（lambda 不捕获易释放对象）
		if main.interactive_actors.has("battle:spider"):
			var actor: TextureRect = main.interactive_actors["battle:spider"]
			if actor == null or not is_instance_valid(actor):
				_reenter_ok = false
				return
			_reenter_ok = ctrl.engage("spider", actor)
		else:
			_reenter_ok = false
	ctrl.battle_finished.connect(scene5_handler)
	# 战斗 1：胜利（触发监听器 → 新战斗）
	GameState.player_current_hp = 550
	GameState.pets[0].current_hp = int(GameState.pet_service.get_stats(GameState.pets[0]).max_hp)
	GameState.pets[1].current_hp = int(GameState.pet_service.get_stats(GameState.pets[1]).max_hp)
	_left_click(main, "battle:spider")
	assert(await _wait_until(func() -> bool: return ctrl.session != null), "reenter battle 1 must start")
	await _wait_until(func() -> bool: return not ctrl.busy)
	ctrl.session.monster_hp = 1
	ctrl._attack()
	# 监听器内新战斗应启动（reenter_count >= 1 且 reenter_ok）——等待异步胜利链完成
	assert(await _wait_until(func() -> bool: return _reenter_count >= 1), "battle_finished listener must fire")
	assert(_reenter_ok, "reenter engage must succeed")
	# 旧 _finish_victory 返回后：新 session 仍 active、新 Controller session 未被清空
	await get_tree().create_timer(0.2).timeout
	assert(ctrl.session != null, "reenter must not clear the new controller session (after 0.2s)")
	assert(FeedbackService.battle_state == "active", "reenter must leave the new session active (after 0.2s)")
	var new_sid := FeedbackService.session_id
	# 整改05：旧胜利流程完整经过 2.2s 恢复段后再断言——旧流程结束时只结束其保存的旧 ID，
	# 新战斗的 session/Controller session/目标怪物/feedback state 必须仍属于新战斗。
	await get_tree().create_timer(2.4).timeout
	assert(FeedbackService.session_id == new_sid,
		"old victory 2.2s recovery must not end the new session (sid %d -> %d)" % [new_sid, FeedbackService.session_id])
	assert(FeedbackService.battle_state == "active", "new session must stay active after old 2.2s recovery")
	assert(ctrl.session != null, "new controller session must survive old 2.2s recovery")
	assert(ctrl.active_monster_id == "spider", "new battle target must still be spider (got %s)" % str(ctrl.active_monster_id))
	FeedbackService.end_session(new_sid)
	assert(FeedbackService.battle_state == "idle", "matching end must reach idle")
	ctrl.cancel_battle()

	# 场景 6（整改05）：battle_finished 失败同步重入——defeat 监听器内立即开始新战斗；
	# 旧失败流程（_finish_defeat）结束时只结束其保存的旧 ID，新 session 不得被误结束。
	# 先断开场景 5 监听器（避免其计数共享/误触发重入干扰本场景）。
	if ctrl.battle_finished.is_connected(scene5_handler):
		ctrl.battle_finished.disconnect(scene5_handler)
	FeedbackService.test_reset()
	_reenter_count = 0
	_reenter_ok = true
	ctrl.battle_finished.connect(func(_monster_id: String, victory: bool) -> void:
		_reenter_count += 1
		
		if _reenter_count > 1:
			return
		if victory:
			return  # 场景 6 只测失败重入
		_reenter_defeat = true
		# 监听器内立即开始新战斗（同步重入）——玩家血量已随 defeat 写回 0，
		# 先恢复（新战斗的前提），再重新获取 actor（lambda 不捕获易释放对象）
		GameState.player_current_hp = 550
		# main_original 的失败回城处理（_on_scene_battle_finished：失败 -> 卡萨诺城 + _apply_current_map）
		# 在本监听器之前已同步执行——切回战斗地图重建 actors（_apply_current_map 同步），
		# 仍在同一次 battle_finished 分发内立即开始新战斗（同步重入）。
		if not main.interactive_actors.has("battle:spider"):
			GameState.current_map_id = "dream_swamp"
			main._apply_current_map()
		if not main.interactive_actors.has("battle:spider"):
			_reenter_ok = false
			return
		var actor: TextureRect = main.interactive_actors["battle:spider"]
		if actor == null or not is_instance_valid(actor):
			_reenter_ok = false
			return
		var engage_result: Variant = ctrl.engage("spider", actor)
		_reenter_ok = bool(engage_result)
	)
	# 战斗 A：失败（玩家死亡——engage 自动首回合内玩家被打死 -> _finish_defeat -> battle_finished(false)）
	GameState.player_current_hp = 1
	GameState.pets[0].current_hp = 0
	GameState.pets[1].current_hp = 0
	_left_click(main, "battle:spider")
	assert(await _wait_until(func() -> bool: return ctrl.session != null), "defeat reenter battle A must start")
	# engage 自动首回合结束战斗（玩家死亡）——等待 battle_finished 监听器触发
	# 监听器内新战斗应启动（reenter_count >= 1 且 reenter_defeat）
	assert(await _wait_until(func() -> bool: return _reenter_count >= 1), "defeat battle_finished listener must fire")
	assert(_reenter_defeat, "listener must observe defeat (victory=false)")
	assert(_reenter_ok, "defeat reenter engage must succeed")
	# 旧 _finish_defeat 返回后：新 session 仍 active、新 Controller session 未被清空
	await get_tree().create_timer(0.3).timeout
	assert(ctrl.session != null, "defeat reenter must not clear the new controller session")
	assert(FeedbackService.battle_state == "active", "defeat reenter must leave the new session active")
	var new_sid6 := FeedbackService.session_id
	FeedbackService.end_session(new_sid6)
	assert(FeedbackService.battle_state == "idle", "defeat reenter matching end must reach idle")
	ctrl.cancel_battle()
	# P2 拒签整改：退出前恢复帧，让被取消/挂起的协程状态完成（消除 GDScriptFunctionState 泄漏）
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS v1.37 整改05 main-scene feedback lifecycle: victory 2.2s-recovery reenter, defeat reenter, idempotent end_session, stale expected protection")
	get_tree().quit(0)
