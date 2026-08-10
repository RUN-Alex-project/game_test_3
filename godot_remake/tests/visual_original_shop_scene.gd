extends Node


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._open_actor_dialogue("grocery")
	await get_tree().process_frame
	main.dialogue_panel._choose("gold_sell")
