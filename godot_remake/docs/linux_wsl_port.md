# Linux / WSL2 开发与自动化测试指南

状态：v1.42 跨平台第一阶段（P0 迁移 + P1 测试基础设施）交付文档
适用：WSL2 Ubuntu / 原生 Linux；Windows 原有能力完整保留（见文末）

---

## 1. 支持的环境

- WSL2 Ubuntu（本工程已验证：Ubuntu-aiot-22.04，内核 6.18.x-microsoft-standard-WSL2）
- 原生 Linux x86_64（同一 runner，无 WSL 特定依赖）

## 2. 推荐工作目录

- 工作树必须位于 Linux ext4 文件系统：`/home/<user>/...` 或 `/root/...`
- 本工程已验证路径：`/root/deepseek-work/TKS3_mod`（从 Windows `E:\deepseek-work\TKS3_mod` 经 tar 管道迁移）

## 3. 不推荐的目录

- `/mnt/c`、`/mnt/d`、`/mnt/e`（Windows NTFS 挂载点）**不能作为长期开发工作树**：
  大小写不敏感（掩盖 res:// 路径大小写错误）、跨文件系统 I/O 显著拖慢 Godot 资源导入与测试。
- 在 NTFS 工作树上"跑通 Linux 测试"不代表真实的 Linux 可移植性。

## 4. Godot 要求

- Godot **4.6.x** Linux 版（已验证 4.6.3.stable.official.7d41c59c4，与 Windows 侧同构建哈希）
- 安装示例：
  ```bash
  curl -sSL -o /tmp/godot.zip \
    https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/godot.zip').extractall('/usr/local/lib/godot463')"
  mv /usr/local/lib/godot463/Godot_v4.6.3-stable_linux.x86_64 /usr/local/bin/godot
  chmod +x /usr/local/bin/godot
  ```

## 5. Python 要求

- Python 3.10+（已验证 3.10.12）；runner 与工具仅使用标准库，无 pip 依赖。

## 6. 设置 GODOT_BIN

Godot 解析优先级：`--godot` 参数 > `GODOT_BIN` > `GODOT_EXE` > `godot4` > `godot`。

```bash
export GODOT_BIN=/usr/local/bin/godot          # 推荐（Linux）
# 或：export GODOT_BIN=$HOME/bin/Godot_v4.6-stable_linux.x86_64
```

找不到 Godot 时 runner 明确 FAIL 并给出修复说明，绝不静默回退到任何 Windows Godot.exe。

## 7. 运行测试（Linux）

```bash
cd /root/deepseek-work/TKS3_mod/godot_remake
./run_tests.sh                    # 全量 applicable 场景 + 主场景冒烟
./run_tests.sh --godot /path/to/godot
```

首次运行前如无 `.godot/` 导入缓存，先执行 `godot --headless --path . --import`。

## 8. 运行测试（Windows，原有方式不变）

```powershell
cd E:\deepseek-work\TKS3_mod\godot_remake
.\run_tests.ps1                   # 薄入口 -> python tools\run_tests.py
```

## 9. test_manifest 说明

- `tests/test_manifest.json` 是**唯一测试清单**（schema_version=1）：
  - `scenes[]`：`path`（res://tests/*.tscn）、`platforms`（["windows","linux"] 或 ["windows"]）、
    可选 `quit_after`（帧上限，覆盖 default_quit_after=1200）、可选 `reason`（Windows-only 原因）
  - `default_quit_after` / `smoke_quit_after`
- Windows runner、Linux runner、doc_gate、baseline 校验全部读取同一 manifest；
  `run_tests.ps1` / `run_tests.sh` 只是薄入口，不维护测试列表。

## 10. 平台专项测试规则

- 默认 `platforms: ["windows","linux"]`。
- 仅在代码**实际包含** Windows 依赖（Windows Desktop export、.exe、PowerShell、Windows-only 发布物、
  Windows API、Windows 绝对路径）时才标记 `["windows"]`，并填写 `reason`；不凭文件名猜测。
- 当前 Windows-only：`test_release_candidate_scene`（校验 Windows Desktop preset、
  Windows exe/pck 发布物哈希、PowerShell exe 冒烟脚本）。`test_release_acceptance_scene`
  经完整代码审查确认纯 GameState/user:// 流程，保持跨平台。

## 11. NOT_APPLICABLE 语义

- Linux 遇到 Windows-only 场景时输出：
  `NOT_APPLICABLE res://tests/xxx.tscn platform=windows current=linux`
- 含义：该测试不属于当前平台的测试集合；**不是 PASS、不是 FAIL、不是 SKIP**
  （门禁规定 SKIP=失败，NOT_APPLICABLE 是独立状态）。Windows 环境仍会执行这些测试。
- 全局注册基线不因平台过滤而减少；当前数量以 `docs/current_test_baseline.json` 与
  `tests/test_manifest.json` 为准，不在本文另写一套数字。

## 12. 运行资源大小写审计 / 可移植性门禁

```bash
python3 tools/check_resource_case.py        # res:// 引用 vs git 实际路径大小写
python3 tools/check_linux_portability.py    # 聚合：大小写 + 生产 Windows 绝对路径 + manifest 一致性 + shell 基础
python3 docs/doc_gate.py                    # 文档/数量/发布物门禁（读 manifest，不再解析 PowerShell）
```

## 13. 已知限制

- Linux export preset（Linux Desktop 发布包）**未包含在本阶段**，属下一阶段。
- GitHub Actions Linux CI 已落地：`.github/workflows/linux-tests.yml`
  （Ubuntu + Godot 4.6.3 + 现场生成导入缓存 + `tools/run_tests.py --only-available`）。
  CI 内不跑 doc gate 与 release gate，它们依赖 Windows 发布产物，完整门禁仍以本机 Windows 复跑为准。
- Windows 发布物目录 `artifacts/releases/v1.41/`：三份文档（交付报告 / 已知问题 / 试玩验收清单）
  已入库；`*.exe`、`*.pck`、`build_manifest.json`、`SHA256SUMS.txt` 是派生产物，不入库，
  由 `python work/v155/rebuild_release.py` 生成。Linux 侧仅 test_release_candidate 依赖它
  （在 Linux 为 NOT_APPLICABLE）。
- 原版 SWF（`.gitignore` 有意排除）只被 `test_native_timeline_registry_scene` 与
  `test_combat_feedback_sequence_scene` 在运行时读取；缺失时用
  `python tools/run_tests.py --only-available` 会把它们报为 `PREREQ_MISSING`。
- 克隆后第一条命令建议是 `python tools/preflight.py`：它会逐项报出缺失的前置与修法，
  避免以 `No loader found for resource` / `SHA256SUMS.txt 不存在` 这类难定位的错误失败。
- 行尾策略见仓库根 `.gitattributes`（文本 LF 入库、*.ps1 CRLF）；不做历史全量重规范化。
- 仓库在 Linux 侧建议 `git config core.filemode false`（若从 NTFS 复制迁移而来）。

## 14. Windows release 测试仍仅在 Windows 执行

- `test_release_candidate_scene`（Windows Desktop 发布物校验）保持 Windows-only；
- Windows 发布门禁链（work/run_release_gate.ps1、smoke_release_exe.ps1）不修改、不迁移。
