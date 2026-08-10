extends Node


func _ready() -> void:
	GameState.current_map_id = "avit_island"
	GameState.level = 80
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._engage_world_monster("battle:spider_queen")
