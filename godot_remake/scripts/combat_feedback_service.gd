extends Node
## v1.37 整改02 唯一生产反馈事件入口（CombatFeedbackService）。
##
## 事务式事件处理（整改02）：
##   emit() 按以下顺序处理，全部校验通过后才提交任何状态：
##     1. 被动技能校验 -> 2. 声音登记校验 -> 3. session 校验 -> 4. 回合校验
##     -> 5. 顺序预检（纯函数，状态副本上计算）-> 6. 去重校验
##     -> 7. 提交回合状态 + dedupe 记录 + 记录事件 + 播放声音
##   所有拒绝路径不得修改 _session_flags / 回合状态 / 资源 / 音效历史。
##
## 纯函数 dedupe key（整改02）：
##   - 显式 dedupe_key 存在时绝不执行默认 key 生成逻辑（先查 payload.has）。
##   - 默认 key 生成无任何副作用（不产生 serial）。
##   - per_item 使用 GameState.claim_loot() 创建的稳定 claim_operation_id：
##     同一次领取操作的重复回调携带相同 operation ID（第二次被 FEEDBACK_DUPLICATE_EVENT 拒绝）；
##     两次独立领取产生不同 operation ID（均接受）。
##
## 战斗生命周期状态机（整改02）：
##   battle_state: idle / active / victory_rewards / defeat_rewards（end_session 后回 idle）。
##   - begin_session() -> active；victory 事件接受 -> victory_rewards（奖励待处理）；
##     player_death/battle_retreat 接受 -> defeat_rewards；end_session() -> idle。
##   - 顺序规则只在战斗上下文（battle_state != idle）执行；非战斗来源事件（idle，
##     如普通掉落领取/升级）不因缺少 victory/reward_queued 被拒。
##   - end_session 唯一调用点（生产）：battle_finished.emit 之后（胜利/失败）、
##     cancel_battle、handle_map_change。奖励事件（reward_queued/loot_claimed）在
##     victory_rewards 状态接受，end_session 之后（idle）的延迟战斗事件被拒。
##
## 声音注册表来自 res://docs/combat_feedback_registry.json（v1.37 整改01 同模式）。

const REGISTRY_PATH := "res://docs/combat_feedback_registry.json"
const MANIFEST_PATH := "res://assets/extracted/sounds/manifest.csv"
const EVENT_HISTORY_LIMIT := 512

const ERROR_DUPLICATE := "FEEDBACK_DUPLICATE_EVENT"
const ERROR_SEQUENCE := "FEEDBACK_SEQUENCE_MISMATCH"
const ERROR_SOUND_UNREGISTERED := "FEEDBACK_SOUND_UNREGISTERED"
const ERROR_PASSIVE_SKILL := "FEEDBACK_PASSIVE_SKILL_TRIGGERED"
const ERROR_STALE_SESSION := "FEEDBACK_STALE_SESSION_EVENT"
const ERROR_SOUND_FIELD_MISMATCH := "FEEDBACK_SOUND_FIELD_MISMATCH"
const ERROR_EVIDENCE_MISSING := "FEEDBACK_EVIDENCE_MISSING"
const ERROR_BATTLE_STATE_MISMATCH := "FEEDBACK_BATTLE_STATE_MISMATCH"
const ERROR_OPERATION_ID_MISSING := "FEEDBACK_OPERATION_ID_MISSING"

## 回合内事件（需 attack_sequence == 服务当前回合；跨回合/战斗级事件不受此限）。
const ROUND_EVENTS := [
	"player_attack_started", "player_attack_frame", "player_attack_finished",
	"skill_started", "skill_failed_stamina", "skill_finished",
	"monster_hit", "monster_attack_started", "monster_attack_finished",
	"player_hit", "dodge",
]

## 战斗状态常量（整改02：把递增 session_id 与"当前正在战斗"分离）。
const STATE_IDLE := "idle"
const STATE_ACTIVE := "active"
const STATE_VICTORY_REWARDS := "victory_rewards"
const STATE_DEFEAT_REWARDS := "defeat_rewards"

## 完整状态矩阵（整改04：19 种注册事件 × 4 状态显式数据表；非法组合命中
## FEEDBACK_BATTLE_STATE_MISMATCH）。idle 只允许非战斗事件（普通领取/失败/升级）；
## active 允许全部战斗事件；victory_rewards 允许升级/奖励入队/领取（不允许攻击/死亡/再次胜利）；
## defeat_rewards 禁止攻击/胜利/奖励入队。
const ALLOWED_EVENTS_BY_STATE := {
	STATE_IDLE: ["loot_claimed", "loot_claim_failed", "level_up"],
	STATE_ACTIVE: ["player_attack_started", "player_attack_frame", "player_attack_finished",
		"skill_started", "skill_failed_stamina", "skill_finished",
		"monster_hit", "monster_attack_started", "monster_attack_finished",
		"player_hit", "dodge", "monster_death", "player_death", "victory",
		"reward_queued", "loot_claimed", "loot_claim_failed", "level_up", "battle_retreat"],
	STATE_VICTORY_REWARDS: ["level_up", "reward_queued", "loot_claimed", "loot_claim_failed"],
	STATE_DEFEAT_REWARDS: ["level_up", "loot_claimed", "loot_claim_failed", "battle_retreat", "player_death", "monster_death", "player_hit", "monster_hit", "dodge"],
}

var session_id: int = 0  # 战斗 session 序号（begin/end 递增；不等于"正在战斗"）
var attack_sequence: int = 0  # 当前回合序号（生产 _attack 每回合递增后 set_attack_sequence）
var battle_state: String = STATE_IDLE  # 战斗生命周期状态（整改02）
var _next_index: int = 1  # 单调递增序号（不依赖系统时间）
var _events: Array[Dictionary] = []  # 有界历史（EVENT_HISTORY_LIMIT）
var _sound_registry: Dictionary = {}  # sound_id(int) -> 注册表条目
var _sound_name_to_id: Dictionary = {}  # sound_name -> sound_id
var _feedback_events: Dictionary = {}  # event_type -> 注册表 feedback_events 条目（dedupe 策略）
var _dedupe_seen: Dictionary = {}  # dedupe_key -> true（当前 session 内）
var _session_flags: Dictionary = {}  # session_id -> 顺序规则状态（仅 accepted 事件提交）
var _loaded: bool = false


func _ready() -> void:
	_load_registry()


## 生产加载注册表（docs/combat_feedback_registry.json）。
func _load_registry() -> void:
	_sound_registry.clear()
	_sound_name_to_id.clear()
	_feedback_events.clear()
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_warning("combat feedback registry missing: " + REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is not Dictionary:
		push_warning("combat feedback registry parse failed")
		return
	for entry: Variant in (parsed as Dictionary).get("sounds", []):
		if not entry is Dictionary:
			continue
		var sound_id := int(entry.get("sound_id", -1))
		if sound_id > 0:
			_sound_registry[sound_id] = entry
	for name_key: String in (parsed as Dictionary).get("sound_name_map", {}):
		_sound_name_to_id[name_key] = int((parsed as Dictionary)["sound_name_map"][name_key])
	var events_raw: Variant = (parsed as Dictionary).get("feedback_events", {})
	if events_raw is Dictionary:
		_feedback_events = (events_raw as Dictionary).duplicate(true)
	_loaded = not _sound_registry.is_empty()


func is_registry_loaded() -> bool:
	return _loaded


func registry_sound_count() -> int:
	return _sound_registry.size()


func sound_id_of(sound_name: String) -> int:
	return int(_sound_name_to_id.get(sound_name, -1))


## 注册表条目（sound_id -> Dictionary），供测试校验路径/格式/token。
func registered_sound(sound_id: int) -> Dictionary:
	return _sound_registry.get(sound_id, {})


## 注册表顶层 evidence_source（测试必须从注册表读取，不得硬编码证据文件路径）。
func test_registry_evidence_source() -> String:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return str((parsed as Dictionary).get("evidence_source", ""))
	return ""


## 新战斗 session：session_id 递增，battle_state=active，清空 dedupe/顺序标志，回合归零。
## 生产调用点：SceneBattleController.engage()（遭遇怪物开战）。
func begin_session() -> int:
	session_id += 1
	attack_sequence = 0
	battle_state = STATE_ACTIVE
	_dedupe_seen.clear()
	_session_flags.clear()
	return session_id


## 结束/取消当前 session（整改03 幂等）：session_id 递增，battle_state=idle，旧 session 事件被拒。
## - expected_session_id >= 0 时只结束匹配且仍活动的 session（不结束随后新建的 session）。
## - 已处于 idle 时直接返回（不再次递增）。
## 生产唯一调用点：battle_finished.emit 之后（胜利/失败）、cancel_battle、handle_map_change。
func end_session(expected_session_id: int = -1) -> void:
	if battle_state == STATE_IDLE:
		return
	if expected_session_id >= 0 and expected_session_id != session_id:
		return
	session_id += 1
	attack_sequence = 0
	battle_state = STATE_IDLE
	_dedupe_seen.clear()
	_session_flags.clear()


## 生产回合推进：controller 每回合 attack_sequence += 1 后调用（同一入口供测试使用）。
func set_attack_sequence(seq: int) -> void:
	attack_sequence = seq


## 唯一生产反馈事件入口（事务式：全部校验通过后才提交状态）。
func emit(event_type: String, payload: Dictionary = {}) -> Dictionary:
	# 1. 被动技能校验（FEEDBACK_PASSIVE_SKILL_TRIGGERED）。
	var skill_id := str(payload.get("skill_id", ""))
	if event_type in ["skill_started", "skill_finished"] and not skill_id.is_empty():
		var skill_def: Variant = GameState.skill_service.skills.get(skill_id, {})
		if skill_def is Dictionary and str((skill_def as Dictionary).get("type", "")) == "passive":
			return _reject(ERROR_PASSIVE_SKILL, event_type, payload)
	# 2. 声音登记校验（FEEDBACK_SOUND_UNREGISTERED）。
	var sound_name := str(payload.get("sound_name", ""))
	if not sound_name.is_empty() and not _sound_name_to_id.has(sound_name):
		return _reject(ERROR_SOUND_UNREGISTERED, event_type, payload)
	# 3. session 校验（FEEDBACK_STALE_SESSION_EVENT）。
	var ev_session := int(payload.get("session_id", session_id))
	if ev_session != session_id:
		return _reject(ERROR_STALE_SESSION, event_type, payload)
	# 3b. 战斗状态匹配校验（整改04：ALLOWED_EVENTS_BY_STATE 显式矩阵）——在 session 校验之后
	#     （旧 session 事件优先 FEEDBACK_STALE_SESSION_EVENT）。
	if not (ALLOWED_EVENTS_BY_STATE.get(battle_state, []) as Array).has(event_type):
		return _reject(ERROR_BATTLE_STATE_MISMATCH, event_type, payload)
	# 3c. per_item 缺少非空 claim_operation_id（整改03：FEEDBACK_OPERATION_ID_MISSING）。
	if str((_feedback_events.get(event_type, {}) as Dictionary).get("dedupe", "")) == "per_item" and str(payload.get("claim_operation_id", "")).is_empty():
		return _reject(ERROR_OPERATION_ID_MISSING, event_type, payload)
	# 4. 旧回合校验（仅战斗上下文）。
	if battle_state != STATE_IDLE and event_type in ROUND_EVENTS:
		var ev_seq := int(payload.get("attack_sequence", attack_sequence))
		if ev_seq != attack_sequence:
			return _reject(ERROR_STALE_SESSION, event_type, payload)
	# 5. 顺序预检（纯函数：状态副本上计算下一状态与违规，不写回——整改02 修复同回合别名污染；
	#    仅战斗上下文执行——idle 上下文（非战斗领取/升级）不受战斗顺序规则约束）。
	var transition := {"violation": "", "flags": {}}
	if battle_state != STATE_IDLE:
		transition = _sequence_transition(event_type, payload)
	var violation := str(transition.get("violation", ""))
	if not violation.is_empty():
		return _reject(ERROR_SEQUENCE, event_type, payload, violation)
	# 6. 去重校验（纯函数 key；显式 key 存在时绝不执行默认 key 生成逻辑——整改02）。
	var dedupe_key := str(payload.get("dedupe_key", "")) if payload.has("dedupe_key") else _default_dedupe_key(event_type, payload)
	if _dedupe_seen.has(dedupe_key):
		return _reject(ERROR_DUPLICATE, event_type, payload)
	# 7. 全部校验通过：提交状态 -> 记录事件 -> 播放声音。
	_session_flags[session_id] = transition.get("flags", {})
	_dedupe_seen[dedupe_key] = true
	_apply_state_transition(event_type)
	var index := _next_index
	_next_index += 1
	_events.append({
		"index": index,
		"event_type": event_type,
		"session_id": session_id,
		"attack_sequence": attack_sequence,
		"battle_state": battle_state,
		"skill_id": skill_id,
		"sound_name": sound_name,
		"dedupe_key": dedupe_key,
		"payload": payload.duplicate(),
		"accepted": true,
		"rejection_code": "",
	})
	if _events.size() > EVENT_HISTORY_LIMIT:
		_events.remove_at(0)
	if not sound_name.is_empty():
		AudioService.play(sound_name)
	return {"accepted": true, "index": index, "rejection_code": ""}


## 战斗状态推进（仅 accepted 事件后调用；idle 上下文不改变状态）。
func _apply_state_transition(event_type: String) -> void:
	if battle_state == STATE_IDLE:
		return
	match event_type:
		"victory":
			battle_state = STATE_VICTORY_REWARDS
		"player_death", "battle_retreat":
			battle_state = STATE_DEFEAT_REWARDS


## 默认 dedupe key（整改02：纯函数，无副作用）。
##   per_attack/per_cast：session + attack_sequence + event_type
##   per_battle/per_victory/per_defeat：session + event_type
##   per_level：session + event_type + level
##   per_item：session + claim_operation_id（由 GameState.claim_loot 创建，稳定标识一次领取操作）
##   其余：session + event_type
func _default_dedupe_key(event_type: String, payload: Dictionary) -> String:
	var strategy := str((_feedback_events.get(event_type, {}) as Dictionary).get("dedupe", ""))
	match strategy:
		"per_attack", "per_cast":
			return "attack:%d:%d:%s" % [session_id, attack_sequence, event_type]
		"per_battle", "per_victory", "per_defeat":
			return "battle:%d:%s" % [session_id, event_type]
		"per_level":
			return "level:%d:%s:%d" % [session_id, event_type, int(payload.get("level", 0))]
		"per_item":
			return "claim:%d:%s" % [session_id, str(payload.get("claim_operation_id", ""))]
		_:
			return "event:%d:%s" % [session_id, event_type]


func _reject(code: String, event_type: String, payload: Dictionary, detail: String = "") -> Dictionary:
	var index := _next_index
	_next_index += 1
	_events.append({
		"index": index,
		"event_type": event_type,
		"session_id": int(payload.get("session_id", session_id)),
		"attack_sequence": int(payload.get("attack_sequence", attack_sequence)),
		"battle_state": battle_state,
		"skill_id": str(payload.get("skill_id", "")),
		"sound_name": str(payload.get("sound_name", "")),
		"dedupe_key": str(payload.get("dedupe_key", "")),
		"payload": payload.duplicate(),
		"accepted": false,
		"rejection_code": code,
		"detail": detail,
	})
	if _events.size() > EVENT_HISTORY_LIMIT:
		_events.remove_at(0)
	return {"accepted": false, "index": index, "rejection_code": code, "detail": detail}


## 顺序规则状态机（整改02：纯函数——在状态副本上计算，绝不写回 _session_flags；
## 同回合也总是 duplicate，修复"同回合 Dictionary 别名污染"缺陷：被 dedupe 拒绝的事件
## 在 transition 阶段不再能直接修改 _session_flags[session_id]）。
func _sequence_transition(event_type: String, payload: Dictionary) -> Dictionary:
	var flags: Dictionary = (_session_flags.get(session_id, {}) as Dictionary).duplicate(true)
	var round := int(payload.get("attack_sequence", attack_sequence))
	if int(flags.get("round", -1)) != round:
		flags["round"] = round
		flags["attack_started"] = false
		flags["monster_attack_started"] = false
		flags["skill_started"] = false
		flags["stamina_failed"] = false
	var violation := ""
	match event_type:
		"player_attack_started":
			if bool(flags.get("player_dead", false)):
				violation = "player_death_freezes_player_attack"
			else:
				flags["attack_started"] = true
		"player_attack_frame":
			if not bool(flags.get("attack_started", false)):
				violation = "attack_frame_without_attack_started"
		"monster_hit":
			if not bool(flags.get("attack_started", false)):
				violation = "monster_hit_before_attack_started"
		"player_attack_finished":
			if not bool(flags.get("attack_started", false)):
				violation = "attack_finished_without_attack_started"
		"skill_started":
			if bool(flags.get("stamina_failed", false)):
				violation = "skill_started_after_stamina_failure"
			else:
				flags["skill_started"] = true
		"skill_failed_stamina":
			if bool(flags.get("skill_started", false)):
				violation = "stamina_failure_after_skill_started"
			else:
				flags["stamina_failed"] = true
		"skill_finished":
			if bool(flags.get("stamina_failed", false)):
				violation = "skill_finished_after_stamina_failure"
			elif not bool(flags.get("skill_started", false)):
				violation = "skill_finished_without_skill_started"
		"monster_attack_started":
			if bool(flags.get("monster_dead", false)):
				violation = "monster_attack_after_monster_death"
			else:
				flags["monster_attack_started"] = true
		"monster_attack_finished":
			if not bool(flags.get("monster_attack_started", false)):
				violation = "monster_attack_finished_without_started"
		"player_hit", "dodge":
			if not bool(flags.get("monster_attack_started", false)):
				violation = "player_hit_or_dodge_without_monster_attack"
		"monster_death":
			flags["monster_dead"] = true
		"player_death":
			flags["player_dead"] = true
		"victory":
			flags["victory"] = true
		"reward_queued":
			if not bool(flags.get("victory", false)):
				violation = "reward_queued_without_victory"
			else:
				flags["reward_queued"] = true
		"loot_claimed", "loot_claim_failed":
			if not bool(flags.get("reward_queued", false)):
				violation = "loot_claim_without_reward_queued"
	return {"violation": violation, "flags": flags}


## 注册表 sounds 与 manifest.csv 校验（篡改任一字段返回 FEEDBACK_SOUND_FIELD_MISMATCH）。
func validate_registry_against_manifest() -> Array:
	var errors: Array = []
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return [{"sound_id": -1, "field": "manifest_missing", "code": ERROR_SOUND_FIELD_MISMATCH}]
	var lines := f.get_as_text().strip_edges().split("\n")
	f.close()
	for line in lines.slice(1):
		var parts := line.split(",")
		if parts.size() < 6:
			continue
		var sound_id := int(parts[0])
		var manifest_format := int(parts[1])
		var manifest_rate := int(parts[2])
		var manifest_width := int(parts[3])
		var manifest_channels := int(parts[4])
		var manifest_samples := int(parts[5])
		var entry := registered_sound(sound_id)
		if entry.is_empty():
			errors.append({"sound_id": sound_id, "field": "missing", "code": ERROR_SOUND_FIELD_MISMATCH})
			continue
		if manifest_format != 2 or str(entry.get("format", "")) != "mp3":
			errors.append({"sound_id": sound_id, "field": "format", "code": ERROR_SOUND_FIELD_MISMATCH})
		if int(entry.get("rate", 0)) != manifest_rate:
			errors.append({"sound_id": sound_id, "field": "rate", "code": ERROR_SOUND_FIELD_MISMATCH})
		if int(entry.get("sample_width", 0)) != manifest_width:
			errors.append({"sound_id": sound_id, "field": "sample_width", "code": ERROR_SOUND_FIELD_MISMATCH})
		if int(entry.get("channels", 0)) != manifest_channels:
			errors.append({"sound_id": sound_id, "field": "channels", "code": ERROR_SOUND_FIELD_MISMATCH})
		if int(entry.get("sample_count", 0)) != manifest_samples:
			errors.append({"sound_id": sound_id, "field": "sample_count", "code": ERROR_SOUND_FIELD_MISMATCH})
	return errors


## 单条注册表条目与 manifest 字段对（篡改负向：测试传篡改条目，返回精确错误码）。
func validate_sound_entry_fields(sound_id: int, entry: Dictionary, manifest_fields: Dictionary) -> String:
	if manifest_fields.is_empty():
		return ERROR_SOUND_FIELD_MISMATCH
	if int(entry.get("rate", 0)) != int(manifest_fields.get("rate", 0)):
		return ERROR_SOUND_FIELD_MISMATCH
	if int(entry.get("sample_width", 0)) != int(manifest_fields.get("sample_width", 0)):
		return ERROR_SOUND_FIELD_MISMATCH
	if int(entry.get("channels", 0)) != int(manifest_fields.get("channels", 0)):
		return ERROR_SOUND_FIELD_MISMATCH
	if int(entry.get("sample_count", 0)) != int(manifest_fields.get("sample_count", 0)):
		return ERROR_SOUND_FIELD_MISMATCH
	if str(entry.get("format", "")) != "mp3":
		return ERROR_SOUND_FIELD_MISMATCH
	return ""


## 证据文件路径验证（v1.37 整改02：变异负向——注册表 evidence_source 指向不存在文件时
## 返回 FEEDBACK_EVIDENCE_MISSING；存在返回 ""）。
func validate_evidence_source(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ERROR_EVIDENCE_MISSING
	return ""


## 证据 token 段归属验证（v1.37 整改02：变异负向——条目 token 必须出现在所属声音段文本内，
## 任一缺失返回 FEEDBACK_EVIDENCE_MISSING）。
func validate_evidence_tokens(entry: Dictionary, segment_text: String) -> String:
	var tokens: Variant = entry.get("evidence_tokens", [])
	if not tokens is Array or (tokens as Array).is_empty():
		return ERROR_EVIDENCE_MISSING
	for token: String in tokens:
		if not segment_text.contains(token):
			return ERROR_EVIDENCE_MISSING
	return ""


# --- 测试钩子（不参与生产路径；历史为数据副本，不持有对象强引用）---

func test_event_history() -> Array:
	return _events.duplicate(true)


func test_accepted_count() -> int:
	var count := 0
	for ev in _events:
		if bool(ev.get("accepted", false)):
			count += 1
	return count


func test_rejected_count() -> int:
	var count := 0
	for ev in _events:
		if not bool(ev.get("accepted", false)):
			count += 1
	return count


func test_last_rejection_code() -> String:
	for i in range(_events.size() - 1, -1, -1):
		if not bool(_events[i].get("accepted", false)):
			return str(_events[i].get("rejection_code", ""))
	return ""


func test_event_count(event_type: String, skill_id: String = "", sound_name: String = "", item_id: String = "") -> int:
	var count := 0
	for ev in _events:
		if not bool(ev.get("accepted", false)) or str(ev.get("event_type", "")) != event_type:
			continue
		if not skill_id.is_empty() and str(ev.get("skill_id", "")) != skill_id:
			continue
		if not sound_name.is_empty() and str(ev.get("sound_name", "")) != sound_name:
			continue
		if not item_id.is_empty() and str(ev.get("payload", {}).get("item_id", "")) != item_id:
			continue
		count += 1
	return count


func test_event_type_sequence() -> Array:
	var result: Array = []
	for ev in _events:
		if bool(ev.get("accepted", false)):
			result.append(str(ev.get("event_type", "")))
	return result


func test_dedupe_key_of(event_type: String, skill_id: String = "") -> String:
	for ev in _events:
		if not bool(ev.get("accepted", false)) or str(ev.get("event_type", "")) != event_type:
			continue
		if not skill_id.is_empty() and str(ev.get("skill_id", "")) != skill_id:
			continue
		return str(ev.get("dedupe_key", ""))
	return ""


func test_session_and_sequence_of(event_type: String, skill_id: String = "") -> Dictionary:
	for ev in _events:
		if not bool(ev.get("accepted", false)) or str(ev.get("event_type", "")) != event_type:
			continue
		if not skill_id.is_empty() and str(ev.get("skill_id", "")) != skill_id:
			continue
		return {"session_id": int(ev.get("session_id", -1)), "attack_sequence": int(ev.get("attack_sequence", -1))}
	return {"session_id": -1, "attack_sequence": -1}


func test_reset() -> void:
	_events.clear()
	_next_index = 1
	_dedupe_seen.clear()
	_session_flags.clear()
	session_id = 0
	attack_sequence = 0
	battle_state = STATE_IDLE
