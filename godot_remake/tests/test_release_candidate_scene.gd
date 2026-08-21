extends Node
## v1.41 专项测试：发布候选版健康检查（P1-3 拒签整改重写）。
## 真实 release validator：对发布目录中每个实际文件计算字节 SHA256 并与 SHA256SUMS/manifest 比较；
## 私有存档检查；清单关键词覆盖；manifest 一致性；exe 冒烟脚本可重跑性。
## 负向全部变异**临时副本目录**（复制发布目录到 user://rc_tmp）后走同一 validator——
## 哈希负向篡改真实字节、私有存档负向加入伪 savegame.json、清单负向删除关键词、
## manifest 负向删除 artifacts 项。不再是布尔纯函数假负向。

const PRESET_PATH := "res://export_presets.cfg"
const CHECKLIST_PATH := "res://artifacts/releases/v1.41/试玩验收清单_v1.41.md"
const KNOWN_ISSUES_PATH := "res://artifacts/releases/v1.41/已知问题_v1.41.md"
const MAPS_PATH := "res://data/maps.json"
const SMOKE_SCRIPT_PATH := "res://work/smoke_release_exe.ps1"

const RELEASE_DIR := "res://artifacts/releases/v1.41"
const TMP_DIR := "user://rc_tmp"
const TMP_GLOBAL := "user://rc_tmp"

const REQUIRED_SYSTEMS := ["背包", "仓库", "商店", "装备", "精炼", "幻兽", "技能", "研究所", "任务簿", "存档"]
const REQUIRED_NPCS := ["杂货商", "收藏家", "仓库", "锻造师", "研究所", "元帅", "首相", "国王", "公主", "侍女", "日常官", "PK官", "抽奖官", "五福娃使者", "探险家"]


func _ready() -> void:
	# 1. export_presets 存在且指向 Windows；project.godot 主场景为 main.tscn
	var pf := FileAccess.open(PRESET_PATH, FileAccess.READ)
	assert(pf != null, "export_presets.cfg must exist")
	var preset_text := pf.get_as_text()
	assert(preset_text.contains("Windows Desktop"), "preset must target Windows Desktop")
	var pgf := FileAccess.open("res://project.godot", FileAccess.READ)
	var project_text := pgf.get_as_text()
	assert(project_text.contains("res://scenes/main.tscn"), "project must declare main scene as scenes/main.tscn")

	# 2. 28 地图覆盖
	var mf := FileAccess.open(MAPS_PATH, FileAccess.READ)
	assert(mf != null, "maps.json must exist")
	var maps: Variant = JSON.parse_string(mf.get_as_text())
	var map_count := (maps as Array).size() if maps is Array else 0
	assert(map_count == 50, "release must have 50 maps, got %d" % map_count)

	# 3. exe 冒烟可重跑脚本存在（校验 exe SHA == manifest -> 启动 -> 日志 -> 退出码 -> SCRIPT ERROR -> PASS 标记）
	assert(FileAccess.file_exists(SMOKE_SCRIPT_PATH), "exe 冒烟脚本必须存在且可重跑: " + SMOKE_SCRIPT_PATH)

	# 4. 正向：真实发布目录通过同一 release validator
	var release_global := ProjectSettings.globalize_path(RELEASE_DIR)
	var forward_code := _validate_release_dir(release_global)
	assert(forward_code == "", "真实发布目录必须通过 release validator（%s）" % forward_code)

	# 5. 负向：全部变异临时副本目录后走同一 validator（先证明变异形成）
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))

	# N1 RC_ARTIFACT_HASH_MISMATCH：篡改副本中一个实际文件的字节 -> validator 必须命中
	var checklist_path := ProjectSettings.globalize_path(TMP_DIR + "/试玩验收清单_v1.41.md")
	var checklist_bytes := FileAccess.get_file_as_bytes(checklist_path)
	assert(not checklist_bytes.is_empty(), "N1 前置：副本清单文件必须可读")
	var tampered := checklist_bytes.duplicate()
	tampered.append(0x41)  # 追加一个字节（真实字节级篡改）
	var tamper_file := FileAccess.open(checklist_path, FileAccess.WRITE)
	assert(tamper_file != null, "N1 变异：篡改文件必须可写")
	tamper_file.store_buffer(tampered)
	tamper_file.close()
	var tampered_back := FileAccess.get_file_as_bytes(checklist_path)
	assert(tampered_back.size() == checklist_bytes.size() + 1, "N1 变异必须生效（字节数 +1）")
	var n1_code := _validate_release_dir(ProjectSettings.globalize_path(TMP_DIR))
	assert(n1_code == "RC_ARTIFACT_HASH_MISMATCH",
		"N1 篡改字节必须被同一 validator 拒绝（got '%s'）" % n1_code)

	# N2 RC_PRIVATE_SAVE_INCLUDED：加入伪 savegame.json -> validator 必须拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	var fake_save := FileAccess.open(ProjectSettings.globalize_path(TMP_DIR + "/savegame.json"), FileAccess.WRITE)
	assert(fake_save != null, "N2 变异：伪存档必须可写")
	fake_save.store_string("{\"version\":21,\"gold\":1}")
	fake_save.close()
	assert(FileAccess.file_exists(TMP_DIR + "/savegame.json"), "N2 变异必须生效（savegame.json 已加入）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_PRIVATE_SAVE_INCLUDED",
		"N2 私有存档必须被同一 validator 拒绝")

	# N3 RC_CHECKLIST_COVERAGE_MISSING：副本清单删除关键词 -> 同一清单验证器拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	var checklist_text := FileAccess.get_file_as_string(checklist_path)
	assert(checklist_text.contains("研究所"), "N3 前置：清单含关键词 研究所")
	var stripped_text := checklist_text.replace("研究所", "研究N所")
	assert(not stripped_text.contains("研究所") and stripped_text.contains("研究N所"), "N3 变异必须生效（关键词已删除）")
	var stripped_file := FileAccess.open(checklist_path, FileAccess.WRITE)
	stripped_file.store_string(stripped_text)
	stripped_file.close()
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_CHECKLIST_COVERAGE_MISSING",
		"N3 清单缺关键词必须被同一 validator 拒绝")

	# N4 RC_MANIFEST_INVALID：副本 manifest 删除 artifacts 项 -> validator 必须拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	var manifest_path := ProjectSettings.globalize_path(TMP_DIR + "/build_manifest.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var original_artifacts: Array = manifest.get("artifacts", [])
	assert(original_artifacts.size() >= 6, "N4 前置：manifest artifacts 非空")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest["artifacts"] = original_artifacts.slice(0, original_artifacts.size() - 1)
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_MANIFEST_INVALID",
		"N4 manifest 篡改必须被同一 validator 拒绝")

	# ---- 第三轮拒签整改：SHA/manifest 重复项四个副本负向（同一 validator，先证明变异形成）----

	# N5 RC_SHA_DUPLICATE：SHA256SUMS 追加完全相同的一行（同文件名重复）-> 拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	var sha_path := ProjectSettings.globalize_path(TMP_DIR + "/SHA256SUMS.txt")
	var sha_orig := FileAccess.get_file_as_string(sha_path)
	var first_sha_line := sha_orig.split("\n")[0]
	assert(not first_sha_line.is_empty(), "N5 前置：SHA256SUMS 有记录行")
	var sha_dup_file := FileAccess.open(sha_path, FileAccess.WRITE)
	assert(sha_dup_file != null, "N5 变异：写 SHA 必须成功")
	sha_dup_file.store_string(sha_orig + first_sha_line + "\n")  # 追加完全相同行
	sha_dup_file.close()
	assert(FileAccess.get_file_as_string(sha_path).split("\n").size() == sha_orig.split("\n").size() + 1,
		"N5 变异必须生效（SHA 行数 +1）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_SHA_DUPLICATE",
		"N5 追加相同 SHA 行必须被同一 validator 拒绝")

	# N6 RC_SHA_DUPLICATE：SHA256SUMS 追加同文件名但错误哈希的行 -> 拒绝（同名记录哈希冲突）
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	sha_orig = FileAccess.get_file_as_string(sha_path)
	var wrong_sha_line := ("0").repeat(64) + "  " + first_sha_line.split("  ")[1]
	var sha_conflict_file := FileAccess.open(sha_path, FileAccess.WRITE)
	assert(sha_conflict_file != null, "N6 变异：写 SHA 必须成功")
	sha_conflict_file.store_string(sha_orig + wrong_sha_line + "\n")
	sha_conflict_file.close()
	assert(FileAccess.get_file_as_string(sha_path).contains(wrong_sha_line), "N6 变异必须生效（同名错误哈希行已加入）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_SHA_DUPLICATE",
		"N6 同文件名错误哈希行必须被同一 validator 拒绝")

	# N7 RC_MANIFEST_DUPLICATE：manifest.artifacts 追加重复项 -> 拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	manifest_path = ProjectSettings.globalize_path(TMP_DIR + "/build_manifest.json")
	var manifest_n7: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	assert(manifest_n7 is Dictionary, "N7 前置：manifest 必须可解析")
	var dup_artifacts: Array = (manifest_n7 as Dictionary).get("artifacts", [])
	dup_artifacts.append(dup_artifacts[0])  # 追加第一项（重复）
	(manifest_n7 as Dictionary)["artifacts"] = dup_artifacts
	var manifest_dup_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(manifest_dup_file != null, "N7 变异：写 manifest 必须成功")
	manifest_dup_file.store_string(JSON.stringify(manifest_n7))
	manifest_dup_file.close()
	var reloaded_arts: Array = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)).get("artifacts", [])
	var art_count := 0
	for a: String in reloaded_arts:
		if a == str(dup_artifacts[0]):
			art_count += 1
	assert(art_count >= 2, "N7 变异必须生效（artifacts 重复项存在）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_MANIFEST_DUPLICATE",
		"N7 manifest 重复 artifact 必须被同一 validator 拒绝")

	# N8 RC_SHA_COUNT_MISMATCH：SHA 记录多一项（额外无对应文件的行）-> 拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	sha_orig = FileAccess.get_file_as_string(sha_path)
	var extra_line := ("1").repeat(64) + "  ghost_file.bin"
	var sha_extra_file := FileAccess.open(sha_path, FileAccess.WRITE)
	assert(sha_extra_file != null, "N8 变异：写 SHA 必须成功")
	sha_extra_file.store_string(sha_orig + extra_line + "\n")
	sha_extra_file.close()
	assert(FileAccess.get_file_as_string(sha_path).contains("ghost_file.bin"), "N8 变异必须生效（SHA 多一项）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_SHA_COUNT_MISMATCH",
		"N8 SHA 多一项必须被同一 validator 拒绝")

	# N9 RC_SHA_COUNT_MISMATCH：SHA 少一项（删除一行）-> 拒绝
	_copy_dir(release_global, ProjectSettings.globalize_path(TMP_DIR))
	sha_orig = FileAccess.get_file_as_string(sha_path)
	var sha_lines9 := sha_orig.split("\n")
	var removed_sha9 := ""
	for l9: String in sha_lines9:
		if l9.strip_edges().is_empty():
			continue
		removed_sha9 = l9
		break
	assert(not removed_sha9.is_empty(), "N9 前置：SHA 有记录行")
	sha_lines9.erase(removed_sha9)
	var sha_less_file := FileAccess.open(sha_path, FileAccess.WRITE)
	assert(sha_less_file != null, "N9 变异：写 SHA 必须成功")
	sha_less_file.store_string("\n".join(sha_lines9))
	sha_less_file.close()
	assert(not FileAccess.get_file_as_string(sha_path).contains(removed_sha9.split("  ")[1]), "N9 变异必须生效（SHA 少一项）")
	assert(_validate_release_dir(ProjectSettings.globalize_path(TMP_DIR)) == "RC_SHA_COUNT_MISMATCH",
		"N9 SHA 少一项必须被同一 validator 拒绝")

	# 清理临时目录（递归删除，DirAccess.remove_absolute 对非空目录会失败）
	_remove_dir_recursive(ProjectSettings.globalize_path(TMP_DIR))
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP_DIR)), "临时目录必须已删除（无残留）")

	print("PASS v1.41 release candidate: preset+main scene, 50 maps, real release validator (byte SHA256 x manifest x SHA256SUMS, private-save, checklist, manifest, SHA/manifest duplicate rejection) forward + 9 tmp-copy mutation negatives, smoke script present")
	get_tree().quit(0)


## 递归删除目录（Godot 的 remove_absolute 只能删空目录/文件）。
## 第四轮拒签整改：每个 remove 检查返回值；最终由调用方断言目录不存在。
func _remove_dir_recursive(global_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(global_dir):
		return
	var dir := DirAccess.open(global_dir)
	assert(dir != null, "递归删除：目录必须可打开: " + global_dir)
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if dir.current_is_dir():
			_remove_dir_recursive(global_dir + "/" + f)
		else:
			assert(DirAccess.remove_absolute(global_dir + "/" + f) == OK,
				"递归删除：文件删除必须成功: " + global_dir + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	assert(DirAccess.remove_absolute(global_dir) == OK, "递归删除：目录删除必须成功: " + global_dir)


## 真实 release validator：目录中每个实际文件的字节 SHA256 与 SHA256SUMS 逐一比较；
## manifest.artifacts 集合与目录一致；exe/pck 哈希一致；无私有存档；清单关键词覆盖。
## 返回 ""（通过）或精确错误码。正向与负向（变异临时副本）共用。
func _validate_release_dir(global_dir: String) -> String:
	var sha_text := FileAccess.get_file_as_string(global_dir + "/SHA256SUMS.txt")
	if sha_text.is_empty():
		return "RC_MANIFEST_INVALID"
	# 第三轮拒签整改：SHA 记录保留行列表（不转 Dictionary 丢重复），
	# 拒绝同文件名重复行（含同名哈希冲突）——重复信息不得被覆盖丢失。
	var sha_entries: Array = []  # 每个元素 {"name": String, "hash": String}
	var sha_seen_names := {}
	for line in sha_text.split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		var parts := line.split("  ")
		if parts.size() != 2:
			return "RC_MANIFEST_INVALID"
		var entry_name := parts[1]
		if sha_seen_names.has(entry_name):
			return "RC_SHA_DUPLICATE"  # 同文件名重复行 / 同名哈希冲突
		sha_seen_names[entry_name] = true
		sha_entries.append({"name": entry_name, "hash": parts[0].to_lower()})
	# 私有存档检查（优先：恶意文件不应被其他错误码掩盖）
	for forbidden in ["savegame.json", "savegame.json.bak", "savegame.json.tmp"]:
		if FileAccess.file_exists(global_dir + "/" + forbidden):
			return "RC_PRIVATE_SAVE_INCLUDED"
	# 清单关键词检查（先于哈希：删关键词的发布包以清单覆盖缺失为主要缺陷）
	var checklist_text := FileAccess.get_file_as_string(global_dir + "/试玩验收清单_v1.41.md")
	for sys in REQUIRED_SYSTEMS:
		if not checklist_text.contains(sys):
			return "RC_CHECKLIST_COVERAGE_MISSING"
	for npc in REQUIRED_NPCS:
		if not checklist_text.contains(npc):
			return "RC_CHECKLIST_COVERAGE_MISSING"
	# 每个实际文件字节 SHA256 与记录逐一比较
	var dir := DirAccess.open(global_dir)
	if dir == null:
		return "RC_MANIFEST_INVALID"
	dir.list_dir_begin()
	var actual_files: Array = []
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name != "SHA256SUMS.txt":
			if file_name.ends_with(".log") or file_name.ends_with(".tmp") or file_name.ends_with(".bak"):
				return "RC_PRIVATE_SAVE_INCLUDED"
			actual_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	# manifest 一致性（先于哈希）：artifacts 不得重复；三方数量与多重集精确相等
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(global_dir + "/build_manifest.json"))
	if not manifest is Dictionary:
		return "RC_MANIFEST_INVALID"
	var m: Dictionary = manifest
	var manifest_arts: Array = m.get("artifacts", [])
	var seen_art := {}
	for artifact_name: String in manifest_arts:
		if seen_art.has(artifact_name):
			return "RC_MANIFEST_DUPLICATE"  # manifest.artifacts 重复
		seen_art[artifact_name] = true
	actual_files.sort()
	var manifest_sorted: Array = manifest_arts.duplicate()
	manifest_sorted.sort()
	var sha_names_sorted: Array = []
	for entry: Dictionary in sha_entries:
		sha_names_sorted.append(str(entry["name"]))
	sha_names_sorted.sort()
	if manifest_sorted != actual_files:
		return "RC_MANIFEST_INVALID"  # manifest 与目录多重集不相等
	if sha_names_sorted != actual_files:
		return "RC_SHA_COUNT_MISMATCH"  # SHA 记录与目录多重集不相等（数量或多一项少一项）
	if sha_names_sorted.size() != manifest_sorted.size():
		return "RC_SHA_COUNT_MISMATCH"
	if bool(m.get("executable_stale", true)):
		return "RC_MANIFEST_INVALID"
	# SHA256SUMS 记录的每个文件必须实际存在 + 每个实际文件字节哈希与记录逐一比较
	var sha_by_name := {}
	for entry: Dictionary in sha_entries:
		sha_by_name[str(entry["name"])] = str(entry["hash"])
		if not FileAccess.file_exists(global_dir + "/" + str(entry["name"])):
			return "RC_ARTIFACT_HASH_MISMATCH"
	var dir2 := DirAccess.open(global_dir)
	if dir2 == null:
		return "RC_MANIFEST_INVALID"
	dir2.list_dir_begin()
	var file2 := dir2.get_next()
	while not file2.is_empty():
		if not dir2.current_is_dir() and file2 != "SHA256SUMS.txt":
			var bytes2 := FileAccess.get_file_as_bytes(global_dir + "/" + file2)
			var ctx2 := HashingContext.new()
			ctx2.start(HashingContext.HASH_SHA256)
			ctx2.update(bytes2)
			var actual_hash2 := ctx2.finish().hex_encode()
			if not sha_by_name.has(file2):
				return "RC_ARTIFACT_HASH_MISMATCH"  # 记录缺失
			if str(sha_by_name[file2]) != actual_hash2:
				return "RC_ARTIFACT_HASH_MISMATCH"  # 字节哈希不一致
		file2 = dir2.get_next()
	dir2.list_dir_end()
	if str(m.get("executable_hash_sha256", "")).to_lower() != sha_by_name.get("魔域1.03_v1.41.exe", ""):
		return "RC_ARTIFACT_HASH_MISMATCH"
	if str(m.get("pck", {}).get("sha256", "")).to_lower() != sha_by_name.get("魔域1.03_v1.41.pck", ""):
		return "RC_ARTIFACT_HASH_MISMATCH"
	return ""


## 递归复制目录（发布目录 -> 临时目录，逐文件字节复制）
func _copy_dir(src_global: String, dst_global: String) -> void:
	_remove_dir_recursive(dst_global)
	assert(DirAccess.make_dir_recursive_absolute(dst_global) == OK, "临时目录必须可创建")
	var dir := DirAccess.open(src_global)
	assert(dir != null, "源目录必须可读: " + src_global)
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			var src_bytes := FileAccess.get_file_as_bytes(src_global + "/" + file_name)
			var dst_file := FileAccess.open(dst_global + "/" + file_name, FileAccess.WRITE)
			assert(dst_file != null, "副本文件必须可写: " + file_name)
			dst_file.store_buffer(src_bytes)
			dst_file.close()
		file_name = dir.get_next()
	dir.list_dir_end()
