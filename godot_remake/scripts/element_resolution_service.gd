extends RefCounted

const RULES_PATH := "res://data/element_rules.json"
const ENC_PATH := "res://data/element_encounters.json"
const REJECT_UNKNOWN := true
const CLAMP_RESIST := true
const BLOCK_NEG_DAMAGE := true
const REJECT_NONFINITE := true
const BLOCK_UNREGISTERED_FIELD := true
const REQUIRE_SNAPSHOT := true
const REQUIRE_REPORT_MATCH := true

var rules: Dictionary = {}
var encounters: Dictionary = {}


func _init() -> void:
	var rf := FileAccess.open(RULES_PATH, FileAccess.READ)
	if rf != null:
		var parsed: Variant = JSON.parse_string(rf.get_as_text())
		rules = parsed if parsed is Dictionary else {}
		rf.close()
	var ef := FileAccess.open(ENC_PATH, FileAccess.READ)
	if ef != null:
		var ep: Variant = JSON.parse_string(ef.get_as_text())
		var data: Dictionary = ep if ep is Dictionary else {}
		for raw: Variant in data.get("encounters", []):
			if raw is Dictionary:
				encounters[str(raw.get("monster_id", ""))] = raw
		ef.close()


func is_registered(monster_id: String) -> bool:
	return encounters.has(monster_id)


func encounter_of(monster_id: String) -> Dictionary:
	var raw: Variant = encounters.get(monster_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func element_enabled(element_id: String) -> bool:
	var table: Dictionary = rules.get("elements", {})
	if not table is Dictionary or not table.has(element_id):
		return false
	return bool((table.get(element_id, {}) as Dictionary).get("enabled", false))


func resolve(event: Dictionary) -> Dictionary:
	var base := float(event.get("base_damage", 0))
	var attacker := str(event.get("attacker_element", ""))
	var defender := str(event.get("defender_element", ""))
	var field_id := str(event.get("field_id", ""))
	var resist := float(event.get("resist", 0))
	var stacks := int(event.get("stacks", 1))
	var monster_id := str(event.get("monster_id", ""))
	var sources: Array = ["base"]
	if not monster_id.is_empty() and not is_registered(monster_id):
		if BLOCK_UNREGISTERED_FIELD:
			return _ok(base, 0.0, base, "none", sources, false, false)
		# leak path: still apply field/affinity against unregistered fights
	if not attacker.is_empty() and not element_enabled(attacker):
		if REJECT_UNKNOWN:
			return {"success": false, "code": "ELEMENT_UNKNOWN", "base": base, "modifier": 0.0, "final": base, "rule_id": "none", "applied": false}
	if not defender.is_empty() and not element_enabled(defender):
		if REJECT_UNKNOWN:
			return {"success": false, "code": "ELEMENT_UNKNOWN", "base": base, "modifier": 0.0, "final": base, "rule_id": "none", "applied": false}
	var rmin := float(rules.get("resist_min", -50))
	var rmax := float(rules.get("resist_max", 80))
	if CLAMP_RESIST and (resist < rmin or resist > rmax):
		return {"success": false, "code": "ELEMENT_RESIST_RANGE", "base": base, "modifier": 0.0, "final": base, "rule_id": "none", "applied": false}
	var cap := int(rules.get("stack_cap", 2))
	if stacks > cap:
		stacks = cap
	var affinity := 0.0
	if not attacker.is_empty() and not defender.is_empty():
		var key := "%s>%s" % [attacker, defender]
		var table: Dictionary = rules.get("affinity", {})
		affinity = float(table.get(key, 0.0))
		sources.append("affinity:%s" % key)
	var field_mod := 0.0
	if not field_id.is_empty():
		var fields: Dictionary = rules.get("fields", {})
		var frow: Dictionary = fields.get(field_id, {}) if fields is Dictionary else {}
		field_mod = float(frow.get("modifier", 0.0))
		sources.append("field:%s" % field_id)
	sources.append("resist")
	var modifier := affinity + field_mod - resist / 100.0
	var raw := base * (1.0 + modifier) * float(maxi(1, stacks))
	if REJECT_NONFINITE and (is_nan(raw) or is_inf(raw) or is_nan(base) or is_inf(base) or is_nan(modifier) or is_inf(modifier)):
		return {"success": false, "code": "ELEMENT_NONFINITE", "base": base, "modifier": modifier, "final": 0.0, "rule_id": "none", "applied": false}
	if not REJECT_NONFINITE and (is_nan(raw) or is_inf(raw)):
		return {"success": true, "code": "OK", "base": base, "modifier": modifier, "final": raw, "rule_id": "leaked", "applied": true, "clipped": false}
	var final_v := raw
	var clipped := false
	var min_final := float(rules.get("min_final_damage", 1))
	if BLOCK_NEG_DAMAGE and final_v < min_final:
		final_v = min_final
		clipped = true
		sources.append("clip:min")
	if not BLOCK_NEG_DAMAGE and final_v < 0.0:
		return {"success": true, "code": "OK", "base": base, "modifier": modifier, "final": final_v, "rule_id": "neg", "applied": true, "clipped": false}
	var rule_id := "elem:%s:%s:%s" % [attacker if not attacker.is_empty() else "none", defender if not defender.is_empty() else "none", field_id if not field_id.is_empty() else "none"]
	return _ok(base, modifier, final_v, rule_id, sources, true, clipped)


func _ok(base: float, modifier: float, final_v: float, rule_id: String, sources: Array, applied: bool, clipped: bool) -> Dictionary:
	return {
		"success": true,
		"code": "OK",
		"base": base,
		"modifier": modifier,
		"final": int(round(final_v)) if not is_inf(final_v) and not is_nan(final_v) else final_v,
		"rule_id": rule_id,
		"sources": sources,
		"applied": applied,
		"clipped": clipped,
	}


func format_report(resolved: Dictionary) -> Dictionary:
	var rule_id := str(resolved.get("rule_id", "none"))
	if not REQUIRE_REPORT_MATCH:
		rule_id = "FORGED"
	return {
		"rule_id": rule_id,
		"base": resolved.get("base", 0),
		"modifier": resolved.get("modifier", 0),
		"final": resolved.get("final", 0),
		"applied": bool(resolved.get("applied", false)),
		"clipped": bool(resolved.get("clipped", false)),
	}
