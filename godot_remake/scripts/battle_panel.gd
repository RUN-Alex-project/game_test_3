extends PanelContainer

signal message_changed(text: String)

const BattleSession = preload("res://scripts/battle_session.gd")

var session
var monster_name: Label
var hp_label: Label
var log_label: Label
var attack_button: Button
var loot_box: VBoxContainer
var skill_box: HBoxContainer
var player_actor: TextureRect
var monster_actor: TextureRect
var attack_sequence: int = 0
var monster_idle_tween: Tween


func _ready() -> void:
	position = Vector2(120, 95)
	size = Vector2(460, 407)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("4c4c4c")
	style.border_color = Color("202020")
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	monster_name = Label.new()
	monster_name.add_theme_font_size_override("font_size", 22)
	monster_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(monster_name)
	var close := Button.new()
	close.text = "撤退"
	close.pressed.connect(_retreat)
	header.add_child(close)
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 18)
	root.add_child(hp_label)
	var battle_stage := HBoxContainer.new()
	battle_stage.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_stage.custom_minimum_size = Vector2(0, 88)
	root.add_child(battle_stage)
	player_actor = _make_actor_view(Vector2(125, 88))
	battle_stage.add_child(player_actor)
	var versus := Label.new()
	versus.text = "⚔"
	versus.custom_minimum_size = Vector2(48, 0)
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	versus.add_theme_font_size_override("font_size", 28)
	versus.add_theme_color_override("font_color", Color("ffc43d"))
	battle_stage.add_child(versus)
	monster_actor = _make_actor_view(Vector2(125, 88))
	battle_stage.add_child(monster_actor)
	log_label = Label.new()
	log_label.custom_minimum_size = Vector2(0, 58)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)
	attack_button = Button.new()
	attack_button.text = "普通攻击"
	attack_button.pressed.connect(_attack)
	root.add_child(attack_button)
	skill_box = HBoxContainer.new()
	root.add_child(skill_box)
	var loot_title := Label.new()
	loot_title.text = "战利品"
	root.add_child(loot_title)
	loot_box = VBoxContainer.new()
	root.add_child(loot_box)


func start_battle(monster_id: String) -> void:
	var player_stats := GameState.get_player_stats()
	if int(player_stats.get("current_hp", 0)) <= 0:
		message_changed.emit("人物没有生命值，请先使用果子恢复后再战斗。")
		return
	session = BattleSession.new(monster_id, player_stats)
	attack_sequence += 1
	player_actor.texture = load("res://assets/extracted/images/image_0447.png")
	player_actor.modulate = Color.WHITE
	monster_actor.texture = load(_monster_texture_path(monster_id))
	monster_actor.modulate = Color.WHITE
	_start_monster_idle()
	_clear_loot_buttons()
	monster_name.text = str(session.monster.get("name", monster_id))
	log_label.text = "战斗开始。"
	attack_button.disabled = session.finished
	_build_skill_buttons()
	_refresh_hp()
	_build_loot_buttons()
	show()


func _attack(skill_id: String = "") -> void:
	if session == null or session.finished:
		return
	var skill_multiplier := GameState.skill_service.active_damage_multiplier(GameState.learned_skills, skill_id)
	AudioService.play("attack")
	_play_attack_animation()
	var result: Dictionary = session.perform_turn(1.0, 1.0, -1.0, skill_multiplier)
	GameState.commit_battle_health(int(session.player_hp), session.pet_states)
	var pet_penalty := GameState.apply_pet_death_penalty(result.get("pet_deaths", []))
	if bool(pet_penalty.get("forced_retreat", false)):
		session.force_defeat("pet_luck_exhausted")
	var target_text := "人物受到%d伤害" % int(result.get("player_damage_taken", 0))
	if str(result.get("monster_target", "")) == "pet":
		target_text = "%s受到%d伤害" % [str(result.get("target_pet_name", "幻兽")), int(result.get("pet_damage_taken", 0))]
	elif bool(result.get("dodged", false)):
		target_text = "人物闪避"
	log_label.text = "第%d回合：你造成%d伤害，幻兽造成%d伤害，%s。" % [
		int(result.get("turn", 0)),
		int(result.get("player_damage", 0)),
		int(result.get("pet_damage", 0)),
		target_text,
	]
	if not skill_id.is_empty():
		log_label.text = "施放%s（%.0f%%）。" % [GameState.skill_service.skills[skill_id].name, skill_multiplier * 100.0] + log_label.text
	if not result.get("pet_deaths", []).is_empty():
		log_label.text += " 幻兽死亡，幸运值-%d。" % int(pet_penalty.get("luck_lost", 0))
	_refresh_hp()
	if not session.finished:
		return
	attack_button.disabled = true
	if session.victory:
		var rewards: Dictionary = session.victory_payload()
		GameState.apply_victory_rewards(rewards)
		GameState.queue_loot(rewards.get("drops", []))
		log_label.text += "\n胜利！经验+%d，军功+%d，功勋+%d，魔石+%d。" % [int(rewards.get("experience", 0)), int(rewards.get("military_merit", 0)), int(rewards.get("nobility_merit", 0)), int(rewards.get("magic_stones", 0))]
		_build_loot_buttons()
		message_changed.emit("战斗胜利")
		AudioService.play("victory")
		var defeat_tween := monster_actor.create_tween()
		defeat_tween.tween_property(monster_actor, "modulate:a", 0.0, 0.3)
	else:
		if str(session.defeat_reason) == "player_death":
			var penalty := GameState.apply_player_defeat_penalty()
			log_label.text += "\n战斗失败：幸运值-%d，当前等级经验-%d，人物生命归零。" % [int(penalty.luck_lost), int(penalty.experience_lost)]
		else:
			log_label.text += "\n幸运值已经耗尽，战斗自动结束。"
		message_changed.emit("战斗失败")
		AudioService.play("death")
		var defeat_tween := player_actor.create_tween()
		defeat_tween.tween_property(player_actor, "modulate:a", 0.0, 0.3)


func _make_actor_view(minimum_size: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.custom_minimum_size = minimum_size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


func _monster_texture_path(monster_id: String) -> String:
	if monster_id == "spider":
		return "res://assets/extracted/images/image_0051.png"
	if monster_id == "spider_queen":
		return "res://assets/extracted/images/image_0053.png"
	if monster_id.begins_with("snow_"):
		return "res://assets/extracted/images/image_0127.png"
	if monster_id.begins_with("pk_champion"):
		return "res://assets/extracted/images/image_0449.png"
	return "res://assets/extracted/images/image_0049.png"


func _start_monster_idle() -> void:
	if monster_idle_tween != null and monster_idle_tween.is_valid():
		monster_idle_tween.kill()
	monster_actor.pivot_offset = monster_actor.size * 0.5
	monster_idle_tween = monster_actor.create_tween().set_loops()
	monster_idle_tween.tween_property(monster_actor, "scale", Vector2(1.035, 0.97), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	monster_idle_tween.tween_property(monster_actor, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_attack_animation() -> void:
	attack_sequence += 1
	var sequence := attack_sequence
	var frame_paths := [
		"res://assets/extracted/images/image_0503.png",
		"res://assets/extracted/images/image_0505.png",
		"res://assets/extracted/images/image_0507.png",
		"res://assets/extracted/images/image_0509.png",
	]
	player_actor.texture = load(frame_paths[0])
	var attack_tween := player_actor.create_tween()
	for frame_index in range(1, frame_paths.size()):
		attack_tween.tween_interval(0.065)
		attack_tween.tween_callback(_set_attack_frame.bind(frame_paths[frame_index], sequence))
	attack_tween.tween_interval(0.065)
	attack_tween.tween_callback(_set_attack_frame.bind("res://assets/extracted/images/image_0447.png", sequence))
	var hit_tween := monster_actor.create_tween()
	hit_tween.tween_property(monster_actor, "rotation", deg_to_rad(-5.0), 0.06)
	hit_tween.tween_property(monster_actor, "rotation", deg_to_rad(5.0), 0.06)
	hit_tween.tween_property(monster_actor, "rotation", 0.0, 0.06)


func _set_attack_frame(texture_path: String, sequence: int) -> void:
	if sequence == attack_sequence and is_instance_valid(player_actor):
		player_actor.texture = load(texture_path)


func _build_loot_buttons() -> void:
	_clear_loot_buttons()
	for item_id: String in GameState.loot_queue:
		var definition := GameState.get_item_definition(item_id)
		var button := Button.new()
		button.text = "拾取：%s" % definition.get("name", item_id)
		button.pressed.connect(_claim_drop.bind(item_id, button))
		loot_box.add_child(button)


func _claim_drop(item_id: String, button: Button) -> void:
	if not GameState.claim_loot(item_id):
		message_changed.emit("背包已满，战利品仍保留")
		return
	button.queue_free()
	_build_loot_buttons()
	message_changed.emit("已拾取：%s" % GameState.get_item_definition(item_id).get("name", item_id))


func _clear_loot_buttons() -> void:
	for child in loot_box.get_children():
		loot_box.remove_child(child)
		child.queue_free()


func _build_skill_buttons() -> void:
	for child in skill_box.get_children():
		skill_box.remove_child(child)
		child.queue_free()
	for skill_id: String in GameState.skill_service.learned_active_skills(GameState.learned_skills):
		var button := Button.new()
		button.text = str(GameState.skill_service.skills[skill_id].name)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_attack.bind(skill_id))
		skill_box.add_child(button)


func _refresh_hp() -> void:
	hp_label.text = "玩家生命：%d / %d    敌人生命：%d / %d" % [
		int(session.player_hp),
		int(session.player_stats.get("max_hp", 1)),
		int(session.monster_hp),
		int(session.monster.get("max_hp", 1)),
	]


func _retreat() -> void:
	if session != null:
		GameState.commit_battle_health(int(session.player_hp), session.pet_states)
	session = null
	hide()
