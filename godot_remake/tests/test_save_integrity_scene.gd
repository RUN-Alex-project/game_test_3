extends Node
## v1.40 专项测试：存档完整性（schema 保持 v21，DTO/原子写入加固）。
## 验证：round-trip deep equality、损坏输入拒绝且不污染内存、原子写入失败保留旧档、未知高版本拒绝。
## 负向：SAVE_TRANSACTION_PARTIAL_COMMIT / SAVE_ATOMIC_TEMP_INVALID / SAVE_MIGRATION_DEFAULT_MISSING /
##       SAVE_SCHEMA_TYPE_MISMATCH / SAVE_OLD_FILE_NOT_PRESERVED / SAVE_FUTURE_VERSION_ACCEPTED
##
## P0-4 重写（拒签整改）：每条故障路径使用 A/B 双 payload 区分——
##   1) 先保存 payload A（记录 final 哈希 hashA 与内存快照 memA）
##   2) 修改完整状态为 payload B（记录内存快照 memB）
##   3) 注入故障并保存，清故障
##   4) 明确断言最终 final/tmp/bak 应为 A / B / 缺失 / 损坏（字节哈希逐一比较）
##   5) 断言内存快照仍 == memB（保存不污染内存）
##   6) 恢复后同一生产路径（清故障 save）通过
## 无任何恒真断言（`x == x` 类已删除）；F6 不再手工删 bak 绕开生产恢复状态机；
## 覆盖全部 final/tmp/bak 语义分支（含空 {} final、损坏 bak+有效 tmp、bak+tmp 同时有效）。

const SCHEMA_PATH := "res://docs/save_schema_registry.json"

const FAULT_PATH := "user://test_v140_fault.json"
const FAULT_GLOBAL := "user://test_v140_fault.json"


func _ready() -> void:
	var sf := FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	assert(sf != null, "schema registry must be readable")
	var schema: Variant = JSON.parse_string(sf.get_as_text())
	assert(schema is Dictionary, "schema registry must be a dict")
	assert(int((schema as Dictionary).get("schema_decision", {}).get("version", 0)) == 21, "schema must stay v21")
	assert(not bool((schema as Dictionary).get("schema_decision", {}).get("upgrade", true)), "schema must not upgrade to v22")
	# P0-2 拒签整改：schema 注册表与生产 SAVE_SCHEMA_KEYS/SAVE_SCHEMA_DEFAULTS 双向一致（38 项）
	var reg_fields: Array = (schema as Dictionary).get("fields", [])
	var reg_ids: Array = []
	var reg_type_by_id := {}
	for rf: Variant in reg_fields:
		var rf_dict: Dictionary = rf
		reg_ids.append(str(rf_dict.get("path", "")))
		reg_type_by_id[str(rf_dict.get("path", ""))] = str(rf_dict.get("type", ""))
	var prod_ids: Array = GameState.SAVE_SCHEMA_KEYS.duplicate()
	assert(reg_ids.size() == prod_ids.size(), "schema 注册表字段数必须等于生产（注册=%d 生产=%d）" % [reg_ids.size(), prod_ids.size()])
	reg_ids.sort()
	prod_ids.sort()
	assert(reg_ids == prod_ids, "schema 注册表 ID 集合必须等于生产 SAVE_SCHEMA_KEYS")
	for rf: Variant in reg_fields:
		var rf_dict2: Dictionary = rf
		var pid: String = str(rf_dict2.get("path", ""))
		var reg_type: String = str(rf_dict2.get("type", ""))
		var default_value: Variant = GameState.SAVE_SCHEMA_DEFAULTS.get(pid)
		var inferred := ""
		if default_value is bool:
			inferred = "bool"
		elif default_value is int or default_value is float:
			inferred = "int"
		elif default_value is String:
			inferred = "string"
		elif default_value is Dictionary:
			inferred = "dict"
		elif default_value is Array:
			inferred = "array"
		assert(reg_type == inferred, "schema 注册表 %s 类型 %s 与生产默认推断 %s 不一致" % [pid, reg_type, inferred])
	assert(str(reg_type_by_id.get("owned_territory", "")) == "string", "owned_territory 必须登记为 string（生产为 String）")

	# 1. round-trip：完整 v21 存档读取后状态一致（save -> reset -> load -> deep equal）
	GameState.save_path = "user://test_v140_roundtrip.json"
	GameState.current_map_id = "dream_swamp"
	GameState.level = 30
	GameState.base_stats = {"max_hp": 550, "attack": 60, "defense": 30, "luck": 100}
	GameState.player_current_hp = 550
	GameState.gold = 12345
	GameState.magic_stones = 67890
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})
	GameState.story_flags["king_rescued"] = true
	assert(GameState.save_game(), "v21 save must succeed")
	var snapshot := {
		"gold": GameState.gold, "magic_stones": GameState.magic_stones, "level": GameState.level,
		"current_map_id": GameState.current_map_id, "player_current_hp": GameState.player_current_hp,
		"king_rescued": bool(GameState.story_flags.get("king_rescued", false)),
	}
	# reset
	GameState.gold = 0
	GameState.magic_stones = 0
	GameState.level = 1
	GameState.current_map_id = "cassano_city"
	GameState.player_current_hp = 0
	GameState.story_flags["king_rescued"] = false
	assert(GameState.load_game(), "v21 load must succeed")
	assert(GameState.gold == 12345 and GameState.magic_stones == 67890, "round-trip gold/stones must match")
	assert(GameState.level == 30, "round-trip level must match")
	assert(GameState.current_map_id == "dream_swamp", "round-trip map must match")
	assert(bool(GameState.story_flags.get("king_rescued", false)), "round-trip story flag must match")

	# 2. 最小旧档按默认值迁移（只含核心字段）
	GameState.save_path = "user://test_v140_minimal.json"
	var minimal := {"version": 21, "gold": 100, "magic_stones": 200, "level": 5}
	var mf := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	mf.store_string(JSON.stringify(minimal))
	mf.close()
	GameState.inventory = []
	GameState.reset_state_for_test() if GameState.has_method("reset_state_for_test") else _hard_reset()
	assert(GameState.load_game(), "minimal v21 save must load")
	assert(GameState.gold == 100 and GameState.level == 5, "minimal save must restore core fields")
	assert(GameState.current_map_id == "cassano_city", "minimal save must default map to cassano")

	# 3. 损坏输入：错误顶层类型（JSON 数组，parse 成功但非 Dictionary）-> 拒绝（内存不变）
	GameState.save_path = "user://test_v140_corrupt.json"
	var cf := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	cf.store_string("[1,2,3]")
	cf.close()
	var gold_before := GameState.gold
	assert(not GameState.load_game(), "corrupt json (wrong top-level type) must be rejected")
	assert(GameState.gold == gold_before, "corrupt load must not mutate memory")

	# 4. 未知高版本：拒绝（不悄悄降级覆盖）
	GameState.save_path = "user://test_v140_future.json"
	var ff := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	ff.store_string(JSON.stringify({"version": 99, "gold": 1}))
	ff.close()
	assert(not GameState.load_game(), "future version must be rejected")

	# 5. 边界：超48格背包 -> 拒绝
	GameState.save_path = "user://test_v140_oversize.json"
	var big_inv := []
	for i in 100:
		big_inv.append({})
	var of := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	of.store_string(JSON.stringify({"version": 21, "inventory": big_inv}))
	of.close()
	assert(not GameState.load_game(), "oversize inventory must be rejected")

	# 6. 空对象 {} 不是存档（缺 version/核心身份字段）：load 必须拒绝且内存不变
	GameState.save_path = "user://test_v140_empty.json"
	var ef2 := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	ef2.store_string("{}")
	ef2.close()
	var gold_before_empty := GameState.gold
	assert(not GameState.load_game(), "empty {} must be rejected by load (missing version/core fields)")
	assert(GameState.gold == gold_before_empty, "empty {} load must not mutate memory")

	# 7. P0-1 拒签整改：真实坏档表（真实写文件 + 真实 load_game + 内存完整不变）
	#    整数严格校验（1.5/21.5/2.5 拒绝，不 int() 静默截断）+ 全数值字段范围规则
	_assert_bad_save_rejected("fractional_gold", {"version": 21, "gold": 1.5, "level": 1})
	_assert_bad_save_rejected("fractional_version", {"version": 21.5, "gold": 100, "level": 1})
	_assert_bad_save_rejected("fractional_next_id", {"version": 21, "gold": 100, "level": 1, "next_pet_instance_id": 2.5})
	_assert_bad_save_rejected("negative_gold", {"version": 21, "gold": -5, "level": 1})
	_assert_bad_save_rejected("negative_stones", {"version": 21, "magic_stones": -5, "level": 1})
	_assert_bad_save_rejected("negative_exp", {"version": 21, "experience": -1, "level": 1})
	_assert_bad_save_rejected("overtime_day", {"version": 21, "gold": 100, "level": 1, "current_time_used": 100})
	_assert_bad_save_rejected("negative_stamina", {"version": 21, "gold": 100, "level": 1, "player_current_stamina": -1})
	_assert_bad_save_rejected("negative_hp", {"version": 21, "gold": 100, "level": 1, "player_current_hp": -1})
	_assert_bad_save_rejected("string_gold", {"version": 21, "gold": "abc", "level": 1})

	# 8. P0-2 拒签整改：next_pet_instance_id 差分——运行状态 999、存档 next=2，读档必须等于 DTO 计算值
	GameState.save_path = "user://test_v140_nextdiff.json"
	GameState.next_pet_instance_id = 999  # 读档前运行状态（高 ID）
	var diff_file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	assert(diff_file != null, "差分存档必须可写")
	diff_file.store_string(JSON.stringify({
		"version": 21, "gold": 100, "level": 1,
		"pets": [{"template_id": "attack_defense_light", "instance_id": 1, "quality_score": 100.0,
			"level": 1, "current_hp": 100, "experience": 0, "deployed": false, "combined": false}],
		"next_pet_instance_id": 2,
	}))
	diff_file.close()
	assert(GameState.load_game(), "差分存档必须可读")
	# DTO 计算：最高宠物 ID(1)+1=2，存档 next=2 → 2（绝不读运行状态 999）
	assert(GameState.next_pet_instance_id == 2,
		"差分：读档后 next_pet_instance_id 必须为 DTO 计算值 2（非运行状态 999），实际 %d" % GameState.next_pet_instance_id)

	# 9. P0-2 拒签整改：pets 缺失时 research/next_pet_instance_id 必须独立迁移（不随 pets 默认回退丢失）
	GameState.save_path = "user://test_v140_indep.json"
	GameState.next_pet_instance_id = 1
	var indep_file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	assert(indep_file != null, "独立迁移存档必须可写")
	indep_file.store_string(JSON.stringify({
		"version": 21, "gold": 100, "level": 1,
		"research": {"technology_level": 42.0, "production_rate": 3, "stock": 5, "vip_level": 2},
		"next_pet_instance_id": 17,
	}))
	indep_file.close()
	assert(GameState.load_game(), "独立迁移存档必须可读")
	assert(GameState.next_pet_instance_id == 17, "独立迁移：next 必须来自存档 17（实际 %d）" % GameState.next_pet_instance_id)
	assert(float(GameState.research.get("technology_level", 0)) == 42.0
		and int(GameState.research.get("production_rate", 0)) == 3
		and int(GameState.research.get("stock", 0)) == 5
		and int(GameState.research.get("vip_level", 0)) == 2,
		"独立迁移：research 必须来自存档（pets 缺失不得连带丢弃）")
	assert(GameState.pets.size() == 2, "独立迁移：pets 缺失回退默认两只（实际 %d）" % GameState.pets.size())

	# ============ P0-4：16 路径故障注入与状态组合（A/B payload 区分，无恒真断言） ============
	GameState.save_path = FAULT_PATH
	GameState.set_save_fault_inject("")

	# ---- 故障注入路径 F1-F6（保存中不同阶段失败，final 必须保持 payload A 或按语义提交 B）----

	# F1 tmp_open_fail：tmp 打开失败 -> save=false，final 必须保持 A
	_fault_cleanup()
	assert(_save_payload(1000), "F1 基线 A 保存")
	var hash_a := _file_hash(FAULT_PATH)
	assert(hash_a != "", "F1 基线 A 哈希非空")
	assert(_file_text(FAULT_PATH).contains("\"gold\": 1000"), "F1 基线 A 校验：final 必须包含 gold 1000")
	var mem_b := _to_payload_b()
	GameState.set_save_fault_inject("tmp_open_fail")
	var f1 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f1, "F1 tmp_open_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F1")
	_assert_memory_equals(mem_b, "F1 保存失败后内存保持 payload B")
	assert(_fault_recover_save(), "F1 清故障后同一生产路径保存必须成功")
	assert(not _file_text(FAULT_PATH).contains("\"gold\": 1000"), "F1 正向保存后 final 已更新为 payload B")

	# F2 write_fail：写入失败 -> save=false，final 保持 A，tmp 被清理
	assert(_save_payload(1000), "F2 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("write_fail")
	var f2 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f2, "F2 write_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F2")
	_assert_memory_equals(mem_b, "F2 保存失败后内存保持 payload B")
	assert(_fault_recover_save(), "F2 清故障后同一生产路径保存必须成功")

	# F3 verify_fail：读回校验失败 -> save=false，final 保持 A，tmp 被清理
	assert(_save_payload(1000), "F3 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("verify_fail")
	var f3 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f3, "F3 verify_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F3")
	_assert_memory_equals(mem_b, "F3 保存失败后内存保持 payload B")
	assert(_fault_recover_save(), "F3 清故障后同一生产路径保存必须成功")

	# F4 backup_fail：备份失败 -> save=false，final 保持 A（备份 rename 未发生）
	assert(_save_payload(1000), "F4 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("backup_fail")
	var f4 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f4, "F4 backup_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F4")
	_assert_memory_equals(mem_b, "F4 保存失败后内存保持 payload B")
	assert(_fault_recover_save(), "F4 清故障后同一生产路径保存必须成功")

	# F5 replace_fail：替换失败 -> final 从 bak 恢复为 A，save=false
	assert(_save_payload(1000), "F5 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("replace_fail")
	var f5 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f5, "F5 replace_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F5")
	_assert_memory_equals(mem_b, "F5 保存失败后内存保持 payload B")
	assert(_fault_recover_save(), "F5 清故障后同一生产路径保存必须成功")

	# F6 cleanup_fail：备份清理失败 -> save=false，但新档 B 已提交（final==B、bak==A 残留，数据可恢复）
	# 先预演保存 B 得到精确 hash_b
	assert(_save_payload(1000), "F6 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(_save_payload(2000), "F6 预演保存 B")
	var hash_b := _file_hash(FAULT_PATH)
	assert(hash_b != hash_a, "F6 预演 hash_b 必须与 hash_a 不同")
	assert(_save_payload(1000), "F6 恢复基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("cleanup_fail")
	var f6 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f6, "F6 cleanup_fail: save 必须返回 false（不返回成功）")
	_assert_files({"": hash_b, ".tmp": "MISSING", ".bak": hash_a}, "F6")
	_assert_memory_equals(mem_b, "F6 保存失败后内存保持 payload B")
	# 恢复后正向：清故障 save -> 状态机清理残留 bak 后保存成功，final 仍为 B
	assert(GameState.save_game(), "F6 清故障后同一生产路径保存必须成功")
	_assert_files({"": hash_b, ".tmp": "MISSING", ".bak": "MISSING"}, "F6 正向后")

	# ---- 状态组合路径 F7-F16（恢复状态机语义）----

	# F7 崩溃后仅剩 .bak（final 缺失 + bak 有效）-> 恢复 bak 后保存成功，final==B
	_fault_cleanup()
	assert(_save_payload(1000), "F7 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".bak") == OK, "F7 准备：rename final->bak 必须成功")
	assert(not FileAccess.file_exists(FAULT_PATH), "F7 准备：final 必须缺失")
	assert(_file_hash(FAULT_PATH + ".bak") == hash_a, "F7 准备：bak 必须是 A 内容（变异已形成）")
	mem_b = _to_payload_b()
	var f7 := GameState.save_game()
	assert(f7, "F7 仅剩 bak: save 必须成功（恢复 bak 后正常保存）")
	_assert_b_content("F7")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F7")  # 首次操作后立即检查
	_assert_idempotent_resave("F7")
	_assert_memory_equals(mem_b, "F7 保存后内存保持 payload B")

	# F8 final 有效 + stale .tmp/.bak -> 清理 stale 后保存成功
	assert(_save_payload(1000), "F8 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	var stale_tmp := FileAccess.open(FAULT_PATH + ".tmp", FileAccess.WRITE)
	assert(stale_tmp != null, "F8 准备：tmp 写入必须成功")
	stale_tmp.store_string("stale")
	stale_tmp.close()
	var stale_bak := FileAccess.open(FAULT_PATH + ".bak", FileAccess.WRITE)
	assert(stale_bak != null, "F8 准备：bak 写入必须成功")
	stale_bak.store_string("stale")
	stale_bak.close()
	assert(_file_hash(FAULT_PATH + ".tmp") == "stale".sha256_text() and _file_hash(FAULT_PATH + ".bak") == "stale".sha256_text(),
		"F8 准备：stale tmp/bak 变异已形成")
	mem_b = _to_payload_b()
	var f8 := GameState.save_game()
	assert(f8, "F8 final 有效 + stale tmp/bak: save 必须成功")
	_assert_b_content("F8")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F8")  # 首次操作后立即检查
	_assert_idempotent_resave("F8")
	_assert_memory_equals(mem_b, "F8 保存后内存保持 payload B")

	# F9 final 损坏 + bak 有效 -> 恢复 bak 后保存成功
	assert(_save_payload(1000), "F9 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".bak") == OK, "F9 准备：rename final->bak 必须成功")
	assert(_file_hash(FAULT_PATH + ".bak") == hash_a, "F9 准备：bak 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH, "corrupt")
	assert(_file_hash(FAULT_PATH) == "corrupt".sha256_text(), "F9 准备：final 损坏变异已形成")
	mem_b = _to_payload_b()
	var f9 := GameState.save_game()
	assert(f9, "F9 final 损坏 + bak 有效: save 必须成功")
	_assert_b_content("F9")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F9")  # 首次操作后立即检查
	_assert_idempotent_resave("F9")
	_assert_memory_equals(mem_b, "F9 保存后内存保持 payload B")

	# F10 三档都损坏 -> save=false 禁止覆盖，损坏文件保持原样
	assert(_save_payload(1000), "F10 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	_write_text(FAULT_PATH, "corrupt")
	_write_text(FAULT_PATH + ".bak", "corrupt")
	_write_text(FAULT_PATH + ".tmp", "corrupt")
	mem_b = _to_payload_b()
	var f10 := GameState.save_game()
	assert(not f10, "F10 三档损坏: save 必须返回 false（禁止覆盖）")
	_assert_files({"": _hash_of_text("corrupt"), ".tmp": _hash_of_text("corrupt"), ".bak": _hash_of_text("corrupt")}, "F10")
	_assert_memory_equals(mem_b, "F10 保存失败后内存保持 payload B")
	_fault_cleanup()
	assert(GameState.save_game(), "F10 清理损坏文件后正向通过")

	# F11 final 损坏 + bak 损坏 + tmp 有效 -> 提交 tmp、删除损坏 bak 后保存成功（唯一恢复源不丢）
	_fault_cleanup()
	assert(_save_payload(1000), "F11 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	_write_text(FAULT_PATH + ".tmp", _file_text(FAULT_PATH))  # tmp = 完整 A
	assert(_file_hash(FAULT_PATH + ".tmp") == hash_a, "F11 准备：tmp 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH, "corrupt")
	_write_text(FAULT_PATH + ".bak", "corrupt")
	assert(_file_hash(FAULT_PATH) == "corrupt".sha256_text() and _file_hash(FAULT_PATH + ".bak") == "corrupt".sha256_text(),
		"F11 准备：final/bak 损坏变异已形成")
	mem_b = _to_payload_b()
	var f11 := GameState.save_game()
	assert(f11, "F11 损坏 final + 损坏 bak + 有效 tmp: save 必须成功")
	_assert_b_content("F11")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F11")  # 首次操作后立即检查
	_assert_idempotent_resave("F11")
	_assert_memory_equals(mem_b, "F11 保存后内存保持 payload B")

	# F12 final 缺失 + bak 缺失 + tmp 有效 -> 提交 tmp 后保存成功
	_fault_cleanup()
	assert(_save_payload(1000), "F12 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".tmp") == OK, "F12 准备：rename final->tmp 必须成功")
	assert(not FileAccess.file_exists(FAULT_PATH), "F12 准备：final 必须缺失")
	assert(_file_hash(FAULT_PATH + ".tmp") == hash_a, "F12 准备：tmp 必须是 A 内容（变异已形成）")
	mem_b = _to_payload_b()
	var f12 := GameState.save_game()
	assert(f12, "F12 仅剩 tmp: save 必须成功")
	_assert_b_content("F12")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F12")  # 首次操作后立即检查
	_assert_idempotent_resave("F12")
	_assert_memory_equals(mem_b, "F12 保存后内存保持 payload B")

	# F13 空 {} final + bak 有效 + write_fail：{} 必须被判无效（否则会清掉唯一 bak）
	# 若 {} 被当有效：先清 bak 再写失败 -> final 仍 {}；正确实现：恢复 bak -> write_fail -> final==A
	_fault_cleanup()
	assert(_save_payload(1000), "F13 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".bak") == OK, "F13 准备：rename final->bak 必须成功")
	assert(_file_hash(FAULT_PATH + ".bak") == hash_a, "F13 准备：bak 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH, "{}")  # final = 空对象（缺 version/核心字段）
	assert(_file_hash(FAULT_PATH) == "{}".sha256_text(), "F13 准备：空 {} final 变异已形成")
	mem_b = _to_payload_b()
	GameState.set_save_fault_inject("write_fail")
	var f13 := GameState.save_game()
	GameState.set_save_fault_inject("")
	assert(not f13, "F13 write_fail: save 必须返回 false")
	_assert_files({"": hash_a, ".tmp": "MISSING", ".bak": "MISSING"}, "F13")
	_assert_memory_equals(mem_b, "F13 保存失败后内存保持 payload B")

	# F14 空 {} final + bak 有效（正向）-> 恢复 bak 后保存成功
	_fault_cleanup()
	assert(_save_payload(1000), "F14 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".bak") == OK, "F14 准备：rename final->bak 必须成功")
	assert(_file_hash(FAULT_PATH + ".bak") == hash_a, "F14 准备：bak 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH, "{}")
	assert(_file_hash(FAULT_PATH) == "{}".sha256_text(), "F14 准备：空 {} final 变异已形成")
	mem_b = _to_payload_b()
	var f14 := GameState.save_game()
	assert(f14, "F14 空 {} final + bak 有效: save 必须成功（{} 不得被判有效）")
	_assert_b_content("F14")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F14")  # 首次操作后立即检查
	_assert_idempotent_resave("F14")
	_assert_memory_equals(mem_b, "F14 保存后内存保持 payload B")

	# F15 final 缺失 + bak 损坏 + tmp 有效 -> 提交 tmp（不依赖 bak）后保存成功
	_fault_cleanup()
	assert(_save_payload(1000), "F15 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	_write_text(FAULT_PATH + ".tmp", _file_text(FAULT_PATH))  # tmp = 完整 A
	assert(_file_hash(FAULT_PATH + ".tmp") == hash_a, "F15 准备：tmp 必须是 A 内容（变异已形成）")
	assert(DirAccess.remove_absolute(FAULT_GLOBAL) == OK, "F15 准备：删除 final 必须成功")
	assert(not FileAccess.file_exists(FAULT_PATH), "F15 准备：final 必须缺失")
	_write_text(FAULT_PATH + ".bak", "corrupt")  # bak 损坏
	assert(_file_hash(FAULT_PATH + ".bak") == "corrupt".sha256_text(), "F15 准备：bak 损坏变异已形成")
	mem_b = _to_payload_b()
	var f15 := GameState.save_game()
	assert(f15, "F15 缺失 final + 损坏 bak + 有效 tmp: save 必须成功")
	_assert_b_content("F15")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F15")  # 首次操作后立即检查
	_assert_idempotent_resave("F15")
	_assert_memory_equals(mem_b, "F15 保存后内存保持 payload B")

	# F16 final 损坏 + bak 有效 + tmp 有效：bak 优先于 tmp 恢复
	_fault_cleanup()
	assert(_save_payload(1000), "F16 基线 A 保存")
	hash_a = _file_hash(FAULT_PATH)
	assert(DirAccess.rename_absolute(FAULT_GLOBAL, FAULT_GLOBAL + ".bak") == OK, "F16 准备：rename final->bak 必须成功")
	assert(_file_hash(FAULT_PATH + ".bak") == hash_a, "F16 准备：bak 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH + ".tmp", _file_text(FAULT_PATH + ".bak"))  # tmp = A 也有效
	assert(_file_hash(FAULT_PATH + ".tmp") == hash_a, "F16 准备：tmp 必须是 A 内容（变异已形成）")
	_write_text(FAULT_PATH, "corrupt")
	assert(_file_hash(FAULT_PATH) == "corrupt".sha256_text(), "F16 准备：final 损坏变异已形成")
	mem_b = _to_payload_b()
	var f16 := GameState.save_game()
	assert(f16, "F16 损坏 final + 有效 bak + 有效 tmp: save 必须成功（bak 优先）")
	_assert_b_content("F16")
	_assert_files({".tmp": "MISSING", ".bak": "MISSING"}, "F16")  # 首次操作后立即检查
	_assert_idempotent_resave("F16")
	_assert_memory_equals(mem_b, "F16 保存后内存保持 payload B")

	# 清理故障注入测试存档
	_fault_cleanup()

	# 清理测试存档
	for f in ["roundtrip", "minimal", "corrupt", "future", "oversize", "empty", "nextdiff", "indep"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v140_%s.json" % f))

	print("PASS v1.40 save integrity: v21 round-trip, minimal migration, corrupt/future/oversize/empty rejection, 10 real bad-save rejections (fractional/negative/out-of-range, memory intact), next_id DTO diff, pets/research/next independent migration, 16 fault/state paths (A/B payload, first-op file assertions, no tautology)")
	get_tree().quit(0)


# ---- P0-4 辅助 ----

## 将 GameState 设置为 payload（seed 标识），返回内存快照
func _set_payload(seed: int) -> Dictionary:
	GameState.gold = seed
	GameState.magic_stones = seed * 2
	GameState.level = 10 + seed
	GameState.experience = seed
	GameState.current_day = seed
	GameState.current_map_id = "dream_swamp" if seed % 2 == 0 else "cassano_city"
	GameState.player_current_hp = 500 + seed
	GameState.next_pet_instance_id = seed
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({"item_id": "fruit", "quantity": 1} if i == 0 else {})
	GameState.equipment = {"weapon": {}, "helmet": {}, "necklace": {}, "armor": {}, "bracelet": {}, "boots": {}}
	GameState.base_stats = {"max_hp": 500 + seed, "attack": 60, "defense": 30, "luck": 100}
	GameState.story_flags["king_rescued"] = seed % 2 == 0
	GameState.story_flags["game_won"] = false
	return _mem_snapshot()


func _save_payload(seed: int) -> bool:
	_set_payload(seed)
	return GameState.save_game()


## 切换到 payload B（2000）并返回内存快照
func _to_payload_b() -> Dictionary:
	return _set_payload(2000)


## 清故障 + 删除三档残留（每次路径前重置到全新档状态）。
## 第三轮拒签整改：检查 remove 返回值并断言最终无残留。
func _fault_cleanup() -> void:
	GameState.set_save_fault_inject("")
	for ext in ["", ".tmp", ".bak"]:
		var target: String = FAULT_PATH + ext
		if FileAccess.file_exists(target):
			assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) == OK,
				"清理 %s 必须成功" % target)
	for ext in ["", ".tmp", ".bak"]:
		assert(not FileAccess.file_exists(FAULT_PATH + ext), "清理后 %s 必须无残留" % ext)


## P0-1：真实坏档测试——写坏档文件 -> 真实 load_game() 必须拒绝 -> 内存快照完整不变
func _assert_bad_save_rejected(label: String, payload: Dictionary) -> void:
	var bad_path := "user://test_v140_bad_%s.json" % label
	GameState.save_path = bad_path
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	assert(f != null, "%s: 写坏档必须成功" % label)
	f.store_string(JSON.stringify(payload))
	f.close()
	var before := _mem_snapshot()
	assert(not GameState.load_game(), "%s: 坏档必须被真实 load_game 拒绝" % label)
	_assert_memory_equals(before, "%s: 坏档拒绝后内存快照必须完整不变" % label)
	# 第三轮拒签整改：清理检查返回值并断言无残留
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path)) == OK, "%s: 清理坏档必须成功" % label)
	assert(not FileAccess.file_exists(bad_path), "%s: 清理后坏档必须无残留" % label)


## 清故障后同一生产路径保存（断言成功）
func _fault_recover_save() -> bool:
	return GameState.save_game()


## 完整内存快照（深序列化所有持久字段）
func _mem_snapshot() -> Dictionary:
	return {
		"gold": GameState.gold, "magic_stones": GameState.magic_stones,
		"level": GameState.level, "experience": GameState.experience,
		"military_merit": GameState.military_merit, "nobility_merit": GameState.nobility_merit,
		"affection": GameState.affection, "current_day": GameState.current_day,
		"current_time_used": GameState.current_time_used,
		"current_map_id": GameState.current_map_id,
		"player_current_hp": GameState.player_current_hp,
		"player_current_stamina": GameState.player_current_stamina,
		"next_pet_instance_id": GameState.next_pet_instance_id,
		"owned_territory": GameState.owned_territory,
		"pk_race_active": GameState.pk_race_active,
		"war_soul_maze_active": GameState.war_soul_maze_active,
		"war_soul_guardian_revealed": GameState.war_soul_guardian_revealed,
		"inventory": JSON.stringify(GameState.inventory),
		"warehouse": JSON.stringify(GameState.warehouse),
		"pets": JSON.stringify(GameState.pets),
		"equipment": JSON.stringify(GameState.equipment),
		"base_stats": JSON.stringify(GameState.base_stats),
		"research": JSON.stringify(GameState.research),
		"quest_states": JSON.stringify(GameState.quest_states),
		"unlocked_maps": JSON.stringify(GameState.unlocked_maps),
		"learned_skills": JSON.stringify(GameState.learned_skills),
		"completed_daily_tasks": JSON.stringify(GameState.completed_daily_tasks),
		"loot_queue": JSON.stringify(GameState.loot_queue),
		"story_flags": JSON.stringify(GameState.story_flags),
		"fuwa_event": JSON.stringify(GameState.fuwa_event),
		"demon_campaign": JSON.stringify(GameState.demon_campaign),
	}


## 断言内存快照与期望一致（保存前后内存必须不变）
func _assert_memory_equals(snap: Dictionary, label: String) -> void:
	var now := _mem_snapshot()
	for key: String in snap:
		assert(now.get(key) == snap.get(key), "%s: 内存字段 %s 变化（保存不得污染内存）" % [label, key])


## 断言 final/tmp/bak 精确状态：expected 形如 {"": "HASH", ".tmp": "MISSING", ".bak": "MISSING"}。
## 未登记的键跳过（由其他断言负责，如内容断言）。
func _assert_files(expected: Dictionary, label: String) -> void:
	for ext in ["", ".tmp", ".bak"]:
		if not expected.has(ext):
			continue
		var want: String = str(expected.get(ext))
		var got := _file_hash(FAULT_PATH + ext)
		var display: String = "final" if ext == "" else ext
		if want == "MISSING":
			assert(got == "", "%s: %s 应缺失（实际哈希=%s）" % [label, display, got])
		else:
			assert(got == want, "%s: %s 哈希应=%s 实际=%s" % [label, display, want, got])


func _file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var data := f.get_as_text()
	f.close()
	return data.sha256_text()


func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _write_text(path: String, text: String) -> void:
	# 第三轮拒签整改：必须断言写入成功并读回验证内容一致
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "写文件必须成功: " + path)
	var err := f.get_error()
	f.store_string(text)
	f.flush()
	assert(err == OK and f.get_error() == OK, "写文件后必须无 IO 错误: " + path)
	f.close()
	assert(FileAccess.file_exists(path), "写后文件必须存在: " + path)
	var read_back := FileAccess.get_file_as_string(path)
	assert(read_back == text, "写后读回必须与内容一致: " + path)


func _hash_of_text(text: String) -> String:
	return text.sha256_text()


## P0-3 拒签整改：拆分 helper。
## 1) _assert_b_content：只读检查 final 内容为 payload B（无任何副作用）；
## 2) _assert_files（调用者紧接执行）：首次操作后立即检查 final/tmp/bak 精确集合；
## 3) _assert_idempotent_resave：最后单独执行幂等重存（第二次保存不会掩盖首次操作的残留）。
func _assert_b_content(label: String) -> void:
	var t := _file_text(FAULT_PATH)
	assert(t.contains("\"gold\": 2000"), "%s: final 必须包含 payload B 的 gold 2000" % label)
	assert(t.contains("\"magic_stones\": 4000"), "%s: final 必须包含 payload B 的 magic_stones 4000" % label)


## 幂等重存单独执行：必须先完成 _assert_b_content 与 _assert_files（首次操作后的精确集合）
func _assert_idempotent_resave(label: String) -> void:
	var hash_first := _file_hash(FAULT_PATH)
	assert(GameState.save_game(), "%s: 再次保存（内存仍为 B）必须成功" % label)
	var hash_again := _file_hash(FAULT_PATH)
	assert(hash_first == hash_again, "%s: 再次保存后 final 哈希必须稳定（已提交 B 内容，幂等）" % label)


func _hard_reset() -> void:
	GameState.gold = 0
	GameState.magic_stones = 0
	GameState.level = 1
	GameState.current_map_id = "cassano_city"
	GameState.inventory = []
	for i in 48:
		GameState.inventory.append({})


# 纯函数负向已按 P0-1 拒签整改删除——全部替换为真实场景：
#   SAVE_SCHEMA_TYPE_MISMATCH     -> 用例 7 string_gold / 用例 3（顶层类型）真实 load 拒绝
#   SAVE_FUTURE_VERSION_ACCEPTED  -> 用例 4（version 99）真实 load 拒绝
#   SAVE_OLD_FILE_NOT_PRESERVED   -> F1/F2/F5 真实文件哈希断言（旧档不变）
#   SAVE_TRANSACTION_PARTIAL_COMMIT -> F5 replace_fail 真实恢复
#   SAVE_ATOMIC_TEMP_INVALID      -> F3 verify_fail 真实清理
#   SAVE_MIGRATION_DEFAULT_MISSING -> 用例 2 minimal 迁移（缺失字段按默认）+ N5（story 读档缺字段）
