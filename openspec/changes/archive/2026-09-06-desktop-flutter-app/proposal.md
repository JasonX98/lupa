## Why

Lupa v0.1.0 的 CLI 已跑通全部核心能力（查词/生词本/复习/发音/导出），但命令行形态对普通用户门槛高。调研报告（19 仓库 + 4 深度案例）确认了一个市场空白：**没有任何开源词典把"数据主权"（本地生词本 + 完整导出）当一等公民**。业务层与数据模型已经稳定（schema 只用标准 SQL、纯函数、三段式缓存键），正是把它迁移到桌面 GUI 的最佳时机。

## What Changes

把 Lupa 从 Python CLI 迁移为 **Flutter Windows 桌面应用**，业务层重写为 Dart：

- 新增 Flutter 桌面 GUI，提供查词 / 生词本 / 复习 / 发音 / 导出交互界面。
- 业务层从 Python 重写为 Dart：`dict` / `notebook` / `media` / `export` 四个模块。
- **放弃**原 README 规划的"Flutter + 本地 FastAPI 中间层"——业务层核心很小，为它维护本地 HTTP 服务进程不划算。
- 技术选型：`ganki`（生成 .apkg）、`sqflite_common_ffi`（SQLite 访问）、`ts-fsrs`（v2 复习算法）、`http`（媒体联网）。
- 数据层直接复用现有 `schema.sql`（标准 SQL，跨语言友好）；`scheduler` 固定间隔与三段式缓存键设计照搬。
- **BREAKING**：无。现有 CLI 保留作为参考实现；本 change 只新增桌面应用并迁移核心逻辑。

## Capabilities

### New Capabilities
- `desktop-app`: Flutter Windows 桌面应用外壳——查词 / 生词本 / 复习 / 发音 / 导出的图形界面与交互。

### Modified Capabilities
- 无。`dictionary` / `notebook` / `media` / `export` 的行为契约保持不变（仍生成可被 Anki 导入的 .apkg、仍按固定间隔调度等），仅实现从 Python 迁移到 Dart，属设计层变更，不在 spec 层。

## Impact

- **新增**：Flutter 项目结构（`lib/` 下 `dict`/`notebook`/`media`/`export`/`ui`）+ Windows 打包配置。
- **Dart 依赖**：`ganki`、`sqflite_common_ffi`、`ts-fsrs`、`http`、`archive`。
- **复用**：`src/lupa/notebook/schema.sql`（标准 SQL 直接搬）、三段式缓存键、固定间隔调度、Anki schema11 三枚举语义。
- **放弃**：FastAPI 中间层规划；`genanki`（Python）在桌面版由 `ganki` 取代。
- **风险前置**：`ganki` 能否稳定生成 Anki 可导入的 .apkg 是本 change 唯一技术不确定点，已列为 tasks 首项 spike。
