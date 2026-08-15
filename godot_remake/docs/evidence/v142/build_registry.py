#!/usr/bin/env python3
"""v1.42 内容注册表构建器：docs/moyu_23_24_content_registry.json。

- 内嵌候选目录数据（地图/任务/NPC/物品/技能/Boss/系统）。
- 写 JSON 前对每个 evidence_token 在受控证据文本（work/v142/text/moyu_*.strings.txt）
  做精确命中校验；local_version_confirmed/partial 的 token 必须在至少一个受控文本命中，
  否则构建失败（防止把猜测写为确认）。
- singleplayer_extension / evidence_gap 条目禁止携带伪造 source/token（source=null, tokens=[]）。
- 输出按 kind 分组统计，供证据文档与测试使用。

用法：python work/v142/build_registry.py [--out docs/moyu_23_24_content_registry.json]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent   # godot_remake/
# 受控证据文本：docs/evidence/v142/ 为仓库内可提交的规范副本（由 work/v142/extract_swf_text.py
# 提取到 work/v142/text/ 后同步复制而来）；token 校验与注册表 evidence_source 都以它为权威，
# 保证克隆仓库后可复核证据链。
TEXT_DIR = ROOT / "docs" / "evidence" / "v142"
TEXT_FILES = {
    "2.2": TEXT_DIR / "moyu_2.2_strings.txt",
    "2.3": TEXT_DIR / "moyu_2.3_strings.txt",
    "2.4": TEXT_DIR / "moyu_2.4_strings.txt",
}

ALLOWED_KIND = {"map", "quest", "npc", "item", "skill", "boss", "system"}
ALLOWED_SOURCE_VERSION = {"2.2", "2.3", "2.4", "project"}
ALLOWED_EVIDENCE_STATUS = {
    "local_version_confirmed", "local_version_partial",
    "singleplayer_extension", "evidence_gap",
}
ALLOWED_DESIGN_STATUS = {
    "borrowed", "adapted", "singleplayer_extension", "not_selected",
}
ALLOWED_PLANNED = {
    "v1.43", "v1.44", "v1.45", "v1.46", "v1.47", "v1.48", "v1.49",
    "v1.50", "v1.51", "v1.52", "v1.53", "v1.54", "v1.55", "not_planned",
}
EVIDENCE_PATH_24 = "docs/evidence/v142/moyu_2.4_strings.txt"

# 现有生产数据 ID（候选目录不得与之冲突）
EXISTING_MAP_IDS = {
    "cassano_city", "palace", "pk_arena", "green_field", "grass_reward", "dungeon",
    "dungeon_floor_2", "dungeon_floor_3", "thunder_continent", "thunder_mine", "desert",
    "dream_swamp", "ice_palace", "ice_border", "demon_camp", "demon_left", "demon_right",
    "demon_banner", "energy_tower", "avit_island", "volcano", "abyss_maze",
    "treeheart_city", "palace_garden", "lottery_room", "pk_arena_2", "pk_arena_3",
    "war_soul_seal_maze",
}
EXISTING_QUEST_IDS = {"border_raid", "dungeon_conquest", "spider_crisis"}


def load_texts():
    texts = {}
    for ver, p in TEXT_FILES.items():
        if not p.exists():
            raise SystemExit("受控证据文本缺失: %s" % p)
        texts[ver] = p.read_text(encoding="utf-8")
    return texts


def check_token(token, texts):
    """返回命中的版本列表；未命中返回空列表。"""
    return [v for v, t in texts.items() if token in t]


def entry(kind, eid, display_name, source_version, evidence_status,
          planned_version, design_status, tokens=None, evidence_source=None,
          deps=None, notes=None, cohort=None):
    if kind not in ALLOWED_KIND:
        raise SystemExit("非法 kind: %s" % kind)
    if source_version not in ALLOWED_SOURCE_VERSION:
        raise SystemExit("非法 source_version: %s" % source_version)
    if evidence_status not in ALLOWED_EVIDENCE_STATUS:
        raise SystemExit("非法 evidence_status: %s" % evidence_status)
    if planned_version not in ALLOWED_PLANNED:
        raise SystemExit("非法 planned_version: %s" % planned_version)
    if design_status not in ALLOWED_DESIGN_STATUS:
        raise SystemExit("非法 design_status: %s" % design_status)
    tokens = tokens or []
    source = evidence_source
    if evidence_status in ("singleplayer_extension", "evidence_gap"):
        # 禁止伪造 source/token
        if source is not None or tokens:
            raise SystemExit("singleplayer_extension/evidence_gap 不得携带 source/token: %s" % eid)
        source = None
    return {
        "id": eid,
        "kind": kind,
        "display_name": display_name,
        "source_version": source_version,
        "evidence_source": source,
        "evidence_tokens": tokens,
        "evidence_status": evidence_status,
        "planned_version": planned_version,
        "design_status": design_status,
        "dependencies": deps or [],
        "notes": notes or "",
        **({"cohort": cohort} if cohort else {}),
    }


def verified(texts, token):
    """断言 token 至少在一个受控文本命中；返回命中版本列表。"""
    hits = check_token(token, texts)
    if not hits:
        raise SystemExit("TOKEN 未在任何受控文本命中（禁止写入确认/部分证据）: %r" % token)
    return hits


def build(out: Path):
    texts = load_texts()
    entries = []

    # ============ 候选地图（>=18）============
    def M(eid, cn, token, pv, ds="borrowed", deps=None, notes=None):
        hits = verified(texts, token)
        entries.append(entry("map", eid, cn, "2.4", "local_version_confirmed", pv, ds,
                             tokens=[token], evidence_source=EVIDENCE_PATH_24,
                             deps=deps, notes=(notes or "") + " 证据版本=%s" % "/".join(hits)))

    M("map_treeheart_road", "树心路", "树心路", "v1.48")
    M("map_treeheart_wild_1", "树心城野外一", "树心城野外一", "v1.48")
    M("map_south_city_1", "南城一", "南城一", "v1.49")
    M("map_south_city_wild_1", "南城野外一", "南城野外一", "v1.49")
    M("map_border_wild_1", "边关野外一", "边关野外一", "v1.49")
    M("map_frozen_valley_1", "冰封谷一", "冰封谷一", "v1.50")
    M("map_frozen_valley_2", "冰封谷二", "冰封谷二", "v1.50")
    M("map_frozen_valley_3", "冰封谷三", "冰封谷三", "v1.50")
    M("map_frozen_corridor", "冰封走廊", "冰封走廊", "v1.50")
    M("map_ice_bridge", "冰桥", "冰桥", "v1.50")
    M("map_abyss_1", "黑渊一", "黑渊一", "v1.51")
    M("map_abyss_2", "黑渊二", "黑渊二", "v1.51")
    M("map_abyss_3", "黑渊三", "黑渊三", "v1.51")
    M("map_thunder_beast_valley", "雷兽谷", "雷兽谷", "v1.50")
    M("map_spider_valley_1", "蜘蛛谷一", "蜘蛛谷一", "not_planned", ds="adapted",
      notes="本地有蜘蛛谷一/二/三与蜘蛛王后；实现排期待确认")
    M("map_white_cloud_mountain", "白云山", "白云山", "v1.48")
    M("map_green_islet", "绿岛", "绿岛", "v1.48")
    M("map_skyview_pavilion", "观天亭", "观天亭", "v1.51")
    M("map_beast_island_1", "百兽岛一", "百兽岛一", "not_planned", ds="adapted",
      notes="本地有百兽岛一/二与船夫航线；实现排期待确认")
    M("map_rose_lake", "玫瑰湖", "玫瑰湖", "v1.53")
    M("map_lost_highland_1", "失落高地一", "失落高地一", "v1.52")
    M("map_hidden_spirit_island", "隐灵岛", "隐灵岛", "not_planned", ds="adapted",
      notes="本地仅有岛名 token；机制证据 gap")

    # ============ 候选任务（60-75，五类）============
    def Q(eid, cn, pv, token, status, ds="borrowed", deps=None, notes=None):
        if token:
            hits = verified(texts, token)
        else:
            hits = []
        entries.append(entry("quest", eid, cn, "2.4" if token else "project",
                             status, pv, ds,
                             tokens=[token] if token else [],
                             evidence_source=EVIDENCE_PATH_24 if token else None,
                             deps=deps,
                             notes=(notes or "") + ((" 证据版本=%s" % "/".join(hits)) if hits else "")))

    def QX(eid, cn, pv, deps=None, notes=None):
        # 单机原创扩展任务：无本地 token
        entries.append(entry("quest", eid, cn, "project", "singleplayer_extension", pv,
                             "singleplayer_extension", deps=deps, notes=notes or ""))

    # 主线（15）
    Q("quest_main_occupy_abyss", "占领黑渊", "v1.51", "我们要将魔族大军打败就得占领黑渊", "local_version_confirmed")
    Q("quest_main_destroy_totem", "摧毁魔的图腾", "v1.51", "首先要消灭魔军主将才能看到魔的图腾", "local_version_confirmed")
    Q("quest_main_kill_demon_prince", "消灭魔王子", "v1.51", "国王派出勇士潜入敌营地里消灭魔王子", "local_version_confirmed")
    Q("quest_main_rejoin_south", "与南城军队会合", "v1.49", "消灭它们就可以与南城军队会合", "local_version_confirmed")
    Q("quest_main_rejoin_swamp", "与沼泽军队会合", "v1.49", "消灭它们就可以与沼泽军队会合", "local_version_confirmed")
    Q("quest_main_ice_valley_campaign", "冰封谷反攻", "v1.50", "消灭冰封谷的魔族军队", "local_version_confirmed")
    Q("quest_main_gobi_king", "接应国王", "v1.48", "我们需要打通戈壁与树心城的通路去接应国王", "local_version_confirmed")
    Q("quest_main_abyss_gate", "军团准入黑渊", "v1.51", "军团才能进入到黑渊", "local_version_confirmed")
    Q("quest_main_totem_guard", "图腾守卫情报", "v1.51", "他们的主要任务是看守魔的图腾", "local_version_confirmed")
    Q("quest_main_totem_weaken", "削弱图腾防御", "v1.51", "但魔的图腾摧毁被魔军保护得非常紧", "local_version_confirmed")
    QX("quest_main_black_abyss", "黑渊调查", "v1.51", notes="原创主线调查段，沿用黑渊地图 token")
    QX("quest_main_treeheart_supply", "树心补给危机", "v1.48", notes="总计划书 v1.48 指定首条新主线")
    QX("quest_main_port_lost_ship", "港口失联货船", "v1.48", notes="总计划书 v1.48 指定")
    QX("quest_main_totem_preparation", "图腾战准备", "v1.51", notes="情报/准备段，为图腾战铺垫")
    QX("quest_main_final_aftermath", "终局后日谈", "v1.54", notes="后日谈委托，v1.54 赛季内容")

    # 区域支线（16）
    Q("quest_side_mining_pick", "猎杀兽之镐", "v1.48", "打败岛上的猎杀兽就可能得到镐", "local_version_confirmed")
    Q("quest_side_mine_ore", "矿洞挖矿", "v1.48", "进入到矿洞里使用镐可以挖到矿石", "local_version_confirmed")
    Q("quest_side_find_hermit", "找寻隐者", "v1.48", "找到隐者", "local_version_confirmed")
    Q("quest_side_green_islet_mechanism", "绿岛机关兽", "v1.48", "只有打败绿岛上的机关兽才能上到白云山", "local_version_confirmed")
    Q("quest_side_thunder_beast_trail", "雷兽行踪", "v1.50", "可能会找到雷兽的行径从而找到雷兽藏身之地", "local_version_confirmed")
    Q("quest_side_radar_tower", "雷塔支柱", "v1.50", "那里有个雷塔", "local_version_confirmed")
    Q("quest_side_ice_port_ferry", "冰宫港口渡船", "v1.50", "冰宫港口的船夫知道雷兽谷怎么去", "local_version_confirmed")
    Q("quest_side_spider_valley", "蜘蛛谷清剿", "v1.52", "大蜘蛛和蜘蛛王后还会爆些书店也没卖的技能书", "local_version_confirmed")
    Q("quest_side_dragon_chief", "龙怪头目讨伐", "v1.52", "消灭龙怪头目", "local_version_confirmed")
    Q("quest_side_rescue_children", "南城救援", "v1.49", "把我的儿子和女儿都抓走了", "local_version_confirmed")
    Q("quest_side_revive_zone", "郊区复活", "v1.49", "可以到郊区去找郊区管理员复活幻兽", "local_version_confirmed")
    Q("quest_side_skill_book_low", "初级锻造技能书", "v1.48", "前往树心城技能导师处买一本初级锻造技能书", "local_version_confirmed")
    Q("quest_side_skill_book_mid", "中级锻造技能书", "v1.48", "找到他就能得到中级锻造技能书", "local_version_confirmed")
    QX("quest_side_rose_lake", "玫瑰湖调查", "v1.53", notes="原创支线，沿用玫瑰湖地图 token")
    QX("quest_side_lost_highland", "失落高地侦察", "v1.52", notes="原创支线，沿用失落高地地图 token")
    Q("quest_side_skyview_pavilion", "观天亭密钥", "v1.51", "键就可以进入到观天亭", "local_version_confirmed")

    # 固定冒险者委托（14，全部 singleplayer_extension，v1.43 启用）
    QX("quest_adv_collect_herb", "采集药材委托", "v1.43")
    QX("quest_adv_defeat_monster", "击败指定怪委托", "v1.43")
    QX("quest_adv_explore_map", "探索地图委托", "v1.43")
    QX("quest_adv_deliver_item", "交付物品委托", "v1.43")
    QX("quest_adv_pet_training", "幻兽培养委托", "v1.43")
    QX("quest_adv_campaign_help", "协助战役委托", "v1.43")
    QX("quest_adv_ore_harvest", "矿石采集委托", "v1.43")
    QX("quest_adv_element_material", "元素材料委托", "v1.43")
    QX("quest_adv_lost_item", "寻回失物委托", "v1.43")
    QX("quest_adv_escort", "护送委托", "v1.43")
    QX("quest_adv_intel", "情报交换委托", "v1.43")
    QX("quest_adv_trade_round", "交易跑腿委托", "v1.43")
    QX("quest_adv_arena_sparring", "切磋委托", "v1.43")
    QX("quest_adv_castle_supply", "城堡补给委托", "v1.43")

    # 分段挑战（12）
    Q("quest_chal_black_knight", "黑骑士试炼", "v1.52", "打败黑骑士", "local_version_confirmed")
    Q("quest_chal_legion_admin", "军团管理员", "v1.52", "军团管理员", "local_version_partial",
      notes="仅名称/职位 token 确认，具体机制未确认")
    Q("quest_chal_city_defense", "守城演习", "v1.52", "防守方需要将四面的敌人都打败才能胜利", "local_version_confirmed")
    Q("quest_chal_swamp_guard", "守卫沼泽", "v1.52", "守卫沼泽", "local_version_partial",
      notes="仅名称 token 确认，机制未确认")
    Q("quest_chal_black_robe", "黑衣圣兽师", "v1.52", "黑衣圣兽师", "local_version_partial",
      notes="仅名称 token 确认，机制未确认")
    Q("quest_chal_sneak_raid", "偷袭后路", "v1.52", "偷袭", "local_version_partial",
      notes="本地仅有'偷袭'动词 token，完整'偷袭后路'规则未确认")
    Q("quest_chal_frozen_valley", "冰封谷试炼", "v1.52", "控制冰封谷", "local_version_confirmed")
    Q("quest_chal_fleet", "断舰行动", "v1.52", "舰队主帅", "local_version_partial",
      notes="本地有舰队主帅/舰队基地/舰队士兵，行动规则未确认")
    Q("quest_chal_big_demon", "大魔王挑战", "v1.52", "消灭大魔王", "local_version_confirmed")
    Q("quest_chal_command_challenge", "挑战指挥官", "v1.52", "你可以挑战指挥官", "local_version_confirmed")
    Q("quest_chal_wild_chief", "野外头目讨伐", "v1.52", "消灭一个野外头目就能增加", "local_version_confirmed")
    Q("quest_chal_pk_ranked", "大赛排名赛", "v1.45", "比赛胜利者分为一、二、三名", "local_version_confirmed")

    # 日常/周常（15）
    Q("quest_daily_donation_1", "捐款任务一", "v1.47", "捐款任务一", "local_version_confirmed")
    Q("quest_daily_donation_2", "捐款任务二", "v1.47", "捐款任务二", "local_version_confirmed")
    Q("quest_daily_donation_3", "捐款任务三", "v1.47", "捐款任务三", "local_version_confirmed")
    Q("quest_daily_donation_4", "捐款任务四", "v1.47", "捐款任务四", "local_version_confirmed")
    Q("quest_daily_training_1", "新手训练一", "v1.48", "新手训练一", "local_version_confirmed")
    Q("quest_daily_training_2", "新手训练二", "v1.48", "新手训练二", "local_version_confirmed")
    Q("quest_daily_training_3", "新手训练三", "v1.48", "新手训练三", "local_version_confirmed")
    Q("quest_daily_training_4", "新手训练四", "v1.48", "新手训练四", "local_version_confirmed")
    Q("quest_daily_regular", "日常任务", "v1.44", "这里的日常任务有", "local_version_confirmed")
    Q("quest_daily_honor", "荣誉任务", "v1.44", "我发布了荣誉任务", "local_version_confirmed")
    Q("quest_daily_bounty", "悬赏任务", "v1.44", "悬赏任务", "local_version_confirmed")
    Q("quest_daily_merit", "军功任务", "v1.44", "军功任务", "local_version_confirmed")
    Q("quest_daily_rank", "功勋任务", "v1.44", "功勋任务", "local_version_confirmed")
    QX("quest_daily_adventurer", "冒险者日常委托", "v1.44", notes="v1.44 日结后启用的冒险者日常池")
    QX("quest_weekly_market", "周挑战", "v1.54", notes="v1.54 每周两项高价值挑战")

    # ============ 固定冒险者：首批 12 + 候补 24 ============
    FIRST = [
        ("npc_adv_lin_xia", "林夏", "见习采集者，委托以收集材料为主"),
        ("npc_adv_su_yan", "苏妍", "情报向，委托以探索地图为主"),
        ("npc_adv_liang_chen", "梁辰", "战士向，委托以击败指定怪为主"),
        ("npc_adv_jiang_yue", "江月", "医师向，委托以交付药材/药品为主"),
        ("npc_adv_qin_he", "秦鹤", "幻兽向，委托以幻兽培养为主"),
        ("npc_adv_gu_ning", "顾宁", "守备向，委托以协助守城战役为主"),
        ("npc_adv_ye_fei", "叶飞", "游侠向，委托以护送与寻回失物为主"),
        ("npc_adv_bai_luo", "白洛", "锻造向，委托以矿石/玄铁收集为主"),
        ("npc_adv_xiao_ran", "萧然", "交易向，委托以交易跑腿为主"),
        ("npc_adv_tang_xue", "唐雪", "药剂向，委托以元素材料收集为主"),
        ("npc_adv_he_ming", "何明", "商旅向，委托以情报交换为主"),
        ("npc_adv_shen_yao", "沈瑶", "学者向，委托以竞技切磋为主"),
    ]
    BACKUP = [
        ("npc_adv_b1", "周楚", "老兵，委托以协助战役为主"),
        ("npc_adv_b2", "孟瑶", "采集者，委托以药圃材料为主"),
        ("npc_adv_b3", "韩露", "歌者，委托以送礼与关系为主"),
        ("npc_adv_b4", "赵云帆", "斥候，委托以探索新地图为主"),
        ("npc_adv_b5", "楚云", "铁匠，委托以玄铁/陨铁为主"),
        ("npc_adv_b6", "沈碧", "药圃主，委托以种植材料为主"),
        ("npc_adv_b7", "陆承", "护卫，委托以护送商队为主"),
        ("npc_adv_b8", "许晴", "商会联络，委托以跑腿交易为主"),
        ("npc_adv_b9", "宋词", "吟游者，委托以情报与信件为主"),
        ("npc_adv_b10", "方远", "猎人，委托以猎杀兽材料为主"),
        ("npc_adv_b11", "罗琳", "驯兽师，委托以幻兽培养为主"),
        ("npc_adv_b12", "程曦", "学者，委托以图鉴收集为主"),
        ("npc_adv_b13", "莫言", "观察者，委托以排行榜观察为主"),
        ("npc_adv_b14", "严正", "军需官，委托以军功贡献为主"),
        ("npc_adv_b15", "柳如烟", "舞者，委托以竞技表演为主"),
        ("npc_adv_b16", "杜若", "医师，委托以药品交付为主"),
        ("npc_adv_b17", "裴行", "铸甲师，委托以装备材料为主"),
        ("npc_adv_b18", "郑和风", "航海，委托以港口航线为主"),
        ("npc_adv_b19", "温良", "粮草官，委托以补给护送为主"),
        ("npc_adv_b20", "谷雨", "农艺，委托以牧场/药圃为主"),
        ("npc_adv_b21", "史明", "史官，委托以记录与情报为主"),
        ("npc_adv_b22", "柯南星", "星象师，委托以元素材料为主"),
        ("npc_adv_b23", "花木兰", "武将，委托以协助战役为主"),
        ("npc_adv_b24", "欧阳雪", "学者，委托以异兽研究为主"),
    ]
    for nid, cn, note in FIRST:
        entries.append(entry("npc", nid, cn, "project", "singleplayer_extension", "v1.43",
                             "singleplayer_extension", cohort="first", notes=note))
    for nid, cn, note in BACKUP:
        entries.append(entry("npc", nid, cn, "project", "singleplayer_extension", "not_planned",
                             "singleplayer_extension", cohort="backup", notes=note + "（候补，不进入 v1.43 生产）"))

    # ============ 候选物品/材料（>=20）============
    def I(eid, cn, token, pv, ds="borrowed", notes=None):
        hits = verified(texts, token)
        entries.append(entry("item", eid, cn, "2.4", "local_version_confirmed", pv, ds,
                             tokens=[token], evidence_source=EVIDENCE_PATH_24,
                             notes=(notes or "") + " 证据版本=%s" % "/".join(hits)))

    I("item_moonlight_box", "初级月光宝盒", "初级月光宝盒", "v1.53")
    I("item_lucky_charm", "永恒幸运符", "永恒幸运符", "v1.53")
    I("item_exp_orb", "超级经验球", "超级经验球", "v1.53")
    I("item_soul_crystal", "灵魂晶石", "灵魂晶石", "v1.53")
    I("item_demon_soul_crystal", "幻魔晶石", "幻魔晶石", "v1.53")
    I("item_war_soul_crystal", "魔魂晶石", "魔魂晶石", "v1.53")
    I("item_element_gem", "元素宝石", "元素宝石", "v1.50")
    I("item_attack_gem", "攻击宝石", "攻击宝石", "v1.50")
    I("item_exp_gem", "经验宝石", "经验宝石", "v1.53")
    I("item_xuantie_ore", "玄铁矿", "玄铁矿", "v1.50")
    I("item_yunite_ore", "陨铁矿", "陨铁矿", "v1.50")
    I("item_amethyst", "紫水晶", "紫水晶", "v1.53")
    I("item_lucky_grass", "幸运幻化草", "幸运幻化草", "v1.53")
    I("item_divine_beast_dan", "神兽内丹", "神兽内丹", "v1.53")
    I("item_plasma_potion", "电浆药水", "电浆药水", "v1.50")
    I("item_warrior_medal", "勇士勋章", "勇士勋章", "v1.52")
    I("item_beast_king_orb", "兽王令", "兽王令", "v1.53")
    I("item_sacred_beast_orb", "圣兽令", "圣兽令", "v1.53")
    I("item_mystic_fruit", "奇异果", "奇异果", "v1.53")
    I("item_rebirth_crystal", "幻兽转世水晶", "幻兽转世水晶", "v1.53")
    I("item_fengwing_bell", "凤翼铃铛", "上品凤翼铃铛", "v1.53")
    I("item_mysterious_item", "神秘物品", "合成神秘物品", "v1.53")

    # ============ 候选技能/Boss/挑战（>=18）============
    def S(eid, cn, token, pv, kind="skill", notes=None):
        hits = verified(texts, token)
        entries.append(entry(kind, eid, cn, "2.4", "local_version_confirmed", pv, "borrowed",
                             tokens=[token], evidence_source=EVIDENCE_PATH_24,
                             notes=(notes or "") + " 证据版本=%s" % "/".join(hits)))

    S("skill_fly_combo", "飞天连斩", "飞天连斩", "v1.52")
    S("skill_whirlwind_slash", "旋风斩", "旋风斩", "v1.52")
    S("skill_blade_light_slash", "刀光斩", "刀光斩", "v1.52")
    S("skill_fireball", "火球术", "火球术", "v1.52")
    S("skill_thunderburst", "爆雷术", "爆雷术", "v1.52")
    S("skill_lightning", "电击术", "电击术", "v1.52")
    S("skill_thunderstrike", "雷霆万钧", "雷霆万钧", "v1.52")
    S("skill_soul_slash", "斩魂", "斩魂", "v1.52")
    S("skill_berserk", "狂暴", "狂暴", "v1.52")

    S("boss_thunder_beast", "雷兽", "雷兽非常厉害", "v1.50", "boss")
    S("boss_spider_queen", "蜘蛛王后", "蜘蛛王后", "v1.52", "boss")
    S("boss_demon_commander", "魔军主将", "魔军主将", "v1.51", "boss")
    S("boss_demon_prince", "魔王子", "魔王子", "v1.51", "boss")
    S("boss_great_demon", "大魔王", "消灭大魔王", "v1.52", "boss")
    S("boss_black_knight", "黑骑士", "打败黑骑士", "v1.52", "boss")
    S("boss_death_general", "死神战将", "死神战将", "v1.52", "boss")
    S("boss_beast_king", "魔灵兽王", "魔灵兽王", "v1.53", "boss")
    S("boss_mechanism_beast", "机关兽", "机关兽", "v1.48", "boss")
    S("boss_radar_tower", "雷塔", "消灭雷塔", "v1.50", "boss")
    S("boss_fleet_admiral", "舰队主帅", "舰队主帅", "v1.52", "boss",
      notes="仅名称 token 确认，机制未确认（partial 口径）")

    # 单机原创系统（singleplayer_extension）
    for sid, cn, pv, note in [
        ("sys_auction", "拍卖会", "v1.46", "单机封闭市场，非原版还原"),
        ("sys_rankings", "排行榜", "v1.45", "异步榜单，非联网"),
        ("sys_daily_ledger", "NPC日结经济", "v1.44", "固定冒险者每日抽象日结"),
        ("sys_industry", "产业与城堡经营", "v1.47", "矿场/药圃/港口货栈/幻兽牧场"),
        ("sys_season", "十四日赛季", "v1.54", "赛季结算循环"),
        ("sys_collection", "收藏图鉴", "v1.53", "幻兽/装备/Boss/地图/信件/称号图鉴"),
    ]:
        entries.append(entry("system", sid, cn, "project", "singleplayer_extension", pv,
                             "singleplayer_extension", notes=note))

    # ============ 汇总校验 ============
    ids = [e["id"] for e in entries]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise SystemExit("重复 ID: %s" % dup)
    for mid in [e["id"] for e in entries if e["kind"] == "map"]:
        if mid in EXISTING_MAP_IDS:
            raise SystemExit("候选地图与现有 maps.json 冲突: %s" % mid)
    for qid in [e["id"] for e in entries if e["kind"] == "quest"]:
        if qid in EXISTING_QUEST_IDS:
            raise SystemExit("候选任务与现有 quests.json 冲突: %s" % qid)

    n_map = sum(1 for e in entries if e["kind"] == "map")
    n_quest = sum(1 for e in entries if e["kind"] == "quest")
    n_npc_first = sum(1 for e in entries if e["kind"] == "npc" and e.get("cohort") == "first")
    n_npc_backup = sum(1 for e in entries if e["kind"] == "npc" and e.get("cohort") == "backup")
    n_item = sum(1 for e in entries if e["kind"] == "item")
    n_skillboss = sum(1 for e in entries if e["kind"] in ("skill", "boss"))
    if n_map < 18:
        raise SystemExit("候选地图 %d < 18" % n_map)
    if not (60 <= n_quest <= 75):
        raise SystemExit("候选任务 %d 不在 60-75 范围" % n_quest)
    if n_npc_first != 12:
        raise SystemExit("首批固定冒险者 %d != 12" % n_npc_first)
    if n_npc_backup < 24:
        raise SystemExit("候补固定冒险者 %d < 24" % n_npc_backup)
    if n_item < 20:
        raise SystemExit("候选物品 %d < 20" % n_item)
    if n_skillboss < 18:
        raise SystemExit("候选技能/Boss %d < 18" % n_skillboss)

    registry = {
        "registry_version": "v1.42.1",
        "baseline_version": "v1.41",
        "generated_for": "v1.42 内容证据与扩展数据合同：本地 2.2/2.3/2.4 纯文本证据 + 单机原创扩展目录",
        "evidence_texts": {
            "2.2": "docs/evidence/v142/moyu_2.2_strings.txt",
            "2.3": "docs/evidence/v142/moyu_2.3_strings.txt",
            "2.4": "docs/evidence/v142/moyu_2.4_strings.txt",
            "note": "docs/evidence/v142 为仓库内可提交的规范副本；work/v142/text 为可重跑提取输出（gitignored）",
        },
        "categories": {
            "map": n_map,
            "quest": n_quest,
            "npc_first": n_npc_first,
            "npc_backup": n_npc_backup,
            "item": n_item,
            "skill_boss": n_skillboss,
            "system": sum(1 for e in entries if e["kind"] == "system"),
            "total": len(entries),
        },
        "entries": entries,
    }

    out.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding="utf-8")
    print("REGISTRY_OK total=%d map=%d quest=%d npc_first=%d npc_backup=%d item=%d skill_boss=%d system=%d -> %s"
          % (len(entries), n_map, n_quest, n_npc_first, n_npc_backup, n_item, n_skillboss,
             len(entries) - n_map - n_quest - n_npc_first - n_npc_backup - n_item - n_skillboss, out))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "docs" / "moyu_23_24_content_registry.json")
    args = ap.parse_args()
    sys.exit(build(args.out))
