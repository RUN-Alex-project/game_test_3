extends Control

signal message_changed(text: String)
signal player_hp_changed(current_hp: int, maximum_hp: int)
signal battle_finished(monster_id: String, victory: bool)

const BattleSession = preload("res://scripts/battle_session.gd")
const TimelineScheduler = preload("res://scripts/timeline_scheduler.gd")

var session
var active_monster_id: String = ""
var target_actor: TextureRect
var target_label: Label
var target_label_was_visible: bool = false
var player_actor: TextureRect
var enemy_panel: Control
var enemy_hp: ColorRect
var active_monster_name: String = ""
var last_attack_skill_id: String = ""
var busy: bool = false
var attack_sequence: int = 0
var feedback_session_id: int = 0  # v1.37 整改03：当前反馈 session（end_session 幂等校验）
## v1.37 整改01：dodge 判定强制 roll 测试钩子（-1.0 = 生产随机；测试注入 [0,1) 使闪避确定性）。
var test_dodge_roll: float = -1.0
var native_attack_active: bool = false
var last_target_attack_kind: String = ""
var native_attack_actor: TextureRect
var native_attack_texture: Texture2D
var native_attack_position: Vector2
var native_attack_size: Vector2
var native_hit_active: bool = false
var last_target_hit_kind: String = ""
var native_hit_actor: TextureRect
var native_hit_texture: Texture2D
var native_hit_position: Vector2
var native_hit_size: Vector2

# v1.36 整改04：真实 Tween/Timer 引用跟踪（非硬编码计数），并按注册表 cancel_policy 驱动取消。
# 每个活动 Tween/Timer 登记其所属时间轴 timeline_id；生产事件站点（cancel_battle=战斗取消事件、
# _apply_current_map=地图切换事件）按 timeline_cancelled_by(timeline_id, event) 查询策略后决定取消行为。
# 整改09：TIMELINE_FRAMES 为四个战斗时间轴（player_attack/normal_monster_attack/boss_attack/
# boss_hit）的帧数据源——生产动画播放（_play_player_attack/_play_target_attack/_play_target_hit）
# 与测试确定性推进共用统一生产调度器 TimelineScheduler（scripts/timeline_scheduler.gd）。
# player_motion 由 main_original.gd 生产帧表（player_idle_frames/player_walk_frames）覆盖。
const TIMELINE_REGISTRY_PATH := "res://docs/native_timeline_registry.json"
const EVENT_BATTLE_CANCEL := "battle_cancel"
const EVENT_MAP_CHANGE := "map_change"
const DEFAULT_TIMELINE_ID := "battle_feedback"  # 未在注册表中的战斗反馈（浮动文字/淡出），默认 on_battle_cancel
const NATIVE_FPS := 12  # SWF 根帧率

# 帧状态表（与 docs/native_timeline_registry.json frames 一致；size=Vector2.ZERO 表示不改节点 size；
# texture="" 表示不换图（single_bitmap）；fallback 为 once_restore 结束点恢复帧）。
const TIMELINE_FRAMES := {
	"player_attack": {
		"frames": [
			{"res": "res://assets/extracted/images/image_0503.png", "offset": Vector2(18, -4), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
			{"res": "res://assets/extracted/images/image_0505.png", "offset": Vector2(18, -4), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
			{"res": "res://assets/extracted/images/image_0507.png", "offset": Vector2(18, -4), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
			{"res": "res://assets/extracted/images/image_0509.png", "offset": Vector2(18, -4), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
		],
		"fallback": "res://assets/extracted/images/image_0455.png",
	},
	"normal_monster_attack": {
		"frames": [
			{"res": "", "offset": Vector2(-5, 0), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
			{"res": "", "offset": Vector2(0, 0), "dur": 1, "size": Vector2.ZERO, "anchor": "top_left"},
		],
		"fallback": "",
	},
	"boss_attack": {
		"frames": [
			{"res": "res://assets/extracted/images/image_0127.png", "offset": Vector2(-33, -42), "dur": 1, "size": Vector2(186, 173), "anchor": "top_left"},
			{"res": "res://assets/extracted/images/image_0129.png", "offset": Vector2(-33, -42), "dur": 1, "size": Vector2(186, 173), "anchor": "top_left"},
		],
		"fallback": "res://assets/extracted/images/image_1072.png",
	},
	"boss_hit": {
		# sprite134 帧1-2 站立（char98）、帧3-4 受击（shape133）——时间轴 t=0 站立、2/12s 受击
		"frames": [
			{"res": "res://assets/extracted/images/image_1072.png", "offset": Vector2(0, 0), "dur": 2, "size": Vector2(101, 132), "anchor": "top_left"},
			{"res": "res://assets/extracted/derived/boss_hit_native.png", "offset": Vector2(0, -7), "dur": 2, "size": Vector2(123, 148), "anchor": "top_left"},
		],
		"fallback": "res://assets/extracted/images/image_1072.png",
	},
}

var _active_tweens: Array = []  # [{tween, timeline_id, cleanup}]
var _active_timers: Array = []  # [{timer, timeline_id}]
var _timeline_policies: Dictionary = {}  # timeline_id -> cancel_policy（生产启动时从注册表读取）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 24
	_build_enemy_panel()
	_load_timeline_policies()


## 生产读取注册表 cancel_policy（docs/native_timeline_registry.json）。
## 文件缺失/解析失败时回退默认 on_battle_cancel（战斗时间轴语义），并告警。
func _load_timeline_policies() -> void:
	_timeline_policies.clear()
	var f := FileAccess.open(TIMELINE_REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_warning("timeline registry missing, cancel_policy falls back to on_battle_cancel: " + TIMELINE_REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is not Dictionary:
		push_warning("timeline registry parse failed, cancel_policy falls back to on_battle_cancel")
		return
	for tl in (parsed as Dictionary).get("timelines", []):
		_timeline_policies[str(tl.get("timeline_id", ""))] = str(tl.get("cancel_policy", "on_battle_cancel"))


## 查询生产注册的 cancel_policy（注册表读取，未知时间轴回退 on_battle_cancel）。
func timeline_cancel_policy(timeline_id: String) -> String:
	return str(_timeline_policies.get(timeline_id, "on_battle_cancel"))


## 策略语义：on_battle_cancel 由 battle_cancel 事件取消；on_map_change 由 map_change 事件取消。
func timeline_cancelled_by(timeline_id: String, event_name: String) -> bool:
	var policy := timeline_cancel_policy(timeline_id)
	if event_name == EVENT_BATTLE_CANCEL:
		return policy == "on_battle_cancel"
	if event_name == EVENT_MAP_CHANGE:
		return policy == "on_map_change"
	return false


func _build_enemy_panel() -> void:
	# The native monster clip carries a narrow 80x8 HP strip above the sprite.
	# Plain color rectangles avoid Godot theme minimums changing that exact size.
	enemy_panel = Control.new()
	enemy_panel.size = Vector2(80, 8)
	enemy_panel.custom_minimum_size = Vector2(80, 8)
	enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := ColorRect.new()
	border.color = Color("d7d7d7")
	border.position = Vector2.ZERO
	border.size = Vector2(80, 8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.add_child(border)
	var track := ColorRect.new()
	track.color = Color("111111")
	track.position = Vector2(1, 1)
	track.size = Vector2(78, 6)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.add_child(track)
	enemy_hp = ColorRect.new()
	enemy_hp.color = Color("e32929")
	enemy_hp.position = Vector2(1, 1)
	enemy_hp.size = Vector2(78, 6)
	enemy_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.add_child(enemy_hp)
	add_child(enemy_panel)
	enemy_panel.hide()

func is_active() -> bool:
	return session != null and not session.finished


func can_change_pet_configuration() -> bool:
	return not busy


func commit_active_health() -> void:
	if is_active():
		GameState.commit_battle_health(int(session.player_hp), session.pet_states)


func refresh_player_configuration() -> void:
	if not is_active():
		return
	session.refresh_player_configuration(GameState.get_player_stats())
	_refresh_battle_hud()


func engage(monster_id: String, actor: TextureRect, label: Label = null, skill_id: String = "") -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var player_stats := GameState.get_player_stats()
	if int(player_stats.get("current_hp", 0)) <= 0:
		message_changed.emit("人物没有生命值，请先使用果子恢复后再战斗。")
		return false
	if session != null and not session.finished:
		if active_monster_id != monster_id or target_actor != actor:
			message_changed.emit("正在攻击%s，请先结束当前战斗。" % active_monster_name)
			return false
		if busy:
			return true
		_attack(skill_id)
		return true
	if busy:
		return true
	if session != null:
		return true
	session = BattleSession.new(monster_id, player_stats, 0, GameState.battle_modifiers(monster_id))
	if session.monster.is_empty():
		session = null
		message_changed.emit("找不到该怪物的战斗数据。")
		return false
	active_monster_id = monster_id
	active_monster_name = str(session.monster.get("name", monster_id))
	target_actor = actor
	target_label = label
	target_label_was_visible = is_instance_valid(label) and label.visible
	last_attack_skill_id = ""
	# v1.37：新战斗 session（FeedbackService 唯一反馈通道；cancel/结束/切图后旧 session 事件被拒）。
	feedback_session_id = FeedbackService.begin_session()
	_position_enemy_panel()
	_refresh_battle_hud()
	enemy_panel.show()
	player_hp_changed.emit(int(session.player_hp), int(session.player_stats.get("max_hp", 1)))
	var control_hint := "左键继续攻击"
	if not GameState.skill_service.learned_active_skills(GameState.learned_skills).is_empty():
		control_hint += "，右键施放最强主动技能"
	message_changed.emit("遭遇%s：%s。敌人会先攻击合体幻兽，再攻击人物。" % [active_monster_name, control_hint])
	_attack(skill_id)
	return true

func cancel_battle() -> void:
	# battle_cancel 事件：取消注册表中 cancel_policy=on_battle_cancel 的时间轴活动。
	# 生产事件调用链：cancel_battle()（战斗取消/地图切换 _rebuild_map_actors）。
	_force_restore_target_hit()
	_force_restore_target_attack()
	_kill_active_tweens(EVENT_BATTLE_CANCEL)
	_clear_active_timers(EVENT_BATTLE_CANCEL)
	attack_sequence += 1
	busy = false
	session = null
	active_monster_id = ""
	active_monster_name = ""
	last_attack_skill_id = ""
	target_actor = null
	target_label = null
	target_label_was_visible = false
	native_attack_active = false
	enemy_panel.hide()
	# v1.37：战斗取消 -> 旧 session 事件全部失效（延迟反馈被 FEEDBACK_STALE_SESSION_EVENT 拒绝）。
	FeedbackService.end_session(feedback_session_id)
	GameState.abandon_active_arena_match("cancel")


## map_change 事件处理器（整改06）：真实地图切换（main_original._apply_current_map）调用，
## 取消注册表中 cancel_policy=on_map_change 的时间轴活动资源（player_motion 等）——
## 真正 stop/kill 并解除跟踪，与 battle_cancel 事件（cancel_battle）语义分离。
func handle_map_change() -> void:
	_kill_active_tweens(EVENT_MAP_CHANGE)
	_clear_active_timers(EVENT_MAP_CHANGE)
	# v1.37：地图切换 -> 旧 session 反馈失效（延迟反馈不得在新地图产生）。
	FeedbackService.end_session(feedback_session_id)


# --- v1.36 整改04：真实 Tween/Timer 跟踪（带 timeline_id 与清理回调）---

## 创建并登记一个 Tween。timeline_id 决定取消策略（timeline_cancelled_by 查询注册表 cancel_policy）。
## cleanup 为可选清理回调：Tween 被 kill 时执行（如浮动文字的 label.queue_free），正常完成时不执行。
func _create_tracked_tween(actor: CanvasItem, timeline_id: String = DEFAULT_TIMELINE_ID, cleanup: Callable = Callable()) -> Tween:
	var tween := actor.create_tween()
	_active_tweens.append({"tween": tween, "timeline_id": timeline_id, "cleanup": cleanup})
	# 整改12：finished 连接绑定 WeakRef（不持强引用），避免 bind(tween) 自引用循环导致
	# tween/sched 永不释放（WeakRef 释放验证失败）。
	tween.finished.connect(_untrack_tween.bind(weakref(tween)))
	return tween


func _untrack_tween(twr) -> void:
	var tween = twr.get_ref() if twr is WeakRef else twr
	for i in range(_active_tweens.size() - 1, -1, -1):
		if _active_tweens[i].get("tween") == tween:
			_active_tweens.remove_at(i)


## 可取消等待：创建 Timer 节点（可 stop，可验证），轮询直到触发或被取消。
## 事件取消 -> _clear_active_timers stop() 全部 Timer -> is_stopped()=true -> 协程循环退出
## -> queue_free 释放节点（协程不悬挂）。调用方随后检查 attack_sequence 判断是否被取消。
func _cancellable_wait(seconds: float, timeline_id: String = DEFAULT_TIMELINE_ID) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	timer.autostart = true
	add_child(timer)
	_active_timers.append({"timer": timer, "timeline_id": timeline_id})
	while is_instance_valid(timer) and not timer.is_stopped():
		await get_tree().process_frame
	if is_instance_valid(timer):
		timer.queue_free()
	for i in range(_active_timers.size() - 1, -1, -1):
		if _active_timers[i].get("timer") == timer:
			_active_timers.remove_at(i)


## 按事件策略 kill 活动 Tween，并执行其清理回调（kill 掉的 Tween 不再触发自身 finished 回调）。
## 整改05：仅移除实际 kill 的条目；不匹配当前事件策略的资源保留跟踪（不得因 clear 丢跟踪）。
func _kill_active_tweens(event_name: String = EVENT_BATTLE_CANCEL) -> void:
	var remaining: Array = []
	for entry in _active_tweens:
		var tid: String = str(entry.get("timeline_id", DEFAULT_TIMELINE_ID))
		if not timeline_cancelled_by(tid, event_name):
			remaining.append(entry)
			continue
		var tween: Variant = entry.get("tween")
		if tween is Tween and is_instance_valid(tween):
			(tween as Tween).kill()
		var cleanup: Callable = entry.get("cleanup", Callable())
		if cleanup.is_valid():
			cleanup.call()
	_active_tweens = remaining


## 按事件策略真正停止活动 Timer（is_stopped() 变为 true，可验证），并释放引用。
## 整改05：仅移除实际 stop 的条目；不匹配当前事件策略的 Timer 保留跟踪。
func _clear_active_timers(event_name: String = EVENT_BATTLE_CANCEL) -> void:
	var remaining: Array = []
	for entry in _active_timers:
		var tid: String = str(entry.get("timeline_id", DEFAULT_TIMELINE_ID))
		if not timeline_cancelled_by(tid, event_name):
			remaining.append(entry)
			continue
		var timer: Variant = entry.get("timer")
		if timer is Timer and is_instance_valid(timer):
			(timer as Timer).stop()
	_active_timers = remaining


## 真实活动 Tween 数（仅计仍有效且 running 的）。
func active_tween_count() -> int:
	var count: int = 0
	for entry in _active_tweens:
		var tween: Variant = entry.get("tween")
		if tween is Tween and is_instance_valid(tween) and (tween as Tween).is_running():
			count += 1
	return count


## 真实活动 Timer 数（仅计仍有效且未停止的 Timer 节点；cancel 后 stop() 使 is_stopped()=true）。
func active_timer_count() -> int:
	var count: int = 0
	for entry in _active_timers:
		var timer: Variant = entry.get("timer")
		if timer is Timer and is_instance_valid(timer) and not (timer as Timer).is_stopped():
			count += 1
	return count


## 测试钩子：返回当前活动 Timer 节点的真实引用（未停止的），供测试在 cancel 前保存并断言 is_stopped()。
func test_get_active_timers() -> Array:
	var result: Array = []
	for entry in _active_timers:
		var timer: Variant = entry.get("timer")
		if timer is Timer and is_instance_valid(timer) and not (timer as Timer).is_stopped():
			result.append(timer)
	return result


## 测试钩子：当前场景树中残留的浮动文字 Label 数量（生产 _float_text 直接 add_child 到控制器）。
func test_count_float_labels() -> int:
	var count: int = 0
	for child in get_children():
		if child is Label:
			count += 1
	return count


# --- v1.36 整改08：生产时间轴播放（生产播放与确定性验证共用同一状态转换函数）---

## 测试 override 注入的帧表（负向验证用：篡改 duration 必须被同一生产验证器捕获）。
var _frame_table_override: Dictionary = {}


## 生产帧表读取：override 优先（测试注入），否则 TIMELINE_FRAMES。
func _frames_for(timeline_id: String) -> Array:
	if _frame_table_override.has(timeline_id):
		return _frame_table_override[timeline_id]
	return (TIMELINE_FRAMES.get(timeline_id, {}) as Dictionary).get("frames", [])


## 统一生产播放驱动（整改09/10/11）：生产调度器 + Tween 排程。
## 排程（无额外 duration 段）：t=0 帧0 已在调度器构造时应用；随后按帧表顺序
## 每帧等待 current_hold（dur/NATIVE_FPS）后 advance（应用下一帧）；末帧等待后
## advance 触发 once_restore（精确恢复原状态）。
## 整改10：tracked Tween 注册时传入 Scheduler 取消 cleanup——Tween 被 battle_cancel/
## map_change 等 kill 时执行 sched.cancel()（幂等 restore），保证取消后精确恢复。
## 整改11：_active_schedulers 仅保存**活动** Scheduler（WeakRef），自然完成（finished）与
## 取消（cleanup）时解除引用；_drive_scheduler 返回包含 Scheduler 与真实 Tween 的生产 handle。
var _active_schedulers: Array = []  # 仅活动 Scheduler 的 WeakRef（注册槽）
var _last_handle: Dictionary = {}  # 活动 handle（整改12：sched/tween 结束或 untrack 时清空，不保留永久强引用）
var _scheduler_cleanup_enabled: bool = true
var _scheduler_untrack_enabled: bool = true


## 返回生产 handle（整改11/12）：{scheduler, tween, timeline_id}——包含真实 Tween，
## 测试可对 handle["tween"] 做确定性推进（tween.custom_step）驱动真实生产排程。
## 整改12：handle 是**活动** handle——sched 自然完成/cancel/battle_cancel/map_change（untrack）时
## 若匹配当前 Scheduler 则清空，不保留已结束 Scheduler/Tween 的永久强引用。
func _drive_scheduler(sched, timeline_id: String) -> Dictionary:
	var handle: Dictionary = {"scheduler": sched, "tween": null, "timeline_id": timeline_id}
	_last_handle = handle
	var cleanup := func() -> void:
		if _scheduler_cleanup_enabled:
			sched.cancel()
		if _scheduler_untrack_enabled:
			_untrack_scheduler(sched)
	var tween := _create_tracked_tween(sched.node as CanvasItem, timeline_id, cleanup)
	handle["tween"] = tween
	_register_scheduler(sched)
	# 整改12：finished 连接绑定 WeakRef（不持 sched 强引用），避免连接阻止 sched 释放
	tween.finished.connect(_untrack_scheduler.bind(weakref(sched)))  # 自然完成时解除引用
	for f in sched.frames:
		tween.tween_interval(float(int((f as Dictionary)["dur"])) / float(NATIVE_FPS))
		tween.tween_callback(sched.advance)
	return handle


## 登记活动 Scheduler（WeakRef——不持有强引用，销毁后自然消失）。
func _register_scheduler(sched) -> void:
	_active_schedulers.append(weakref(sched))


## 解除 Scheduler 引用（自然完成 / cancel / battle_cancel / map_change 后调用）。
## 参数可为 WeakRef（finished 连接）或 Scheduler 本身（cleanup/测试清理）。
## 整改12：若活动 handle 匹配当前 Scheduler，一并清空（不保留已结束对象的强引用）。
func _untrack_scheduler(wr) -> void:
	var sched = wr.get_ref() if wr is WeakRef else wr
	if sched == null:
		return
	for i in range(_active_schedulers.size() - 1, -1, -1):
		var swr: WeakRef = _active_schedulers[i]
		if is_instance_valid(swr) and swr.get_ref() == sched:
			_active_schedulers.remove_at(i)
	if not _last_handle.is_empty() and _last_handle.get("scheduler") == sched:
		_last_handle = {}


## 当前有效 Scheduler 数（整改12）：注册槽中 WeakRef 仍有效的调度器数。
## 自然完成（finished->untrack）与取消（cleanup->untrack）后解除引用回到 0。
func active_scheduler_count() -> int:
	var count: int = 0
	for wr in _active_schedulers:
		if is_instance_valid(wr) and wr.get_ref() != null:
			count += 1
	return count


## 注册数组实际槽位数（整改12）：包括已失效 WeakRef 的残留槽——泄漏检测用
## （untrack 禁用时槽残留被 SCHEDULER_REFERENCE_LEAK 命中）。
func tracked_scheduler_slot_count() -> int:
	return _active_schedulers.size()


## 是否仍有活动 handle（整改12）：handle 非空且指向未 ended 的 Scheduler。
func has_active_scheduler_handle() -> bool:
	if _last_handle.is_empty():
		return false
	var s = _last_handle.get("scheduler")
	return s != null and not s.ended


## 测试钩子：最近一次 _drive_scheduler 的生产 handle（与真实 _play_* 链路同一对象）。
func test_last_handle() -> Dictionary:
	return _last_handle


## 测试钩子：最近一次 _drive_scheduler 启动的生产调度器（与真实 _play_* 链路同一对象）。
func test_last_scheduler():
	if _last_handle.is_empty():
		return null
	return _last_handle.get("scheduler")


## 测试开关：禁用 Scheduler 取消 cleanup（取消负向验证——恢复缺失必须被验证器捕获）。
func test_set_scheduler_cleanup_enabled(enabled: bool) -> void:
	_scheduler_cleanup_enabled = enabled


## 测试开关：禁用 Scheduler untrack（引用泄漏负向验证——SCHEDULER_REFERENCE_LEAK）。
func test_set_scheduler_untrack_enabled(enabled: bool) -> void:
	_scheduler_untrack_enabled = enabled


## 确定性：t 秒时刻的帧索引（12fps；帧 i 占 [start_i, end_i)，end_i = start_i + dur_i/12）。
## 精确边界属于新帧（t=end_i -> 帧 i+1）。超出总时长返回 -1（已结束）。
## tick 与 acc 均以"帧数"为单位（t*12 vs 累计 dur），避免跨单位比较。
## 与生产播放共用 _frames_for（含 override），负向篡改同样被本函数反映。
func test_timeline_frame_index_at(timeline_id: String, t: float) -> int:
	var frames := _frames_for(timeline_id)
	if frames.is_empty() or t < 0.0:
		return -1
	var tick: float = t * float(NATIVE_FPS)
	var acc: float = 0.0
	for i in range(frames.size()):
		acc += float(int((frames[i] as Dictionary)["dur"]))
		if tick < acc - 0.000001:
			return i
	return -1


## 测试注入帧表覆盖（负向验证：篡改 duration/边界）。
func test_set_frame_table_override(timeline_id: String, frames: Array) -> void:
	_frame_table_override[timeline_id] = frames


func test_clear_frame_table_override(timeline_id: String) -> void:
	_frame_table_override.erase(timeline_id)


func _attack(skill_id: String = "") -> void:
	if session == null or session.finished or busy:
		return
	if not skill_id.is_empty() and int(GameState.learned_skills.get(skill_id, 0)) <= 0:
		message_changed.emit("尚未学会该主动技能。")
		return
	var effective_skill_id := skill_id
	var stamina_fallback := false
	if not skill_id.is_empty():
		var stamina_result := GameState.try_use_skill_stamina(skill_id)
		if not bool(stamina_result.get("success", false)):
			effective_skill_id = ""
			stamina_fallback = true
	last_attack_skill_id = effective_skill_id
	busy = true
	attack_sequence += 1
	var sequence := attack_sequence
	FeedbackService.set_attack_sequence(sequence)
	# v1.37 整改01：新回合 attack_sequence 建立后才能发出技能事件（技能事件携带当前回合）。
	if not skill_id.is_empty():
		if stamina_fallback:
			# 体力不足降级普通攻击——只产生 skill_failed_stamina，不产生 skill_started/skill_finished；
			# 体力已在 try_use_skill_stamina 内只扣一次。
			FeedbackService.emit("skill_failed_stamina", {"attack_sequence": sequence, "skill_id": skill_id})
		else:
			# 主动技能成功——skill_started + SWF 证据声音
			# （sprite523 帧27 飞天连斩=sound_0518 / 帧63 星魔剑=sound_0520）。
			var skill_sound := ""
			if effective_skill_id == "flying_slash":
				skill_sound = "skill_flying_slash"
			elif effective_skill_id == "star_sword":
				skill_sound = "skill_star_sword"
			FeedbackService.emit("skill_started", {"attack_sequence": sequence, "skill_id": effective_skill_id, "sound_name": skill_sound})
	var multiplier := GameState.skill_damage_multiplier(effective_skill_id)
	FeedbackService.emit("player_attack_started", {
		"attack_sequence": sequence,
		"skill_id": effective_skill_id,
		"sound_name": "attack",  # 基线声音保持（sound_0014；导出名=传送.wav，gap 注记见注册表）
	})
	# v1.37 整改01：dodge 判定强制 roll 测试钩子（-1.0 = 生产随机；测试注入 [0,1) 使闪避确定性）。
	var result: Dictionary = session.perform_turn(1.0, 1.0, test_dodge_roll, multiplier)
	GameState.commit_battle_health(int(session.player_hp), session.pet_states)
	var dead_pet_ids: Array = result.get("pet_deaths", [])
	var pet_penalty: Dictionary = GameState.apply_pet_death_penalty(dead_pet_ids)
	if not dead_pet_ids.is_empty():
		# Drop the defeated pet's merged attack and defense before the next turn.
		session.refresh_player_configuration(GameState.get_player_stats())
	if bool(pet_penalty.get("forced_retreat", false)):
		session.force_defeat("pet_luck_exhausted")
	# v1.37：命中反馈（攻击开始先于命中，顺序由 FeedbackService 校验）。
	FeedbackService.emit("monster_hit", {"attack_sequence": sequence, "damage": int(result.get("player_damage", 0))})
	_play_player_attack(sequence)
	# v1.37：攻击动画帧反馈（生产攻击动画起点）。
	FeedbackService.emit("player_attack_frame", {"attack_sequence": sequence, "skill_id": effective_skill_id})
	_play_target_hit(sequence)
	_float_damage(target_actor.position + Vector2(target_actor.size.x * 0.5, 0), int(result.get("player_damage", 0)), Color("fff06a"))
	if int(result.get("pet_damage", 0)) > 0:
		_float_damage(target_actor.position + Vector2(target_actor.size.x * 0.5 + 24, 18), int(result.get("pet_damage", 0)), Color("67e8ff"), "幻兽 ")
	var monster_acted := str(result.get("monster_target", "none")) != "none"
	if monster_acted:
		# v1.37：怪物攻击反馈 + SWF 证据声音（普通怪 sprite124 帧7=sound_0123 / Boss sprite135 帧6=sound_0132）。
		FeedbackService.emit("monster_attack_started", {
			"attack_sequence": sequence,
			"sound_name": "monster_attack_boss" if _uses_native_boss_clip(target_actor) else "monster_attack_normal",
		})
		var monster_response_delay := 0.35 if _uses_native_boss_clip(target_actor) else 0.24
		await _cancellable_wait(monster_response_delay)
		if sequence != attack_sequence:
			return
		_play_target_attack(sequence)
		if int(result.get("monster_damage", 0)) > 0:
			if str(result.get("monster_target", "")) == "pet":
				_float_text(player_actor.position + Vector2(player_actor.size.x * 0.5, -8), "%s -%d" % [str(result.get("target_pet_name", "幻兽")), int(result.get("pet_damage_taken", 0))], Color("ff9f69"))
			else:
				_float_damage(player_actor.position + Vector2(player_actor.size.x * 0.5, 10), int(result.get("player_damage_taken", 0)), Color("ff6969"))
				# v1.37：受击反馈（dodge 路径与幻兽承伤路径不产生 player_hit）。
				FeedbackService.emit("player_hit", {"attack_sequence": sequence, "damage": int(result.get("monster_damage", 0))})
		elif bool(result.get("dodged", false)):
			_float_text(player_actor.position + Vector2(player_actor.size.x * 0.5, 10), "闪避", Color("7dff8a"))
			FeedbackService.emit("dodge", {"attack_sequence": sequence})
		FeedbackService.emit("monster_attack_finished", {"attack_sequence": sequence})
	_refresh_battle_hud()
	var skill_prefix := ""
	if stamina_fallback:
		skill_prefix = "体力不足，技能退化为普通攻击　"
	elif not effective_skill_id.is_empty():
		skill_prefix = "%s　" % str(GameState.skill_service.skills[effective_skill_id].name)
	var target_text := ""
	if str(result.get("monster_target", "")) == "pet":
		target_text = "%s受到%d伤害" % [str(result.get("target_pet_name", "幻兽")), int(result.get("pet_damage_taken", 0))]
	elif bool(result.get("dodged", false)):
		target_text = "人物闪避"
	else:
		target_text = "人物受到%d伤害" % int(result.get("player_damage_taken", 0))
	var battle_message := "%s第%d回合：人物与合体幻兽造成%d伤害，%s。" % [
		skill_prefix,
		int(result.get("turn", 0)),
		int(result.get("player_damage", 0)),
		target_text,
	]
	if not dead_pet_ids.is_empty():
		battle_message += " 幻兽死亡，幸运值-%d。" % int(pet_penalty.get("luck_lost", 0))
		if bool(pet_penalty.get("forced_retreat", false)):
			battle_message += " 幸运值已耗尽，自动退出战斗。"
	message_changed.emit(battle_message)
	await _cancellable_wait(0.33 if monster_acted else 0.28)
	if sequence != attack_sequence:
		return
	# v1.37 整改01：技能完成反馈（仅技能成功施放；与 skill_started 同一 session/回合，
	# 先于 player_attack_finished）。体力不足降级路径不产生 skill_finished。
	if not stamina_fallback and not effective_skill_id.is_empty():
		FeedbackService.emit("skill_finished", {"attack_sequence": sequence, "skill_id": effective_skill_id})
	# v1.37：攻击完成反馈（攻击开始先于命中与完成，FeedbackService 顺序校验）。
	FeedbackService.emit("player_attack_finished", {"attack_sequence": sequence, "skill_id": effective_skill_id})
	busy = false
	if session != null and session.finished:
		if session.victory:
			# v1.37：怪物死亡反馈（死亡后不得再产生怪物攻击，顺序校验保证）。
			FeedbackService.emit("monster_death", {"attack_sequence": sequence})
			await _finish_victory()
		else:
			await _finish_defeat()

func _finish_victory() -> void:
	var defeated_actor := target_actor
	var defeated_label := target_label
	var defeated_label_was_visible := target_label_was_visible
	var defeated_id := active_monster_id
	# v1.37：胜利反馈（victory 先于 reward_queued，顺序校验保证）。
	FeedbackService.emit("victory", {"sound_name": "victory"})
	GameState.commit_battle_health(int(session.player_hp), session.pet_states)
	var rewards: Dictionary = session.victory_payload()
	var campaign_drop := GameState.roll_final_campaign_drop(defeated_id)
	if not campaign_drop.is_empty():
		var reward_drops: Array = rewards.get("drops", [])
		reward_drops.append(campaign_drop)
		rewards["drops"] = reward_drops
	var story_result: Dictionary = GameState.apply_victory_rewards(rewards)
	var drops: Array = rewards.get("drops", [])
	GameState.queue_loot(drops)
	# v1.37：奖励入队反馈（在 claim_loot 前，保证 reward_queued 先于 loot_claimed）。
	FeedbackService.emit("reward_queued", {"item_count": drops.size()})
	var claimed_names: Array[String] = []
	for item_id: Variant in drops:
		var normalized := str(item_id)
		if GameState.claim_loot(normalized):
			claimed_names.append(str(GameState.get_item_definition(normalized).get("name", normalized)))
	var reward_text := "胜利！经验%d，军功%d，功勋%d，魔石%d。" % [
		int(rewards.get("experience", 0)),
		int(rewards.get("military_merit", 0)),
		int(rewards.get("nobility_merit", 0)),
		int(rewards.get("magic_stones", 0)),
	]
	if not claimed_names.is_empty():
		reward_text += " 获得：" + "、".join(claimed_names)
	if not GameState.loot_queue.is_empty():
		reward_text += " 背包已满的物品保留在待领取队列。"
	if bool(story_result.get("triggered", false)):
		if str(story_result.get("event", "")) in ["final_campaign", "fuwa_beast"]:
			reward_text += " " + str(story_result.get("message", ""))
		else:
			reward_text += " 你击败了魔族高级将领并救出了国王！"
			if str(story_result.get("reward_type", "")) == "nobility_rank":
				reward_text += " 王国授予你“%s”爵位，请回皇宫询问最终战争策略。" % str(story_result.get("rank_name", "王"))
			else:
				reward_text += " 获得200,000魔石，请回皇宫询问最终战争策略。"
	message_changed.emit(reward_text)
	_force_restore_target_hit()
	_force_restore_target_attack()
	if is_instance_valid(defeated_actor):
		defeated_actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		defeated_actor.hide()
	if is_instance_valid(defeated_label):
		defeated_label.hide()
	var player_stats := GameState.get_player_stats()
	player_hp_changed.emit(int(player_stats.current_hp), int(player_stats.max_hp))
	enemy_panel.hide()
	session = null
	active_monster_id = ""
	active_monster_name = ""
	last_attack_skill_id = ""
	target_actor = null
	target_label = null
	target_label_was_visible = false
	# v1.37 整改04：发外部同步信号前保存不可变局部值——旧流程结束时只结束这个局部 ID，
	# 不读取可能被 battle_finished 监听器（同步开新战斗）覆盖的成员 feedback_session_id。
	var finished_feedback_session_id := feedback_session_id
	battle_finished.emit(defeated_id, true)
	# v1.37：胜利结束 session（后续旧 session 延迟事件被拒）。
	FeedbackService.end_session(finished_feedback_session_id)
	await _cancellable_wait(2.2)
	if is_instance_valid(defeated_actor):
		defeated_actor.modulate = Color.WHITE
		defeated_actor.mouse_filter = Control.MOUSE_FILTER_STOP
		defeated_actor.show()
	if is_instance_valid(defeated_label) and defeated_label_was_visible:
		defeated_label.show()

func _finish_defeat() -> void:
	var defeated_id := active_monster_id
	var reason := str(session.defeat_reason)
	GameState.commit_battle_health(int(session.player_hp), session.pet_states)
	var defeat_message := "幸运值已经耗尽，战斗自动结束，已返回卡萨诺城。"
	if reason == "player_death" or int(session.player_hp) <= 0:
		var penalty := GameState.apply_player_defeat_penalty()
		defeat_message = "战斗失败：幸运值-%d，当前等级经验-%d，人物生命归零。已返回卡萨诺城。" % [int(penalty.luck_lost), int(penalty.experience_lost)]
		# v1.37：玩家死亡反馈（每场战斗一次，deathman.wav；幸运耗尽退出不产生玩家死亡事件）。
		FeedbackService.emit("player_death", {"sound_name": "death"})
	else:
		# v1.37 整改01：战斗退出（幸运耗尽）反馈——唯一反馈通道语义事件，不再直接调用 AudioService。
		FeedbackService.emit("battle_retreat", {"sound_name": "death"})
	message_changed.emit(defeat_message)
	if is_instance_valid(player_actor):
		var fade_seq := attack_sequence
		# 被取消时 cleanup 恢复 modulate（kill 不触发 finished，轮询由 is_running() 接管，不悬挂）。
		var fade := _create_tracked_tween(player_actor, DEFAULT_TIMELINE_ID, func() -> void:
			if is_instance_valid(player_actor):
				player_actor.modulate = Color.WHITE
		)
		fade.tween_property(player_actor, "modulate:a", 0.25, 0.25)
		while is_instance_valid(fade) and fade.is_running():
			await get_tree().process_frame
		if not is_instance_valid(fade) or fade_seq != attack_sequence:
			return  # 被取消（kill 后 is_running()=false 且 attack_sequence 已递增）：不再继续
		player_actor.modulate = Color.WHITE
	var player_stats := GameState.get_player_stats()
	player_hp_changed.emit(int(player_stats.current_hp), int(player_stats.max_hp))
	enemy_panel.hide()
	session = null
	active_monster_id = ""
	active_monster_name = ""
	last_attack_skill_id = ""
	target_actor = null
	target_label = null
	target_label_was_visible = false
	var finished_feedback_session_id := feedback_session_id
	battle_finished.emit(defeated_id, false)
	# v1.37：失败结束 session（旧 session 事件被拒）。
	FeedbackService.end_session(finished_feedback_session_id)

func _position_enemy_panel() -> void:
	if not is_instance_valid(target_actor):
		return
	enemy_panel.position = Vector2(
		clampf(target_actor.position.x + target_actor.size.x * 0.5 - 40.0, 4.0, 616.0),
		clampf(target_actor.position.y - 13.0, 72.0, 468.0)
	)

func _refresh_battle_hud() -> void:
	if session == null:
		return
	var maximum := maxi(1, int(session.monster.get("max_hp", 1)))
	var ratio := clampf(float(session.monster_hp) / float(maximum), 0.0, 1.0)
	enemy_hp.size.x = 78.0 * ratio
	player_hp_changed.emit(int(session.player_hp), int(session.player_stats.get("max_hp", 1)))

func _play_player_attack(sequence: int) -> void:
	if not is_instance_valid(player_actor):
		return
	# 整改09：统一生产调度器（t=0 帧0；1/12 帧1；2/12 帧2；3/12 帧3；4/12 once_restore）。
	# 整改10：on_restore 为空——调度器快照负责精确恢复原 texture/position/size
	# （once_restore 恢复原状态，任务书 7.4；注册表 fallback_frame 保留为证据字段）。
	var sched = TimelineScheduler.new("player_attack", _frames_for("player_attack"), player_actor,
		player_actor.position, Callable(), sequence)
	_drive_scheduler(sched, "player_attack")


func _uses_native_boss_clip(actor: TextureRect) -> bool:
	if not is_instance_valid(actor) or actor.texture == null:
		return false
	var path := actor.texture.resource_path
	return path.ends_with("image_1072.png") or path.ends_with("image_0097.png")


func _play_target_hit(sequence: int) -> void:
	if not is_instance_valid(target_actor):
		return
	if not _uses_native_boss_clip(target_actor):
		# sprite124 has no hit label or alternate hit bitmap; native feedback is
		# the HP strip update and floating damage text only.
		last_target_hit_kind = "normal_damage_only"
		native_hit_active = false
		return
	var actor := target_actor
	native_hit_actor = actor
	native_hit_texture = actor.texture
	native_hit_position = actor.position
	native_hit_size = actor.size
	last_target_hit_kind = "boss_native_shape"
	native_hit_active = true
	# sprite134 帧1-2 站立（char98）、帧3-4 受击（shape133）——帧表顺序 [站立, 受击]（整改09 统一）。
	# 统一生产调度器：t=0 站立；2/12 受击；4/12 once_restore。
	var sched = TimelineScheduler.new("boss_hit", _frames_for("boss_hit"), actor,
		native_hit_position, _restore_target_hit.bind(actor, sequence), sequence)
	_drive_scheduler(sched, "boss_hit")


func _restore_target_hit(actor: TextureRect, sequence: int) -> void:
	if sequence != attack_sequence or native_hit_actor != actor or not is_instance_valid(actor):
		return
	actor.texture = native_hit_texture
	actor.position = native_hit_position
	actor.size = native_hit_size
	native_hit_actor = null
	native_hit_texture = null
	native_hit_active = false


func _force_restore_target_hit() -> void:
	if is_instance_valid(native_hit_actor):
		native_hit_actor.texture = native_hit_texture
		native_hit_actor.position = native_hit_position
		native_hit_actor.size = native_hit_size
	native_hit_actor = null
	native_hit_texture = null
	native_hit_active = false


func _play_target_attack(sequence: int) -> void:
	if not is_instance_valid(target_actor) or session == null:
		return
	_force_restore_target_hit()
	var actor := target_actor
	var original_position := actor.position
	var original_size := actor.size
	var original_texture := actor.texture
	native_attack_actor = actor
	native_attack_texture = original_texture
	native_attack_position = original_position
	native_attack_size = original_size
	native_attack_active = true
	if _uses_native_boss_clip(actor):
		# Native boss frames 6-10 use 186x173 bitmaps at (-65,-42.15);
		# the standing bitmap begins at x=-32, hence the relative (-33,-42) offset.
		# 整改09：统一生产调度器（t=0 帧0；1/12 帧1；2/12 once_restore）
		last_target_attack_kind = "boss_frames"
		var sched = TimelineScheduler.new("boss_attack", _frames_for("boss_attack"), actor,
			original_position, _restore_target_attack.bind(actor, original_texture, original_position, original_size, sequence), sequence)
		_drive_scheduler(sched, "boss_attack")
	else:
		# Native normal-monster frames 7-10 move the standing art five pixels left and back.
		# 整改09：SWF 证据为离散位置变化（sprite124 frame7 Move+HasMatrix translate=-5px 单帧位移，
		# 无补间证据）-> 按帧边界离散应用 offset；总时长 = 2 帧 × 1/12（两帧数据两段时长）。
		last_target_attack_kind = "normal_lunge"
		var sched2 = TimelineScheduler.new("normal_monster_attack", _frames_for("normal_monster_attack"), actor,
			original_position, _restore_target_attack.bind(actor, original_texture, original_position, original_size, sequence), sequence)
		_drive_scheduler(sched2, "normal_monster_attack")


func _restore_target_attack(actor: TextureRect, texture: Texture2D, position: Vector2, size: Vector2, sequence: int) -> void:
	if sequence != attack_sequence or not is_instance_valid(actor):
		return
	actor.texture = texture
	actor.position = position
	actor.size = size
	native_attack_active = false
	if native_attack_actor == actor:
		native_attack_actor = null
		native_attack_texture = null


func _force_restore_target_attack() -> void:
	if is_instance_valid(native_attack_actor):
		native_attack_actor.texture = native_attack_texture
		native_attack_actor.position = native_attack_position
		native_attack_actor.size = native_attack_size
	native_attack_actor = null
	native_attack_texture = null
	native_attack_active = false


func _float_damage(origin: Vector2, amount: int, color: Color, prefix: String = "-") -> void:
	_float_text(origin, "%s%d" % [prefix, amount], color)


func _float_text(origin: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = origin
	label.size = Vector2(110, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	# cleanup=label.queue_free：Tween 正常完成时由 chain 回调释放；被 kill 时由 _kill_active_tweens
	# 执行同一清理回调，保证取消战斗后浮动文字 Label 不残留。
	var tween := _create_tracked_tween(label, DEFAULT_TIMELINE_ID, label.queue_free)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", origin.y - 32.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)
