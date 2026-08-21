# 魔域 1.03 Godot 重制版

一个以原版 SWF 的图片、音频、地图、角色坐标和 ActionScript 反查结果为依据的 Godot 4 单机重制工程。当前版本重点完成了原版主城与 28 张地图的交互框架、战斗/掉落、装备养成、幻兽、任务剧情、存档和自动化验收链；玩法数值中的用户定制项也集中保存在 JSON 数据和 `GameState` 配置中。

> 这不是把 SWF 直接转换成 Godot 的工具，也不宣称所有画面已经逐像素一致。已确认的原版证据、运行时重建值和仍待确认的证据缺口，分别记录在 `docs/` 下的注册表和复验报告中。

## 1. 快速开始

### 运行环境

- Windows 10/11（PowerShell）
- Godot 4.6 或兼容的 Godot 4.x 版本
- 兼容渲染器；项目固定 700×550 的逻辑画布，并允许窗口缩放

### 启动游戏

在本目录打开 PowerShell：

```powershell
# 编辑器
godot --path . --editor

# 直接运行主场景
godot --path .
```

主场景为 `res://scenes/main.tscn`。如果系统没有把 `godot` 加入 PATH，请把命令替换为 Godot 可执行文件的绝对路径，例如：

```powershell
& "C:\Program Files\Godot\Godot.exe" --path .
```

首次运行会在 Godot 的 `user://` 目录创建本地存档；存档不写入仓库。

## 2. 玩家操作

### 地图移动

- `WASD` 或方向键：移动主角。
- 地图边缘的绿色入口：切换到相邻地图。
- 被等级、爵位、日期或剧情锁定的入口仍可点击，游戏会显示具体原因，不会静默无反应。
- 点击地图中的 NPC、怪物、矿点、宝箱和任务对象，直接走当前地图的原生交互路径。

### 主界面

- 底栏：`背包`、`装备`、`幻兽`、`技能`、`VIP`。
- `垃圾箱`：显示丢弃提示；背包和仓库中的物品支持拖动交换。
- 顶部：人物卡、两张幻兽卡和当前地图卡。幻兽卡可召回、合体或解体。
- NPC 对话：点击人物后选择橙色选项；商店、仓库、研究所和任务窗口从对话入口打开。

### 战斗

- 左键点击怪物：普通攻击并进入该怪物的原地战斗。
- 右键点击怪物：尝试施放已学会的最强主动技能；没有可用技能时按当前生产逻辑处理。
- 技能消耗人物体力；体力不足时会记录失败反馈并按游戏规则降级处理，不会重复扣除。
- 战斗中可观察人物/幻兽生命、伤害飘字、怪物受击、掉落和战斗结束状态。

## 3. 工程结构

| 目录/文件 | 作用 |
| --- | --- |
| `project.godot` | Godot 项目设置、主场景、Autoload 和 WASD 输入绑定 |
| `scenes/` | 主场景、战斗与测试场景资源 |
| `scripts/game_state.gd` | 金币、魔石、经验、地图、任务、背包、存档等持久状态 |
| `scripts/main_original.gd` | 主场景 HUD、地图实体、NPC、出口和玩家输入 |
| `scripts/scene_battle_controller.gd` | 原地战斗、战斗动画、取消与生命周期 |
| `scripts/combat_service.gd` | 伤害、闪避、掉落和战斗结算公式 |
| `scripts/pet_service.gd` | 幻兽创建、升级、合体和研究所状态 |
| `scripts/enhancement_service.gd` | 品质、魔魂、战魂、天魂、地魂处理 |
| `data/*.json` | 可审阅的地图、怪物、物品、技能、任务、爵位和成长配置 |
| `tests/` | Godot headless 自动化场景测试 |
| `docs/` | 证据注册表、数值审计、存档审计、UI 审计和攻略 |

三个 Autoload 服务为 `GameState`、`AudioService`、`FeedbackService`。玩法代码应优先调用这些服务，不要在 UI 中复制金币、掉落或成长公式。

## 4. 当前玩法总览

### 地图与解锁

工程包含 28 张地图。主要等级门槛如下：

| 区域 | 等级门槛 | 主要内容 |
| --- | ---: | --- |
| 卡萨诺城、皇宫、草原、地下城一层至三层 | 无单独等级门槛（剧情解锁） | 主城 NPC、五福娃、救王主线和地下城 |
| 雷鸣大陆、雷鸣矿洞 | 10 | 野外战斗、矿点、雷鸣 Boss |
| 戈壁 | 20 | 沙漠路线与 Boss |
| 迷梦沼泽 | 30 | 蜘蛛危机、沼泽 Boss |
| 冰宫至魔军阵地、能量塔 | 50 | 冰雪军功链、魔军剧情 |
| 亚维特岛 | 70 | 蜘蛛王后和亚维特 Boss |
| 火山 | 90 | 火山 Boss |
| 深渊迷宫 | 100 | 最终区域与深渊 Boss |

PK 赛场、后花园、抽奖房、树心城和战魂封印谜宫是特殊入口，不完全按野外等级路线推进。精确出口、条件和动态实体请以 `data/maps.json` 与 `docs/world_interaction_registry.json` 为准。

### 当前生效的数值覆盖

这些是本工程当前配置，不代表所有数值都来自原版：

| 项目 | 当前值 |
| --- | ---: |
| 人物获得经验倍率 | ×10 |
| Boss 军功倍率 | ×10 |
| 普通怪军功倍率 | ×1 |
| 普通掉落倍率 | ×1 |
| 品质成功率 | 100% |
| 魔魂成功率 | 100% |
| 战魂晶石成功率 | 50% |
| 99 朵玫瑰好感 | +50 |
| 999 朵玫瑰好感 | +250 |
| 研究所技术等级上限 | 300 |
| 研究所产量任务 | 每次 +2，日产量上限 6 |

配置来源见 `data/progression.json`、`data/enhancement.json`、`data/pet_config.json` 和 `docs/value_audit_registry.json`。修改数值时请同时更新对应测试和审计注册表。

### 背包、仓库与商店

- 人物背包和仓库各有 48 个逻辑槽位；界面按分页显示，背包每页 24 格，仓库按原生紧凑布局分批显示。
- 物品支持堆叠、数量显示、悬停说明和跨容器拖动；合法交换以原子操作提交，拖动失败不会凭空删除物品。
- 杂货商负责普通物品和银矿出售；收藏家负责金矿、收藏品和魔石交易；矿石品质会影响交易结果。
- 经验球容量为 27,000，用于幻兽训练/幻化相关流程；它不是人物直接升级按钮。

### 装备与养成

人物装备有武器、头盔、项链、衣服、手镯、战靴六个槽位。品质、魔魂、战魂、天魂和地魂分别由 `enhancement.json` 与装备服务处理；材料不足或已激活等前置失败不扣料；每次实际尝试只扣一次对应材料，战魂激活失败仍按一次尝试处理。

幻兽系统包含：基础属性、经验和等级、出征/召回、合体/解体、幻化、经验球训练、研究所生产和研究所购买。幻兽最高 50 级，最多同时出征 2 只；人物等级对幻兽有额外的等级空间限制。

### 任务、剧情和时间

当前日历从第 1 天开始，每天有固定的时间消耗。日常任务、研究所生产、PK 报名、周日礼物和部分剧情入口会读取日期；不要用“重复点击”代替跨日推进。

重要剧情链：地下城三层救王 → 皇宫王室对话 → 后花园/侍女/公主事件 → 冰雪边境与四支魔军增援 → 魔军主帅 → 能量塔 → 结局页。五福娃、战魂封印、PK 和研究所是并行支线。

## 5. 存档与数据修改

- 存档位于 Godot 的 `user://savegame.json`，当前 schema 版本为 **v22**。
- 保存采用临时文件、校验、备份和原子替换；读取采用 DTO 先校验、再一次性提交，坏档不会直接覆盖当前内存状态。
- `data/*.json` 是游戏配置，不是存档。建议先备份，再修改一个字段，运行对应测试验证。
- 不要手工编辑 `user://savegame.json` 来跳过流程；如果必须诊断坏档，先复制文件并保留原始内容。

## 6. 开发与测试

### 克隆后第一步：前置检查

```powershell
cd <repo>\godot_remake
$env:GODOT_EXE = "<Godot_v4.6.3-stable_win64.exe 真实路径>"
python tools/preflight.py
```

按仓库策略有三类输入不入库：Godot 导入缓存 `.godot/`、原版 SWF、发布产物
（`*.exe` / `*.pck` / `build_manifest.json` / `SHA256SUMS.txt`）。
`tools/preflight.py` 会逐项报出缺什么、在哪、怎么补，以及当前能跑到什么程度，
不必等到全量以 `No loader found for resource` 这类错误失败才发现。

缺前置又想先跑能跑的部分：`python tools/run_tests.py --only-available`。
它把前置缺失的场景报为 `PREREQ_MISSING`（不是 PASS、不是 SKIP），
并打印与完整门禁不同的结束标记，避免部分运行被当成完整证据。

### 快速回归

```powershell
cd E:\deepseek-work\TKS3_mod\godot_remake
.\run_tests.ps1
```

`tests/test_manifest.json` 是唯一测试清单，当前登记 90 个自动化场景，最后再运行一次主场景冒烟，共 91 RUN；`run_tests.ps1`（Windows）与 `run_tests.sh`（Linux）都是 `tools/run_tests.py` 的薄入口。runner 会检查退出码、`PASS` 完成标记、脚本错误、失败标记、ObjectDB 泄漏和不可写测试数据。场景清单以 manifest 实际内容为准，不要在文档中手写另一套数量。

当前测试口径：**90 个自动化场景 + 主场景冒烟，共 91 RUN**（数量由 `docs/doc_gate.py` 从 `tests/test_manifest.json` 机械读取，基线见 `docs/current_test_baseline.json`；历史版本数量冻结不机械替换）。

### Linux / WSL 快速开始（简版）

```bash
cd ~/deepseek-work/TKS3_mod/godot_remake   # 必须位于 ext4（/home 或 /root），不要用 /mnt/*
export GODOT_BIN=/usr/local/bin/godot      # Godot 4.6 Linux
./run_tests.sh
```

Windows-only 场景（如 release 候选校验）在 Linux 输出 `NOT_APPLICABLE`，不算 SKIP/PASS/FAIL。详见 `docs/linux_wsl_port.md`。

### 文档与发布门禁

```powershell
python .\docs\doc_gate.py
```

发布包、哈希、存档和旧报告的复验记录见 `docs/综合整改报告.md`、`docs/v1.37-v1.41_全版本复验文档.md` 和 `docs/UI修复交付报告.md`。

`artifacts/releases/v1.41/` 里三份文档（交付报告 / 已知问题 / 试玩验收清单）是内容，已入库；
`*.exe`、`*.pck`、`build_manifest.json`、`SHA256SUMS.txt` 是派生产物，不入库，由
`python work/v155/rebuild_release.py` 生成。个人日志一律不提交。

### 启动与打包

```powershell
.\tools\play.ps1                 # 校验 exe/pck 哈希三方一致后启动 v1.41 发布包
.\tools\play.ps1 -VerifyOnly     # 只校验不启动
.\tools\build_playable.ps1       # 另出 embed_pck=true 单文件包到 artifacts/playable/
```

v1.41 是非内嵌导出，exe 必须与同名 `.pck` 同目录，单独移动 exe 会启动失败；
`tools/play.ps1` 会先确认这一点再启动。想要一个能整体拷走双击运行的文件就用
`tools/build_playable.ps1`，它输出到 `artifacts/playable/`，不改动已签署的 `artifacts/releases/v1.41/`。

### 修改原则

1. 先修改数据/生产代码，再补测试和文档；不要让测试绕过生产入口。
2. 每个成功断言应有状态差；每个负向测试应先证明变异生效，再命中精确错误码。
3. 原版证据、运行时重建值和推断内容分开标注，不要把名称推断写成触发证据。
4. 上一版本未正式验收时，不开始下一版本的玩法改动。

## 7. 已知限制

- 少数 SWF 时间轴、按钮触发细节、NPC 悬停状态和动态附加机制仍记录为 evidence gap。
- 画面使用原资源和原始坐标重建，但尚未把所有窗口做逐像素截图验收。
- 原始 SWF、审计工具下载物、Godot 导入缓存和发布中间产物不属于源代码提交范围。
- 某些掉落概率是“基础概率 × 幸运/baoli”后的运行时结果，攻略中只对有明确配置的项目给出数值；未确认的概率不会猜测。

## 8. 相关文档

- [玩家攻略](docs/玩家攻略.md)
- [世界交互注册表](docs/world_interaction_registry.json)
- [故事对话注册表](docs/story_dialogue_registry.json)
- [数值审计注册表](docs/value_audit_registry.json)
- [存档 schema 注册表](docs/save_schema_registry.json)
- [UI 修复交付报告](docs/UI修复交付报告.md)
- [综合整改报告](docs/综合整改报告.md)
