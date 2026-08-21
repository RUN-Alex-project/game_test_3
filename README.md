# 魔域 1.03 Godot 重制版

这是一个以《魔域 1.03》原 SWF 的资源、地图、角色和交互证据为基础，用 Godot 4 重建的单机游戏项目。当前可运行工程位于 [`godot_remake/`](godot_remake/)。

## 从哪里开始

- 想直接运行：阅读 [`godot_remake/README.md`](godot_remake/README.md)。
- 想按流程游玩：阅读 [`godot_remake/docs/玩家攻略.md`](godot_remake/docs/玩家攻略.md)。
- 想了解数值和证据：查看 [`godot_remake/data/`](godot_remake/data/) 与 [`godot_remake/docs/`](godot_remake/docs/)。
- 想验证工程：在 `godot_remake` 目录执行 `.\run_tests.ps1`。

## 当前边界

工程是可运行的 Godot 重制版，不是原 SWF 的字节级转换器。原始 SWF 的部分时间轴、视觉细节和少数触发证据仍在专项文档中标为 gap；运行时采用仓库内已提取的图片、音频和数据，不要求把原始 SWF 放进项目目录。

## 目录

```text
godot_remake/
  assets/       运行时图片、音频与提取资源
  data/         物品、怪物、地图、技能、幻兽和成长数值
  scenes/       Godot 场景
  scripts/      游戏状态、地图、战斗、UI 与服务
  tests/        自动化场景测试
  docs/         证据注册表、审计记录、攻略与发布门禁
```

## 贡献前须知

请先阅读 `godot_remake/README.md` 的“开发与测试”章节。不要提交 `.godot/`、`_playdata/`、发布包、日志、原始 SWF、审计临时目录或个人存档；这些文件不属于游戏源代码交付范围。
