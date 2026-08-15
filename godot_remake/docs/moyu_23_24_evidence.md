# 魔域 2.2/2.3/2.4 本地内容证据文档

状态：v1.42 交付文档（候选目录与证据 token，未接入生产）
证据约束：仅文本、源代码、JSON、资源路径、命令与日志；无任何非文本附件。

---

## 1. 反查范围与可重跑命令

| 版本 | SWF 路径 | 提取命令（可重跑） | 退出码 | 耗时 | 受控证据文本（仓库内规范副本） |
|---|---|---|---|---|---|
| 2.2 | E:\魔域\2.2.swf | `timeout 90 python work/v142/extract_swf_text.py "E:/魔域/2.2.swf" "work/v142/text/moyu_2.2_strings.txt" --label "2.2"` | 0 | ~3.3s | [docs/evidence/v142/moyu_2.2_strings.txt](evidence/v142/moyu_2.2_strings.txt) |
| 2.3 | E:\魔域\2.3.swf | `timeout 180 python work/v142/extract_swf_text.py "E:/魔域/2.3.swf" "work/v142/text/moyu_2.3_strings.txt" --label "2.3"` | 0 | ~3.5s | [docs/evidence/v142/moyu_2.3_strings.txt](evidence/v142/moyu_2.3_strings.txt) |
| 2.4 | E:\魔域\2.4.swf | `timeout 180 python work/v142/extract_swf_text.py "E:/魔域/2.4.swf" "work/v142/text/moyu_2.4_strings.txt" --label "2.4"` | 0 | ~3.4s | [docs/evidence/v142/moyu_2.4_strings.txt](evidence/v142/moyu_2.4_strings.txt) |

路径说明：`work/v142/text/` 为可重跑提取输出目录（仓库 .gitignore 忽略，不提交）；`docs/evidence/v142/` 为仓库内可提交的规范副本，注册表 `evidence_source` 与测试校验均以它为权威，保证克隆仓库后证据链可复核。

提取统计（去重后唯一字符串条数）：

| 版本 | UTF-8 CJK | GBK CJK（二级） | ASCII 标识符 |
|---|---:|---:|---:|
| 2.2 | 2978 | 64835 | 24046 |
| 2.3 | 3063 | 68852 | 28306 |
| 2.4 | 3089 | 69244 | 28462 |

说明：
- UTF-8 CJK 为主模式（游戏正文为 UTF-8 编码，含全角标点）；GBK 二级模式大量来自二进制数据误配，仅作辅助不用于 token 判定。
- ASCII 标识符用于定位 AS2 类名/变量/路径（如 `HuanShouClass`、`RoleMC`、`DefineSprite_2185_任务系统`），仅辅助定位，不单独作为机制证据。

## 2. 2.2 处理记录（可终止、如实登记）

- **尝试 1（FFDec 全量反编译，历史审计产物，位于 TKS3_mod/work/moyu_versions_audit）**：JPEXS Free Flash Decompiler v.26.2.1 对 2.2 的 AS2 动作码翻译报 `SEVERE: Invalid property index: PopItem/DuplicateItem/DeleteActionItem...`，产生约 1.8GB 错误日志，p-code 导出为空。结论：2.2 的**动作码/p-code 级别导出不稳定**，不能作为机制证据。
- **尝试 2（本项目可重跑字节扫描）**：`work/v142/extract_swf_text.py` 不解析动作码语义，只扫描原始字节中的 UTF-8/GBK CJK 与 ASCII 连续段，对 2.2 稳定成功（exit 0，~3.3s，2978 条 UTF-8 中文）。输出落 `work/v142/text/`（gitignored），同步规范副本至 `docs/evidence/v142/`。
- **口径**：2.2 的内容 token 以"字符串确实存在于 SWF 字节中"为证据级别；不声称 2.2 的机制/拓扑/坐标已确认。

## 3. 内容分类统计（见 docs/moyu_23_24_content_registry.json）

| 类别 | 数量 | 说明 |
|---|---:|---|
| 候选地图 | 22 | 全部 local_version_confirmed，token 精确命中 |
| 候选任务 | 72 | 主线 15 / 区域支线 16 / 冒险者委托 14 / 分段挑战 12 / 日常周常 15 |
| 首批固定冒险者 | 12 | singleplayer_extension（本项目原创，v1.43 启用） |
| 候补固定冒险者 | 24 | singleplayer_extension（不进入 v1.43 生产） |
| 候选物品/材料 | 22 | 全部 local_version_confirmed |
| 候选技能/Boss | 20 | 9 技能 + 11 Boss，token 精确命中 |
| 单机原创系统 | 6 | 拍卖/排行/日结/产业/赛季/图鉴，singleplayer_extension |
| **合计** | **178** | — |

证据状态分布：`local_version_confirmed` 108 / `local_version_partial` 5 / `singleplayer_extension` 65 / `evidence_gap` 0。

## 4. 版本分配

`planned_version`：v1.43×26、v1.44×7、v1.45×2、v1.46×1、v1.47×5、v1.48×18、v1.49×7、v1.50×17、v1.51×15、v1.52×30、v1.53×20、v1.54×3、not_planned×27。均在《v1.42 以后单机长线扩展任务书》版本路线内。

## 5. 代表性证据 token 示例（全部精确命中，逐条可 grep）

- 地图：`树心路`、`南城一`、`南城野外一`、`冰封谷一/二/三`、`冰封走廊`、`冰桥`、`黑渊一/二/三`、`雷兽谷`、`白云山`、`绿岛`、`观天亭`
- 主线：`我们要将魔族大军打败就得占领黑渊`、`首先要消灭魔军主将才能看到魔的图腾`、`国王派出勇士潜入敌营地里消灭魔王子`、`消灭它们就可以与南城军队会合`
- 区域支线：`只有打败绿岛上的机关兽才能上到白云山`、`可能会找到雷兽的行径从而找到雷兽藏身之地`、`冰宫港口的船夫知道雷兽谷怎么去`
- 朋友/关系：`邮寄物品给朋友也可能收到朋友回邮物品`、`还有一定概率能接到朋友的任务`、`朋友越多任务奖励越高`
- 资源/城堡：`关于军衔和爵位的更多信息你可以到皇宫里向元帅打听`、`从南城二的右上角可以进入到我的城堡`
- 挑战：`防守方需要将四面的敌人都打败才能胜利`、`比赛胜利者分为一、二、三名`、`你可以挑战指挥官`
- 幻兽/元素：`全套四件装备都有相同元素就可以构成元素套装`、`幻兽使用雷神兽内丹后将会获得新的生命`
- 物品：`初级月光宝盒`、`永恒幸运符`、`超级经验球`、`玄铁矿`、`陨铁矿`、`上品凤翼铃铛`
- 技能/Boss：`飞天连斩`、`旋风斩`、`雷霆万钧`、`雷兽非常厉害`、`蜘蛛王后`、`魔军主将`

## 6. 关键证据句子摘录（完整句，便于人工复核）

> 说明：有一种叫做雷兽的怪物，经常出现在各村子害人。它行动非常迅速……现在已经知道雷兽是来自一个叫雷兽谷的地方，那里有个雷塔，它是雷兽的能量支柱。毁掉雷塔可以大大削弱雷兽的力量，还可以把雷兽吸引出来。

> 军团，据说是魔族军队中战斗力最强的军团。他们的主要任务是看守魔的图腾，是魔的图腾给与了魔族军队战斗力的，只要能将魔的图腾摧毁，魔族军队就会被全面战胜。但魔的图腾摧毁被魔军保护得非常紧，首先要消灭魔军主将才能看到魔的图腾。

> 你需要打通戈壁与树心城的通路去接应国王。（原文：我们需要打通戈壁与树心城的通路去接应国王）

## 7. 未覆盖范围与 evidence_gap 声明

本版本**没有任何条目登记为 evidence_gap**。以下为"已确认存在的证据能力边界"，不是条目级 gap，统一登记在 [docs/expansion_content_decisions.md](expansion_content_decisions.md) 与注册表 notes 中：

1. 字节扫描只证明字符串存在于 SWF 字节中，**不证明运行机制**（按钮跳转、触发条件、数值公式）。所有 confirmed token 只用于"该内容名称/文本在原版存在"。
2. 地图名称 token 不证明地图拓扑、角色坐标或全部交互已确认（总计划书 2.3 规则）。
3. 2.2 的 FFDec 动作码/p-code 导出失败，因此 2.2 仅能提供字符串级别证据，机制级别仍为 gap。
4. 本地存在"朋友/好友/邮寄"文本与入口，不代表存在完整拍卖行或联网玩家经济；拍卖/排行/日结均标 singleplayer_extension。
5. `偷袭后路`、`军团管理员`、`守卫沼泽`、`黑衣圣兽师`、`断舰行动` 五个挑战仅确认名称/局部 token（local_version_partial），完整规则未确认。
6. DefineText/DefineEditText 静态字形文本依赖字体映射，纯字节扫描无法直接还原；既有 FFDec 审计显示 2.3/2.4 静态文本仅"魔域"标题。
