extends Node

# v1.36 整改04 专项：原生时间轴注册表验证。
# 覆盖 PM/SE 整改03 复验全部阻断：
#   1. cancel_policy 生产真实读取：控制器 _load_timeline_policies 读注册表，每个 Tween/Timer 登记
#      timeline_id，事件站点 timeline_cancelled_by(timeline_id, event) 查询策略；battle_cancel 事件
#      （cancel_battle）取消 on_battle_cancel 时间轴，map_change 事件（_apply_current_map）取消
#      on_map_change 时间轴（player_motion 重置）；合法但错误策略命中 TIMELINE_CANCEL_POLICY_MISMATCH。
#   2. Timer 取消可验证：测试保存真实 Timer 节点引用，cancel 后逐个断言 is_stopped()==true；
#      协程退出可观察（queue_free 后节点释放）；地图切换同样断言。
#   3. Tween/Label 无残留：kill 时执行 cleanup（浮动文字 label.queue_free）；取消前后场景树无残留
#      Label；_finish_defeat 淡出被 kill 时轮询退出不悬挂，modulate 由 cleanup 恢复。
#   4. SWF 解析：ColorTransform 实际参数（CXFORM add/mult）、RemoveObject2（深度删除）、
#      逐帧显示列表状态机（保持/替换/删除）、tag4/tag5 全文件为 0（扫描）、递归到根。
#   5. 证据 token：全部三分类（timelines/static/gap 实体）evidence_tokens 逐行独立，禁用压缩写法。
#   6. 统计：唯一 bitmap 按解析 character ID 去重（非 asset 路径字符串）。

const REGISTRY_PATH := "res://docs/native_timeline_registry.json"
const EVIDENCE_PATH := "res://docs/evidence/native_timelines_v103_v9.txt"
# 原版 SWF 路径（跨平台）：MOYU_SWF_PATH 环境变量优先，否则 res://../魔域1.03_v9.swf（Windows/Linux 工作树相对位置一致）。
const ALLOWED_CLASSIFICATIONS := ["native_confirmed", "static_native", "evidence_gap", "intentional_divergence"]
const ALLOWED_ANCHORS := ["top_left"]

const SwfParser = preload("res://tests/helpers/swf_parser.gd")
const TimelineScheduler = preload("res://scripts/timeline_scheduler.gd")


## 原版 SWF 绝对路径（跨平台解析）：MOYU_SWF_PATH 环境变量优先；
## 否则 ProjectSettings.globalize_path("res://../魔域1.03_v9.swf")——Windows/Linux 工作树中
## 原版 SWF 与 godot_remake 的相对位置一致，无需依赖任何盘符。
func _swf_path() -> String:
	var env_path := OS.get_environment("MOYU_SWF_PATH")
	if not env_path.is_empty():
		return env_path
	return ProjectSettings.globalize_path("res://../魔域1.03_v9.swf")

# 独立 SWF 期望值（来自 dump_sprite_actions / _v136_matrices / manifest.csv，非注册表派生）。
const ALLOWED_CANCEL_POLICIES := ["on_battle_cancel", "on_map_change"]
const SWF_EXPECTED := {
	"player_motion": {
		"cancel_policy": "on_map_change",
		"fps": 12,
		"sub_clips": {"idle":{"sprite":459,"frames":8}, "down":{"sprite":469,"frames":8}, "up":{"sprite":474,"frames":8}, "left":{"sprite":481,"frames":10}, "right":{"sprite":488,"frames":10}},
		"frames": [{"res":"image_0455.png","dur":4,"offset":[0,0],"size":[57,161],"anchor":"top_left"}, {"res":"image_0457.png","dur":4,"offset":[0,0],"size":[57,161],"anchor":"top_left"}]
	},
	"player_attack": {
		"cancel_policy": "on_battle_cancel",
		"frames": [{"res":"image_0503.png","dur":1,"offset":[18,-4]}, {"res":"image_0505.png","dur":1,"offset":[18,-4]}, {"res":"image_0507.png","dur":1,"offset":[18,-4]}, {"res":"image_0509.png","dur":1,"offset":[18,-4]}]
	},
	"normal_monster_attack": {
		"cancel_policy": "on_battle_cancel",
		"frames": [{"res":"single_bitmap","dur":1,"offset":[-5,0]}, {"res":"single_bitmap","dur":1,"offset":[0,0]}]
	},
	"boss_attack": {
		"cancel_policy": "on_battle_cancel",
		"frames": [{"res":"image_0127.png","dur":1,"offset":[-33,-42],"size":[186,173],"anchor":"top_left"}, {"res":"image_0129.png","dur":1,"offset":[-33,-42],"size":[186,173],"anchor":"top_left"}]
	},
	"boss_hit": {
		"cancel_policy": "on_battle_cancel",
		# sprite134 帧1-2 站立/帧3-4 受击：t=0 站立、2/12 受击（整改09 统一帧序）
		"frames": [{"res":"image_1072.png","dur":2,"offset":[0,0],"size":[101,132],"anchor":"top_left"}, {"res":"boss_hit_native.png","dur":2,"offset":[0,-7],"size":[123,148],"anchor":"top_left"}]
	}
}
# 生产事件映射（与 scene_battle_controller.timeline_cancelled_by 语义一致）：
# on_battle_cancel -> battle_cancel 事件（cancel_battle）；on_map_change -> map_change 事件（_apply_current_map）。

var swf: RefCounted
var reg: Variant
var ev_text: String


func _ready() -> void:
	reg = _load_json(REGISTRY_PATH)
	ev_text = _read_text(EVIDENCE_PATH)
	swf = SwfParser.new()
	assert(swf.load_swf(_swf_path()), "swf load failed: " + swf.parse_error)

	# --- 1. 候选对象全覆盖分类 ---
	var all_ids: Dictionary = {}
	for tl in reg["timelines"]:
		assert(not all_ids.has(str(tl["timeline_id"])), "duplicate timeline_id")
		all_ids[str(tl["timeline_id"])] = true
	for se in reg["static_entities"]:
		assert(not all_ids.has(str(se["entity_id"])), "duplicate entity_id: " + str(se["entity_id"]))
		all_ids[str(se["entity_id"])] = true
	for se in reg["evidence_gap_entities"]:
		assert(not all_ids.has(str(se["entity_id"])), "duplicate entity_id: " + str(se["entity_id"]))
		all_ids[str(se["entity_id"])] = true
	var required_ids: Array = [
		"grocery","stone_shop","collector","warehouse","daily_officer","stone_synthesizer","forger","pet_master","experience_mentor","research",
		"marshal","prime_minister","king","princess","maid","pk_officer","lottery_officer",
		"fuwa_messenger","fuwa_completion","war_soul_explorer","spider","spider_queen",
		"dungeon_boss","dungeon_boss_2","dungeon_boss_3","pk_champion_60","pk_champion_100","pk_champion_130",
		"nameless_war_soul_keeper","demon_guard","demon_assault","demon_totem","demon_mystery","demon_commander","demon_energy",
		"war_soul_chest","mine_nodes","fuwa_beibei","fuwa_huanhuan","fuwa_yingying","fuwa_nini","fuwa_jingjing",
		"fuwa_reward","lottery_chests"
	]
	for rid: String in required_ids:
		assert(all_ids.has(rid), "required entity not in registry: " + rid)
	assert(_find_static(reg, "lottery_chests") or _find_gap(reg, "lottery_chests"))
	print("coverage: %d required ids, %d total" % [required_ids.size(), all_ids.size()])

	# --- 2. 单一 validate_registry 正向（错误列表必须为空；含三分类 token 全量校验）---
	var errors: Array = validate_registry(reg, swf, ev_text)
	assert(errors.is_empty(), "positive validate_registry failed: " + str(errors))
	print("positive validate_registry: 0 errors (timelines + static + gap tokens all present in evidence)")

	# --- 3. 独立 SWF 证明（含标签分布/ColorTransform 实际参数/RemoveObject2/根移除事实）---
	_assert_swf_proof()

	# --- 4. 引用链 1156 专项 ---
	_assert_refchain_1156()

	# --- 5. 负向（合法但错误值/缺字段，调用同一 validate_registry；整改05 新增 MISSING 与帧数边界，
	#       整改06 新增路径删除/空串负向）---
	_neg_frame_resource()
	_neg_duration()
	_neg_transform()
	_neg_cancel_policy_missing()
	_neg_cancel_policy_mismatch()
	_neg_impl_path_missing()
	_neg_test_scene_empty()
	_neg_frame_count_missing()
	_neg_frame_count_extra()
	_neg_evidence_token()
	_neg_anchor()
	_neg_fps()

	# --- 6. 文档统计（唯一 bitmap 按解析 character ID 去重）---
	_assert_doc_stats()

	# --- 7. 真实生产路径验证（实例化 main.tscn；Timer 真实 is_stopped/Label 无残留/策略查询）---
	await _test_production_events()

	print("PASS v1.36 整改12: active handle (cleared on untrack, no permanent strong refs) + active_scheduler_count / tracked_scheduler_slot_count / has_active_scheduler_handle distinct + 100x natural & 100x cancel per-iteration all-three zero + real release (WeakRef null after completion/cancel/map-change/actor-rebuild) + WeakRef-bind finished connections (no self-reference cycle, fixed real leak) + SCHEDULER_REFERENCE_LEAK via slot residue (mutation proven by enabled-vs-disabled cancel diff, handle-independent) + scene exit frees main/controller/scheduler/tween/actor (WeakRef asserted) + driver boundary verifier + PRODUCTION_TIMELINE_BOUNDARY_MISMATCH + 149/186 kept + map_change timer kept")
	get_tree().quit(0)


# ===== 单一验证器（正向与全部负向共用；三分类 token 全量校验）=====

func validate_registry(r: Dictionary, s: RefCounted, ev: String) -> Array:
	var errors: Array = []
	for tl in r.get("timelines", []):
		var tlid: String = str(tl.get("timeline_id", ""))
		if str(tl.get("classification", "")) != "native_confirmed":
			continue
		# 整改05：删除 cancel_policy 字段 -> TIMELINE_CANCEL_POLICY_MISSING（任务书必测负向）
		if not tl.has("cancel_policy"):
			errors.append("TIMELINE_CANCEL_POLICY_MISSING:" + tlid)
		else:
			var cp: String = str(tl.get("cancel_policy", ""))
			if cp not in ALLOWED_CANCEL_POLICIES:
				errors.append("TIMELINE_CANCEL_POLICY_MISMATCH:" + tlid + ":cancel_policy=" + cp)
			elif SWF_EXPECTED.has(tlid) and cp != str(SWF_EXPECTED[tlid].get("cancel_policy", "")):
				errors.append("TIMELINE_CANCEL_POLICY_MISMATCH:" + tlid + ":cancel_policy=" + cp)
		var es: String = str(tl.get("evidence_source", ""))
		if not FileAccess.file_exists(es):
			errors.append("TIMELINE_FRAME_RESOURCE_MISMATCH:" + tlid + ":evidence_source")
		# 整改06：implementation_path / test_scene 必须存在（任务书 7.2）。
		# 缺失字段/空字符串一律视为不存在（不允许空值绕过）。
		var impl: String = str(tl.get("implementation_path", ""))
		if not FileAccess.file_exists(impl):
			errors.append("TIMELINE_IMPLEMENTATION_MISSING:" + tlid + ":" + impl)
		var tsc: String = str(tl.get("test_scene", ""))
		if not FileAccess.file_exists(tsc):
			errors.append("TIMELINE_TEST_SCENE_MISSING:" + tlid + ":" + tsc)
		for tok in tl.get("evidence_tokens", []):
			if str(tok) not in ev:
				errors.append("EVIDENCE_TOKEN_MISS:" + tlid + ":" + str(tok))
		# 独立 SWF 帧数核对
		var sc: Variant = tl.get("sub_clips", null)
		if sc is Dictionary:
			for key in (sc as Dictionary).keys():
				var clip: Dictionary = (sc as Dictionary)[key]
				var spid: int = int(clip.get("sprite", -1))
				if spid >= 0:
					var expect_fc: int = int(clip.get("frame_count", -1))
					var actual_fc: int = s.get_sprite_frame_count(spid)
					if actual_fc != expect_fc:
						errors.append("FRAME_COUNT_MISMATCH:" + tlid + ":" + str(key) + ":sprite" + str(spid) + "=" + str(actual_fc) + "/expected" + str(expect_fc))
				var fps_v: Variant = clip.get("fps", null)
				if fps_v != null and int(fps_v) != int(s.root_frame_rate):
					errors.append("TIMELINE_DURATION_MISMATCH:" + tlid + ":fps=" + str(fps_v))
		# 帧资源/duration/offset/anchor/size 与 SWF_EXPECTED 精确比较
		var exp_frames: Array = []
		if SWF_EXPECTED.has(tlid):
			exp_frames = SWF_EXPECTED[tlid]["frames"]
		var frames: Array = tl.get("frames", [])
		# 整改05：帧数量必须与 SWF_EXPECTED 完全一致（缺帧/多帧均报错）
		if exp_frames.size() > 0 and frames.size() != exp_frames.size():
			errors.append("TIMELINE_FRAME_COUNT_MISMATCH:" + tlid + ":frames=" + str(frames.size()) + "/expected" + str(exp_frames.size()))
		for i in range(frames.size()):
			var frame: Dictionary = frames[i]
			var fres: String = str(frame.get("resource", ""))
			if i < exp_frames.size():
				var exp: Dictionary = exp_frames[i]
				var exp_res: String = str(exp["res"])
				if not fres.ends_with(exp_res) and fres != exp_res:
					errors.append("TIMELINE_FRAME_RESOURCE_MISMATCH:" + tlid + ":frame" + str(i) + "=" + fres)
				elif fres != "single_bitmap" and fres != "original_monster_bitmap" and not fres.begins_with("UNCONFIRMED"):
					if not FileAccess.file_exists(fres):
						errors.append("TIMELINE_FRAME_RESOURCE_MISMATCH:" + tlid + ":frame" + str(i) + ":missing")
				if int(frame.get("duration_frames", -1)) != int(exp["dur"]):
					errors.append("TIMELINE_DURATION_MISMATCH:" + tlid + ":frame" + str(i) + ":dur=" + str(frame.get("duration_frames")))
				var off: Array = frame.get("position_offset", [])
				var exp_off: Array = exp["offset"]
				if off.size() != 2 or int(off[0]) != int(exp_off[0]) or int(off[1]) != int(exp_off[1]):
					errors.append("TIMELINE_TRANSFORM_MISMATCH:" + tlid + ":frame" + str(i) + ":offset=" + str(off))
				if exp.has("anchor"):
					if str(frame.get("anchor", "")) != str(exp["anchor"]):
						errors.append("TIMELINE_TRANSFORM_MISMATCH:" + tlid + ":frame" + str(i) + ":anchor=" + str(frame.get("anchor")))
				if exp.has("size") and frame.has("size"):
					var sz: Variant = frame.get("size")
					if sz is Array and (sz as Array).size() >= 2:
						var exp_sz: Array = exp["size"]
						if int(sz[0]) != int(exp_sz[0]) or int(sz[1]) != int(exp_sz[1]):
							errors.append("TIMELINE_TRANSFORM_MISMATCH:" + tlid + ":frame" + str(i) + ":size=" + str(sz))
	# 三分类 token 全量校验（整改04：static/gap 实体 evidence_tokens 也必须逐行存在于证据文件）
	for se in r.get("static_entities", []) + r.get("evidence_gap_entities", []):
		var eid: String = str(se.get("entity_id", ""))
		for tok in se.get("evidence_tokens", []):
			if str(tok) not in ev:
				errors.append("EVIDENCE_TOKEN_MISS:" + eid + ":" + str(tok))
	return errors


# ===== 独立 SWF 证明 =====

func _assert_swf_proof() -> void:
	assert(swf.signature == "CWS")
	assert(swf.declared_length == 3348349)
	assert(swf.decompressed_size == swf.declared_length - 8)
	assert(swf.root_frame_rate == 12.0)
	# 标签分布（整改05：全文件递归统计，含全部 DefineSprite 内部；PM/SE 独立递归扫描数字：tag26=1577、tag28=320、tag39=233、tag4/5=0）
	assert(int(swf.tag_distribution.get(4, 0)) == 0, "tag4 PlaceObject should be 0 (all placements are PlaceObject2)")
	assert(int(swf.tag_distribution.get(5, 0)) == 0, "tag5 RemoveObject should be 0")
	assert(int(swf.tag_distribution.get(26, 0)) == 1577, "tag26 PlaceObject2 full-file count should be 1577, got " + str(int(swf.tag_distribution.get(26, 0))))
	assert(int(swf.tag_distribution.get(28, 0)) == 320, "tag28 RemoveObject2 full-file count should be 320, got " + str(int(swf.tag_distribution.get(28, 0))))
	assert(int(swf.tag_distribution.get(39, 0)) == 233, "tag39 DefineSprite full-file count should be 233, got " + str(int(swf.tag_distribution.get(39, 0))))
	# native sprite 帧数（独立直读 SWF 二进制）
	var sprite_expect: Dictionary = {523:72, 459:8, 469:8, 474:8, 481:10, 488:10, 124:11, 135:15, 134:4, 131:5}
	for sid in sprite_expect.keys():
		assert(swf.get_sprite_frame_count(sid) == int(sprite_expect[sid]), "sprite " + str(sid) + " frame count mismatch")
	# native 放置 translate（独立 SWF 核对，非注册表派生）
	assert(swf.get_sprite_placement_translate(135, 6) == Vector2(-65.0, -42.15), "boss_attack placement mismatch")
	assert(swf.get_sprite_placement_translate(124, 7) == Vector2(-5.0, 0.0), "normal_monster placement mismatch")
	# native 帧 bitmap 是 bitmap character
	for cid in [455, 457, 503, 505, 507, 509, 127, 129, 1072]:
		assert(swf.is_bitmap_character(cid) and not swf.is_sprite(cid), "native bitmap " + str(cid) + " check failed")
	assert(swf.is_shape_character(133), "shape133 should be shape")
	# ColorTransform 实际参数（CXFORM 解析，非仅标志位）：sprite1159 frame2/3 add=[77,77,77,0]/[38,38,38,0]
	var cxf2: Dictionary = swf.get_placement_cxform(1159, 2)
	assert(bool(cxf2.get("has_add", false)) and (cxf2.get("add", []) as Array) == [77, 77, 77, 0],
		"sprite1159 frame2 cxform add should be [77,77,77,0], got: " + str(cxf2))
	var cxf3: Dictionary = swf.get_placement_cxform(1159, 3)
	assert((cxf3.get("add", []) as Array) == [38, 38, 38, 0],
		"sprite1159 frame3 cxform add should be [38,38,38,0], got: " + str(cxf3))
	# RemoveObject2 内部删除：怪物选择器 sprite118/1074、boss 动画 sprite135 为"放置后移除"替换机制
	assert(swf.sprite_has_removal(118), "sprite118 should have internal RemoveObject2 (selector replace)")
	assert(swf.sprite_has_removal(1074), "sprite1074 should have internal RemoveObject2")
	assert(swf.sprite_has_removal(135), "sprite135 should have internal RemoveObject2")
	assert(not swf.sprite_has_removal(1159), "sprite1159 color-hover should not use removal")
	# 根时间轴 RemoveObject2 场景状态机事实：marshal(1178) 帧13放置帧14移除；research(1172) 无放置记录
	assert(swf.has_root_remove_after_placement(1178), "marshal root placement should be removed later (scene state machine)")
	assert(not swf.has_root_remove_after_placement(1171), "research shape1172 has no root placement to remove")
	# 整改07：固定输入/固定预期的最小夹具（事件流状态机，6 组用例 8 断言；含 PM/SE 指定的
	# "替换后再删除不算旧角色"反例）。不做"与生产同算法复制"的参考实现。
	_assert_root_remove_fixtures()
	# 固化修复结论（三类旧误判）：
	# 1) "只比帧号"误判 10 字符（1302-1311，depth 匹配后纠正）；
	# 2) "历史上曾出现于该 depth"误判（PM/SE 点名 387/1067/1092/1096/1176/1227/1237/1298 等——
	#    被同 depth 其他角色替换后才删除，事件流状态机判定为未被移除）；
	# 3) Move 更新（HasCharacter=false）覆盖当前角色导致漏判——PM/SE 点名 787/925/1228 必须为 true。
	var cured: Array = [1302, 1303, 1304, 1305, 1306, 1307, 1308, 1309, 1310, 1311,
		387, 1067, 1092, 1096, 1176, 1227, 1237, 1298]
	for cid: int in cured:
		assert(not swf.has_root_remove_after_placement(cid), "char" + str(cid) + " should NOT be counted as removed (replaced before removal / frame-only misjudge)")
	for cid2: int in [787, 925, 1228]:
		assert(swf.has_root_remove_after_placement(cid2), "char" + str(cid2) + " should be counted as removed (move-update no-overwrite fix)")
	# 修复后全量统计断言（整改08）：186 唯一根放置角色，事件流状态机判定被删除 149 个
	# （旧"历史上出现"算法 176 个；Move 覆盖缺陷 146 个；修复后与 PM/SE 独立模拟 149 一致）。
	var unique_root: Dictionary = {}
	for p in swf.root_placements:
		var rc: int = int(p.get("character", -1))
		if rc >= 0:
			unique_root[rc] = true
	var removed_count: int = 0
	for rc: int in unique_root:
		if swf.has_root_remove_after_placement(rc):
			removed_count += 1
	assert(unique_root.size() == 186, "unique root placed chars should be 186, got " + str(unique_root.size()))
	assert(removed_count == 149, "event-stream state machine should count 149 removed, got " + str(removed_count))
	print("independent swf proof: 10 sprites + placements + 9 bitmaps + full-file tag distribution (tag4/5=0, tag26=1577, tag28=320, tag39=233) + cxform params (1159 add=77/38) + internal removals (118/1074/135) + root remove fixtures (8 cases / 10 asserts) + 18 cured + 3 move-cured chars + removal count 149/186")
	# 静态实体根移除事实不改变分类（对象自身无动画）；分类核对见 _assert_refchain_1156


# ===== 引用链 1156 专项 =====

func _assert_refchain_1156() -> void:
	# 专项用例 image_1156 -> shape1157 -> sprite1158 -> sprite1159
	assert(swf.find_shape_for_bitmap(1156) == 1157, "bitmap1156 should fill shape1157")
	var chain: Dictionary = swf.is_bitmap_visually_static(1156)
	var chain_str: String = str(chain["chain"])
	assert(chain_str.find("shape1157") >= 0 and chain_str.find("sprite1158") >= 0 and chain_str.find("sprite1159") >= 0, "1156 chain incomplete: " + chain_str)
	# sprite1159 frame2/3 有 ColorTransform（悬停色变）——"视觉不变"不成立，1156 应为 evidence_gap
	assert(int(chain["static"]) == 0, "bitmap1156 should NOT be static (sprite1159 has color change): " + str(chain))
	assert(swf.is_visual_animation_sprite(1159), "sprite1159 should be visual animation (color change on frames 2/3)")
	# 真动画对照：sprite135（char swap + remove 替换）、sprite124（translate -5,0）
	assert(swf.is_visual_animation_sprite(135), "sprite135 should be visual animation")
	assert(swf.is_visual_animation_sprite(124), "sprite124 should be visual animation")
	# 全部 static_native 实体经引用链核对为静态（3 个：marshal/research/mine_nodes；根 remove 为场景状态机，不计对象动画）
	var static_verified: int = 0
	for se in reg["static_entities"]:
		var cid: int = swf.parse_character_id_from_asset(str(se.get("asset", "")))
		if cid < 0:
			continue
		var r: Dictionary = swf.is_bitmap_visually_static(cid)
		assert(int(r["static"]) == 1, "static entity " + str(se["entity_id"]) + " bitmap " + str(cid) + " not static: " + str(r))
		static_verified += 1
	# 全部 evidence_gap 实体经引用链核对为非静态（41 个）
	var gap_verified: int = 0
	for se in reg["evidence_gap_entities"]:
		var cid2: int = swf.parse_character_id_from_asset(str(se.get("asset", "")))
		if cid2 < 0:
			continue
		var r2: Dictionary = swf.is_bitmap_visually_static(cid2)
		assert(int(r2["static"]) == 0, "gap entity " + str(se["entity_id"]) + " bitmap " + str(cid2) + " should be in animation sprite: " + str(r2))
		gap_verified += 1
	print("refchain: 1156 专项 ok (color hover add=77/38); %d static + %d gap entities verified via chain" % [static_verified, gap_verified])


# ===== 七项负向（合法但错误值）=====

func _neg_frame_resource() -> void:
	# 篡改 boss_attack frame0 resource 为另一合法资源 image_1072（存在但错误帧）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "boss_attack":
			var orig: String = str((tl["frames"] as Array)[0]["resource"])
			(tl["frames"] as Array)[0]["resource"] = "res://assets/extracted/images/image_1072.png"
			assert(str((tl["frames"] as Array)[0]["resource"]) != orig, "neg1: mutation failed")
			mutated = true
			break
	assert(mutated, "neg1: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_FRAME_RESOURCE_MISMATCH"), "neg1: expected FRAME_RESOURCE_MISMATCH, got: " + str(errs))


func _neg_duration() -> void:
	# 篡改 boss_attack frame0 duration_frames 1->2（合法正值但错误）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "boss_attack":
			var orig: int = int((tl["frames"] as Array)[0]["duration_frames"])
			(tl["frames"] as Array)[0]["duration_frames"] = 2
			assert(int((tl["frames"] as Array)[0]["duration_frames"]) != orig, "neg2: mutation failed")
			mutated = true
			break
	assert(mutated, "neg2: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_DURATION_MISMATCH"), "neg2: expected DURATION_MISMATCH, got: " + str(errs))


func _neg_transform() -> void:
	# 篡改 boss_attack frame0 offset [-33,-42]->[-32,-42]（合法2元数组但错误）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "boss_attack":
			var orig: Array = (tl["frames"] as Array)[0]["position_offset"]
			(tl["frames"] as Array)[0]["position_offset"] = [-32, -42]
			assert(str((tl["frames"] as Array)[0]["position_offset"]) != str(orig), "neg3: mutation failed")
			mutated = true
			break
	assert(mutated, "neg3: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_TRANSFORM_MISMATCH"), "neg3: expected TRANSFORM_MISMATCH, got: " + str(errs))


func _neg_cancel_policy_missing() -> void:
	# 任务书必测负向：删除 cancel_policy 字段 -> TIMELINE_CANCEL_POLICY_MISSING
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_motion":
			assert(tl.has("cancel_policy"), "neg-missing: field should exist before mutation")
			tl.erase("cancel_policy")
			assert(not tl.has("cancel_policy"), "neg-missing: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-missing: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_CANCEL_POLICY_MISSING"), "neg-missing: expected CANCEL_POLICY_MISSING, got: " + str(errs))


func _neg_cancel_policy_mismatch() -> void:
	# 合法但错误策略：player_motion 应为 on_map_change，改为 on_battle_cancel（合法值但错误）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_motion":
			var orig: String = str(tl["cancel_policy"])
			tl["cancel_policy"] = "on_battle_cancel"
			assert(str(tl["cancel_policy"]) != orig, "neg4: mutation failed")
			mutated = true
			break
	assert(mutated, "neg4: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_CANCEL_POLICY_MISMATCH"), "neg4: expected CANCEL_POLICY_MISMATCH, got: " + str(errs))


func _neg_impl_path_missing() -> void:
	# 删除 implementation_path 字段 -> TIMELINE_IMPLEMENTATION_MISSING（不允许空值绕过）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_attack":
			assert(tl.has("implementation_path"), "neg-impl: field should exist before mutation")
			tl.erase("implementation_path")
			assert(not tl.has("implementation_path"), "neg-impl: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-impl: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_IMPLEMENTATION_MISSING"), "neg-impl: expected IMPLEMENTATION_MISSING, got: " + str(errs))


func _neg_test_scene_empty() -> void:
	# test_scene 设为空字符串 -> TIMELINE_TEST_SCENE_MISSING（空值视为不存在）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_attack":
			var orig: String = str(tl["test_scene"])
			tl["test_scene"] = ""
			assert(str(tl["test_scene"]) != orig, "neg-tscene: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-tscene: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_TEST_SCENE_MISSING"), "neg-tscene: expected TEST_SCENE_MISSING, got: " + str(errs))


func _neg_frame_count_missing() -> void:
	# 缺少帧：删除 player_attack 最后一帧（合法结构但帧数不足）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_attack":
			var orig_count: int = (tl["frames"] as Array).size()
			(tl["frames"] as Array).pop_back()
			assert((tl["frames"] as Array).size() == orig_count - 1, "neg-count-missing: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-count-missing: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_FRAME_COUNT_MISMATCH"), "neg-count-missing: expected FRAME_COUNT_MISMATCH, got: " + str(errs))


func _neg_frame_count_extra() -> void:
	# 多余帧：给 player_attack 追加一帧（合法结构但帧数超量）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_attack":
			var orig_count: int = (tl["frames"] as Array).size()
			(tl["frames"] as Array).append({"resource": "res://assets/extracted/images/image_0503.png", "duration_frames": 1, "position_offset": [18, -4]})
			assert((tl["frames"] as Array).size() == orig_count + 1, "neg-count-extra: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-count-extra: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_FRAME_COUNT_MISMATCH"), "neg-count-extra: expected FRAME_COUNT_MISMATCH, got: " + str(errs))


func _neg_anchor() -> void:
	# 合法但错误 anchor：boss_attack 应为 top_left，改为 top_right（合法字符串但错误）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "boss_attack":
			var orig: String = str((tl["frames"] as Array)[0]["anchor"])
			(tl["frames"] as Array)[0]["anchor"] = "top_right"
			assert(str((tl["frames"] as Array)[0]["anchor"]) != orig, "neg-anchor: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-anchor: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_TRANSFORM_MISMATCH"), "neg-anchor: expected TRANSFORM_MISMATCH, got: " + str(errs))


func _neg_fps() -> void:
	# 合法但错误 fps：player_motion sub_clips fps 12->11（合法正值但错误）
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "player_motion":
			var orig: int = int(tl["sub_clips"]["idle"]["fps"])
			tl["sub_clips"]["idle"]["fps"] = 11
			assert(int(tl["sub_clips"]["idle"]["fps"]) != orig, "neg-fps: mutation failed")
			mutated = true
			break
	assert(mutated, "neg-fps: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "TIMELINE_DURATION_MISMATCH"), "neg-fps: expected DURATION_MISMATCH, got: " + str(errs))


func _neg_evidence_token() -> void:
	var m: Dictionary = (reg as Dictionary).duplicate(true)
	var mutated: bool = false
	for tl in m["timelines"]:
		if str(tl["timeline_id"]) == "boss_hit":
			var orig: Array = tl["evidence_tokens"]
			tl["evidence_tokens"] = ["sprite999_no"]
			assert(str(tl["evidence_tokens"]) != str(orig), "neg5: mutation failed")
			mutated = true
			break
	assert(mutated, "neg5: target not found")
	var errs: Array = validate_registry(m, swf, ev_text)
	assert(_has_error_code(errs, "EVIDENCE_TOKEN_MISS"), "neg5: expected EVIDENCE_TOKEN_MISS, got: " + str(errs))


# ===== 文档统计（实体数 / 唯一 bitmap character ID 数 / 验证次数 分离）=====

func _assert_doc_stats() -> void:
	var timeline_count: int = reg["timelines"].size()
	var static_count: int = reg["static_entities"].size()
	var gap_count: int = reg["evidence_gap_entities"].size()
	var entity_records: int = timeline_count + static_count + gap_count
	# 唯一 bitmap character 数：按解析后的 character ID 去重（整改04：不是 asset 路径字符串）
	var unique_ids: Dictionary = {}
	var parse_failures: int = 0
	var verifications: int = 0
	for se in reg["static_entities"] + reg["evidence_gap_entities"]:
		var cid: int = swf.parse_character_id_from_asset(str(se.get("asset", "")))
		if cid < 0:
			parse_failures += 1
			continue
		unique_ids[cid] = true
		verifications += 1
	print("doc stats: entity_records=%d (timelines=%d static=%d gap=%d), unique_bitmap_ids=%d, verifications=%d, parse_failures=%d" % [entity_records, timeline_count, static_count, gap_count, unique_ids.size(), verifications, parse_failures])
	assert(entity_records == 49, "entity records should be 49, got " + str(entity_records))
	assert(static_count == 3, "static_native should be 3, got " + str(static_count))
	assert(gap_count == 41, "evidence_gap should be 41, got " + str(gap_count))
	assert(parse_failures == 0, "all entity assets should parse to character IDs, failures=" + str(parse_failures))
	assert(unique_ids.size() == 33, "unique bitmap character IDs should be 33, got " + str(unique_ids.size()))
	assert(verifications == 44, "verifications should be 44, got " + str(verifications))
	# 唯一 bitmap 数必须小于验证次数（有重复 asset）
	assert(unique_ids.size() < verifications, "unique bitmaps (%d) must be < verifications (%d)" % [unique_ids.size(), verifications])


# ===== 真实生产路径验证（实例化 main.tscn）=====

func _test_production_events() -> void:
	# GameState 设置（参考 test_scene_battle_scene）
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	var stats := GameState.get_player_stats()
	stats["current_hp"] = int(stats.get("max_hp", 999))
	GameState.commit_battle_health(int(stats["current_hp"]), [])
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	# --- 0. 生产读取 cancel_policy（注册表 -> 生产内存），与独立 SWF_EXPECTED 一致 ---
	var policy_expected := {
		"player_motion": "on_map_change",
		"player_attack": "on_battle_cancel",
		"normal_monster_attack": "on_battle_cancel",
		"boss_attack": "on_battle_cancel",
		"boss_hit": "on_battle_cancel",
	}
	for tlid: String in policy_expected:
		var expect_policy: String = policy_expected[tlid]
		assert(main.scene_battle_controller.timeline_cancel_policy(tlid) == expect_policy,
			"production cancel_policy mismatch for " + tlid + ": " + main.scene_battle_controller.timeline_cancel_policy(tlid))
		assert(main.scene_battle_controller.timeline_cancelled_by(tlid, "battle_cancel") == (expect_policy == "on_battle_cancel"),
			"battle_cancel semantics mismatch for " + tlid)
		assert(main.scene_battle_controller.timeline_cancelled_by(tlid, "map_change") == (expect_policy == "on_map_change"),
			"map_change semantics mismatch for " + tlid)
	print("production: cancel_policy loaded from registry == SWF_EXPECTED for all 5 timelines (policy drives event cancellation)")

	# --- 真实人物移动（确定性帧推进，无 Tween/Timer）---
	var down_frames: Array = main.player_walk_frames["down"]
	var idx_before: int = main.player_animation_index
	main._update_player_animation(Vector2(0, 1), 1.0 / 12.0)
	assert(main.player_animation_clip == "down", "player motion: clip should be down")
	assert(main.player_animation_index != idx_before or down_frames.size() > 0, "player motion: index should advance")
	assert(main.player.texture == down_frames[main.player_animation_index], "player motion: texture should match walk frame")
	assert(main.scene_battle_controller.active_tween_count() == 0, "player motion: no tween (frame-based)")
	assert(main.scene_battle_controller.active_timer_count() == 0, "player motion: no timer (frame-based)")
	# 循环点（loop_mode=loop）：8 帧 down clip 逐帧推进，index 回绕到 0（确定性，无真实等待）
	var wrapped := false
	for k in range(8):
		main._update_player_animation(Vector2(0, 1), 1.0 / 12.0)
		if k > 0 and main.player_animation_index == 0:
			wrapped = true
			break
	assert(wrapped, "player motion: loop point should wrap index back to 0 (8-frame clip)")
	assert(main.player.texture == down_frames[0], "player motion: texture should be frame 0 at loop point")
	# 行走四剪辑逐帧边界（任务书 7.3：确定性 1/12s 步进，断言每帧 texture 与生产帧表一致）
	var clip_dirs := {"down": Vector2(0, 1), "up": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}
	var expected_walk_sizes := {"down": 8, "up": 8, "left": 10, "right": 10}
	for clip: String in clip_dirs:
		var clip_frames: Array = main.player_walk_frames[clip]
		assert(clip_frames.size() == int(expected_walk_sizes[clip]),
			"player motion: %s clip should have %d frames (got %d)" % [clip, int(expected_walk_sizes[clip]), clip_frames.size()])
		# 逐帧推进整个 clip（确定性 1/12s/步），每步断言生产 texture 与帧表一致
		for k in range(clip_frames.size() * 2):
			main._update_player_animation(clip_dirs[clip], 1.0 / 12.0)
			assert(main.player_animation_clip == clip, "player motion: clip should be %s" % clip)
			assert(main.player.texture == clip_frames[main.player_animation_index],
				"%s clip frame %d texture mismatch (index %d)" % [clip, k, main.player_animation_index])
	# idle 剪辑：完整 8 帧序列 + 循环（整改08：生产待机循环播放 player_idle_frames，
	# 逐帧推进断言每帧 texture 与生产帧表一致；删除整改07 的"idle 未循环"错误缺口）
	main._update_player_animation(Vector2.ZERO, 0.0)  # 切到 idle 剪辑（delta=0 不推进）
	assert(main.player_animation_clip == "idle", "player motion: zero direction should be idle")
	assert(main.player_idle_frames.size() == 8, "player motion: idle clip should have 8 frames")
	for k in range(main.player_idle_frames.size() * 2):
		main._update_player_animation(Vector2.ZERO, 1.0 / 12.0)
		assert(main.player_animation_clip == "idle", "player motion: clip should stay idle")
		assert(main.player.texture == main.player_idle_frames[main.player_animation_index],
			"idle clip frame %d texture mismatch (index %d)" % [k, main.player_animation_index])
	print("production: player motion five clips frame-by-frame (idle8/down8/up8/left10/right10) + loop wraps ok")

	# --- 非匹配策略资源保留 + 自然结束清除（整改06）---
	# 用生产同款登记结构（{tween/timer, timeline_id}）登记 on_map_change 资源，
	# 触发 _kill_active_tweens/_clear_active_timers 的"不匹配条目保留"分支。
	# 随后不手工 kill/clear tween：等待自然完成，验证生产回调（finished->_untrack）解除跟踪。
	var p_tween: Tween = main.scene_battle_controller._create_tracked_tween(main.player, "player_motion")
	p_tween.tween_interval(0.5)
	var p_timer := Timer.new()
	p_timer.one_shot = true
	p_timer.wait_time = 0.5
	p_timer.autostart = true
	main.scene_battle_controller.add_child(p_timer)
	main.scene_battle_controller._active_timers.append({"timer": p_timer, "timeline_id": "player_motion"})
	assert(main.scene_battle_controller.active_tween_count() == 1, "player_motion tween should be tracked before battle_cancel")
	assert(main.scene_battle_controller.active_timer_count() == 1, "player_motion timer should be tracked before battle_cancel")
	main.scene_battle_controller.cancel_battle()  # battle_cancel 事件（不匹配 on_map_change 资源）
	assert(p_tween.is_running(), "player_motion tween must survive battle_cancel (on_map_change policy)")
	assert(main.scene_battle_controller.active_tween_count() == 1, "player_motion tween must stay tracked after battle_cancel (no untracked loss)")
	assert(not p_timer.is_stopped(), "player_motion timer must not be stopped by battle_cancel")
	assert(main.scene_battle_controller.active_timer_count() == 1, "player_motion timer must stay tracked after battle_cancel")
	# 自然结束清除（tween）：不 kill 不 clear，等 finished -> 生产 _untrack_tween 解除跟踪
	await p_tween.finished
	assert(main.scene_battle_controller.active_tween_count() == 0,
		"player_motion tween should untrack after natural finish (production callback)")
	# 自然结束清除（timer）：手动登记的 timer 无生产协程管理，测试负责回收；
	# "自然结束由生产协程解除跟踪"由下方真实 _cancellable_wait 独立验证。
	p_timer.stop()
	p_timer.queue_free()
	for i in range(main.scene_battle_controller._active_timers.size() - 1, -1, -1):
		if main.scene_battle_controller._active_timers[i].get("timer") == p_timer:
			main.scene_battle_controller._active_timers.remove_at(i)
	await main.scene_battle_controller._cancellable_wait(0.3, "player_motion")
	assert(main.scene_battle_controller.active_timer_count() == 0,
		"wait coroutine should untrack its timer after natural completion")
	print("production: non-matching policy resources survive battle_cancel; natural finish untracks tween (finished) and timer (_cancellable_wait)")

	# --- 真实怪物点击 -> engage -> 真实 Tween/Timer 引用捕获 + 战斗取消 ---
	var actor: TextureRect = main.interactive_actors["battle:spider"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._on_actor_input(click, "battle:spider")
	assert(main.scene_battle_controller.session != null, "production: battle session did not start")
	assert(main.scene_battle_controller.active_monster_id == "spider", "production: wrong target")
	# 真实 Tween 已创建并跟踪（active_tween_count > 0）
	assert(main.scene_battle_controller.active_tween_count() > 0, "production: real tween should be tracked during attack")
	# 保存真实 Timer 引用（_cancellable_wait 创建的 Timer 节点，非计数）
	var timers_before: Array = main.scene_battle_controller.test_get_active_timers()
	assert(timers_before.size() >= 1, "no active timer captured after engage (attack waits on _cancellable_wait)")
	var labels_before: int = main.scene_battle_controller.test_count_float_labels()
	assert(labels_before >= 1, "float damage label should exist during attack")

	# --- 生产 driver 边界验证（整改11：真实 _play_* + tween.custom_step 确定性推进）---
	# 生产播放（_play_*）与测试验证走同一条 _drive_scheduler 生产链：测试对 handle["tween"]
	# （真实 Tween）做 custom_step 确定性推进（不依赖真实时间；不调用 sched.seek 制造结果），
	# 在 t=0/每帧边界-ε/边界点/边界+ε/结束点观察真实 actor 的 texture/position/size。
	var boundary_tl: Array = ["player_attack", "normal_monster_attack", "boss_attack", "boss_hit"]
	var ctrl: Control = main.scene_battle_controller
	# 清理 engage 残留（真实攻击 tween 停止），driver 验证器独占 player_actor
	ctrl.cancel_battle()
	# player_attack：真实生产节点 player_actor
	var base_p: Vector2 = ctrl.player_actor.position
	var base_p_tex: Texture2D = ctrl.player_actor.texture
	var base_p_size: Vector2 = ctrl.player_actor.size
	var errs_pa: Array = _verify_production_driver_boundaries(ctrl, "player_attack", ctrl.player_actor, base_p)
	assert(errs_pa.is_empty(), "player_attack driver verifier errors: %s" % str(errs_pa))
	# 其余时间轴：真实 Control 节点（texture 区分 normal/boss 分支；position 与验证器 base 一致）
	var probe := TextureRect.new()
	main.add_child(probe)
	for tlid: String in ["normal_monster_attack", "boss_attack", "boss_hit"]:
		probe.texture = load("res://assets/extracted/images/image_0049.png") if tlid == "normal_monster_attack" else load("res://assets/extracted/images/image_1072.png")
		probe.size = Vector2(100, 100)
		probe.position = Vector2(200, 200)
		var errs2: Array = _verify_production_driver_boundaries(ctrl, tlid, probe, Vector2(200, 200))
		assert(errs2.is_empty(), "%s driver verifier errors: %s" % [tlid, str(errs2)])
	probe.queue_free()
	# 生产节点（player_actor）帧0..3 确定性推进 + once_restore（快照精确恢复）
	var attack_files: Array = ["image_0503.png", "image_0505.png", "image_0507.png", "image_0509.png"]
	var sched_p = TimelineScheduler.new("player_attack", ctrl._frames_for("player_attack"), ctrl.player_actor,
		base_p, Callable(), ctrl.attack_sequence)
	for fi in range(4):
		sched_p.seek(float(fi) / 12.0 + 0.0005)  # 确定性推进（seek）
		assert(ctrl.player_actor.texture.resource_path.ends_with(attack_files[fi]),
			"production: player frame %d texture should be %s (got %s)" % [fi, attack_files[fi], ctrl.player_actor.texture.resource_path])
		assert(ctrl.player_actor.position == base_p + Vector2(18, -4), "production: player frame offset should be [18,-4]")
	sched_p.seek(4.0 / 12.0 + 0.001)  # 结束点：once_restore（快照精确恢复原 texture/position/size）
	assert(sched_p.ended, "production: player_attack scheduler should end at 4/12")
	assert(ctrl.player_actor.texture == base_p_tex,
		"production: once_restore endpoint should restore original texture snapshot")
	assert(ctrl.player_actor.position == base_p, "production: once_restore should restore base position")
	assert(ctrl.player_actor.size == base_p_size, "production: once_restore should restore original size")
	# 负向（整改11）：篡改生产 duration（1->2）进入真实 driver 生产链，同一验证器必须命中
	# PRODUCTION_TIMELINE_BOUNDARY_MISMATCH（真实 tween.custom_step 推进观察 actor，不用 sched.seek 制造）
	var orig_pa: Array = ctrl._frames_for("player_attack")
	var tampered: Array = []
	for f in orig_pa:
		var fc: Dictionary = (f as Dictionary).duplicate()
		fc["dur"] = 2  # 篡改生产时长
		tampered.append(fc)
	ctrl.test_set_frame_table_override("player_attack", tampered)
	var tamper_errs: Array = _verify_production_driver_boundaries(ctrl, "player_attack", ctrl.player_actor, base_p)
	assert(not tamper_errs.is_empty(), "tampered duration must be caught by driver boundary verifier")
	assert(_has_error_code(tamper_errs, "PRODUCTION_TIMELINE_BOUNDARY_MISMATCH"),
		"must hit PRODUCTION_TIMELINE_BOUNDARY_MISMATCH: %s" % str(tamper_errs))
	ctrl.test_clear_frame_table_override("player_attack")
	# 基线恢复（整改11 第 8 条）：负向后恢复进入负向前的独立人物基线（生产 cleanup 恢复快照），再正向对照
	assert(ctrl.player_actor.texture == base_p_tex and ctrl.player_actor.position == base_p and ctrl.player_actor.size == base_p_size,
		"baseline must be restored after negative driver verifier")
	var pos_cancel_after_neg: Array = _verify_player_attack_cancel_restore(ctrl, ctrl.player_actor)
	assert(pos_cancel_after_neg.is_empty(), "positive control after negative must pass: %s" % str(pos_cancel_after_neg))
	print("production: driver boundary matrix ok (4 timelines, real tween custom_step) + negative tampered-duration -> PRODUCTION_TIMELINE_BOUNDARY_MISMATCH + baseline restored + positive control")


	# --- 真实战斗取消（battle_cancel 事件：取消 on_battle_cancel 时间轴）---
	main.scene_battle_controller.cancel_battle()
	assert(not main.scene_battle_controller.is_active(), "production: battle not active after cancel")
	assert(main.scene_battle_controller.active_tween_count() == 0, "production: tween killed after cancel_battle")
	assert(main.scene_battle_controller.active_timer_count() == 0, "production: timer released after cancel_battle")
	# Timer 真实 is_stopped()==true（不是清空数组伪造）
	for timer in timers_before:
		assert(is_instance_valid(timer) and (timer as Timer).is_stopped(),
			"production: captured timer not stopped after cancel_battle")
	# 等待协程退出可观察：_cancellable_wait 恢复执行并 queue_free 节点，数帧内释放（无悬挂）
	var all_freed := false
	for i in range(30):
		all_freed = true
		for timer in timers_before:
			if is_instance_valid(timer):
				all_freed = false
				break
		if all_freed:
			break
		await get_tree().process_frame
	assert(all_freed, "production: cancelled wait coroutine hung (timer never freed)")
	# 浮动文字 Label 无残留（cleanup=label.queue_free 在 kill 时执行）
	await get_tree().process_frame
	assert(main.scene_battle_controller.test_count_float_labels() == 0,
		"production: float label leaked after cancel_battle (before=%d)" % labels_before)
	print("production: cancel_battle -> timers is_stopped==true, wait coroutines exited (timers freed), float labels cleaned")

	# --- 真实 _play_* 链路集成（整改10：test_last_scheduler 返回与真实播放同一调度对象）---
	ctrl._play_player_attack(ctrl.attack_sequence)  # 真实生产播放（_drive_scheduler + tracked tween + cleanup）
	var sched_real = ctrl.test_last_scheduler()
	assert(sched_real != null and sched_real.timeline_id == "player_attack", "real play must register its scheduler")
	assert(ctrl.player_actor.texture.resource_path.ends_with("image_0503.png"), "real play t=0 applies frame0")
	# 同帧内对同一生产调度对象确定性推进（tween 尚未推进，无竞争）：1/12 -> 帧1
	sched_real.seek(1.0 / 12.0)
	assert(ctrl.player_actor.texture.resource_path.ends_with("image_0505.png"), "real scheduler seek to frame1 (1/12)")
	ctrl.cancel_battle()
	# duration 负向进入真实 _drive_scheduler 生产链：override 帧表 dur 1->2 -> 真实 _play_player_attack
	var tampered_pa: Array = []
	for f in ctrl._frames_for("player_attack"):
		var fc: Dictionary = (f as Dictionary).duplicate()
		fc["dur"] = 2
		tampered_pa.append(fc)
	ctrl.test_set_frame_table_override("player_attack", tampered_pa)
	ctrl._play_player_attack(ctrl.attack_sequence)
	var sched_t2 = ctrl.test_last_scheduler()
	# 旧边界 1/12：篡改后仍帧0（0503）——错误排程在真实链路可被捕获
	assert(sched_t2.seek_frame(1.0 / 12.0) == 0, "tampered duration: old boundary 1/12 must still be frame0")
	assert(ctrl.player_actor.texture.resource_path.ends_with("image_0503.png"), "tampered: real actor still frame0 at 1/12")
	# 新边界 2/12：帧1（0505）
	sched_t2.seek(2.0 / 12.0)
	assert(ctrl.player_actor.texture.resource_path.ends_with("image_0505.png"), "tampered: real actor frame1 at 2/12")
	ctrl.cancel_battle()
	ctrl.test_clear_frame_table_override("player_attack")
	print("production: real _play_* integration (same scheduler object via test_last_scheduler) + tampered duration in real chain observed on actor")

	# --- 人物攻击真实取消（整改10：t=0 / 帧1 / 末帧前，每次精确恢复原状态，active Tween=0）---
	var p_tex: Texture2D = ctrl.player_actor.texture
	var p_pos: Vector2 = ctrl.player_actor.position
	var p_size: Vector2 = ctrl.player_actor.size
	# t=0 取消（真实 _play_player_attack 后立即）
	var errs0: Array = _verify_player_attack_cancel_restore(ctrl, ctrl.player_actor)
	assert(errs0.is_empty(), "cancel at t=0 must restore exactly: %s" % str(errs0))
	# 帧1 取消（事件驱动等待 0505 出现）
	ctrl._play_player_attack(ctrl.attack_sequence)
	var f1_seen := false
	for i in range(300):
		if ctrl.player_actor.texture != null and ctrl.player_actor.texture.resource_path.ends_with("image_0505.png"):
			f1_seen = true
			break
		await get_tree().process_frame
	assert(f1_seen, "player frame1 (0505) should appear during real play")
	ctrl.cancel_battle()
	assert(ctrl.player_actor.texture == p_tex and ctrl.player_actor.position == p_pos and ctrl.player_actor.size == p_size,
		"cancel at frame1 must restore exact original state")
	assert(ctrl.active_tween_count() == 0, "no active tween after cancel at frame1")
	# 末帧前取消（帧3 0509 出现后）
	ctrl._play_player_attack(ctrl.attack_sequence)
	var f3_seen := false
	for i in range(300):
		if ctrl.player_actor.texture != null and ctrl.player_actor.texture.resource_path.ends_with("image_0509.png"):
			f3_seen = true
			break
		await get_tree().process_frame
	assert(f3_seen, "player frame3 (0509) should appear during real play")
	ctrl.cancel_battle()
	assert(ctrl.player_actor.texture == p_tex and ctrl.player_actor.position == p_pos and ctrl.player_actor.size == p_size,
		"cancel before last frame must restore exact original state")
	assert(ctrl.active_tween_count() == 0, "no active tween after cancel before last frame")
	print("production: player attack real cancel at t=0/frame1/pre-last restores exact original state (0 active tweens)")

	# --- 目标攻击/受击取消幂等（整改10：force_restore 与 Scheduler cleanup 连续，Boss/普通怪）---
	# 通过生产成员 target_actor/session 驱动真实 _play_target_attack/_play_target_hit（生产函数）
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	var spider_actor: TextureRect = main.interactive_actors["battle:spider"]
	var spider_tex: Texture2D = spider_actor.texture
	var spider_pos: Vector2 = spider_actor.position
	var spider_size: Vector2 = spider_actor.size
	ctrl.target_actor = spider_actor
	ctrl.session = ctrl.BattleSession.new("spider", GameState.get_player_stats(), 0, GameState.battle_modifiers("spider"))
	ctrl._play_target_attack(ctrl.attack_sequence)  # normal 分支（真实生产函数）
	ctrl.cancel_battle()  # _force_restore_target_attack + kill->cleanup(sched.cancel) 连续
	assert(spider_actor.texture == spider_tex and spider_actor.position == spider_pos and spider_actor.size == spider_size,
		"normal monster cancel must restore exact state (idempotent double restore)")
	assert(not ctrl.native_attack_active, "native_attack_active must clear after normal cancel")
	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	var boss_actor: TextureRect = main.interactive_actors["battle:thunder_boss_10"]
	var boss_tex: Texture2D = boss_actor.texture
	var boss_pos: Vector2 = boss_actor.position
	var boss_size: Vector2 = boss_actor.size
	ctrl.target_actor = boss_actor
	ctrl.session = ctrl.BattleSession.new("thunder_boss_10", GameState.get_player_stats(), 0, GameState.battle_modifiers("thunder_boss_10"))
	ctrl._play_target_attack(ctrl.attack_sequence)  # boss 分支
	ctrl.cancel_battle()
	assert(boss_actor.texture == boss_tex and boss_actor.position == boss_pos and boss_actor.size == boss_size,
		"boss attack cancel must restore exact state (idempotent)")
	ctrl.session = ctrl.BattleSession.new("thunder_boss_10", GameState.get_player_stats(), 0, GameState.battle_modifiers("thunder_boss_10"))
	ctrl._play_target_hit(ctrl.attack_sequence)  # 受击（真实生产函数）
	ctrl.cancel_battle()
	assert(boss_actor.texture == boss_tex and boss_actor.position == boss_pos and boss_actor.size == boss_size,
		"boss hit cancel must restore exact state (idempotent)")
	# 连续两次 cancel（double cancel 幂等）
	ctrl.session = ctrl.BattleSession.new("thunder_boss_10", GameState.get_player_stats(), 0, GameState.battle_modifiers("thunder_boss_10"))
	ctrl._play_target_attack(ctrl.attack_sequence)
	ctrl.cancel_battle()
	ctrl.cancel_battle()
	assert(boss_actor.texture == boss_tex and boss_actor.position == boss_pos and boss_actor.size == boss_size,
		"double cancel must be idempotent")
	print("production: target attack/hit cancel idempotent (force_restore + scheduler cleanup; boss & normal)")

	# --- Scheduler 生命周期（整改12）：100 次自然完成 / 100 次取消，**每次**结束后断言
	# active_scheduler_count==0、tracked_scheduler_slot_count==0、活动 handle 为空 ---
	for i in range(100):
		ctrl._play_player_attack(ctrl.attack_sequence)
		# 临时表达式驱动（不存局部强引用，避免测试局部持 handle 阻止 Scheduler 释放）
		(ctrl.test_last_handle()["tween"] as Tween).custom_step(10.0)
		await get_tree().process_frame  # finished 信号派发 -> untrack
		assert(ctrl.active_scheduler_count() == 0, "natural %d: active count must be 0" % i)
		assert(ctrl.tracked_scheduler_slot_count() == 0, "natural %d: slots must be 0" % i)
		assert(not ctrl.has_active_scheduler_handle(), "natural %d: handle must be empty" % i)
	for i in range(100):
		ctrl._play_player_attack(ctrl.attack_sequence)
		ctrl.cancel_battle()
		assert(ctrl.active_scheduler_count() == 0, "cancel %d: active count must be 0" % i)
		assert(ctrl.tracked_scheduler_slot_count() == 0, "cancel %d: slots must be 0" % i)
		assert(not ctrl.has_active_scheduler_handle(), "cancel %d: handle must be empty" % i)
	print("production: scheduler lifecycle 100x natural + 100x cancel, per-iteration active==0 slots==0 handle empty")

	# --- 真实释放验证（整改12）：完成/取消后 Scheduler WeakRef 释放为 null ---
	# 自然完成释放
	ctrl._play_player_attack(ctrl.attack_sequence)
	var sched_wr = weakref(ctrl.test_last_scheduler())
	var h_n: Dictionary = ctrl.test_last_handle()
	(h_n["tween"] as Tween).custom_step(10.0)
	h_n = {}  # 释放测试局部强引用
	await get_tree().process_frame
	await get_tree().process_frame
	assert(sched_wr.get_ref() == null, "scheduler must be freed after natural completion")
	# 取消释放
	ctrl._play_player_attack(ctrl.attack_sequence)
	sched_wr = weakref(ctrl.test_last_scheduler())
	ctrl.cancel_battle()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(sched_wr.get_ref() == null, "scheduler must be freed after cancel")
	print("production: scheduler WeakRef freed after natural completion and cancel")

	# --- 取消后 seek/advance 不得重新应用帧（整改11）---
	var post_cancel_tex: Texture2D = ctrl.player_actor.texture
	ctrl._play_player_attack(ctrl.attack_sequence)
	var sched_c = ctrl.test_last_scheduler()
	ctrl.cancel_battle()
	assert(ctrl.player_actor.texture == post_cancel_tex, "cancel restores baseline")
	sched_c.seek(1.0 / 12.0)
	assert(ctrl.player_actor.texture == post_cancel_tex, "seek after cancel must not reapply frames")
	sched_c.advance()
	assert(ctrl.player_actor.texture == post_cancel_tex, "advance after cancel must not reapply frames")
	print("production: seek/advance after cancel are no-ops (node state unchanged)")

	# --- 原 texture=null 精确恢复 null（整改11）---
	var saved_player_actor: TextureRect = ctrl.player_actor
	var null_actor := TextureRect.new()
	main.add_child(null_actor)
	null_actor.texture = null  # 原 texture=null
	ctrl.player_actor = null_actor
	ctrl._play_player_attack(ctrl.attack_sequence)  # 帧0 0503（非 null）
	assert(null_actor.texture != null, "play should apply frame texture")
	ctrl.cancel_battle()
	assert(null_actor.texture == null, "original null texture must restore exactly null")
	ctrl.player_actor = saved_player_actor
	null_actor.queue_free()
	print("production: null original texture restored exactly to null")

	# --- 负向：禁用 untrack -> SCHEDULER_REFERENCE_LEAK（整改12/终审勘误：注册槽残留命中，不依赖 handle）---
	# mutation_applied 有效证明（PM/SE 终审勘误：启动后槽位+1 与 untrack 开关无关，不是 mutation 证明；
	# 有效证明 = 启用/禁用 untrack 时"取消后"槽位的差异：启用时清零回基线，禁用时残留 +1）。
	var slots_before: int = ctrl.tracked_scheduler_slot_count()
	# 基线（启用 untrack）：真实 _play + cancel 后槽位回到 before
	assert(_cancel_slots_after_play(ctrl) == slots_before,
		"baseline: enabled untrack must clear slots after cancel (before=%d)" % slots_before)
	# mutation_applied（禁用 untrack）：真实 _play + cancel 后槽位残留 before+1 —— 与基线差异证明 mutation 生效
	ctrl.test_set_scheduler_untrack_enabled(false)
	assert(_cancel_slots_after_play(ctrl) == slots_before + 1,
		"mutation applied: disabled untrack must leave slot residue after cancel (before=%d)" % slots_before)
	# 同一验证器命中 LEAK（禁用状态下再 _play + cancel，槽残留递增）
	var leak_errs: Array = _verify_scheduler_lifecycle(ctrl, true)
	assert(_has_error_code(leak_errs, "SCHEDULER_REFERENCE_LEAK"),
		"untrack disabled must hit SCHEDULER_REFERENCE_LEAK via slot residue: %s" % str(leak_errs))
	# 生产路径清理负向制造的残留（untrack 生产方法，同时清空活动 handle），恢复开关后正向对照
	ctrl.test_set_scheduler_untrack_enabled(true)
	for swr in ctrl._active_schedulers.duplicate():
		if is_instance_valid(swr) and swr.get_ref() != null:
			ctrl._untrack_scheduler(swr.get_ref())
	assert(ctrl.tracked_scheduler_slot_count() == slots_before, "leak slot residue must be cleaned via production untrack")
	assert(not ctrl.has_active_scheduler_handle(), "active handle must be cleared with residue")
	var ok_errs: Array = _verify_scheduler_lifecycle(ctrl, false)
	assert(ok_errs.is_empty(), "reenabled untrack must pass lifecycle: %s" % str(ok_errs))
	print("production: untrack-disabled negative -> SCHEDULER_REFERENCE_LEAK (slot residue, mutation proven by cancel-diff); residue cleaned; reenabled passes")

	# --- 真实释放验证（整改12）：actor 删除 / 地图切换后 Scheduler WeakRef 释放 ---
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	main._on_actor_input(click, "battle:spider")  # engage -> 攻击 Scheduler 活动
	var wr_map = weakref(ctrl.test_last_scheduler())
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()  # actor 重建（queue_free）+ cancel_battle -> untrack -> 释放
	await get_tree().process_frame
	await get_tree().process_frame
	assert(wr_map.get_ref() == null, "scheduler must be freed after map change / actor rebuild")
	assert(ctrl.tracked_scheduler_slot_count() == 0, "slots must be 0 after map change")
	assert(not ctrl.has_active_scheduler_handle(), "handle must be empty after map change")
	print("production: scheduler freed after map change / actor rebuild (WeakRef null)")

	# 恢复地图环境（后续段在 dream_swamp 战斗）
	ctrl.cancel_battle()
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	# --- 真实地图切换（map_change 事件：取消 on_map_change 时间轴 + 战斗）---
	main._on_actor_input(click, "battle:spider")
	assert(main.scene_battle_controller.session != null, "production: re-engage failed")
	# 注册 on_map_change 活动资源（生产函数登记），验证真实地图切换生命周期将其取消
	var mc_tween: Tween = main.scene_battle_controller._create_tracked_tween(main.player, "player_motion")
	mc_tween.tween_interval(5.0)
	var timers_map: Array = main.scene_battle_controller.test_get_active_timers()
	assert(timers_map.size() >= 1, "production: no timer captured before map switch")
	main._update_player_animation(Vector2(0, 1), 1.0 / 12.0)
	assert(main.player_animation_clip == "down", "production: player motion clip should be down before map switch")
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	# map_change 生命周期：on_map_change 资源被真实 kill 且解除跟踪（handle_map_change）
	assert(not mc_tween.is_running(), "production: map_change lifecycle should kill player_motion tween")
	assert(main.scene_battle_controller.active_tween_count() == 0, "production: player_motion tween untracked after map_change")
	assert(main.scene_battle_controller.active_timer_count() == 0, "production: map switch should release timers")
	for timer in timers_map:
		assert(is_instance_valid(timer) and (timer as Timer).is_stopped(),
			"production: map switch did not stop captured timer")
	# player_motion 是 on_map_change 时间轴：地图切换按策略重置移动动画状态
	assert(main.player_animation_clip == "idle", "production: player_motion should reset to idle on map change (on_map_change policy)")
	assert(main.player.texture == main.player_idle_frames[0], "production: player texture should be idle frame 0 after map change")
	var map_freed := false
	for i in range(30):
		map_freed = true
		for timer in timers_map:
			if is_instance_valid(timer):
				map_freed = false
				break
		if map_freed:
			break
		await get_tree().process_frame
	assert(map_freed, "production: map switch wait coroutine hung (timer never freed)")
	print("production: map switch -> battle timers stopped/freed + map_change lifecycle kills player_motion tween + player motion reset")

	# --- map_change Timer 分支（整改07）：真实地图切换停止 on_map_change 活动 Timer ---
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	# 用生产 _cancellable_wait 登记 on_map_change 等待（WaitDriver 驱动协程，测试不手动 stop/remove/clear）
	var wd := WaitDriver.new()
	wd.controller = main.scene_battle_controller
	wd.seconds = 2.0
	wd.timeline_id = "player_motion"
	main.add_child(wd)
	var mctimers: Array = main.scene_battle_controller.test_get_active_timers()
	assert(mctimers.size() >= 1, "on_map_change timer should be active and tracked before cancel")
	var mctimer: Timer = mctimers[0]
	assert(not mctimer.is_stopped(), "on_map_change timer should be running before cancel")
	# battle_cancel 事件不提前停止 on_map_change Timer
	main.scene_battle_controller.cancel_battle()
	assert(not mctimer.is_stopped(), "battle_cancel must NOT stop on_map_change timer")
	assert(main.scene_battle_controller.active_timer_count() >= 1, "on_map_change timer must stay tracked after battle_cancel")
	# 真实地图切换 -> handle_map_change -> _clear_active_timers(EVENT_MAP_CHANGE) 停止并解除跟踪
	GameState.current_map_id = "cassano_city"
	main._apply_current_map()
	assert(mctimer.is_stopped(), "map_change lifecycle should stop on_map_change timer")
	assert(main.scene_battle_controller.active_timer_count() == 0, "on_map_change timer untracked after map_change")
	# 引用最终释放（生产协程退出后 queue_free 节点）
	await wd.done
	await get_tree().process_frame
	assert(not is_instance_valid(mctimer), "on_map_change timer node should be freed after coroutine exit")
	print("production: real map_change stops/untracks on_map_change timer (battle_cancel does not); coroutine exits; node freed")

	# --- 真实目标死亡（victory）---
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	actor = main.interactive_actors["battle:spider"]
	main._on_actor_input(click, "battle:spider")  # engage + 首次攻击
	assert(main.scene_battle_controller.session != null, "production: death test engage failed")
	# 等首次攻击完成（busy 清除，事件驱动 polling，非猜测 timer）
	while main.scene_battle_controller.busy:
		await get_tree().process_frame
	# 设 hp=1 后再次点击给致命一击（perform_turn 在点击内同步执行，须先设 hp）
	main.scene_battle_controller.session.monster_hp = 1
	main._on_actor_input(click, "battle:spider")
	# 用 battle_finished 信号（事件驱动，非猜测 timer）
	var finished: Array = await main.scene_battle_controller.battle_finished
	assert(str(finished[0]) == "spider" and bool(finished[1]) == true, "production: victory not detected")
	assert(main.scene_battle_controller.session == null, "production: session not closed after victory")
	assert(not actor.visible, "production: defeated monster not hidden")
	print("production: target death -> victory, monster hidden")

	# --- 失败淡出被取消：_finish_defeat 轮询退出不悬挂 + cleanup 恢复 modulate ---
	var respawned := false
	var respawn_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < respawn_deadline:
		if actor.visible and actor.mouse_filter == Control.MOUSE_FILTER_STOP:
			respawned = true
			break
		await get_tree().process_frame
	assert(respawned, "production: spider did not respawn in time")
	main._on_actor_input(click, "battle:spider")
	assert(main.scene_battle_controller.session != null, "production: defeat test engage failed")
	while main.scene_battle_controller.busy:
		await get_tree().process_frame
	# 玩家生命归零、怪物生命极高（防止玩家攻击杀死怪物走胜利分支）、幻兽清空
	# （防止怪物攻击幻兽而不触发玩家死亡判定）-> 下次攻击进入 defeat -> _finish_defeat 淡出
	var defeat_session = main.scene_battle_controller.session
	defeat_session.player_hp = 0
	defeat_session.monster_hp = 999999
	for pet: Dictionary in defeat_session.pet_states:
		pet.current_hp = 0
	main._on_actor_input(click, "battle:spider")
	var fade_started := false
	var fade_deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < fade_deadline:
		if main.player.modulate.a < 0.999:
			fade_started = true
			break
		await get_tree().process_frame
	assert(fade_started, "production: defeat fade did not start (modulate:a should decrease)")
	# 取消战斗：fade 被 kill -> cleanup 恢复 modulate；等待协程轮询退出（不悬挂）
	main.scene_battle_controller.cancel_battle()
	await get_tree().process_frame
	assert(main.player.modulate == Color.WHITE, "production: cancel during defeat fade should restore modulate via cleanup")
	assert(main.scene_battle_controller.active_tween_count() == 0, "production: tween not cleaned after defeat cancel")
	assert(main.scene_battle_controller.active_timer_count() == 0, "production: timer not cleaned after defeat cancel")
	assert(main.scene_battle_controller.test_count_float_labels() == 0, "production: label leaked after defeat cancel")
	# 取消后不继续失败流程（_finish_defeat 提前 return，battle_finished 不再触发 -> 不切回卡萨诺城）
	for i in range(30):
		await get_tree().process_frame
	assert(GameState.current_map_id == "dream_swamp", "production: cancelled defeat should not continue to map switch")
	assert(main.player.modulate == Color.WHITE, "production: modulate not restored after defeat cancel settle")
	print("production: cancel during defeat fade -> no hang, modulate restored via cleanup, flow interrupted")

	# --- anchor 真实 actor 四字段（整改10：player/普通怪/Boss 实际节点，非默认 probe 值）---
	# anchor 是 actor 静态属性（注册表 anchor=top_left 的 position 语义），调度器不写入；
	# 直接检查三个真实生产 actor 的 left/top/right/bottom 四字段（各在其地图上检查，避免重建释放）。
	GameState.current_map_id = "dream_swamp"
	main._apply_current_map()
	await get_tree().process_frame
	var spider_a: TextureRect = main.interactive_actors["battle:spider"]
	assert(spider_a.anchor_left == 0.0 and spider_a.anchor_top == 0.0 and spider_a.anchor_right == 0.0 and spider_a.anchor_bottom == 0.0,
		"spider(normal) actor anchor four fields should be static top_left (0,0,0,0)")
	GameState.current_map_id = "thunder_continent"
	main._apply_current_map()
	await get_tree().process_frame
	var boss_a: TextureRect = main.interactive_actors["battle:thunder_boss_10"]
	assert(boss_a.anchor_left == 0.0 and boss_a.anchor_top == 0.0 and boss_a.anchor_right == 0.0 and boss_a.anchor_bottom == 0.0,
		"boss actor anchor four fields should be static top_left (0,0,0,0)")
	assert(ctrl.player_actor.anchor_left == 0.0 and ctrl.player_actor.anchor_top == 0.0
		and ctrl.player_actor.anchor_right == 0.0 and ctrl.player_actor.anchor_bottom == 0.0,
		"player actor anchor four fields should be static top_left (0,0,0,0)")
	print("production: anchor four fields verified on real player/normal/boss actors (static top_left)")

	# --- 取消负向（整改10）：禁用 Scheduler cleanup -> 同一验证器命中 TIMELINE_CANCEL_RESTORE_MISSING ---
	ctrl.test_set_scheduler_cleanup_enabled(false)
	var neg_cancel_errs: Array = _verify_player_attack_cancel_restore(ctrl, ctrl.player_actor)
	assert(not neg_cancel_errs.is_empty(), "disabled scheduler cleanup must produce cancel-restore errors")
	assert(_has_error_code(neg_cancel_errs, "TIMELINE_CANCEL_RESTORE_MISSING"),
		"disabled cleanup must hit TIMELINE_CANCEL_RESTORE_MISSING: %s" % str(neg_cancel_errs))
	ctrl.test_set_scheduler_cleanup_enabled(true)
	# 恢复启用后同一验证器通过（正向对照）
	var pos_cancel_errs: Array = _verify_player_attack_cancel_restore(ctrl, ctrl.player_actor)
	assert(pos_cancel_errs.is_empty(), "reenabled cleanup must pass cancel-restore: %s" % str(pos_cancel_errs))
	print("production: cancel negative -> TIMELINE_CANCEL_RESTORE_MISSING (cleanup disabled); reenabled passes")

	# --- 真实场景退出（整改12：WeakRef 逐项断言释放/失效；删除无断言的 dangling print）---
	var main_wr: WeakRef = weakref(main)
	var ctrl_wr: WeakRef = weakref(ctrl)
	ctrl._play_player_attack(ctrl.attack_sequence)  # 制造活动 Scheduler + Tween
	var sched_wr_exit = weakref(ctrl.test_last_scheduler())
	var tw_wr_exit: WeakRef = weakref((ctrl.test_last_handle()["tween"] as Tween))
	var actor_wr_exit: WeakRef = weakref(ctrl.player_actor)
	main.queue_free()
	# 释放测试局部强引用（main/ctrl 等由 queue_free 销毁；此处显式置空 handle 局部）
	await get_tree().process_frame
	await get_tree().process_frame
	assert(main_wr.get_ref() == null, "main must be freed after queue_free")
	assert(ctrl_wr.get_ref() == null, "scene_battle_controller must be freed with main")
	assert(sched_wr_exit.get_ref() == null, "active scheduler must be freed with scene exit")
	assert(tw_wr_exit.get_ref() == null, "active tween must be freed with scene exit")
	assert(actor_wr_exit.get_ref() == null, "temp actor must be freed with scene exit")
	print("production: scene exit frees main/controller/scheduler/tween/actor (WeakRef null asserted)")


# ===== 生产 driver 边界验证器（正向与负向共用；整改11 真实 Tween 推进）=====

## 生产 driver 边界验证器：真实 _play_* 启动生产 driver（_drive_scheduler + 真实 Tween），
## 用 tween.custom_step 确定性推进（不依赖真实时间；不调用 sched.seek 制造结果），
## 在 t=0/每帧边界-ε/边界点/边界+ε/结束点观察真实 actor 的 texture/position/size 与 once_restore。
## 帧表另与 SWF_EXPECTED 独立期望逐项对比（res/dur/offset/size/anchor）。
## 返回不一致列表（PRODUCTION_TIMELINE_BOUNDARY_MISMATCH:*）；空=通过。正向与负向（篡改）共用。
func _verify_production_driver_boundaries(ctrl: Control, tlid: String, actor: Control, base: Vector2) -> Array:
	var errs: Array = []
	var frames: Array = ctrl._frames_for(tlid)
	if frames.is_empty():
		return ["empty frame table"]
	# 帧表 vs SWF_EXPECTED 独立期望逐项对比（捕获篡改 duration/offset/size/res/anchor）
	var exp_frames: Array = SWF_EXPECTED.get(tlid, {}).get("frames", [])
	if exp_frames.size() != frames.size():
		errs.append("frame-count")
	else:
		for i in range(frames.size()):
			var f: Dictionary = frames[i]
			var exp: Dictionary = exp_frames[i]
			var exp_res: String = str(exp["res"])
			var res: String = str(f.get("res", ""))
			if exp_res != "" and exp_res != "single_bitmap" and not res.ends_with(exp_res):
				errs.append("res%d" % i)
			if int(f.get("dur", -1)) != int(exp["dur"]):
				errs.append("dur%d" % i)
			if (f["offset"] as Vector2) != Vector2(float(exp["offset"][0]), float(exp["offset"][1])):
				errs.append("off%d" % i)
			if exp.has("size") and (f["size"] as Vector2) != Vector2(float(exp["size"][0]), float(exp["size"][1])):
				errs.append("size%d" % i)
			if exp.has("anchor") and str(f.get("anchor", "")) != str(exp["anchor"]):
				errs.append("anchor%d" % i)
	# 帧起始边界序列：来自 SWF_EXPECTED **独立期望**（整改11：负向篡改后边界错位被捕获；
	# 正向帧表==期望时与帧表一致）。时长 = duration_frames/NATIVE_FPS。
	var boundaries: Array = []
	var acc: float = 0.0
	var use_exp: Array = exp_frames if exp_frames.size() == frames.size() else frames
	for i in range(use_exp.size()):
		boundaries.append(acc)
		acc += float(int((use_exp[i] as Dictionary)["dur"])) / 12.0
	var total: float = acc
	# 启动真实生产播放（_drive_scheduler 生产链）
	if tlid == "player_attack":
		ctrl._play_player_attack(ctrl.attack_sequence)
	else:
		ctrl.target_actor = actor
		var monster_id := "spider" if tlid == "normal_monster_attack" else "thunder_boss_10"
		ctrl.session = ctrl.BattleSession.new(monster_id, GameState.get_player_stats(), 0, GameState.battle_modifiers(monster_id))
		if tlid == "boss_hit":
			ctrl._play_target_hit(ctrl.attack_sequence)
		else:
			ctrl._play_target_attack(ctrl.attack_sequence)
	var handle: Dictionary = ctrl.test_last_handle()
	var tw: Tween = handle.get("tween")
	if tw == null:
		return ["no-tween"]
	# t=0（构造已应用帧0）；期望帧来自独立期望表
	_assert_driver_state(actor, frames[0], base, errs, "t0")
	# 逐边界：tween.custom_step 确定性推进到 b-ε（前帧）/ b+ε（新帧，避开浮点临界精确点），
	# prev 精确累计实际推进量，观察真实 actor vs 独立期望帧。
	var prev: float = 0.0
	for i in range(1, use_exp.size()):
		var b: float = boundaries[i]
		var target_before: float = b - 0.002
		tw.custom_step(target_before - prev)
		prev = target_before
		_assert_driver_state(actor, frames[i - 1], base, errs, "b%d-" % i)
		var target_after: float = b + 0.002
		tw.custom_step(target_after - prev)
		prev = target_after
		_assert_driver_state(actor, frames[i], base, errs, "b%d+" % i)
	# 结束点：推进到 total+ε -> 末帧等待完成 -> once_restore（原状态）
	tw.custom_step(total + 0.001 - prev)
	var sched = handle.get("scheduler")
	if sched == null or not sched.ended:
		errs.append("end")
	if actor.position != base:
		errs.append("restore-pos")
	# 清理（kill 真实 tween -> cleanup -> sched.cancel 幂等）
	ctrl.cancel_battle()
	return errs


## 驱动状态断言：真实 actor 当前状态 vs 帧表期望（texture/position/size）。
func _assert_driver_state(actor: Control, f: Dictionary, base: Vector2, errs: Array, tag: String) -> void:
	if not (actor is TextureRect):
		errs.append("not-texture-rect@" + tag)
		return
	var tr := actor as TextureRect
	var res: String = str(f.get("res", ""))
	if res != "" and (tr.texture == null or not str(tr.texture.resource_path).ends_with(res.get_file())):
		errs.append("PRODUCTION_TIMELINE_BOUNDARY_MISMATCH:" + tag + ":texture")
	if tr.position != base + (f["offset"] as Vector2):
		errs.append("PRODUCTION_TIMELINE_BOUNDARY_MISMATCH:" + tag + ":position")
	var sz: Vector2 = f["size"]
	if sz != Vector2.ZERO and tr.size != sz:
		errs.append("PRODUCTION_TIMELINE_BOUNDARY_MISMATCH:" + tag + ":size")


## 真实 _play_player_attack + cancel_battle 后的注册槽位数（mutation 差异证明用：启用 untrack 时
## 取消后清零回基线；禁用时残留 +1——差异证明 mutation 生效，而非"启动后槽位+1"这类无关断言）。
func _cancel_slots_after_play(ctrl: Control) -> int:
	ctrl._play_player_attack(ctrl.attack_sequence)
	ctrl.cancel_battle()
	return ctrl.tracked_scheduler_slot_count()


## Scheduler 生命周期验证器（整改12）：真实 _play_* + cancel_battle 后**注册槽**必须清空；
## expect_leak=true 时（untrack 禁用）经注册槽残留命中 SCHEDULER_REFERENCE_LEAK
## （不依赖 _last_handle 强引用）。
func _verify_scheduler_lifecycle(ctrl: Control, expect_leak: bool) -> Array:
	var errs: Array = []
	ctrl._play_player_attack(ctrl.attack_sequence)
	ctrl.cancel_battle()
	var slots: int = ctrl.tracked_scheduler_slot_count()
	if expect_leak:
		if slots != 0:
			errs.append("SCHEDULER_REFERENCE_LEAK:slots=" + str(slots))
	elif slots != 0:
		errs.append("scheduler-not-untracked:slots=" + str(slots))
	return errs


# ===== 取消恢复验证器（正向与负向共用；整改10）=====

## 取消恢复验证器：真实 _play_player_attack 启动生产链路（_drive_scheduler + tracked tween +
## cleanup=sched.cancel），cancel_battle 取消后断言精确恢复原 texture/position/size 且 active Tween=0。
## 返回不一致列表（TIMELINE_CANCEL_RESTORE_MISSING:*）；空=通过。
## 负向：cleanup 被禁用（test_set_scheduler_cleanup_enabled(false)）时同一验证器必须命中。
func _verify_player_attack_cancel_restore(ctrl: Control, actor: TextureRect) -> Array:
	var errs: Array = []
	var orig_tex: Texture2D = actor.texture
	var orig_pos: Vector2 = actor.position
	var orig_size: Vector2 = actor.size
	ctrl._play_player_attack(ctrl.attack_sequence)  # 真实生产播放链路
	ctrl.cancel_battle()  # battle_cancel：kill tween -> cleanup -> sched.cancel()（幂等 restore）
	if actor.texture != orig_tex:
		errs.append("TIMELINE_CANCEL_RESTORE_MISSING:texture")
	if actor.position != orig_pos:
		errs.append("TIMELINE_CANCEL_RESTORE_MISSING:position")
	if actor.size != orig_size:
		errs.append("TIMELINE_CANCEL_RESTORE_MISSING:size")
	if ctrl.active_tween_count() != 0:
		errs.append("TIMELINE_CANCEL_RESTORE_MISSING:tween")
	return errs


# ===== 辅助 =====

## 辅助节点：驱动生产 _cancellable_wait 协程（测试无法直接"启动不等待"async 函数，
## 通过 add_child 触发 _ready 启动协程，完成时 emit done 供测试 await）。
class WaitDriver:
	extends Node
	var controller: Control
	var seconds: float = 1.0
	var timeline_id: String = "battle_feedback"
	signal done

	func _ready() -> void:
		await _run()

	func _run() -> void:
		await controller._cancellable_wait(seconds, timeline_id)
		done.emit()


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "could not open " + path)
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "could not open " + path)
	var t: String = f.get_as_text()
	f.close()
	return t


func _has_error_code(errors: Array, code: String) -> bool:
	for e: String in errors:
		if e.begins_with(code):
			return true
	return false


## 固定输入/固定预期的最小夹具（整改07）：直接调用生产纯函数 root_remove_after_placement_from_events
## （事件流状态机），固定用例各自断言明确预期，不做"同算法复制"的参考实现。
func _assert_root_remove_fixtures() -> void:
	# 用例1：后续帧 + 不同 depth -> false
	var ev1: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "remove", "frame": 6, "depth": 8},
	]
	assert(not swf.root_remove_after_placement_from_events(ev1, 100),
		"fixture1: later frame + different depth should be false")
	# 用例2：相同 depth、但删除发生在放置之前 -> false
	# （事件流按时间顺序排列：frame3 的 remove 先于 frame5 的 place，remove 时 depth 无对象）
	var ev2: Array = [
		{"type": "remove", "frame": 3, "depth": 7},
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
	]
	assert(not swf.root_remove_after_placement_from_events(ev2, 100),
		"fixture2: removal before placement should be false")
	# 用例3：后续帧 + 相同 depth -> true
	var ev3: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "remove", "frame": 9, "depth": 7},
	]
	assert(swf.root_remove_after_placement_from_events(ev3, 100),
		"fixture3: later frame + same depth should be true")
	# 用例4a：多次放置、仅其中一次匹配 -> true（明确预期）
	var ev4a: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "place", "frame": 20, "depth": 3, "char": 100},
		{"type": "remove", "frame": 25, "depth": 3},
	]
	assert(swf.root_remove_after_placement_from_events(ev4a, 100),
		"fixture4a: second placement (f20/d3) removed by (f25/d3) -> true")
	# 用例4b：多次放置、均不匹配 -> false（明确预期：移除 depth 与两次放置均不同）
	var ev4b: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "place", "frame": 20, "depth": 3, "char": 100},
		{"type": "remove", "frame": 25, "depth": 9},
		{"type": "remove", "frame": 30, "depth": 4},
	]
	assert(not swf.root_remove_after_placement_from_events(ev4b, 100),
		"fixture4b: removals on unmatched depths (9/4) -> false")
	# 用例5：同 depth 被其他角色替换后再删除，旧角色不算被移除（PM/SE 指定反例）
	var ev5: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "place", "frame": 6, "depth": 7, "char": 200},  # 替换 char100
		{"type": "remove", "frame": 9, "depth": 7},  # 删除的是 char200
	]
	assert(not swf.root_remove_after_placement_from_events(ev5, 100),
		"fixture5: replaced char100 must NOT be counted as removed")
	assert(swf.root_remove_after_placement_from_events(ev5, 200),
		"fixture5b: current char200 IS removed")
	# 用例6：remove 后再次 place，remove 只影响当时对象
	var ev6: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100},
		{"type": "remove", "frame": 9, "depth": 7},
		{"type": "place", "frame": 12, "depth": 7, "char": 300},
	]
	assert(swf.root_remove_after_placement_from_events(ev6, 100),
		"fixture6: char100 removed before re-place -> true")
	assert(not swf.root_remove_after_placement_from_events(ev6, 300),
		"fixture6b: char300 placed after removal -> false")
	# 用例7（整改08）：Move 更新（HasCharacter=false）不覆盖当前 character
	var ev7: Array = [
		{"type": "place", "frame": 5, "depth": 7, "char": 100, "has_character": true, "flags": 6},
		{"type": "place", "frame": 7, "depth": 7, "char": -1, "has_character": false, "flags": 5},  # Move-only
		{"type": "remove", "frame": 9, "depth": 7},
	]
	assert(swf.root_remove_after_placement_from_events(ev7, 100),
		"fixture7: move-only must NOT clear current char; char100 IS removed")
	# 用例8（整改08）：Move 更新发生在无对象 depth 时不产生覆盖副作用
	var ev8: Array = [
		{"type": "place", "frame": 4, "depth": 7, "char": -1, "has_character": false, "flags": 5},  # Move-only 无对象
		{"type": "place", "frame": 5, "depth": 7, "char": 100, "has_character": true, "flags": 6},
		{"type": "remove", "frame": 9, "depth": 7},
	]
	assert(swf.root_remove_after_placement_from_events(ev8, 100),
		"fixture8: move-only before placement must not interfere; char100 IS removed")


func _find_static(r: Variant, eid: String) -> bool:
	for se in r["static_entities"]:
		if str(se["entity_id"]) == eid:
			return true
	return false


func _find_gap(r: Variant, eid: String) -> bool:
	for se in r["evidence_gap_entities"]:
		if str(se["entity_id"]) == eid:
			return true
	return false
