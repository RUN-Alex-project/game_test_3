extends Node

var main: Node = null

func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.level = 1
	GameState.nobility_merit = 0          # 爵位 0 -> 后花园保持锁定，本测试的阻挡样本
	var gold_before := GameState.gold
	var stones_before := GameState.magic_stones
	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 用户 2026-08-21 取消地图等级门槛后，1 级新档在卡萨诺城的四个出口全部开放。
	# 这条断言同时防止等级死锁复发（原先四个出口分别要 10/20/70 级，而经验只能来自战斗）。
	for dir_key in ["right", "top", "left", "bottom"]:
		var exit_btn: Button = main.direction_buttons[dir_key]
		assert(exit_btn.visible, "cassano exit %s not visible" % dir_key)
		assert(not exit_btn.locked and not exit_btn.disabled,
			"level-1 cassano exit %s must be open after map level gates were removed" % dir_key)
	print("OPEN cassano exits at level 1: right/top/left/bottom all unlocked")

	# Palace (top) -> allowed
	var top: Button = main.direction_buttons["top"]
	var map_before := GameState.current_map_id
	top.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "palace", "allowed palace exit did not switch map: %s" % GameState.current_map_id)
	assert(GameState.current_map_id != map_before, "map did not change after allowed exit click")
	print("ENTER palace map=%s" % GameState.current_map_id)

	# 后花园（palace 的 right 出口）要求爵位达到勋爵以上 -> locked 但仍可点击并给出原因。
	# 等级门槛取消后，这里是验证「阻挡出口不 disabled」的样本。
	var garden: Button = main.direction_buttons["right"]
	assert(garden.target_map_id == "palace_garden", "palace right exit is not the garden: %s" % garden.target_map_id)
	assert(garden.visible, "garden exit not visible")
	assert(garden.locked and not garden.disabled, "garden exit must be locked-but-clickable without a noble rank")
	main.status_label.text = ""
	garden.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "palace", "blocked garden exit changed current_map_id: %s" % GameState.current_map_id)
	assert(GameState.gold == gold_before, "blocked exit changed gold")
	assert(GameState.magic_stones == stones_before, "blocked exit changed magic_stones")
	var reason: String = main.status_label.text
	assert("爵位" in reason, "blocked garden exit did not show the nobility reason; status=%s" % reason)
	print("BLOCK garden reason=%s map=%s gold=%d stones=%d" % [reason, GameState.current_map_id, GameState.gold, GameState.magic_stones])

	# Palace -> return to cassano_city (bottom) allowed
	var bottom: Button = main.direction_buttons["bottom"]
	assert(bottom.visible and not bottom.locked, "palace->cassano return exit must be allowed")
	bottom.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "cassano_city", "palace return did not switch back: %s" % GameState.current_map_id)
	print("RETURN cassano map=%s" % GameState.current_map_id)

	print("PASS map exit blocking: level gates removed (all cassano exits open), remaining gates stay clickable+show reason+state unchanged; allowed exits switch map")
	get_tree().quit(0)
