extends Node

# v1.33 专项：活动主场景已退役旧 MapPanel/BattlePanel 运行时依赖。
# 1. 场景树无 map_panel.gd / battle_panel.gd 节点。
# 2. main_original.gd 不再 preload 两旧脚本，也无 var map_panel / var battle_panel。
# 3. 有效怪物 _start_battle() 由 SceneBattleController 接管并锁定目标。
# 4. 不存在怪物 _start_battle() 只更新状态提示，不创建面板，不替换已锁定目标。
# 5. 场景边缘出口仍由 NativeExitButton 完成地图切换。

const MAIN_SCRIPT := "res://scripts/main_original.gd"


func _has_legacy_panel_node(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and s is GDScript:
			var p: String = s.resource_path
			if p.ends_with("map_panel.gd") or p.ends_with("battle_panel.gd"):
				return true
	return false


func _ready() -> void:
	# --- 断言 1 / 3 / 4：dream_swamp 主场景 ---
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	# 1. 活动场景树不含旧地图/战斗面板节点
	assert(not _has_legacy_panel_node(main), "legacy map/battle panel node still exists in the active scene tree")

	# 3. 有效怪物 _start_battle -> SceneBattleController 接管并锁定目标
	main._start_battle("spider")
	assert(main.scene_battle_controller.session != null, "_start_battle did not engage the scene battle controller")
	assert(main.scene_battle_controller.active_monster_id == "spider", "_start_battle did not lock the native scene target")

	# 4. 不存在怪物 _start_battle -> 只更新状态提示，不创建面板，不替换已锁定目标
	main._start_battle("nonexistent_monster")
	assert("当前场景中找不到该怪物" in main.status_label.text, "missing-monster _start_battle did not update the status hint")
	assert(not _has_legacy_panel_node(main), "missing-monster _start_battle created a legacy panel node")
	assert(main.scene_battle_controller.active_monster_id == "spider", "missing-monster _start_battle replaced the locked target")

	# --- 断言 2：源码文本不再 preload / 声明旧成员 ---
	var src := FileAccess.open(MAIN_SCRIPT, FileAccess.READ)
	assert(src != null, "could not open main_original.gd")
	var text := src.get_as_text()
	src.close()
	assert(not 'preload("res://scripts/map_panel.gd")' in text, "main_original.gd still preloads map_panel.gd")
	assert(not 'preload("res://scripts/battle_panel.gd")' in text, "main_original.gd still preloads battle_panel.gd")
	assert(not "var map_panel" in text, "main_original.gd still declares var map_panel")
	assert(not "var battle_panel" in text, "main_original.gd still declares var battle_panel")

	# --- 断言 5：场景边缘出口仍由 NativeExitButton 完成地图切换 ---
	GameState.current_map_id = "cassano_city"
	var main2 := preload("res://scenes/main.tscn").instantiate()
	add_child(main2)
	await get_tree().process_frame
	var left: Button = main2.direction_buttons["left"]
	assert(left.target_map_id == "thunder_continent", "cassano left exit does not target Thunder Continent")
	left.emit_signal("pressed")
	assert(GameState.current_map_id == "thunder_continent", "NativeExitButton did not complete the map travel")
	assert(not _has_legacy_panel_node(main2), "map travel reintroduced a legacy panel node")

	# P2 拒签整改：quit 前确定性等待战斗/反馈协程自然完成（流程上限 2.2s）再释放场景
	await get_tree().create_timer(2.5).timeout
	if main.is_inside_tree():
		remove_child(main)
	main.queue_free()
	remove_child(main2)
	main2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS no legacy map/battle panels in active scene; _start_battle routes to SceneBattleController; NativeExitButton still handles travel")
	get_tree().quit(0)
