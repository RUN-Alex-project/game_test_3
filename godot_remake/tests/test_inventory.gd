extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var state := root.get_node_or_null("GameState")
	if state == null:
		_fail("GameState autoload is missing")
		return

	var original_non_empty := _non_empty_count(state.inventory)
	var source_item: Dictionary = state.inventory[0].duplicate(true)
	if not state.move_item(0, 3):
		_fail("valid move was rejected")
		return
	if not state.inventory[0].is_empty() or state.inventory[3] != source_item:
		_fail("valid move did not commit atomically")
		return

	var snapshot: Array = state.inventory.duplicate(true)
	if state.move_item(99, 2):
		_fail("invalid source was accepted")
		return
	if state.inventory != snapshot:
		_fail("invalid move changed the inventory")
		return
	if _non_empty_count(state.inventory) != original_non_empty:
		_fail("an item disappeared during move tests")
		return

	state.gold = 99_999_999_999
	state.magic_stones = 99_999_999_999
	if not state.save_game():
		_fail("save failed")
		return
	state.gold = 1
	state.magic_stones = 1
	state.inventory[3] = {}
	if not state.load_game():
		_fail("load failed")
		return
	if state.gold != 99_999_999_999 or state.magic_stones != 99_999_999_999:
		_fail("64-bit currency did not survive save/load")
		return
	if state.inventory[3] != source_item:
		_fail("inventory did not survive save/load")
		return

	print("PASS inventory atomic move, invalid-drop safety, and save/load")
	quit(0)


func _non_empty_count(items: Array) -> int:
	var count := 0
	for item: Dictionary in items:
		if not item.is_empty():
			count += 1
	return count


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
