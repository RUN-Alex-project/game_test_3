extends Node

# v1.32 验证：检查 docs/swf_evidence_registry.json 的结构、Godot 路径存在性、
# 测试场景存在性、image 资源存在性，以及 SWF 角色号不重复冲突。
# v1.32 整改 01 增补：ID 唯一、image_id 与文件 basename 一致、注册表地图集合与
# data/maps.json 完全一致、地图背景已登记、scope=legacy 资源不得被活动代码/数据引用、
# known_uses 与 evidence_source 非空。
# 本测试不启动玩法，只校验注册表本身，符合“不得修改玩法/UI/数值/存档”的约束。

const REGISTRY_PATH := "res://docs/swf_evidence_registry.json"
const MAPS_JSON_PATH := "res://data/maps.json"

const REQUIRED_TOP_KEYS := [
	"registry_version",
	"baseline_version",
	"canvas",
	"coordinate_convention",
	"ui_components",
	"animations",
	"shared_characters",
	"image_assets",
	"maps",
	"evidence_gaps",
]
const REQUIRED_ENTRY_KEYS := ["id", "name", "primary_character", "godot_file", "test_file"]

# 隐藏的旧面板脚本，不计入“活动代码”。v1.33 将清理这些文件。
const LEGACY_SCRIPTS := ["main.gd", "battle_panel.gd", "map_panel.gd", "shop_panel.gd"]
const ALLOWED_SCOPES := ["runtime", "active+legacy", "legacy"]

var _file_text_cache: Dictionary = {}


func _ready() -> void:
	assert(FileAccess.file_exists(REGISTRY_PATH), "SWF evidence registry is missing at " + REGISTRY_PATH)
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	assert(file != null, "could not open SWF evidence registry")
	var registry: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert(not registry.is_empty(), "registry JSON did not parse or is empty")

	for key in REQUIRED_TOP_KEYS:
		assert(registry.has(key), "registry missing top-level key: " + key)
	assert(str(registry["registry_version"]) == "1.32", "registry_version is not 1.32")
	assert(str(registry["baseline_version"]) == "v1.31", "baseline_version is not v1.31")
	var canvas: Dictionary = registry["canvas"]
	assert(int(canvas["width"]) == 700 and int(canvas["height"]) == 550, "canvas is not the native 700x550 stage")

	var components: Array = registry["ui_components"]
	var animations: Array = registry["animations"]
	var shared: Array = registry["shared_characters"]
	var images: Array = registry["image_assets"]
	var maps: Array = registry["maps"]
	assert(components.size() >= 15, "too few ui_components registered: %d" % components.size())
	assert(animations.size() >= 4, "too few animations registered: %d" % animations.size())
	assert(images.size() >= 100, "too few image_assets registered: %d" % images.size())
	assert(maps.size() >= 28, "too few maps registered: %d" % maps.size())

	# Each component/animation must carry required keys and point at existing files.
	for entry in components + animations:
		for key in REQUIRED_ENTRY_KEYS:
			assert(entry.has(key), "entry %s missing key %s" % [str(entry.get("id", "?")), key])
		var godot_file: String = str(entry["godot_file"])
		var test_file: String = str(entry["test_file"])
		assert(not godot_file.is_empty() and FileAccess.file_exists(godot_file), "godot_file does not exist: " + godot_file)
		assert(not test_file.is_empty() and FileAccess.file_exists(test_file), "test_file does not exist: " + test_file)

	# --- 检查1：各类主键唯一 ---
	_assert_unique_ids(components, "ui_component")
	_assert_unique_ids(animations, "animation")
	_assert_unique_ids(shared, "shared_character", "id")
	_assert_unique_ids(images, "image_asset", "image_id")
	_assert_unique_ids(maps, "map", "map_id")

	# --- primary_character 唯一性：重复角色号必须有 reuse_of 文档化复用关系 ---
	var claims: Dictionary = {}
	for entry in components + animations:
		var pc: String = str(entry.get("primary_character", ""))
		if pc.is_empty():
			continue
		if not claims.has(pc):
			claims[pc] = []
		claims[pc].append({"id": str(entry["id"]), "reuse_of": str(entry.get("reuse_of", ""))})

	var all_ids: Array = []
	for entry in components + animations:
		all_ids.append(str(entry["id"]))

	for pc in claims:
		var owners: Array = claims[pc]
		if owners.size() <= 1:
			continue
		var canonical_count := 0
		for owner in owners:
			if str(owner["reuse_of"]).is_empty():
				canonical_count += 1
		assert(canonical_count == 1, "primary_character %s claimed by %d entries; expected exactly one canonical owner (reuse_of empty) and the rest documented reuse_of. owners=%s" % [pc, owners.size(), str(owners)])
		for owner in owners:
			var reuse_target: String = str(owner["reuse_of"])
			if not reuse_target.is_empty():
				assert(reuse_target in all_ids, "reuse_of target %s for %s does not reference a known entry id" % [reuse_target, str(owner["id"])])

	# --- image assets：文件存在、basename 与 image_id 一致、known_uses/evidence_source 非空、scope 合法 ---
	var registered_image_basenames: Dictionary = {}
	for img in images:
		assert(img.has("image_id") and img.has("file"), "image_asset entry missing image_id/file: " + str(img))
		var img_file: String = str(img["file"])
		assert(FileAccess.file_exists(img_file), "image_asset file does not exist: " + img_file)
		# 检查2：image_id 与无扩展名 basename 一致
		var basename: String = img_file.get_file().get_basename()
		assert(basename == str(img["image_id"]), "image_id %s does not match file basename %s" % [str(img["image_id"]), basename])
		registered_image_basenames[basename] = true
		# 检查6：known_uses 与 evidence_source 非空
		var known_uses = img.get("known_uses")
		assert(known_uses is Array and known_uses.size() > 0, "image %s has empty known_uses" % str(img["image_id"]))
		assert(not str(img.get("evidence_source", "")).is_empty(), "image %s has empty evidence_source" % str(img["image_id"]))
		# scope 合法性
		var scope: String = str(img.get("scope", "runtime"))
		assert(scope in ALLOWED_SCOPES, "image %s has invalid scope: %s" % [str(img["image_id"]), scope])
		# source_refs：稳定路径+token 定位（v1.33 整改，取代易漂移的数字行号）
		if img.has("source_refs"):
			var refs = img["source_refs"]
			assert(refs is Array and refs.size() > 0, "image %s has empty source_refs" % str(img["image_id"]))
			var has_active_ref := false
			for ref in refs:
				assert(ref.has("path") and ref.has("token"), "image %s source_ref missing path/token" % str(img["image_id"]))
				var rpath: String = str(ref["path"])
				var rtoken: String = str(ref["token"])
				assert(not rpath.is_empty() and not rtoken.is_empty(), "image %s source_ref has empty path/token" % str(img["image_id"]))
				assert(FileAccess.file_exists(rpath), "source_ref path does not exist: %s" % rpath)
				assert(rtoken in _read_text_cached(rpath), "source_ref token %s not found in %s" % [rtoken, rpath])
				if not (rpath.get_file() in LEGACY_SCRIPTS):
					has_active_ref = true
			if scope == "runtime" or scope == "active+legacy":
				assert(has_active_ref, "runtime/active+legacy image %s has no non-legacy source_ref" % str(img["image_id"]))

	# --- 检查5：scope=legacy 资源不得被活动代码或活动数据引用 ---
	var active_texts: Array = _collect_active_texts()
	for img in images:
		if str(img.get("scope", "runtime")) != "legacy":
			continue
		var legacy_id: String = str(img["image_id"])
		for text: String in active_texts:
			assert(not (legacy_id in text), "image %s marked scope=legacy but is referenced in active code/data" % legacy_id)

	# --- 检查3 + 检查4：注册表地图集合与 data/maps.json 完全一致；背景与 maps.json 一致并已登记 ---
	var maps_file := FileAccess.open(MAPS_JSON_PATH, FileAccess.READ)
	assert(maps_file != null, "could not open data/maps.json")
	var maps_json: Array = JSON.parse_string(maps_file.get_as_text())
	maps_file.close()
	assert(maps_json is Array and maps_json.size() > 0, "data/maps.json did not parse as a non-empty array")

	var maps_json_ids: Array = []
	var maps_json_bg: Dictionary = {}
	for m in maps_json:
		var mid: String = str(m["id"])
		maps_json_ids.append(mid)
		maps_json_bg[mid] = str(m["background"])

	var registry_map_ids: Array = []
	var registry_map_bg: Dictionary = {}
	for m in maps:
		var mid: String = str(m["map_id"])
		registry_map_ids.append(mid)
		registry_map_bg[mid] = str(m["background"])

	# 检查3：集合完全一致（双向包含）
	assert(registry_map_ids.size() == maps_json_ids.size(), "map count mismatch: registry %d vs maps.json %d" % [registry_map_ids.size(), maps_json_ids.size()])
	for mid in maps_json_ids:
		assert(mid in registry_map_ids, "map %s exists in maps.json but not in registry" % mid)
	for mid in registry_map_ids:
		assert(mid in maps_json_ids, "map %s exists in registry but not in maps.json" % mid)

	# 检查4：每个地图背景与 maps.json 一致，且对应文件已登记到 image_assets
	for mid in maps_json_ids:
		var bg_basename: String = maps_json_bg[mid].get_file().get_basename()
		var reg_bg_basename: String = str(registry_map_bg.get(mid, "")).get_file().get_basename()
		assert(reg_bg_basename == bg_basename, "map %s background mismatch: registry %s vs maps.json %s" % [mid, reg_bg_basename, bg_basename])
		assert(registered_image_basenames.has(bg_basename), "map %s background %s is not registered in image_assets" % [mid, bg_basename])

	# shared_characters：每个携带 id 和 primary_character。
	for sc in shared:
		assert(sc.has("id") and sc.has("primary_character"), "shared_character missing id/primary_character: " + str(sc))

	# 注册表不得含依赖“看截图/目测”的验收描述。
	var raw_lower := JSON.stringify(registry).to_lower()
	assert(not ("看截图" in raw_lower) and not ("see screenshot" in raw_lower) and not ("目测" in raw_lower), "registry contains a screenshot-dependent acceptance description")

	print("PASS swf_evidence_registry structure, path existence, id uniqueness, character reuse rules, image basename/scope/legacy-isolation, and maps.json parity (%d components, %d animations, %d images, %d maps)" % [components.size(), animations.size(), images.size(), maps.size()])
	get_tree().quit(0)


# 收集“活动代码 + 活动数据”的文本，用于检测 legacy 资源是否被活动入口引用。
# 活动代码 = scripts/ 下除 LEGACY_SCRIPTS 外的全部 .gd；活动数据 = data/ 下全部 .json。
func _collect_active_texts() -> Array:
	var texts: Array = []
	var scripts_dir := DirAccess.open("res://scripts")
	assert(scripts_dir != null, "could not open res://scripts")
	scripts_dir.list_dir_begin()
	var sfn: String = scripts_dir.get_next()
	while sfn != "":
		if not scripts_dir.current_is_dir() and sfn.ends_with(".gd") and not (sfn in LEGACY_SCRIPTS):
			texts.append(_read_text("res://scripts/" + sfn))
		sfn = scripts_dir.get_next()
	scripts_dir.list_dir_end()

	var data_dir := DirAccess.open("res://data")
	assert(data_dir != null, "could not open res://data")
	data_dir.list_dir_begin()
	var dfn: String = data_dir.get_next()
	while dfn != "":
		if not data_dir.current_is_dir() and dfn.ends_with(".json"):
			texts.append(_read_text("res://data/" + dfn))
		dfn = data_dir.get_next()
	data_dir.list_dir_end()
	return texts


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "could not read active source: " + path)
	var t: String = f.get_as_text()
	f.close()
	return t


# 带缓存的文本读取，供 source_refs 的 token 校验重复读取同一文件时使用。
func _read_text_cached(path: String) -> String:
	if _file_text_cache.has(path):
		return _file_text_cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "could not read source_ref file: " + path)
	var t: String = f.get_as_text()
	f.close()
	_file_text_cache[path] = t
	return t


# 检查一个条目集合的 id 唯一。id_field 默认 "id"。
func _assert_unique_ids(entries: Array, label: String, id_field: String = "id") -> void:
	var seen: Dictionary = {}
	for entry in entries:
		var id_val: String = str(entry.get(id_field, ""))
		assert(not id_val.is_empty(), "%s entry has empty %s" % [label, id_field])
		assert(not seen.has(id_val), "duplicate %s %s: %s" % [label, id_field, id_val])
		seen[id_val] = true
