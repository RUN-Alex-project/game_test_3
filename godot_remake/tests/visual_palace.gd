extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.current_day = 7
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._travel_to("palace")
	await get_tree().process_frame
	main._open_actor_dialogue("marshal")
