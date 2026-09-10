## Context

动机见 proposal.md「Why」。当前 `desktop/lib/data/schema.sql` 只有单词生词本（Anki notes/cards/revlog）+ 3 张媒体缓存表，`meta.schema_version = 1`，`ensureNotebookDb` 对已存在的 `notebook.sqlite` 幂等跳过。本 change 在此数据库上加一套**与单词完全隔离**的短语三表（主表 + 例句子表 + 复习历史表），并复用一个已经模型无关的固定间隔调度纯函数。Python 侧不再同步（AGENTS.md 已改为 Flutter 为唯一事实源）。

## Goals / Non-Goals

**Goals:**
- 用独立三表在现有 `notebook.sqlite` 中落地短语集：`phrases` / `phrase_examples` / `phrase_review_log`，SRS 状态内联在 `phrases` 行。
- 提供纯函数的短语 CRUD、独立到期队列、独立复习答题、独立统计。
- 复用 `notebook/scheduler.dart` 的固定间隔纯函数，与单词调度行为一致。
- 独立的 Anki / CSV 导出（自有 model / deck / guid）。
- 纯 Flutter 实现，不改 Python。

**Non-Goals:**
- 例句朗读 TTS（v1 不做，不接媒体缓存）。
- 短语与词库词条关联、短语统计页面。
- 不重构单词 repo / 导出 / 复习页。

## Decisions

### 1. 独立三表，放进现有 notebook.sqlite（同库不同表）

`phrases`（主表，含 SRS 状态列）、`phrase_examples`（子表，`ordinal` 排序）、`phrase_review_log`（复习历史）。

- **理由**：数据目录切换、备份、`exports/` 路径全复用现有 notebook 逻辑；"独立"体现在业务与表，不拆库文件。用户决策 #1。
- **备选（否决）**：独立 `phrase.sqlite` 会让 `data_files.dart` 复制逻辑与 schema.sql 双份各再加一处，且媒体缓存/备份要分开处理，收益低。

### 2. 迁移策略：版本化 + `CREATE TABLE IF NOT EXISTS`

现有用户已有 `schema_version=1` 的库。采用二者结合：

- **新库**：`schema.sql` 直接建三张新表，`meta.schema_version` 写 `2`。
- **旧库**：`ensureNotebookDb` 在库存在后检查 `meta.schema_version`，若 `< 2` 则执行新表 DDL（`CREATE TABLE IF NOT EXISTS`，幂等）并把 `schema_version` 升到 `2`。

- **理由**：新表是纯增量，无列变更，`IF NOT EXISTS` 最稳，避免复杂 ALTER。
- **备选（否决）**：只在 schema.sql 加表 + 期望新库——旧库永远没有短语表，功能对存量用户不可见。

### 3. 纯函数仓库层，复刻现有 repo 模式

`desktop/lib/phrase/repo.dart`：每个函数内部开独立连接（`singleInstance: false`）、`finally` 关闭、`PRAGMA foreign_keys = ON`；业务逻辑不读 stdin / 不写 stdout。分页/排序/去重与单词 repo 一致（`COLLATE NOCASE`）。

- **理由**：与 `notebook/repo.dart` 既定风格对齐，便于测试与维护。
- **调度**：直接复用 `notebook/scheduler.dart` 的 `nextInterval` / `dueTimestamp`（纯函数，无 IO，模型无关）。

### 4. 独立复习队列与入口

`duePhrases` 只查 `phrases` 表（`state` / `due`），与单词 `dueWords` 完全分离。短语复习页独立渲染卡面（正面短语，背面字面/释义/典故/场景/例句），不接触 `NotebookEntry`。

### 5. 独立导出

- **apkg**：`desktop/lib/export/phrase_apkg.dart` 用 ganki，独立 `_modelId` / `_deckId`（"Lupa::短语集"），字段 Phrase/Literal/Meaning/Origin/Scene/Tags/Examples，guid `sha1("lupa::phrase::<text>")`（与单词 `lupa::<word>` 不冲突，重复导入更新而非新建）。
- **CSV**：`desktop/lib/export/phrase_csv.dart`，UTF-8 带 BOM，列含 phrase/lit/meaning/origin/scene/scene_tag/tags/added/examples（例句按行或定界拼接）。

### 6. 标签与去重

- tags 存 `phrases.tags` 列，**逗号分隔**（原型表单即逗号输入；短语不导进生词本 deck，无需 Anki 空格约定）。
- 去重：`phrase` 用 `COLLATE NOCASE`（与单词 repo 一致）。
- chips 筛选集合由现有短语 tag 去重衍生（口语/通用/书面由数据决定，不做固定枚举）。

### 7. 例句子表规避 flds 平铺

短语例句是可变长 `{en, zh}` 数组，Anki `flds` 是 `\x1f` 平铺字段、项目又禁 JSON1——用 `phrase_examples` 子表（`ordinal` 排序）天然规避编码冲突，导出时再拼进 Examples 字段。

## Risks / Trade-offs

- [旧库无新表] → 版本化 `CREATE TABLE IF NOT EXISTS` 迁移，幂等，函数内完成。
- [schema.sql 双份同步已解除] → 短语 schema 只进 `desktop/lib/data/schema.sql`；`src/lupa/` 不动。
- [例句文本含分隔符] → 不引入字段内编码，例句在子表，无冲突；仅导出拼装时用 `\n`/分隔，导出前转义。
- [数据目录切换/备份漏掉短语] → 短语随 `notebook.sqlite` 一起走，`data_files.dart` 复用现有复制逻辑，无需额外处理。
- [chips 标签动态衍生] → 标签集合随数据变化，UI 无固定枚举，需在列表层聚合 unique tags。

## Migration Plan

1. `desktop/lib/data/schema.sql`：追加三张新表 + `meta` `schema_version` 改 `2`（新库模板）。
2. `ensureNotebookDb`（或新增 `migrate()`）：旧库 `< 2` 时跑新表 DDL 并升级版本号；两版本兼容。
3. 新增 `verify_phrase_repo.dart`（临时库）校验建表/CRUD/调度/迁移，不污染真实数据。
4. 回滚：短语表为增量，删除风险低；若需回滚仅删表（无损于单词数据）。

## Open Questions

无需要现在定夺的阻塞项；chips 标签集合派生细节已在 Decision 6 明确。
