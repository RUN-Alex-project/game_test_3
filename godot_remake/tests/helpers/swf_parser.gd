extends RefCounted
## v1.36 独立 SWF 证据解析器（整改05：完整引用链 + ColorTransform 实际参数 + RemoveObject2 + 帧序显示列表状态机 + 全文件递归 tag 统计 + 根移除 depth 匹配）。
## 解析 bitmap->shape fill->sprite 嵌套->根 placement 引用链，逐帧比较显示列表
## （保持/替换/删除、character、完整 matrix translate/scale/rotate、ColorTransform 实际参数）。
##
## 位序 MSB-first: PlaceObject2 HasCharacter=0x02, HasMatrix=0x04, HasColorTransform=0x08, Move=0x01。
## 全文件 tag 统计（递归进入全部 DefineSprite，整改05 修正口径）: PlaceObject(tag4)=0, RemoveObject(tag5)=0,
## PlaceObject2(tag26)=1577, RemoveObject2(tag28)=320, DefineSprite(tag39)=233。
## 复刻 work/find_swf_bitmap_shapes.py（shape fill）与 work/_v136_classify.py（完整 matrix + color + 根递归）。

const TAG_END := 0
const TAG_SHOW_FRAME := 1
const TAG_DEFINE_SHAPE := 2
const TAG_DEFINE_BITS_JPEG := 6
const TAG_DEFINE_SOUND := 14
const TAG_DEFINE_BITS_LOSSLESS := 20
const TAG_DEFINE_BITS_JPEG2 := 21
const TAG_DEFINE_SHAPE2 := 22
const TAG_PLACE_OBJECT_2 := 26
const TAG_REMOVE_OBJECT_2 := 28
const TAG_DEFINE_SHAPE3 := 32
const TAG_DEFINE_BITS_JPEG3 := 35
const TAG_DEFINE_BITS_LOSSLESS2 := 36
const TAG_DEFINE_SPRITE := 39
const COMPRESSION_DEFLATE := 1
const ROOT_ID := -1

var swf_path: String = ""
var signature: String = ""
var version: int = 0
var declared_length: int = 0
var decompressed_size: int = 0
var root_frame_count: int = 0
var root_frame_rate: float = 0.0
var parse_error: String = ""
var _loaded: bool = false

var sprite_frame_counts: Dictionary = {}
var bitmap_characters: Dictionary = {}
var shape_characters: Dictionary = {}
var shape_bitmap_fills: Dictionary = {}
var sprite_placements: Dictionary = {}  # sprite_id -> Array[placement]
var root_placements: Array = []
var root_removals: Array = []  # 根时间轴 RemoveObject2: [{depth, frame}]
var root_events: Array = []  # 根时间轴原始 tag 顺序事件流（place/remove，供显示列表状态机模拟）
var tag_distribution: Dictionary = {}  # tag code -> 出现次数（全文件）
var sound_definitions: Dictionary = {}  # sound_id -> {format, rate, sample_width, channels, sample_count}（v1.37 整改01）


func _init(path: String = "") -> void:
	if path != "":
		load_swf(path)


func load_swf(path: String) -> bool:
	swf_path = path
	sprite_frame_counts.clear()
	bitmap_characters.clear()
	shape_characters.clear()
	shape_bitmap_fills.clear()
	sprite_placements.clear()
	root_placements.clear()
	root_removals.clear()
	root_events.clear()
	tag_distribution.clear()
	sound_definitions.clear()
	parse_error = ""
	_loaded = false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		parse_error = "cannot open swf: " + path
		return false
	var raw: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 8:
		parse_error = "swf too small"
		return false
	signature = raw.slice(0, 3).get_string_from_ascii()
	version = raw[3]
	declared_length = raw.decode_u32(4)
	if signature != "CWS" and signature != "FWS":
		parse_error = "unsupported signature: " + signature
		return false
	var body: PackedByteArray
	if signature == "CWS":
		var compressed: PackedByteArray = raw.slice(8)
		if compressed.size() < 6:
			parse_error = "compressed body too small"
			return false
		var expected_size: int = declared_length - 8
		body = compressed.decompress(expected_size, COMPRESSION_DEFLATE)
		if body.size() != expected_size:
			parse_error = "zlib decompress failed"
			return false
	else:
		body = raw.slice(8)
	decompressed_size = body.size()
	_parse_body(body)
	_loaded = (parse_error == "")
	return _loaded


func _parse_body(body: PackedByteArray) -> void:
	var nbits: int = body[0] >> 3
	var root_start: int = (5 + 4 * nbits + 7) / 8 + 4
	if root_start >= 4 and root_start - 4 < body.size():
		root_frame_rate = float(body.decode_u16(root_start - 4) >> 8)
	if root_start >= 2 and root_start - 2 < body.size():
		root_frame_count = body.decode_u16(root_start - 2)
	var pos: int = root_start
	var body_size: int = body.size()
	var root_frame: int = 1
	while pos + 2 <= body_size:
		var header: int = body.decode_u16(pos)
		var code: int = header >> 6
		var length: int = header & 63
		pos += 2
		if length == 63:
			if pos + 4 > body_size:
				break
			length = body.decode_u32(pos)
			pos += 4
		var body_start: int = pos
		var body_end: int = body_start + length
		if body_end > body_size:
			break
		tag_distribution[code] = int(tag_distribution.get(code, 0)) + 1
		if code == TAG_END:
			break
		elif code == TAG_SHOW_FRAME:
			root_frame += 1
		elif code == TAG_PLACE_OBJECT_2 and length >= 3:
			var pl: Dictionary = _parse_place_object_2(body, body_start, length)
			pl["frame"] = root_frame
			root_placements.append(pl)
			# 整改08：记录 flags/has_character（HasCharacter=false 的 Move 更新不得覆盖当前 character）
			root_events.append({
				"type": "place", "frame": root_frame, "depth": int(pl["depth"]),
				"char": int(pl["character"]), "has_character": (int(pl["flags"]) & 0x02) != 0,
				"flags": int(pl["flags"]),
			})
		elif code == TAG_REMOVE_OBJECT_2 and length >= 2:
			var rem_depth: int = body.decode_u16(body_start)
			root_removals.append({"depth": rem_depth, "frame": root_frame})
			root_events.append({"type": "remove", "frame": root_frame, "depth": rem_depth})
		elif code == TAG_DEFINE_SOUND and length >= 7:
			# v1.37 整改01：DefineSound（tag14）——SoundId UI16；SoundFormat 4b；SoundRate 2b；
			# SoundSize 1b（0=8bit->1 字节 / 1=16bit->2 字节）；SoundType 1b（0=mono->1 / 1=stereo->2）；
			# SampleCount UI32。与 manifest/注册表三方比对用。
			var sound_id: int = body.decode_u16(body_start)
			var flags: int = body[body_start + 2]
			var rate: int = [5512, 11025, 22050, 44100][(flags >> 2) & 0x03]
			var sample_width: int = 1 + ((flags >> 1) & 0x01)
			var channels: int = 1 + (flags & 0x01)
			sound_definitions[sound_id] = {
				"format": flags >> 4,  # SWF SoundFormat 码（2=MP3）
				"rate": rate,
				"sample_width": sample_width,
				"channels": channels,
				"sample_count": body.decode_u32(body_start + 3),
			}
		elif code == TAG_DEFINE_SPRITE and length >= 4:
			var sid: int = body.decode_u16(body_start)
			var fc: int = body.decode_u16(body_start + 2)
			sprite_frame_counts[sid] = fc
			sprite_placements[sid] = _parse_sprite_timeline(body, body_start + 4, body_end)
		elif code in [TAG_DEFINE_BITS_JPEG, TAG_DEFINE_BITS_LOSSLESS, TAG_DEFINE_BITS_JPEG2, TAG_DEFINE_BITS_JPEG3, TAG_DEFINE_BITS_LOSSLESS2] and length >= 2:
			bitmap_characters[body.decode_u16(body_start)] = code
		elif code in [TAG_DEFINE_SHAPE, TAG_DEFINE_SHAPE2, TAG_DEFINE_SHAPE3] and length >= 2:
			var shape_id: int = body.decode_u16(body_start)
			shape_characters[shape_id] = code
			var fills: Array = _parse_shape_bitmap_fills(body, body_start, code)
			if not fills.is_empty():
				shape_bitmap_fills[shape_id] = fills
		pos = body_end


func _parse_sprite_timeline(body: PackedByteArray, start: int, end: int) -> Array:
	var placements: Array = []
	var frame: int = 1
	var pos: int = start
	while pos + 2 <= end:
		var header: int = body.decode_u16(pos)
		var code: int = header >> 6
		var length: int = header & 63
		pos += 2
		if length == 63:
			if pos + 4 > end:
				break
			length = body.decode_u32(pos)
			pos += 4
		var bs: int = pos
		var be: int = bs + length
		if be > end:
			break
		tag_distribution[code] = int(tag_distribution.get(code, 0)) + 1
		if code == TAG_PLACE_OBJECT_2 and length >= 3:
			var pl: Dictionary = _parse_place_object_2(body, bs, length)
			pl["frame"] = frame
			placements.append(pl)
		elif code == TAG_REMOVE_OBJECT_2 and length >= 2:
			placements.append({"depth": body.decode_u16(bs), "remove": true, "frame": frame})
		elif code == TAG_SHOW_FRAME:
			frame += 1
		elif code == TAG_END:
			break
		pos = be
	return placements


func _parse_place_object_2(body: PackedByteArray, bs: int, length: int) -> Dictionary:
	var flags: int = body[bs]
	var depth: int = body.decode_u16(bs + 1)
	var cursor: int = bs + 3
	var char_id: int = -1
	var sx: int = 0; var sy: int = 0; var r0: int = 0; var r1: int = 0; var tx: int = 0; var ty: int = 0
	if (flags & 0x02) and cursor + 2 <= bs + length:  # HasCharacter
		char_id = body.decode_u16(cursor)
		cursor += 2
	if (flags & 0x04) and cursor + 1 <= bs + length:  # HasMatrix
		var res: Array = _read_full_matrix(body, cursor * 8)
		sx = int(res[0]); sy = int(res[1]); r0 = int(res[2]); r1 = int(res[3]); tx = int(res[4]); ty = int(res[5])
		cursor = (int(res[6]) + 7) / 8  # 矩阵后的位位置（取整到下一字节）
	var has_color: bool = (flags & 0x08) != 0  # HasColorTransform
	var cxform: Dictionary = {}
	if has_color and cursor + 1 <= bs + length:
		# 解析实际 ColorTransform 参数（multiply/add 四通道），非仅标志位。
		var cr: Array = _read_cxform(body, cursor * 8)
		cxform = {"has_add": int(cr[0]), "has_mult": int(cr[1]), "nbits": int(cr[2]), "mult": cr[3], "add": cr[4]}
	return {"depth": depth, "character": char_id, "sx": sx, "sy": sy, "r0": r0, "r1": r1, "tx": tx, "ty": ty, "has_color": has_color, "flags": flags, "cxform": cxform}


# --- 位级读取（MSB-first）---

func _read_bits(body: PackedByteArray, bit_pos: int, count: int) -> Array:
	var value: int = 0
	var bp: int = bit_pos
	for i in range(count):
		var byte_idx: int = bp / 8
		if byte_idx >= body.size():
			break
		var bit_idx: int = 7 - (bp % 8)
		value = (value << 1) | ((body[byte_idx] >> bit_idx) & 1)
		bp += 1
	return [value, bp]


func _read_signed_bits(body: PackedByteArray, bit_pos: int, count: int) -> Array:
	var res: Array = _read_bits(body, bit_pos, count)
	var value: int = int(res[0])
	if count > 0 and ((value >> (count - 1)) & 1) != 0:
		value -= (1 << count)
	res[0] = value
	return res


func _skip_rect(body: PackedByteArray, pos: int) -> int:
	var res: Array = _read_bits(body, pos * 8, 5)
	var n: int = int(res[0])
	var bp: int = int(res[1]) + n * 4
	return (bp + 7) / 8


func _skip_matrix(body: PackedByteArray, pos: int) -> int:
	var bp: int = pos * 8
	var res: Array
	res = _read_bits(body, bp, 1); bp = int(res[1])
	if int(res[0]):
		res = _read_bits(body, bp, 5); bp = int(res[1]) + int(res[0]) * 2
	res = _read_bits(body, bp, 1); bp = int(res[1])
	if int(res[0]):
		res = _read_bits(body, bp, 5); bp = int(res[1]) + int(res[0]) * 2
	res = _read_bits(body, bp, 5); bp = int(res[1]) + int(res[0]) * 2
	return (bp + 7) / 8


## 完整 matrix：[sx, sy, r0, r1, tx, ty, new_bit_pos]
func _read_full_matrix(body: PackedByteArray, bit_pos: int) -> Array:
	var bp: int = bit_pos
	var res: Array
	var sx: int = 0; var sy: int = 0; var r0: int = 0; var r1: int = 0; var tx: int = 0; var ty: int = 0
	res = _read_bits(body, bp, 1); bp = int(res[1])
	if int(res[0]):
		res = _read_bits(body, bp, 5); var sn: int = int(res[0]); bp = int(res[1])
		if sn > 0:
			res = _read_signed_bits(body, bp, sn); sx = int(res[0]); bp = int(res[1])
			res = _read_signed_bits(body, bp, sn); sy = int(res[0]); bp = int(res[1])
	res = _read_bits(body, bp, 1); bp = int(res[1])
	if int(res[0]):
		res = _read_bits(body, bp, 5); var rn: int = int(res[0]); bp = int(res[1])
		if rn > 0:
			res = _read_signed_bits(body, bp, rn); r0 = int(res[0]); bp = int(res[1])
			res = _read_signed_bits(body, bp, rn); r1 = int(res[0]); bp = int(res[1])
	res = _read_bits(body, bp, 5); var tn: int = int(res[0]); bp = int(res[1])
	if tn > 0:
		res = _read_signed_bits(body, bp, tn); tx = int(res[0]); bp = int(res[1])
		res = _read_signed_bits(body, bp, tn); ty = int(res[0]); bp = int(res[1])
	return [sx, sy, r0, r1, tx, ty, bp]


## 解析实际 ColorTransform（CXFORM）参数，返回 [has_add, has_mult, nbits, mult[4], add[4], new_bit_pos]。
## mult 缺省 256（=×1.0），add 缺省 0。sprite1159 frame2/3 实测 add=[77,77,77,0]/[38,38,38,0]（悬停变亮）。
func _read_cxform(body: PackedByteArray, bit_pos: int) -> Array:
	var bp: int = bit_pos
	var res: Array
	res = _read_bits(body, bp, 1); var has_add: int = int(res[0]); bp = int(res[1])
	res = _read_bits(body, bp, 1); var has_mult: int = int(res[0]); bp = int(res[1])
	res = _read_bits(body, bp, 4); var nbits: int = int(res[0]); bp = int(res[1])
	var mult: Array = [256, 256, 256, 256]
	var add: Array = [0, 0, 0, 0]
	if has_mult:
		for i in range(4):
			res = _read_signed_bits(body, bp, nbits)
			mult[i] = int(res[0])
			bp = int(res[1])
	if has_add:
		for i in range(4):
			res = _read_signed_bits(body, bp, nbits)
			add[i] = int(res[0])
			bp = int(res[1])
	return [has_add, has_mult, nbits, mult, add, bp]


func _parse_shape_bitmap_fills(body: PackedByteArray, body_start: int, code: int) -> Array:
	var cursor: int = _skip_rect(body, body_start + 2)
	if code == 83:
		cursor = _skip_rect(body, cursor)
		cursor += 1
	var fill_count: int = body[cursor]
	cursor += 1
	if fill_count == 0xFF:
		fill_count = body.decode_u16(cursor)
		cursor += 2
	var bitmaps: Array = []
	for i in range(fill_count):
		if cursor >= body.size():
			break
		var fill_type: int = body[cursor]
		cursor += 1
		if fill_type == 0:
			cursor += 4 if code in [32, 83] else 3
		elif fill_type in [0x10, 0x12, 0x13]:
			cursor = _skip_matrix(body, cursor)
			var header: int = body[cursor]
			cursor += 1
			var stop_count: int = header & 0x0F
			cursor += stop_count * (1 + (4 if code in [32, 83] else 3))
			if fill_type == 0x13:
				cursor += 2
		elif fill_type in [0x40, 0x41, 0x42, 0x43]:
			var bmp_id: int = body.decode_u16(cursor)
			cursor += 2
			cursor = _skip_matrix(body, cursor)
			bitmaps.append(bmp_id)
		else:
			break
	return bitmaps


# --- 查询接口 ---

func is_loaded() -> bool:
	return _loaded

func get_sprite_frame_count(sprite_id: int) -> int:
	return int(sprite_frame_counts.get(sprite_id, -1))

func is_bitmap_character(char_id: int) -> bool:
	return bitmap_characters.has(char_id)

func is_shape_character(char_id: int) -> bool:
	return shape_characters.has(char_id)

func is_sprite(char_id: int) -> bool:
	return sprite_frame_counts.has(char_id)

func bitmap_tag_code(char_id: int) -> int:
	return int(bitmap_characters.get(char_id, -1))

func root_is_placed_on_root(char_id: int) -> bool:
	for p in root_placements:
		if int(p["character"]) == char_id:
			return true
	return false


## 纯函数（事件流状态机）：char_id 放置后是否被同 depth 的 RemoveObject2 移除。
## events 为原始 tag 顺序事件流：[{type:"place", frame, depth, char, has_character, flags} | {type:"remove", frame, depth}]。
## 按事件顺序模拟显示列表：
##   - place 且 HasCharacter=true：更新 depth 的当前 character（放置/替换）；
##   - place 且 HasCharacter=false（Move 更新）：只更新已有对象位置/颜色，**不覆盖**当前 character；
##   - remove：删除 depth 的当前 character（"此刻该 depth 上的角色被移除"）。
## 被替换过的旧角色不再参与后续 remove 判定
## （frame5 char100→depth7、frame6 char200→depth7、frame9 remove depth7：char100=false、char200=true）。
func root_remove_after_placement_from_events(events: Array, char_id: int) -> bool:
	var removed: Dictionary = {}
	var depth_current: Dictionary = {}  # depth -> 当前 character
	for ev in events:
		var depth: int = int(ev.get("depth", -1))
		if depth < 0:
			continue
		if str(ev.get("type", "")) == "place":
			# 整改08：Move 更新（HasCharacter=false）不覆盖当前 character
			if bool(ev.get("has_character", true)):
				depth_current[depth] = int(ev.get("char", -1))
		else:  # remove
			if depth_current.has(depth):
				var cur: int = int(depth_current[depth])
				if cur >= 0:
					removed[cur] = true
			depth_current.erase(depth)
	return removed.has(char_id)


## 根时间轴事实查询：char_id 放置后是否被同 depth 的 RemoveObject2 移除（场景状态机切换）。
## 基于 root_events（解析器按原始 tag 顺序记录 place/remove 事件流）模拟 depth->当前 character
## 显示列表：被其他角色替换后再删除的旧角色不算"被移除"。
## 根时间轴 remove 是场景状态切换机制（285 个 RemoveObject2 分布在帧3-38 的部分帧，
## 帧7/37 无 RemoveObject2，非每帧清空），不构成对象自身动画证据，
## 但作为事实如实记录，需 gotoAndStop 审计确认对象常驻帧。
func has_root_remove_after_placement(char_id: int) -> bool:
	return root_remove_after_placement_from_events(root_events, char_id)


## sprite 内某帧的 ColorTransform 实际参数（{has_add,has_mult,nbits,mult[4],add[4]}）；无 color 时返回 {}。
func get_placement_cxform(sprite_id: int, frame: int) -> Dictionary:
	if not sprite_placements.has(sprite_id):
		return {}
	for p in sprite_placements[sprite_id]:
		if int(p["frame"]) == frame and bool(p.get("has_color", false)):
			return p.get("cxform", {})
	return {}


func find_shape_for_bitmap(bitmap_id: int) -> int:
	for shape_id in shape_bitmap_fills:
		if bitmap_id in shape_bitmap_fills[shape_id]:
			return int(shape_id)
	return -1


## 放置 char_id 的 sprite 列表（含 ROOT_ID=-1 表示根时间轴）。RemoveObject2 条目（无 character）跳过。
func find_placers_of(char_id: int) -> Array:
	var result: Array = []
	for sprite_id in sprite_placements:
		for p in sprite_placements[sprite_id]:
			if int(p.get("character", -1)) == char_id:
				result.append(int(sprite_id))
				break
	for p in root_placements:
		if int(p.get("character", -1)) == char_id:
			result.append(ROOT_ID)
			break
	return result


func _placements_of(sid: int) -> Array:
	if sid == ROOT_ID:
		return root_placements
	return sprite_placements.get(sid, [])


## 是否真正视觉动画：某 depth 跨帧 >1 char（替换），或后续 HasMatrix translate/scale/rotate 变化，
## 或任意帧 HasColorTransform（颜色变化），或对象放置后被 RemoveObject2 删除（显示列表删除）。
## 输入按解析顺序 = 帧序；初始放置（首个非零 translate）不计（静态位置）。
func is_visual_animation_sprite(sprite_id: int) -> bool:
	return _placements_animated(_placements_of(sprite_id))


## 逐帧显示列表状态机：按帧序模拟每 depth 的对象存在/替换/删除。
## 变化判定：char 替换（同 depth >1 字符）、矩阵 translate/scale/rotate 后续变化、
## ColorTransform、对象从"存在"变为"被 RemoveObject2 移除"。
func _placements_animated(pls: Array) -> bool:
	var depth_chars: Dictionary = {}
	var depth_matrix: Dictionary = {}
	var depth_changed_t: Dictionary = {}
	var depth_changed_sr: Dictionary = {}
	var depth_color: Dictionary = {}
	var depth_removed: Dictionary = {}
	var depth_present: Dictionary = {}  # depth -> 是否已有对象
	for p in pls:
		var depth: int = int(p["depth"])
		if bool(p.get("remove", false)):
			# 对象从存在变为被删除 -> 显示列表变化（帧序：仅当该 depth 此前存在对象）
			if bool(depth_present.get(depth, false)):
				depth_removed[depth] = true
			depth_present[depth] = false
			continue
		if int(p["character"]) >= 0:
			if not depth_chars.has(depth):
				depth_chars[depth] = {}
			(depth_chars[depth] as Dictionary)[int(p["character"])] = true
			depth_present[depth] = true
		if int(p["flags"]) & 0x04:  # HasMatrix
			var mat: Array = [int(p["sx"]), int(p["sy"]), int(p["r0"]), int(p["r1"]), int(p["tx"]), int(p["ty"])]
			if depth_matrix.has(depth):
				var old: Array = depth_matrix[depth]
				if old[4] != mat[4] or old[5] != mat[5]:
					depth_changed_t[depth] = true
				if old[0] != mat[0] or old[1] != mat[1] or old[2] != mat[2] or old[3] != mat[3]:
					depth_changed_sr[depth] = true
			else:
				depth_matrix[depth] = mat
			depth_present[depth] = true
		if bool(p.get("has_color", false)):
			depth_color[depth] = true
			depth_present[depth] = true
	for depth in depth_chars:
		if (depth_chars[depth] as Dictionary).size() > 1:
			return true
	return depth_changed_t.size() > 0 or depth_changed_sr.size() > 0 or depth_color.size() > 0 or depth_removed.size() > 0


## bitmap 视觉静态分析：递归到根，返回 {static, chain, changes}。
## static=true 当且仅当链路中所有 wrapper（含根）均无 char swap/translate/scale_rotate/color 变化。
func is_bitmap_visually_static(bitmap_id: int) -> Dictionary:
	var shape_id: int = find_shape_for_bitmap(bitmap_id)
	if shape_id < 0:
		return {"static": true, "chain": "bitmap" + str(bitmap_id) + "(no shape)", "changes": []}
	var chain: String = "bitmap" + str(bitmap_id) + "->shape" + str(shape_id)
	var changes: Array = []
	var checked: Array = []
	var frontier: Array = [shape_id]
	var visited: Dictionary = {}
	while not frontier.is_empty():
		var cid: int = int(frontier.pop_front())
		if visited.has(cid):
			continue
		visited[cid] = true
		var wrappers: Array = find_placers_of(cid)
		for w in wrappers:
			if w in checked:
				continue
			checked.append(w)
			if w == ROOT_ID:
				chain += "->root"
				# 仅检查该 character 在根时间轴的放置是否有变化（不是整个场景时间轴）
				var root_pls: Array = []
				for p in root_placements:
					if int(p["character"]) == cid:
						root_pls.append(p)
				if _placements_animated(root_pls):
					changes.append("root:change")
			else:
				chain += "->sprite" + str(w)
				if _placements_animated(sprite_placements.get(w, [])):
					changes.append("sprite" + str(w) + ":change")
				frontier.append(w)
	return {"static": changes.is_empty(), "chain": chain, "changes": changes, "checked": checked}


## sprite_id 在指定 frame 的放置 translate（像素，twips/20）。优先非零 translate；否则首个放置。
func get_sprite_placement_translate(sprite_id: int, frame: int) -> Variant:
	if not sprite_placements.has(sprite_id):
		return null
	var first: Variant = null
	for p in sprite_placements[sprite_id]:
		if int(p["frame"]) != frame:
			continue
		var tx: int = int(p.get("tx", 0))
		var ty: int = int(p.get("ty", 0))
		var v := Vector2(float(tx) / 20.0, float(ty) / 20.0)
		if first == null:
			first = v
		if tx != 0 or ty != 0:
			return v
	return first


## sprite 时间轴内是否存在 RemoveObject2（对象删除，显示列表变化之一）。
func sprite_has_removal(sprite_id: int) -> bool:
	if not sprite_placements.has(sprite_id):
		return false
	for p in sprite_placements[sprite_id]:
		if bool(p.get("remove", false)):
			return true
	return false


func parse_character_id_from_asset(asset_path: String) -> int:
	var base: String = asset_path.get_file().get_basename()
	if not base.begins_with("image_"):
		return -1
	var num_str: String = base.substr(6)
	if not num_str.is_valid_int():
		return -1
	return num_str.to_int()
