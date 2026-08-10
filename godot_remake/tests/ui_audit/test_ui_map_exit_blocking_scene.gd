extends Node

var main: Node = null

func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.level = 1
	var gold_before := GameState.gold
	var stones_before := GameState.magic_stones
	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# Avit (right) requires level 70 -> locked but clickable
	var right: Button = main.direction_buttons["right"]
	assert(right.visible, "Avit exit not visible")
	assert(right.locked and not right.disabled, "Avit exit must be locked-but-clickable at level 1")
	main.status_label.text = ""
	right.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "cassano_city", "blocked Avit exit changed current_map_id: %s" % GameState.current_map_id)
	assert(GameState.gold == gold_before, "blocked exit changed gold")
	assert(GameState.magic_stones == stones_before, "blocked exit changed magic_stones")
	var reason: String = main.status_label.text
	assert("70" in reason, "blocked Avit exit did not show required level 70; status=%s" % reason)
	print("BLOCK avit reason=%s map=%s gold=%d stones=%d" % [reason, GameState.current_map_id, GameState.gold, GameState.magic_stones])

	# Palace (top) requires level 1 -> allowed
	var top: Button = main.direction_buttons["top"]
	assert(top.visible and not top.locked, "palace exit must be unlocked at level 1")
	var map_before := GameState.current_map_id
	top.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "palace", "allowed palace exit did not switch map: %s" % GameState.current_map_id)
	assert(GameState.current_map_id != map_before, "map did not change after allowed exit click")
	print("ENTER palace map=%s" % GameState.current_map_id)

	# Palace -> return to cassano_city (bottom) allowed
	var bottom: Button = main.direction_buttons["bottom"]
	assert(bottom.visible and not bottom.locked, "palace->cassano return exit must be allowed")
	bottom.emit_signal("pressed")
	await get_tree().process_frame
	assert(GameState.current_map_id == "cassano_city", "palace return did not switch back: %s" % GameState.current_map_id)
	print("RETURN cassano map=%s" % GameState.current_map_id)

	print("PASS map exit blocking: locked exits clickable+show reason+state unchanged; allowed exits switch map")
	get_tree().quit(0)
