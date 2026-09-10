## Why

短语（词组 / 惯用语）是英语学习的高价值内容，但 Lupa 目前只管理"单词"——查词加入生词本、复习、导出都只面向单词。用户记录短语需要更丰富的结构（字面直译、核心释义、典故来源、使用场景、多条例句 + 标签），且这些短语还应进入复习。原型 `openspec/Lupa桌面版高保真原型.html` 的「短语集」页已定义该数据模型与交互，本 change 将其落地为 Flutter 端**完全独立**的能力。

## What Changes

- **独立短语数据模型**：新增 `phrases`（短语 + 字面直译 + 核心释义 + 典故来源 + 场景 + 标签 + 内联 SRS 状态）、`phrase_examples`（可变长例句 en/zh 子表）、`phrase_review_log`（复习历史）三张表，全部放进现有 `notebook.sqlite`（同库不同表，`meta.schema_version` 1 → 2）。
- **独立短语仓库层（纯函数）**：`addPhrase / updatePhrase / removePhrase / listPhrases / getPhrase / duePhrases / answerPhrase / phraseStats`；按 `phrase` 用 `COLLATE NOCASE` 大小写不敏感去重；业务逻辑不读 stdin / 不写 stdout。
- **独立复习队列与入口**：短语专属复习页 + `phraseDue` 队列，复用 `notebook/scheduler.dart` 固定间隔纯函数（`dueTimestamp/nextInterval`），SRS 状态内联在 `phrases` 行上。
- **独立导出**：短语单独的 apkg / csv，使用自有 model / deck / guid（`sha1("lupa::phrase::<text>")`），与单词导出（`lupa::<word>` + 生词本 model/deck）完全隔离。
- **独立 UI**：侧栏新增「短语集」入口（`Ctrl+I`）+ 短语复习入口；短语列表（chips 按 tag 筛选）、详情弹窗（字面/释义/典故/场景/标签/例句/复习 meta）、记录与编辑表单（短语*、释义*、字面、典故、场景、场景标签、例句增删、tags 逗号分隔）。
- **Flutter-only**：不写 Python 实现、不同步 `src/lupa/`。AGENTS.md 已同步改为「Flutter 为唯一事实源，Python 为待移除的 MVP 参考实现」。

**非目标（v1 明确不做）**：例句朗读 TTS、短语与词库词条关联、短语统计页面、短语媒体缓存。

## Capabilities

### New Capabilities

- `phrases`: 短语集——独立的短语数据模型（主表 + 例句子表 + 复习历史表）、独立 CRUD、独立复习队列、独立 apkg/csv 导出与短语 UI（列表 / 详情 / 记录 / 编辑 / 复习）。

### Modified Capabilities

（无——单词生词本、单词导出、单词复习、媒体缓存行为均不变，短语完全隔离，无 spec 级行为变更。）

## Impact

- **数据库**：`desktop/lib/data/schema.sql` 追加 `phrases` / `phrase_examples` / `phrase_review_log`，`meta.schema_version` 从 1 升到 2；仅标准 SQLite ≥ 3.38。
- **新增文件（Flutter）**：`desktop/lib/phrase/repo.dart`（纯函数层）、`desktop/lib/pages/phrase_page.dart`、`desktop/lib/pages/phrase_review_page.dart`、`desktop/lib/export/phrase_apkg.dart`、`desktop/lib/export/phrase_csv.dart`、相关 `widgets/`；`app_shell.dart` 加导航与 `Ctrl+I`；`app_state.dart` 加短语状态与 CRUD/导出入口。
- **复用**：`desktop/lib/notebook/scheduler.dart`（固定间隔纯函数）、`desktop/lib/export/apkg.dart` 的 ganki 用法（新建独立短语 model/deck）。
- **不动**：单词 repo / 导出 / 复习页、`src/lupa/`（Python）、词库 `dict.sqlite`（只读）。
- **验证**：新增 `desktop/tool/verify_phrase_repo.dart`（临时库、不污染真实数据）+ `flutter test` 冒烟；`flutter analyze` 零新增告警。
