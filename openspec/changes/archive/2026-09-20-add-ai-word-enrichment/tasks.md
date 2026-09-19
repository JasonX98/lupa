## 1. schema v3 与迁移

- [x] 1.1 `desktop/lib/data/schema.sql` 新增 `word_ai_groups`（`note_id` / `kind` / `ordinal` / `label` / `gloss`）与 `word_ai_examples`（`group_id` / `ordinal` / `en` / `zh`）两表，外键分别 `note_id → notes(id) ON DELETE CASCADE` 与 `group_id → word_ai_groups(id) ON DELETE CASCADE`，并包在 `-- >>> WORD_AI_TABLES_V3 >>>` / `-- <<< WORD_AI_TABLES_V3 <<<` marker 之间；验证：`dart run tool/verify_notebook_db.dart` 的表清单断言能看到两张新表
- [x] 1.2 `schema.sql` 给 `ai_cache` 加 `model` / `prompt_tokens` / `completion_tokens` / `cache_hit_tokens` 四列（均带 `DEFAULT`），并把 `meta.schema_version` 抬到 `3`；验证：新建库后 `PRAGMA table_info(ai_cache)` 含这 4 列
- [x] 1.3 `desktop/lib/data/notebook_db.dart` 新增 `loadWordAiSchemaSql()`（照 `loadPhraseSchemaSql`）与 v3 迁移分支：**整个分支包在事务里**、新表走 marker 区块、4 条 `ALTER TABLE ADD COLUMN` 先查 `PRAGMA table_info(ai_cache)` 再执行（SQLite 无 `ADD COLUMN IF NOT EXISTS`）、最后抬 `schema_version`；验证：`dart run tool/verify_notebook_db.dart` 全绿，且对同一个库连续调用两次 `ensureNotebookDb` 不报 `duplicate column name`
- [x] 1.4 `notebook_db.dart` 新增 `aiCacheStats()`（条数 / 命中次数 / 累计 token / 不合格条目数）与 `clearAiCache()`，形状照 `mediaCacheStats` / `clearMediaCache`；验证：`tool/verify_notebook_db.dart` 断言空库四项统计均为 0
- [x] 1.5 对齐既有脚本的 schema 断言：`tool/verify_notebook_db.dart:37` 与 `tool/verify_phrase_repo.dart:43,404,422` 的 `schema_version` 由 2 改 3（旧库 fixture 的迁移目标 1 → 3）；验证：这三个脚本各自 PASS
- [x] 1.6 `schema.sql` 顶部注释降级 Anki 措辞（「抄自 Anki schema11.sql（行业事实标准）」→「参考 Anki 的表结构」），并把 `meta.lupa_version` 改为「最后写入该库的应用版本」——由 `ensureNotebookDb` 在运行时从 `version.dart` 的 `lupaVersion` 写入，同时把 `tool/verify_notebook_db.dart:37` 的恒真断言改为断言该值等于当前 `lupaVersion`；验证：新建库后 `meta.lupa_version` 与 `pubspec.yaml` 的 `version` 相等

## 2. 纯函数层（零 IO、可单测）

- [x] 2.1 `desktop/lib/ai/pos.dart` 新增 `parsePos(String translation)` 与 `enrichMode(word, translation)`：前者按 `\n` 拆行、匹配 18 种白名单前缀、跳过无前缀行、有序去重；后者返回 `full`（≥1 组）/ `degraded`（0 组且全小写）/ `none`（0 组且含大写）；验证：`desktop/test/ai_pos_test.dart` 覆盖 `record`（4 组 full）/ `serene`（`a.`+`n.` full）/ `Mr`（0 组 none）/ `online`（0 组 degraded）/ `DNA`（none）/ `n. [棒](投手投出的)快球`（`n.`）/ `[计] 因特网...`（跳过）
- [x] 2.2 `desktop/lib/ai/card.dart` 定义 `AiCard` / `AiGroup` / `AiExample` 模型与 `parseAiCard`；验证：`desktop/test/ai_card_test.dart` 断言解析畸形 JSON、缺字段、字段类型错误三种输入均不抛未捕获异常
- [x] 2.3 `card.dart` 新增 `validateAiCard`，实现 L1 结构 / L2 覆盖（返回词性组 ⊇ 本地集合，仅 full 模式）/ L3 自洽（模型自报词性 ⊆ 自己的分组，仅 define）/ L4 自证（`is_known_word == true` 且 `canonical` 一致）；验证：`desktop/test/ai_card_test.dart` 每条校验各一组正反用例，且 L2 在 degraded / define 模式下不生效
- [x] 2.4 `card.dart` 实现 L5：每条例句必须含该词本身或其任一已知词形（大小写不敏感、宽松包含）；验证：`desktop/test/ai_card_test.dart` 用「含该词 / 含其过去式 / 两者都不含」三种输入，第三种判失败
- [x] 2.5 `card.dart` 实现「每词性 1–2 条例句」的截断（多于 2 条按截断处理而非判失败）；验证：`desktop/test/ai_card_test.dart` 断言 3 条例句被截为 2 条且不产生校验失败
- [x] 2.6 `desktop/lib/dict/lemma.dart` 新增 `buildLemmaIndex(db)`（扫 `exchange` 建 变形 → 原形 映射）与 `lookupLemma(db, word)`（精确命中优先返回 null）；验证：`desktop/test/lemma_test.dart` 覆盖 `went→go` / `children→child` / `bought→buy` / `better` 精确命中返回 null / 无匹配返回 null
- [x] 2.7 `desktop/lib/ai/prompt.dart` 新增 `promptVersion` 常量与三套提示词（`enrich` 分组 / `enrich-plain` 降级 / `define` 整卡；固定生成规范放 system 段前部、词相关信息放 user 段）；验证：`desktop/test/ai_card_test.dart` 断言同一 feature 的 system 段逐字稳定（前缀缓存的前提），且三套 system 段互不相同

## 3. AI 客户端、缓存层与验证脚本

- [x] 3.1 `desktop/lib/ai/client.dart` 新增 `AiError` + `AiErrorKind`（auth / rateLimit / network / timeout / server / malformed / invalid）与 `chatJson()`：`POST <base_url>/chat/completions` 带 `response_format: {type: 'json_object'}`，按状态码与异常分类；验证：`desktop/test/ai_client_test.dart` 对七类各一组用例，且 `flutter analyze` 无新增告警
- [x] 3.2 `client.dart` 加网络层重试（1 次，固定退避 2s，`Retry-After ≤ 5s` 则遵守）与**总请求预算封顶 3 次**；验证：`desktop/test/ai_client_test.dart` 断言「429 后成功共 2 次请求」「401 只 1 次请求」「预算到顶后不再发送」
- [x] 3.3 `desktop/lib/ai/repo.dart` 新增 `ai_cache` 读写：三段式键 `<provider>/<model>:<word小写>:<feature>`（feature ∈ `enrich` / `enrich-plain` / `define`）、命中 `hit_count+1`、信封 payload（`card` / `raw` / `model` / `usage`）、不合格条目标记且下次命中不直接渲染也不自动重试；验证：`dart run tool/verify_ai.dart` 剧本 1 断言键格式、信封字段与命中计数
- [x] 3.4 `desktop/lib/ai/enrich.dart` 新增编排：缓存命中 → 请求 → 校验 → 修复重试（回灌缺失项）→ 落缓存；验证：`dart run tool/verify_ai.dart` 剧本 4 / 5 / 6 三段通过
- [x] 3.5 `desktop/tool/verify_ai.dart` 搭骨架：`HttpServer.bind(InternetAddress.loopbackIPv4, 0)` 取随机端口、临时目录写只含 `providers.deepseek.base_url` 的 `config.json`、`setConfigHomeOverride` 注入、剧本支持「按第 N 次请求返回不同响应」并记录收到的请求体；验证：脚本在**断网**条件下能跑完至少一条断言
- [x] 3.6 `tool/verify_ai.dart` 补满剧本：正常返回 / enrich 落库 / **enrich-plain 降级落库** / define 落库 / L2 缺词性触发重试 / 两次都缺降级 / L5 失败 / `is_known_word=false` / `canonical` 不一致 / 429 重试 / 401 不重试 / 超时降级 / 畸形 JSON 不进缓存 / **词性解析器全量回归**（对真实 `dict.sqlite` 3 万词断言白名单 18 种不越界、`full` 28492 词、`degraded` 1417 词、`none` 91 词，合计 30000）；验证：`dart run tool/verify_ai.dart` 全绿且全过程不触网
- [x] 3.7 `tool/verify_ai.dart` 加 `--live` 模式（需显式提供密钥时启用），跑一批多词性词并打印 L2 覆盖率、L5 通过率、平均请求次数、token 用量与前缀缓存命中；验证：已用真实 DeepSeek 密钥执行，四项指标均打印 —— **L2 5/5、L5 81/81、平均请求次数 1.13、前缀缓存命中 2944/4363 token（67.5%）**。四个分支均覆盖：full 补齐（record/present/abandon/serene/go）、降级（online）、真未收录整卡（limerence）、拼写错误自证（recieve → 提示 canonical=receive）。实施期修正：原用例把 `serendipity` 当未收录词，但它其实在词库里（translation 有 `n.` 前缀），已换成 `limerence` 并补上拼写错误用例
- [x] 3.8 `tool/verify_dict_query.dart` 补词形还原断言（对真实词库断言 `went→go` / `children→child` / `bought→buy` / `took→take`，且 `better` 走精确命中不报还原）；验证：该脚本全绿

## 4. 设置第五组「AI」

- [x] 4.1 `desktop/lib/data/config.dart` 的 `defaultConfig` 增 `providers.deepseek`（`base_url` / `model` / `api_key` / `timeout_sec`）与 `settings.ai`（`enabled: false` / `provider` / `autoEnrich: true`）；验证：删掉本地 `config.json` 后启动，新生成的默认配置含这两个块且深合并不丢既有键
- [x] 4.2 `desktop/lib/state/app_state.dart` 加 AI 配置项读写与密钥解析（`LUPA_AI_KEY` > `config.json`）；验证：`desktop/test/settings_state_test.dart` 断言环境变量优先、回落配置文件、两处都空时视为未配置
- [x] 4.3 `desktop/lib/pages/settings_page.dart` 新增第五组「AI」（启用开关 / 服务商 / 模型 / Base URL / 密钥掩码输入 + 显示切换 / 超时 / 自动补齐开关），并写明「密钥以明文保存在 `config.json`」；验证：`desktop/test/settings_ui_test.dart` 断言存在五组标题与新控件，且「发音」组内容与改动前逐项一致
- [x] 4.4 设置页接 `aiCacheStats()` / `clearAiCache()`，展示条数 / 命中 / token / 不合格条目数，清理入口与「清理媒体缓存」并列且独立；验证：`desktop/test/settings_ui_test.dart` 断言统计行渲染、清理后统计归零、媒体缓存统计不受影响
- [x] 4.5 修版本号漂移：`desktop/lib/version.dart` 与 `desktop/pubspec.yaml` 同步为 `0.3.0`，`README.md` 的版本与 zip 名同步；新增 `desktop/test/version_test.dart` 读 `pubspec.yaml` 断言 `lupaVersion` 一致；验证：该测试通过，且故意改错一处时测试转红

## 5. 查词页

- [x] 5.1 `state/app_state.dart` 加 AI 编排：四态查询、`enrichWord` / `defineWord` / `regenerate`、并发去重（照 `preloadPhonetics` 的 loading 集合）与结果按词校验丢弃（被丢弃的结果仍写入 `ai_cache`）；验证：`desktop/test/ai_ui_test.dart` 断言快速连查两词只渲染后者且两者都进了缓存
- [x] 5.2 `pages/search_page.dart` 实现渲染优先级（已保存快照 > `ai_cache` > 请求/按钮）与自动补齐的触发点（仅在 `_submit()` 拿到词条之后），并按 `enrichMode` 分流：`none` 直接不显示 AI 区块、`degraded` 走降级提示词；验证：`desktop/test/ai_ui_test.dart` 断言联想输入期间零请求、已保存的词零请求、`Mr` 类词零请求、`online` 类词走降级
- [x] 5.3 `pages/search_page.dart` 实现未收录三段式：① 本地词形还原提示且可跳原形 → ② 生词本回退并标注「不在词库中」→ ③ AI 入口（不可用时说明原因）；验证：`desktop/test/ai_ui_test.dart` 三条分支各一组用例
- [x] 5.4 前缀联想合并生词本候选，词库候选排在前面；验证：`desktop/test/ai_ui_test.dart` 断言「仅匹配生词本的前缀仍出候选」与「同一前缀命中两者时顺序为词库在前」
- [x] 5.5 `widgets/word_bits.dart` 新增 AI 例句 / 搭配渲染组件（按词性分组、搭配带例句、降级内容用「通用例句」标题、部分缺失时标注）；验证：`desktop/test/ai_ui_test.dart` 断言多词性词分组渲染、降级内容不带词性分组、缺失项有标注
- [x] 5.6 查词页 AI 失败态：内联提示 + 重试入口；401/403 在本次会话首次出现时额外弹一次 SnackBar 引导设置页，之后仅内联；验证：`desktop/test/ai_ui_test.dart` 断言失败态内联、词库内容仍可见、鉴权失败首次弹一次且第二次不弹

## 6. 生词本与导出

- [x] 6.1 `desktop/lib/notebook/repo.dart` 抽出 `_insertNote`，`addWord` 改为调用它（对外行为与错误类型不变）；验证：`dart run tool/verify_e2e.dart` 既有 15 条断言全绿
- [x] 6.2 `notebook/repo.dart` 新增 `addAiWord(nbPath, word, AiCard, tags)`：写 `flds` 5 段 + `notes.data` 的 provenance JSON + 旁表两组；验证：`dart run tool/verify_ai.dart` 剧本 3 断言 `notes.data` 含来源、旁表落库、`flds` 仍为 5 段
- [x] 6.3 `notebook/repo.dart`：`NotebookEntry` 加 `aiGroups`，新增 `_loadAiGroups(con, ids)` 批量取（照 `_loadExamples` 的 `WHERE note_id IN (...)` + Dart 内分组），接进 `_entriesFromRows`；验证：`dart run tool/verify_ai.dart` 断言按词性分组与组内顺序
- [x] 6.4 `notebook/repo.dart`：确认 `removeWord` 删笔记时新表被级联清空（`_openNb` 已开 `PRAGMA foreign_keys`）；若外键未生效则在同一事务内显式删除；验证：`dart run tool/verify_ai.dart` 断言移出后两张新表无残留行
- [x] 6.5 `widgets/word_detail_dialog.dart` 展示 AI 例句与搭配、标注 AI 生成来源、提供「重新生成」入口（二次确认后覆盖缓存与旁表两侧）；验证：`desktop/test/ai_ui_test.dart` 断言详情展示分组例句、来源标注与确认弹窗文案
- [x] 6.6 `desktop/lib/export/apkg.dart`：model 由 6 字段增至 8 字段（新增 `Examples` / `Collocations`），导出时 join 旁表并渲成 `<ul><li>`（含 HTML 转义）；验证：`dart run tool/verify_export.dart` 断言字段名列表与 `<li>` 列表项
- [x] 6.7 `desktop/lib/export/csv.dart`：`csvHeader` 末尾追加 `examples` / `collocations`，新增 `fmtExamples` / `fmtCollocations` 纯函数（en 与 zh 之间用换行 + 缩进，不引入分隔符字符）；验证：`dart run tool/verify_export.dart` 断言前 7 列表头逐字未变、新列在末尾、含换行的单元格可被 `csv` 包正确解析回多行
- [x] 6.8 顺手改本次触碰到的注释与 UI 文案：`notebook/repo.dart`（「Anki 兼容的唯一实现」「Anki 字段分隔符」等）、`notebook/scheduler.dart`（Anki ease / due 约定）、`state/app_state.dart:117`、`pages/export_page.dart` 的「在 Anki 端更新卡片」；验证：`flutter analyze` 无新增告警，且 `grep -rn "Anki" desktop/lib` 的结果只剩导出格式说明

## 7. 文档与发布

- [x] 7.1 `README.md`：功能清单加 AI 补齐与本地词形还原、依赖说明改为「零 HTTP 依赖」、版本号与 zip 名同步为 0.3.0、Anki 措辞降级；验证：通读一遍，其中所有版本号与 `pubspec.yaml` 一致
- [x] 7.2 `AGENTS.md`：版本号改 0.3.0；「验证」小节加入 `verify_ai.dart`；`anki_import_compare.py` 条目降级为「可选的历史校验工具，不再是验收条件」；验证：`grep` 确认版本一致且措辞已降级、条目未被删除
- [x] 7.3 全量回归：依次执行 `verify_notebook_db` → `verify_dict_query` → `verify_phrase_repo` → `verify_ai` → `verify_e2e` → `verify_export` → `verify_media` → `flutter test` → `flutter analyze`；验证：全部 PASS / 全绿，且 `verify_e2e.dart` 的既有断言无一条被修改
- [x] 7.4 `flutter build windows --release`，确认输出目录含新的 `data/schema.sql`；验证：构建成功（`√ Built build\windows\x64\runner\Release\lupa.exe`），`Release/` 内含 v3 的 `data/schema.sql`（10744 字节，含 `word_ai_groups` / `word_ai_examples` / `schema_version 3` / `cache_hit_tokens`）。已实测两条启动路径：①**旧 v2 库迁移**（拿本地遗留的 `schema_version=2` 库启动 → 升到 3、11 → 13 表、`ai_cache` 补齐 4 列）；②**解压即用**（删掉库后无 `LUPA_HOME` 启动 → 自动建出 v3 库 + 生成含 `deepseek` 与 `settings.ai` 的 config.json）。发行包 `Lupa-0.3.0-windows.zip`（27 项，与既有包同结构，`lupa_data/` 只含 `dict.sqlite`）已放该目录，并解压到全新目录启动复验通过
