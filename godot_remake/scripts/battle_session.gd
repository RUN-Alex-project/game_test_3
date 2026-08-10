extends RefCounted

const CombatService = preload("res://scripts/combat_service.gd")

var combat
var monster_id: String
var monster: Dictionary
var player_stats: Dictionary
var player_hp: int
var monster_hp: int
var pet_states: Array[Dictionary] = []
var finished: bool = false
var victory: bool = false
var defeat_reason: String = ""
var turn: int = 0


func _init(target_monster_id: String, stats: Dictionary, seed_value: int = 0, monster_modifiers: Dictionary = {}) -> void:
	combat = CombatService.new(seed_value)
	monster_id = target_monster_id
	monster = combat.get_monster(monster_id).duplicate(true)
	for stat_name: String in ["level", "max_hp", "attack", "defense", "combat_power"]:
		if monster.has(stat_name) and monster_modifiers.has(stat_name):
			monster[stat_name] = maxi(1, roundi(float(monster[stat_name]) * float(monster_modifiers[stat_name])))
	player_stats = stats.duplicate(true)
	var maximum_player_hp := maxi(1, int(player_stats.get("max_hp", 1)))
	player_hp = clampi(int(player_stats.get("current_hp", maximum_player_hp)), 0, maximum_player_hp)
	monster_hp = int(monster.get("max_hp", 1))
	var raw_pets: Variant = player_stats.get("battle_pets", [])
	if raw_pets is Array:
		for raw_pet: Variant in raw_pets:
			if not raw_pet is Dictionary:
				continue
			var pet: Dictionary = raw_pet.duplicate(true)
			var maximum_pet_hp := maxi(1, int(pet.get("max_hp", 1)))
			pet.current_hp = clampi(int(pet.get("current_hp", maximum_pet_hp)), 0, maximum_pet_hp)
			pet_states.append(pet)
	if monster.is_empty():
		finished = true
	elif player_hp <= 0:
		finished = true
		defeat_reason = "player_no_hp"


func perform_turn(player_variance: float = 1.0, monster_variance: float = 1.0, dodge_roll: float = -1.0, skill_multiplier: float = 1.0) -> Dictionary:
	if finished:
		return {"accepted": false}
	turn += 1
	var player_damage: int = combat.calculate_damage(
		roundi(int(player_stats.get("attack", 1)) * maxf(1.0, skill_multiplier)),
		int(monster.get("defense", 0)),
		player_variance,
	)
	monster_hp = maxi(0, monster_hp - player_damage)
	# In the SWF, combined pets merge attack/defense into the player. They are
	# animated alongside the player but do not apply a second independent hit.
	var pet_damage := 0
	var pet_attacks: Array[Dictionary] = []
	var result: Dictionary = {
		"accepted": true,
		"turn": turn,
		"player_damage": player_damage,
		"pet_damage": pet_damage,
		"pet_attacks": pet_attacks,
		"monster_damage": 0,
		"player_damage_taken": 0,
		"pet_damage_taken": 0,
		"player_hp": player_hp,
		"monster_hp": monster_hp,
		"monster_target": "none",
		"target_pet_id": 0,
		"target_pet_name": "",
		"pet_deaths": [],
		"dodged": false,
		"skill_multiplier": maxf(1.0, skill_multiplier),
	}
	if monster_hp == 0:
		finished = true
		victory = true
		result["finished"] = true
		result["victory"] = true
		return result

	var target_pet_index := _first_alive_pet_index()
	if target_pet_index >= 0:
		# Player defense already includes every currently combined pet, matching
		# xinxi.byhit before damage is delegated to the first combined pet.
		var merged_defense := int(player_stats.get("defense", 0))
		var pet_damage_taken: int = combat.calculate_damage(int(monster.get("attack", 1)), merged_defense, monster_variance)
		var previous_pet_hp := int(pet_states[target_pet_index].get("current_hp", 0))
		pet_states[target_pet_index].current_hp = maxi(0, previous_pet_hp - pet_damage_taken)
		result.monster_damage = pet_damage_taken
		result.pet_damage_taken = pet_damage_taken
		result.monster_target = "pet"
		result.target_pet_id = int(pet_states[target_pet_index].get("instance_id", 0))
		result.target_pet_name = str(pet_states[target_pet_index].get("name", "幻兽"))
		if previous_pet_hp > 0 and int(pet_states[target_pet_index].current_hp) == 0:
			result.pet_deaths = [int(pet_states[target_pet_index].get("instance_id", 0))]
	else:
		var actual_dodge_roll: float = combat.random.randf() if dodge_roll < 0.0 else dodge_roll
		var dodged: bool = actual_dodge_roll < float(player_stats.get("dodge_percent", 0)) / 100.0
		var player_damage_taken := 0
		if not dodged:
			player_damage_taken = combat.calculate_damage(
				int(monster.get("attack", 1)),
				int(player_stats.get("defense", 0)),
				monster_variance,
			)
		player_hp = maxi(0, player_hp - player_damage_taken)
		result.monster_damage = player_damage_taken
		result.player_damage_taken = player_damage_taken
		result.player_hp = player_hp
		result.monster_target = "player"
		result.dodged = dodged
		if player_hp == 0:
			finished = true
			defeat_reason = "player_death"
			result.finished = true
			result.victory = false
	result["pet_states"] = pet_states.duplicate(true)
	return result


func _first_alive_pet_index() -> int:
	for index in pet_states.size():
		if int(pet_states[index].get("current_hp", 0)) > 0:
			return index
	return -1


func refresh_player_configuration(stats: Dictionary) -> void:
	var current_by_id: Dictionary = {}
	for pet: Dictionary in pet_states:
		current_by_id[int(pet.get("instance_id", 0))] = int(pet.get("current_hp", 0))
	player_stats = stats.duplicate(true)
	var maximum_player_hp := maxi(1, int(player_stats.get("max_hp", 1)))
	player_hp = clampi(player_hp, 0, maximum_player_hp)
	pet_states.clear()
	var raw_pets: Variant = player_stats.get("battle_pets", [])
	if raw_pets is Array:
		for raw_pet: Variant in raw_pets:
			if not raw_pet is Dictionary:
				continue
			var pet: Dictionary = raw_pet.duplicate(true)
			var maximum_pet_hp := maxi(1, int(pet.get("max_hp", 1)))
			var instance_id := int(pet.get("instance_id", 0))
			pet.current_hp = clampi(int(current_by_id.get(instance_id, pet.get("current_hp", maximum_pet_hp))), 0, maximum_pet_hp)
			pet_states.append(pet)


func force_defeat(reason: String) -> void:
	if victory:
		return
	finished = true
	victory = false
	defeat_reason = reason


func health_payload() -> Dictionary:
	return {"player_hp":player_hp, "pet_states":pet_states.duplicate(true)}


func victory_payload(forced_rolls: Array[float] = []) -> Dictionary:
	if not finished or not victory:
		return {}
	var luck := int(GameState.base_stats.get("luck", 0))
	var payload: Dictionary = combat.victory_rewards(monster_id, luck)
	payload["drops"] = combat.roll_drops(monster_id, forced_rolls, luck, bool(GameState.story_flags.get("war_soul_secret_unlocked", false)))
	return payload