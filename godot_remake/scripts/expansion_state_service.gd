extends RefCounted

const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const RelationshipServiceScript = preload("res://scripts/relationship_service.gd")
const CommissionServiceScript = preload("res://scripts/commission_service.gd")
const DayCycleServiceScript = preload("res://scripts/day_cycle_service.gd")
const MailServiceScript = preload("res://scripts/mail_service.gd")
const MarketServiceScript = preload("res://scripts/market_service.gd")
const RankingServiceScript = preload("res://scripts/ranking_service.gd")
const ArenaServiceScript = preload("res://scripts/arena_service.gd")
const BattleSnapshotServiceScript = preload("res://scripts/battle_snapshot_service.gd")
const GuildMarketServiceScript = preload("res://scripts/guild_market_service.gd")
const AuctionServiceScript = preload("res://scripts/auction_service.gd")
const EconomyLedgerServiceScript = preload("res://scripts/economy_ledger_service.gd")
const PropertyServiceScript = preload("res://scripts/property_service.gd")
const TerritoryEconomyServiceScript = preload("res://scripts/territory_economy_service.gd")
const AssignmentServiceScript = preload("res://scripts/assignment_service.gd")
const TerritoryLedgerServiceScript = preload("res://scripts/territory_ledger_service.gd")
const StoryChapterServiceScript = preload("res://scripts/story_chapter_service.gd")
const EvidenceCollectionServiceScript = preload("res://scripts/evidence_collection_service.gd")
const ChapterEncounterServiceScript = preload("res://scripts/chapter_encounter_service.gd")
const WeeklyContractServiceScript = preload("res://scripts/weekly_contract_service.gd")
const BorderStoryServiceScript = preload("res://scripts/border_story_service.gd")
const SupplyServiceScript = preload("res://scripts/supply_service.gd")
const BorderDefenseServiceScript = preload("res://scripts/border_defense_service.gd")
const BorderWeeklyServiceScript = preload("res://scripts/border_weekly_service.gd")
const IceStoryServiceScript = preload("res://scripts/ice_story_service.gd")
const ElementResolutionServiceScript = preload("res://scripts/element_resolution_service.gd")
const IceEncounterServiceScript = preload("res://scripts/ice_encounter_service.gd")
const IceWeeklyServiceScript = preload("res://scripts/ice_weekly_service.gd")
const ElementConsumableServiceScript = preload("res://scripts/element_consumable_service.gd")
const AbyssFinaleServiceScript = preload("res://scripts/abyss_finale_service.gd")
const EchoEncounterServiceScript = preload("res://scripts/echo_encounter_service.gd")
const TotemTrialServiceScript = preload("res://scripts/totem_trial_service.gd")
const FinaleEpilogueServiceScript = preload("res://scripts/finale_epilogue_service.gd")
const ChallengeServiceScript = preload("res://scripts/challenge_service.gd")
const WarriorMasteryServiceScript = preload("res://scripts/warrior_mastery_service.gd")
const EquipmentMasteryServiceScript = preload("res://scripts/equipment_mastery_service.gd")
const ChallengeRotationServiceScript = preload("res://scripts/challenge_rotation_service.gd")
const PetCollectionServiceScript = preload("res://scripts/pet_collection_service.gd")
const PetSupportServiceScript = preload("res://scripts/pet_support_service.gd")
const PetTrialServiceScript = preload("res://scripts/pet_trial_service.gd")
const ResearchContractServiceScript = preload("res://scripts/research_contract_service.gd")
const SeasonCycleServiceScript = preload("res://scripts/season_cycle_service.gd")
const EpilogueEventServiceScript = preload("res://scripts/epilogue_event_service.gd")

const DEFAULT_WORLD_SEED := 1297043285
const CONTRACT_FIELD_NAMES := [
	"revision", "world_seed", "day_sequence", "adventurers", "relationships",
	"mailbox", "commission_state", "rankings", "season", "economy", "properties",
	"auction", "campaign", "collections", "market", "territory_economy", "chapters",
	"challenges", "warrior_mastery", "equipment_mastery", "pet_endgame",
]

var adventurer_service = AdventurerServiceScript.new()
var relationship_service = RelationshipServiceScript.new()
var commission_service = CommissionServiceScript.new()
var day_cycle_service = DayCycleServiceScript.new()
var mail_service = MailServiceScript.new()
var market_service = MarketServiceScript.new()
var ranking_service = RankingServiceScript.new()
var arena_service = ArenaServiceScript.new()
var snapshot_service = BattleSnapshotServiceScript.new()
var guild_market_service = GuildMarketServiceScript.new()
var auction_service = AuctionServiceScript.new()
var economy_ledger_service = EconomyLedgerServiceScript.new()
var property_service = PropertyServiceScript.new()
var territory_economy_service = TerritoryEconomyServiceScript.new()
var assignment_service = AssignmentServiceScript.new()
var territory_ledger_service = TerritoryLedgerServiceScript.new()
var story_chapter_service = StoryChapterServiceScript.new()
var evidence_collection_service = EvidenceCollectionServiceScript.new()
var chapter_encounter_service = ChapterEncounterServiceScript.new()
var weekly_contract_service = WeeklyContractServiceScript.new()
var border_story_service = BorderStoryServiceScript.new()
var supply_service = SupplyServiceScript.new()
var border_defense_service = BorderDefenseServiceScript.new()
var border_weekly_service = BorderWeeklyServiceScript.new()
var ice_story_service = IceStoryServiceScript.new()
var element_resolution_service = ElementResolutionServiceScript.new()
var ice_encounter_service = IceEncounterServiceScript.new()
var ice_weekly_service = IceWeeklyServiceScript.new()
var element_consumable_service = ElementConsumableServiceScript.new()
var abyss_finale_service = AbyssFinaleServiceScript.new()
var echo_encounter_service = EchoEncounterServiceScript.new()
var totem_trial_service = TotemTrialServiceScript.new()
var finale_epilogue_service = FinaleEpilogueServiceScript.new()
var challenge_service = ChallengeServiceScript.new()
var warrior_mastery_service = WarriorMasteryServiceScript.new()
var equipment_mastery_service = EquipmentMasteryServiceScript.new()
var challenge_rotation_service = ChallengeRotationServiceScript.new()
var pet_collection_service = PetCollectionServiceScript.new()
var pet_support_service = PetSupportServiceScript.new()
var pet_trial_service = PetTrialServiceScript.new()
var research_contract_service = ResearchContractServiceScript.new()
var season_cycle_service = SeasonCycleServiceScript.new()
var epilogue_event_service = EpilogueEventServiceScript.new()


func empty_contract() -> Dictionary:
	return {
		"revision": 1,
		"world_seed": 0,
		"day_sequence": 0,
		"adventurers": {},
		"relationships": {},
		"mailbox": [],
		"commission_state": {},
		"rankings": {},
		"season": {},
		"economy": {},
		"properties": {},
		"auction": {},
		"campaign": {},
		"collections": {},
		"market": {},
		"territory_economy": {},
		"chapters": {},
		"challenges": {},
		"warrior_mastery": {},
		"equipment_mastery": {},
		"pet_endgame": {},
	}


func default_enabled_state() -> Dictionary:
	var state := empty_contract()
	state["world_seed"] = DEFAULT_WORLD_SEED
	return _hydrate_roster(state)


func _hydrate_roster(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	if int(out.get("world_seed", 0)) == 0:
		out["world_seed"] = DEFAULT_WORLD_SEED
	if int(out.get("revision", 0)) < 1:
		out["revision"] = 1
	var adventurers: Dictionary = out.get("adventurers", {})
	if not adventurers is Dictionary:
		adventurers = {}
	var relationships: Dictionary = out.get("relationships", {})
	if not relationships is Dictionary:
		relationships = {}
	var commissions: Dictionary = out.get("commission_state", {})
	if not commissions is Dictionary:
		commissions = {}
	for adv_id in adventurer_service.all_ids():
		var runtime: Dictionary = {}
		if adventurers.get(adv_id) is Dictionary:
			runtime = (adventurers[adv_id] as Dictionary).duplicate(true)
		var defaults: Dictionary = adventurer_service.default_runtime(adv_id)
		for key in defaults.keys():
			if not runtime.has(key):
				runtime[key] = defaults[key]
		adventurers[adv_id] = runtime
		if not relationships.has(adv_id):
			relationships[adv_id] = relationship_service.default_runtime(adv_id)
	for comm_id in commission_service.all_ids():
		if not commissions.has(comm_id):
			commissions[comm_id] = commission_service.default_runtime(comm_id)
	out["adventurers"] = adventurers
	out["relationships"] = relationships
	out["commission_state"] = commissions
	for empty_list in ["mailbox"]:
		if not out.get(empty_list) is Array:
			out[empty_list] = []
	for empty_dict in ["rankings", "season", "economy", "properties", "auction", "campaign", "collections", "market", "territory_economy", "chapters", "challenges", "warrior_mastery", "equipment_mastery", "pet_endgame"]:
		if not out.get(empty_dict) is Dictionary:
			out[empty_dict] = {}
	var economy: Dictionary = out.get("economy", {})
	if not economy is Dictionary:
		economy = {}
	else:
		economy = economy.duplicate(true)
	var ledgers: Dictionary = {}
	if economy.get("adventurer_ledgers") is Dictionary:
		ledgers = (economy["adventurer_ledgers"] as Dictionary).duplicate(true)
	for adv_id in adventurer_service.all_ids():
		ledgers[adv_id] = market_service.normalize_ledger(adv_id, ledgers.get(adv_id, {}))
	economy["adventurer_ledgers"] = ledgers
	if not economy.get("daily_settlement_log") is Array:
		economy["daily_settlement_log"] = []
	out["economy"] = economy
	out["rankings"] = ranking_service.normalize(out.get("rankings", {}))
	var season: Dictionary = {}
	if out.get("season") is Dictionary:
		season = (out["season"] as Dictionary).duplicate(true)
	if not season.get("arena_seed_state") is Dictionary:
		season["arena_seed_state"] = {"season_id": 0, "matches": []}
	out["season"] = season_cycle_service.normalize(season)
	out = season_cycle_service.ensure(out, 1, int(out.get("world_seed", DEFAULT_WORLD_SEED)))
	out = guild_market_service.sync_auction(out)
	out["properties"] = property_service.normalize(out.get("properties", {}))
	out["territory_economy"] = territory_economy_service.normalize(out.get("territory_economy", {}))
	out["chapters"] = story_chapter_service.normalize(out.get("chapters", {}))
	out["chapters"] = border_story_service.normalize(out.get("chapters", {}))
	out["chapters"] = ice_story_service.normalize(out.get("chapters", {}))
	out["chapters"] = abyss_finale_service.normalize(out.get("chapters", {}))
	out["challenges"] = challenge_service.normalize(out.get("challenges", {}))
	out["warrior_mastery"] = warrior_mastery_service.normalize(out.get("warrior_mastery", {}))
	out["equipment_mastery"] = equipment_mastery_service.normalize(out.get("equipment_mastery", {}))
	out["pet_endgame"] = pet_collection_service.normalize(out.get("pet_endgame", {}))
	return out


## ????????????? GameState ????
func build_from_save(raw: Variant) -> Dictionary:
	if raw == null:
		return default_enabled_state()
	if not raw is Dictionary:
		return {}
	var incoming: Dictionary = raw
	var state := empty_contract()
	for field_name in CONTRACT_FIELD_NAMES:
		if incoming.has(field_name):
			var value: Variant = incoming.get(field_name)
			if value is Dictionary or value is Array:
				state[field_name] = value.duplicate(true)
			else:
				state[field_name] = value
	if not _types_ok(state):
		return {}
	if not _runtime_ids_legal(state):
		return {}
	if not relationship_service.history_operation_ids_unique(state):
		return {}
	if not mail_service.validate_mailbox(state.get("mailbox", [])).is_empty():
		return {}
	if not guild_market_service.validate_save(state.get("market", {})).is_empty():
		return {}
	if not property_service.validate_save(state).is_empty():
		return {}
	if not territory_economy_service.validate_save(state).is_empty():
		return {}
	if not assignment_service.validate_save(state).is_empty():
		return {}
	if not story_chapter_service.validate_save(state).is_empty():
		return {}
	if not border_story_service.validate_save(state).is_empty():
		return {}
	if not ice_story_service.validate_save(state).is_empty():
		return {}
	if not abyss_finale_service.validate_save(state).is_empty():
		return {}
	if not challenge_service.validate_save(state).is_empty():
		return {}
	if not warrior_mastery_service.validate_save(state).is_empty():
		return {}
	if not equipment_mastery_service.validate_save(state).is_empty():
		return {}
	if not pet_collection_service.validate_save(state).is_empty():
		return {}
	if not pet_support_service.validate_save(state).is_empty():
		return {}
	if not pet_trial_service.validate_save(state).is_empty():
		return {}
	if not research_contract_service.validate_save(state).is_empty():
		return {}
	if not season_cycle_service.validate_save(state).is_empty():
		return {}
	return _hydrate_roster(state)


func _types_ok(state: Dictionary) -> bool:
	if not _is_integer_like(state.get("revision")):
		return false
	if not _is_integer_like(state.get("world_seed")):
		return false
	if not _is_integer_like(state.get("day_sequence")):
		return false
	if int(state.get("revision", 0)) < 1:
		return false
	if int(state.get("world_seed", -1)) < 0:
		return false
	if int(state.get("day_sequence", -1)) < 0:
		return false
	for dict_name in ["adventurers", "relationships", "commission_state", "rankings", "season", "economy", "properties", "auction", "campaign", "collections", "market", "territory_economy", "chapters", "challenges", "warrior_mastery", "equipment_mastery", "pet_endgame"]:
		if not state.get(dict_name) is Dictionary:
			return false
	if not state.get("mailbox") is Array:
		return false
	return true


func _runtime_ids_legal(state: Dictionary) -> bool:
	var allowed: Dictionary = {}
	for adv_id in adventurer_service.all_ids():
		allowed[adv_id] = true
	for adv_id in state.get("adventurers", {}).keys():
		if not allowed.has(str(adv_id)):
			return false
	for adv_id in state.get("relationships", {}).keys():
		if not allowed.has(str(adv_id)):
			return false
		var rel: Variant = state["relationships"][adv_id]
		if not rel is Dictionary:
			return false
		if not _is_integer_like(rel.get("value", 0)) or int(rel.get("value", 0)) < 0:
			return false
	for comm_id in state.get("commission_state", {}).keys():
		if not commission_service.has_id(str(comm_id)):
			return false
	return true


func _is_integer_like(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return v == floorf(v)
	return false


func validate_data_files() -> Dictionary:
	var errors: Array[String] = []
	errors.append_array(adventurer_service.validate_roster())
	errors.append_array(relationship_service.validate_rules())
	errors.append_array(commission_service.validate_templates())
	errors.append_array(day_cycle_service.validate_schedules())
	errors.append_array(mail_service.validate_rules())
	errors.append_array(market_service.validate_profiles())
	errors.append_array(ranking_service.validate_rules())
	errors.append_array(arena_service.validate_rules())
	errors.append_array(snapshot_service.validate_templates())
	errors.append_array(guild_market_service.validate_data())
	errors.append_array(auction_service.validate_rules())
	errors.append_array(property_service.validate_data())
	errors.append_array(territory_economy_service.validate_data())
	errors.append_array(assignment_service.validate_data())
	errors.append_array(challenge_service.validate_catalog())
	errors.append_array(pet_collection_service.validate_catalog())
	errors.append_array(season_cycle_service.validate_rules())
	return {"ok": errors.is_empty(), "errors": errors}
