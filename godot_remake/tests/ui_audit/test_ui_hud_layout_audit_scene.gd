extends Node

const SIZES := [Vector2i(700, 550), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const SIZE_NAMES := ["700x550", "1280x720", "1920x1080", "2560x1440(maximized-proxy)"]

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player_card: Dictionary = main.player_status_card
	var pet_card_1: Dictionary = main.pet_status_cards[0]
	var pet_card_2: Dictionary = main.pet_status_cards[1]
	var location_panel: Control = main.location_label.get_parent()

	var out_of_bounds := 0
	var overlap := 0
	var child_exceed := 0

	for i in SIZES.size():
		get_window().size = SIZES[i]
		await get_tree().process_frame
		await get_tree().process_frame
		var vp: Rect2 = get_viewport().get_visible_rect()
		var win: Vector2i = get_window().size
		print("=== HUD size=%s window=%s viewport=%s ===" % [SIZE_NAMES[i], str(win), str(vp)])

		var panels: Array = [player_card.panel, pet_card_1.panel, pet_card_2.panel, location_panel]
		var names: Array = ["player_card", "pet_card_1", "pet_card_2", "map_card"]
		var rects: Array = []
		for p in panels:
			rects.append(p.get_global_rect())
		for j in panels.size():
			var r: Rect2 = rects[j]
			print("%s rect = %s" % [names[j], str(r)])
			if r.position.y < -0.01 or r.position.x < -0.01 or r.end.x > vp.size.x + 0.5 or r.end.y > vp.size.y + 0.5:
				out_of_bounds += 1
				push_error("OUT_OF_BOUNDS %s %s vp=%s" % [names[j], str(r), str(vp)])
		for a in range(panels.size()):
			for b in range(a + 1, panels.size()):
				if rects[a].intersects(rects[b]):
					overlap += 1
					push_error("OVERLAP %s %s" % [names[a], names[b]])

		var groups: Array = [
			[player_card.title, player_card.portrait, player_card.hp_bar, player_card.stamina_bar, player_card.secondary_bar, player_card.footer],
			[pet_card_1.title, pet_card_1.portrait, pet_card_1.hp_bar, pet_card_1.secondary_bar, pet_card_1.footer, pet_card_1.recall_button, pet_card_1.combine_button],
			[pet_card_2.title, pet_card_2.portrait, pet_card_2.hp_bar, pet_card_2.secondary_bar, pet_card_2.footer, pet_card_2.recall_button, pet_card_2.combine_button],
			[],
		]
		for g in groups.size():
			var pr: Rect2 = rects[g].grow(0.5)
			for child in groups[g]:
				var cr: Rect2 = child.get_global_rect()
				if not pr.encloses(cr):
					child_exceed += 1
					push_error("CHILD_EXCEED %s child=%s rect=%s parent=%s" % [names[g], child.name, str(cr), str(rects[g])])

		if i == 0:
			print("player title rect = %s" % str(player_card.title.get_global_rect()))
			print("player portrait rect = %s" % str(player_card.portrait.get_global_rect()))
			print("player hp_bar rect = %s" % str(player_card.hp_bar.get_global_rect()))
			print("player stamina_bar rect = %s" % str(player_card.stamina_bar.get_global_rect()))
			print("player exp_bar rect = %s" % str(player_card.secondary_bar.get_global_rect()))
			print("player footer rect = %s" % str(player_card.footer.get_global_rect()))
			print("pet1 recall_button rect = %s" % str(pet_card_1.recall_button.get_global_rect()))
			print("pet1 combine_button rect = %s" % str(pet_card_1.combine_button.get_global_rect()))

	print("HUD out_of_bounds = %d" % out_of_bounds)
	print("HUD overlap = %d" % overlap)
	print("HUD child_exceed = %d" % child_exceed)
	assert(out_of_bounds == 0, "HUD node outside viewport")
	assert(overlap == 0, "HUD cards overlap")
	assert(child_exceed == 0, "HUD child exceeds parent")
	# P2: top safe margin standard = 4px. Every top HUD card sits >= 4px below
	# the viewport top so the panel border, title glyphs and portrait are never
	# flush with the window edge (the user's "top UI cut off" complaint).
	const TOP_SAFE_MARGIN := 4.0
	assert(player_card.panel.global_position.y >= TOP_SAFE_MARGIN, "player card above safe margin: %s" % str(player_card.panel.global_position.y))
	assert(pet_card_1.panel.global_position.y >= TOP_SAFE_MARGIN, "pet card 1 above safe margin")
	assert(pet_card_2.panel.global_position.y >= TOP_SAFE_MARGIN, "pet card 2 above safe margin")
	assert(location_panel.global_position.y >= TOP_SAFE_MARGIN, "map card above safe margin")
	# Topmost content (title text + portrait) must also respect the margin.
	assert(player_card.title.get_global_rect().position.y >= TOP_SAFE_MARGIN, "player title glyph area above safe margin: %s" % str(player_card.title.get_global_rect()))
	assert(player_card.portrait.get_global_rect().position.y >= TOP_SAFE_MARGIN, "player portrait above safe margin")
	# Card panels must NOT clip their children (so meters/labels/footer are not cut).
	for p in [player_card.panel, pet_card_1.panel, pet_card_2.panel, location_panel]:
		assert(p.clip_contents == false, "HUD card panel clips children: %s" % str(p))
	# Font drawing proof: the title glyph height must fit within the title Label
	# rect so the text is not vertically clipped.
	var title_font_h: int = int(ThemeDB.fallback_font.get_height(14))
	var title_rect_h: float = player_card.title.size.y
	assert(float(title_font_h) <= title_rect_h + 0.01, "title font height %d exceeds label rect %.1f (text would clip)" % [title_font_h, title_rect_h])
	# 建议3: pet card titles (font 14), pet portraits, pet button text (font 10)
	var pet_font_h: int = int(ThemeDB.fallback_font.get_height(14))
	var btn_font_h: int = int(ThemeDB.fallback_font.get_height(10))
	var pet_cards: Array = [pet_card_1, pet_card_2]
	for i in pet_cards.size():
		var pc: Dictionary = pet_cards[i]
		assert(float(pet_font_h) <= pc.title.size.y + 0.01, "pet card %d title font %d exceeds rect %.1f" % [i, pet_font_h, pc.title.size.y])
		assert(pc.portrait.get_global_rect().position.y >= TOP_SAFE_MARGIN, "pet card %d portrait above safe margin" % i)
		assert(float(btn_font_h) <= pc.recall_button.size.y + 0.01, "pet card %d recall font %d exceeds rect %.1f" % [i, btn_font_h, pc.recall_button.size.y])
		assert(float(btn_font_h) <= pc.combine_button.size.y + 0.01, "pet card %d combine font %d exceeds rect %.1f" % [i, btn_font_h, pc.combine_button.size.y])
		print("FONT pet%d title_h=%d rect=%.1f portrait_y=%.1f btn_h=%d recall_rect=%.1f combine_rect=%.1f" % [i, pet_font_h, pc.title.size.y, pc.portrait.get_global_rect().position.y, btn_font_h, pc.recall_button.size.y, pc.combine_button.size.y])
	# 建议3: map card title (当前地图, font 13) + map text area (location_label, font 13)
	var map_title: Label = null
	for child in location_panel.get_children():
		if child is Label and child != main.location_label:
			map_title = child
			break
	assert(map_title != null, "map card title label not found")
	var map_font_h: int = int(ThemeDB.fallback_font.get_height(13))
	assert(float(map_font_h) <= map_title.size.y + 0.01, "map title font %d exceeds rect %.1f" % [map_font_h, map_title.size.y])
	assert(float(map_font_h) <= main.location_label.size.y + 0.01, "map text font %d exceeds rect %.1f" % [map_font_h, main.location_label.size.y])
	assert(map_title.get_global_rect().position.y >= TOP_SAFE_MARGIN, "map title above safe margin")
	print("FONT map_title_h=%d rect=%.1f map_text_h=%d rect=%.1f title_y=%.1f" % [map_font_h, map_title.size.y, map_font_h, main.location_label.size.y, map_title.get_global_rect().position.y])
	print("HUD top_safe_margin=%d clip_contents=false title_font_h=%d rect_h=%.1f" % [int(TOP_SAFE_MARGIN), title_font_h, title_rect_h])
	print("PASS HUD layout audit: 4 sizes, in-viewport, no overlap, children within parents, 4px safe margin, no clip, player/pet/map font fits")
	get_tree().quit(0)
