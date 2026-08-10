extends RefCounted


static func evaluate(snapshot: Dictionary) -> Dictionary:
	var won := bool(snapshot.get("won", false))
	var combat_power := int(snapshot.get("combat_power", 0))
	var player_level := int(snapshot.get("level", 1))
	var equipment_power := int(snapshot.get("equipment_combat_power", 0))
	var pet_power := int(snapshot.get("pet_combat_power", 0))
	var military_level := int(snapshot.get("military_level", 0))
	var nobility_level := int(snapshot.get("nobility_level", 0))
	var affection_level := int(snapshot.get("affection_level", 0))
	var wealth := int(snapshot.get("gold", 0) / 10000) + int(snapshot.get("magic_stones", 0))
	var highest_count := 0

	var combat_rating := "无"
	if won:
		if combat_power >= 1200:
			combat_rating = "终极勇士（最高评价）"
			highest_count += 1
		elif combat_power >= 1000:
			combat_rating = "罕见的"
		elif combat_power >= 800:
			combat_rating = "非常厉害"
		elif combat_power >= 600:
			combat_rating = "很厉害"
		elif combat_power >= 300:
			combat_rating = "普通"

	var level_rating := "低级菜鸟"
	if player_level >= 132:
		level_rating = "冲级能手（最高评价）"
		highest_count += 1
	elif player_level >= 120:
		level_rating = "练级高手"
	elif player_level >= 100:
		level_rating = "很会升级"
	elif player_level >= 70:
		level_rating = "练级还行"

	var equipment_rating := "装备打造傻鸟"
	if equipment_power >= 126:
		equipment_rating = "装备打造宗师（最高评价）"
		highest_count += 1
	elif equipment_power >= 108:
		equipment_rating = "装备打造大师"
	elif equipment_power >= 72:
		equipment_rating = "装备打造高手"
	elif equipment_power >= 48:
		equipment_rating = "装备打造学徒"

	var pet_rating := "不会培养幻兽"
	if pet_power >= 400:
		pet_rating = "究极幻兽师（最高评价）"
		highest_count += 1
	elif pet_power >= 320:
		pet_rating = "幻兽培养大师"
	elif pet_power >= 250:
		pet_rating = "幻兽培养高手"
	elif pet_power >= 100:
		pet_rating = "善于培养幻兽"

	var military_rating := _military_rating(military_level)
	if military_level >= 11:
		highest_count += 1
	var nobility_rating := _nobility_rating(nobility_level)
	if nobility_level >= 6:
		highest_count += 1
	var affection_rating := _affection_rating(affection_level)
	if affection_level >= 6:
		highest_count += 1

	var wealth_rating := "贫穷的家伙"
	if wealth >= 500000:
		wealth_rating = "富可敌国（最高评价）"
		highest_count += 1
	elif wealth >= 350000:
		wealth_rating = "大富豪"
	elif wealth >= 200000:
		wealth_rating = "小富商"
	elif wealth >= 50000:
		wealth_rating = "还能过日子"

	return {
		"combat_rating":combat_rating,
		"level_rating":level_rating,
		"equipment_rating":equipment_rating,
		"pet_rating":pet_rating,
		"military_rating":military_rating,
		"nobility_rating":nobility_rating,
		"affection_rating":affection_rating,
		"wealth_rating":wealth_rating,
		"highest_count":highest_count,
		"review":_composite_review(won, highest_count, military_level),
		"wealth":wealth,
	}


static func format_report(snapshot: Dictionary) -> String:
	var result := evaluate(snapshot)
	return """[center][font_size=28][color=#ffd34d]游戏结束[/color][/font_size][/center]

[color=#f7e6b2]你在亚特兰蒂斯奋战了 [color=#ffffff]%d[/color] 天。

总战斗力：[color=#ffffff]%d[/color]　评价：[color=#71ff71]%s[/color]
人物等级：[color=#ffffff]%d级[/color]　评价：[color=#71ff71]%s[/color]
装备战斗力：[color=#ffffff]%d[/color]　评价：[color=#71ff71]%s[/color]
幻兽战斗力：[color=#ffffff]%d[/color]　评价：[color=#71ff71]%s[/color]
军衔：[color=#ffffff]%s[/color]　评价：[color=#71ff71]%s[/color]
爵位：[color=#ffffff]%s[/color]　评价：[color=#71ff71]%s[/color]
与公主关系：[color=#ffffff]%s[/color]　评价：[color=#71ff71]%s[/color]
金币：[color=#ffffff]%s[/color]　魔石：[color=#ffffff]%s[/color]　评价：[color=#71ff71]%s[/color]

[color=#ffd34d]综合评价：[/color]
%s[/color]""" % [
		int(snapshot.get("day", 1)), int(snapshot.get("combat_power", 0)), result.combat_rating,
		int(snapshot.get("level", 1)), result.level_rating,
		int(snapshot.get("equipment_combat_power", 0)), result.equipment_rating,
		int(snapshot.get("pet_combat_power", 0)), result.pet_rating,
		str(snapshot.get("military_name", "无军衔")), result.military_rating,
		str(snapshot.get("nobility_name", "平民")), result.nobility_rating,
		str(snapshot.get("affection_name", "未认识")), result.affection_rating,
		_format_number(int(snapshot.get("gold", 0))), _format_number(int(snapshot.get("magic_stones", 0))), result.wealth_rating,
		result.review,
	]


static func _military_rating(rank_level: int) -> String:
	if rank_level >= 11:
		return "亚特兰蒂斯战神（最高评价）"
	if rank_level >= 10:
		return "亚特兰蒂斯名将"
	if rank_level >= 7:
		return "亚特兰蒂斯高级军官"
	if rank_level >= 4:
		return "亚特兰蒂斯中级军官"
	if rank_level >= 1:
		return "亚特兰蒂斯下级军官"
	return "无名小兵"


static func _nobility_rating(rank_level: int) -> String:
	if rank_level >= 6:
		return "人类的骄傲（最高评价）"
	if rank_level >= 5:
		return "无上荣誉的贵族"
	if rank_level >= 3:
		return "令人尊敬的贵族"
	if rank_level >= 2:
		return "荣誉贵族"
	if rank_level >= 1:
		return "贵族"
	return "平民"


static func _affection_rating(rank_level: int) -> String:
	if rank_level >= 6:
		return "情圣（最高评价）"
	if rank_level >= 4:
		return "情商过人"
	if rank_level >= 3:
		return "交际高手"
	if rank_level >= 2:
		return "善于交往"
	return "不懂交往"


static func _composite_review(won: bool, highest_count: int, military_level: int) -> String:
	if not won:
		return "无"
	if highest_count == 7:
		return "你能玩到这地步，我无语――绝世高手啊。（最高评价）"
	if highest_count > 5:
		return "天啊！你凭着超人的智慧，无比的英勇，击败数不清的魔族大军，被人类推举为最高军事领袖之一。魔族大军已经溃不成军了，人类已经为胜利准备了盛宴，等待你凯旋。你真不愧是天才游戏玩家。"
	if military_level > 7:
		return "你以势如破竹的进攻将魔族大军打得落花流水。魔族一谈到你的名字就脸色大变，在你率领的钢铁军队打击下，它们已经知道胜利无望，正在做逃跑的准备。"
	if military_level > 4:
		return "在这60天里，亚特兰蒂斯出现了一个神勇的战士，就是你。你的无畏勇气打倒一批批魔族大军，人们赠与你不败将军的称号，从你身上看到了人类胜利的希望。"
	if military_level > 1:
		return "你在60天的战斗里取得了优异的战绩。亚特兰蒂斯与魔族的战斗还在进行中，你已经是一位英勇的战士，希望你能战斗到胜利！"
	return "游戏结束了。哎，你唱着：“我是一只菜菜鸟，想要飞呀却飞也飞不高~。”离开了游戏。"


static func _format_number(value: int) -> String:
	var raw := str(absi(value))
	var output := ""
	while raw.length() > 3:
		output = "," + raw.right(3) + output
		raw = raw.left(raw.length() - 3)
	return ("-" if value < 0 else "") + raw + output
