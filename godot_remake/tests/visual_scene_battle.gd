extends Node


func _ready() -> void:
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	GameState.player_current_hp = 321
	GameState.pets[0].current_hp = 12
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._engage_world_monster("battle:spider")
