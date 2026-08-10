extends RefCounted
## v1.36 整改09：统一生产时间轴调度器。
## 生产动画播放（scene_battle_controller._play_player_attack/_play_target_attack/_play_target_hit）
## 与测试确定性推进（seek/advance）共用本调度对象——同一状态转换与排程语义。
##
## 离散帧排程（唯一语义，无额外 duration 段）：
##   t=0 立即应用 frame0 -> 等待 frame0.duration -> 应用 frame1 -> 等待 frame1.duration
##   -> ... -> 等待最后一帧 duration -> once_restore（position 回 base + on_restore 回调）。
##
## 帧表帧格式（与 TIMELINE_FRAMES 一致）：{res, offset: Vector2, dur, size: Vector2, anchor}。
## size=Vector2.ZERO 表示不改节点 size；res="" 表示不换图（single_bitmap）。

const NATIVE_FPS := 12


## 构造：保存原状态快照（texture/size，position 由 base 表示），立即应用 frame0（t=0）。
## frames 由调用方传入（生产帧表 TIMELINE_FRAMES 或测试注入）。
func _init(tl_id: String, frame_table: Array, target: CanvasItem, base_pos: Vector2, restore_cb: Callable = Callable(), seq: int = -1) -> void:
	timeline_id = tl_id
	frames = frame_table
	node = target
	base = base_pos
	on_restore = restore_cb
	sequence = seq
	# 原状态快照（取消/自然结束时精确恢复 texture/size；position 恢复 base）
	if is_instance_valid(node):
		if node is TextureRect:
			_snapshot_texture = (node as TextureRect).texture
			_snapshot_size = (node as TextureRect).size
	_apply(0)


var timeline_id: String = ""
var frames: Array = []
var node: CanvasItem
var base: Vector2
var on_restore: Callable = Callable()
var sequence: int = -1
var frame_index: int = -1
var ended: bool = false  # 自然结束（once_restore）或取消后为 true
var cancelled: bool = false  # 取消（cancel()）后为 true
var steps: int = 0  # 已推进的帧步数
var _snapshot_texture: Texture2D = null
var _snapshot_size: Vector2 = Vector2.ZERO


## 当前帧保持时长（秒）= duration_frames / NATIVE_FPS；ended 后为 0。
func current_hold() -> float:
	if ended or frame_index < 0 or frame_index >= frames.size():
		return 0.0
	return float(int((frames[frame_index] as Dictionary)["dur"])) / float(NATIVE_FPS)


## 时间轴总时长（秒）= Σ dur / NATIVE_FPS。
func total_duration() -> float:
	var acc: float = 0.0
	for f in frames:
		acc += float(int((f as Dictionary)["dur"])) / float(NATIVE_FPS)
	return acc


## 确定性：t 秒时刻应显示的帧索引（与生产排程同一语义：t=0 帧0；帧 i 占
## [start_i, end_i)，end_i = start_i + dur_i/12；精确边界属于新帧）。超出总时长返回 -1。
func seek_frame(t: float) -> int:
	if t < 0.0 or frames.is_empty():
		return -1
	var tick: float = t * float(NATIVE_FPS)
	var acc: float = 0.0
	for i in range(frames.size()):
		acc += float(int((frames[i] as Dictionary)["dur"]))
		if tick < acc - 0.000001:
			return i
	return -1


## 确定性推进（seek）：把调度器推进到 t 秒时刻（应用对应帧状态）；超出总时长则执行 once_restore。
## 整改11：ended/cancelled 后不得重新应用任何帧（幂等终止）。
func seek(t: float) -> void:
	if ended:
		return
	var idx := seek_frame(t)
	if idx < 0:
		_restore()
		return
	_apply(idx)


## 单步推进一帧（生产等待完成后调用）：应用 frame_index+1；已到末帧则执行 once_restore。
## 整改11：ended/cancelled 后不得重新应用任何帧（幂等终止）。
func advance() -> void:
	if ended:
		return
	steps += 1
	if frame_index + 1 < frames.size():
		_apply(frame_index + 1)
	else:
		_restore()


## 帧状态应用（唯一状态写入路径）：texture/position/size 写入生产节点。
## sequence>=0 时仅当 sequence==调用方当前序列才应用（生产攻击序列保护由调用方回调检查，
## 本调度器通过 sequence 参数在外部校验）。
func _apply(idx: int) -> void:
	frame_index = idx
	if not is_instance_valid(node):
		return
	var f: Dictionary = frames[idx]
	if node is CanvasItem:
		var res: String = str(f.get("res", ""))
		if node is TextureRect:
			var tr := node as TextureRect
			if res != "":
				tr.texture = load(res)
			tr.position = base + (f["offset"] as Vector2)
			var sz: Vector2 = f["size"]
			if sz != Vector2.ZERO:
				tr.size = sz


## 幂等 cancel()（整改10）：Tween 被 battle_cancel/map_change 等 kill 时由 tracked cleanup 调用。
## 自然结束（ended）或已取消（cancelled）后不再执行——只能 restore 一次。
func cancel() -> void:
	if ended or cancelled:
		return
	cancelled = true
	_restore()


## once_restore（自然结束）与 cancel() 共用的恢复路径：精确恢复原状态
## （position=base、size=快照、texture=快照——整改11：原 texture=null 时也精确恢复 null），
## 再执行 on_restore 回调（生产逻辑副作用，幂等重复恢复无害）。end 后再次调用直接返回（幂等）。
func _restore() -> void:
	if ended:
		return
	ended = true
	if is_instance_valid(node):
		node.position = base
		if node is TextureRect:
			var tr := node as TextureRect
			tr.texture = _snapshot_texture  # 可为 null（原 texture=null 精确恢复 null）
			tr.size = _snapshot_size
	if on_restore.is_valid():
		on_restore.call()
