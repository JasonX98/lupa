## Why

Lupa 的版本号在 4 处不一致（Python `0.1.0`、Flutter `1.0.0+1`、UI 显示 `v1.0.0`、README 标 `v0.2`），版本语义混乱；同时缺少 `AGENTS.md` 作为 AI/协作者的项目说明，导致协作上手成本高。

## What Changes

- 统一版本格式为 **x.y.z**，初值定为 **0.1.0**（选 A：README 的功能状态标签也改写为 `v0.1.0`）。
- `desktop/pubspec.yaml`：`version: 1.0.0+1` → `version: 0.1.0`（去除 `+1` build 号）。
- `desktop/lib/widgets/app_shell.dart`：UI 显示 `v1.0.0` → `v0.1.0`。
- `README.md`：状态标签 `v0.2` → `v0.1.0`（功能描述保留，仅版本标签统一）。
- 新增根目录 `AGENTS.md`：项目定位 / 技术栈 / 常用命令 / 关键约束 / 验证方式。
- Python 侧（`pyproject.toml`、`src/lupa/__init__.py`、两处 `schema.sql` meta）已是 `0.1.0`，无需改动，仅确认一致。

## Capabilities

### New Capabilities
- 无。本 change 为纯配置/文档变更，无 spec 级行为变更，`.openspec.yaml` 设 `skip_specs: true`。

### Modified Capabilities
- 无。

## Impact

- **文件**：`desktop/pubspec.yaml`、`desktop/lib/widgets/app_shell.dart`、`README.md`；新增 `AGENTS.md`。
- **BREAKING**：无。纯版本字符串与文档变更，无运行时行为改变。
- **注意**：若 `pubspec.lock` 内嵌版本，改 `pubspec.yaml` 后重跑 `flutter pub get`（可选）。
