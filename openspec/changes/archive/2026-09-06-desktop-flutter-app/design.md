## Context

Lupa v0.1.0 核心能力已跑通，数据模型已稳定（`schema.sql` 只用标准 SQL、业务层纯函数、缓存键三段式）。调研报告确认"数据主权"是市场空白，且桌面端离用户最近。本设计记录把 Lupa 迁移为 Flutter Windows 桌面应用的技术选型（见 proposal.md - Why，不重复）。

## Goals / Non-Goals

**Goals:**
- 用 Flutter/Dart 重写业务层，产出 Windows 桌面应用。
- 数据层直接复用现有 `schema.sql`，实现跨语言复用。
- 保持现有 4 个能力的行为契约不变（查词/生词本/复习/发音/导出）。

**Non-Goals:**
- 不做云同步（保留本地优先）。
- 不引入 LLM 增强（v2 再说）。
- 不实现 Android/iOS（Windows 优先，但架构保持跨平台兼容）。
- 不替换 `ts-fsrs` 之外的复习算法。

## Decisions

### 1. 框架：Flutter/Dart（而非 Python GUI / Compose / Tauri）
- 选 Flutter 因为：符合 README 既有方向、单语言单可执行（无需本地服务进程）、跨平台可扩展到移动端。
- 放弃 Python GUI（PySide6/Flet）：能最大化复用现有代码，但长期跨平台受限，且与"重写业务层、脱离 Python 依赖"的目标冲突。
- 放弃 Compose Multiplatform（Kotlin）：需完全脱离现有 Python 资产，且用户无 Kotlin 绑定。
- 放弃 Tauri（Rust+Web）：引入 Rust + 前端两套技术栈，学习成本高。

### 2. 放弃"Flutter + 本地 FastAPI 中间层"
- 原 README 规划了 FastAPI 中间层让"业务规则 Python 写一份"。但业务层核心很小（报告里 anki_packager 核心 < 40KB，Lupa 类似），为它维护一个本地 HTTP 服务进程、双打包、进程通信，代价大于收益。改为 Dart 直接重写业务层。

### 3. apkg 导出：`ganki`（而非自研）
- `ganki` 是 `genanki`（当前 Lupa 在用的 Python 库）的直接 Dart 移植，支持自定义 model、**稳定 guid**（同词更新而非重复建卡）、media、异步 `writeToFile`。
- 已逐行读完 `genanki` 源码确认 `.apkg` 本质 = ZIP + `collection.anki2`（5 表）+ media JSON，无魔法。`ganki` 让 Lupa 的 `export/apkg.py` 可 1:1 映射为 Dart 调用。
- 备选自研：可行（结构已完全摸清），但没必要重复造轮子。

### 4. SQLite 访问：`sqflite_common_ffi`
- 桌面/全平台标准，直接执行现有 `schema.sql`（标准 SQL）。
- 备选 `drift`（类型安全 ORM）：需代码生成与 schema 改写，与"复用现有 schema.sql"目标冲突，暂不用。

### 5. 词库规模：保持 3 万词裁剪，不上 FTS5
- 当前 `build.py` 已按 `frq` 裁剪到 3 万词（覆盖 99% 阅读场景）。3 万词用普通索引 + 前缀 LIKE 即毫秒级，**无需** FTS5 或 dikt 那种 ikvpack 二进制格式（那是 76 万词/百万级才需要的优化）。

### 6. 复习算法：v1 固定间隔，v2 接 `ts-fsrs`
- v1 照搬 `scheduler` 的 `INTERVALS=(1,3,7,15,30)`，逻辑 ~50 行 Dart。
- v2 用 `ts-fsrs`（MIT）；参数不自动拟合（个人学习者攒不够 1000 条 revlog，用官方默认）。

### 7. 平台差异：conditional export（借鉴 dikt）
- 桌面/移动用 sqlite3 FFI，Web 用 SQLite WASM，用 Dart `conditional export` 三文件模式隔离，调用方零感知。

## Risks / Trade-offs

- **[ganki 成熟度/兼容性]** → 列为 tasks 首项 spike：写最小项目用 ganki 生成 .apkg 并导入 Anki 验证（含重复导出同词更新）。
- **[Windows 打包]** → Flutter 桌面构建 + 分发，需验证图标/安装包；spike 后单独处理。
- **[数据复用]** → 现有 `dict.sqlite` / `notebook.sqlite` 是否直接复用，或由 Dart 侧重新构建/初始化；schema 一致则复用。
- **[业务层重写风险]** → 固定间隔、三段式缓存键、Anki 三枚举语义都是已验证的设计，重写为 Dart 时严格对齐，避免行为漂移。

## Migration Plan

1. 先做 `ganki` apkg spike（消除最大不确定点）。
2. 搭 Flutter 项目骨架，建数据层（复用 schema.sql）。
3. 逐模块重写：`dict` → `notebook` → `media` → `export`。
4. 接 `desktop-app` GUI。
5. Python CLI 保留作为参考实现，不动。

## Open Questions

- 无。技术选型已定，剩余不确定点（ganki 可用性）已作为 spike 前置，不阻塞方案与任务拆分。
