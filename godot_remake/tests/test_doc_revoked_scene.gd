extends Node
## v1.37 整改04：文档 REVOKED 负向——被撤销短语不得出现在非 REVOKED 行。


func _ready() -> void:
	# 撤销短语列表（整改04 REVOKED 声明）
	var revoked_phrases := [
		"58 处 attachSound", "54503 个 action", "46 个 action 码", "action_total 54503",
		"hitsb 为动画段 label", "hitsb/next_gw_hit/hitgw 为动画段 label",
		"v2 独立验证", "0x8E GotoLabel",
	]
	var docs := {
		"res://docs/evidence/combat_feedback_v103_v9.txt": FileAccess.open("res://docs/evidence/combat_feedback_v103_v9.txt", FileAccess.READ),
		"res://docs/combat_feedback_registry.json": FileAccess.open("res://docs/combat_feedback_registry.json", FileAccess.READ),
		"res://开发进度.md": FileAccess.open("res://开发进度.md", FileAccess.READ),
	}
	for path in docs:
		var f = docs[path]
		assert(f != null, "doc must exist: " + path)
		var lines: Array = f.get_as_text().split("
")
		var bad: Array = []
		for i in lines.size():
			var line: String = lines[i]
			if line.contains("REVOKED") or line.contains("已被整改03撤销") or line.contains("已被撤销"):
				continue  # REVOKED 行豁免
			for phrase in revoked_phrases:
				if line.contains(phrase):
					bad.append("%s:%d: %s" % [path, i + 1, phrase])
		assert(bad.is_empty(), "revoked phrases in non-REVOKED lines: " + str(bad))
	print("PASS v1.37 整改04 doc REVOKED negative: revoked phrases only in REVOKED lines")
	get_tree().quit(0)
