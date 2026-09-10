## 1. 数据库 Schema 与迁移

- [x] 1.1 在 `desktop/lib/data/schema.sql` 追加 `phrases` / `phrase_examples` / `phrase_review_log` 三表与索引，并将 `meta.schema_version` 改为 `2`；验证：临时库按 schema 建表成功且 meta 读到 `2`
- [x] 1.2 在 `desktop/lib/data/notebook_db.dart` 增加版本迁移：旧库 `schema_version < 2` 时用 `CREATE TABLE IF NOT EXISTS` 补齐三张新表并升级到 `2`；验证：对 `schema_version=1` 的旧库跑迁移后三表存在、单词 notes/cards/revlog 未受影响且幂等
- [x] 1.3 新增 `desktop/tool/verify_phrase_repo.dart`（临时库、不污染真实数据），覆盖建表 / 迁移 / CRUD / 调度 / 导出；验证：`LUPA_HOME=... flutter run 该脚本` 全部断言通过

## 2. 短语仓库层（纯函数）

- [x] 2.1 `desktop/lib/phrase/repo.dart` 实现 `addPhrase`（`phrase` 与 `meaning` 必填、`COLLATE NOCASE` 去重、写入初始 SRS 状态）；验证：单测覆盖成功 / 缺释义 / 重复短语
- [x] 2.2 实现 `updatePhrase`（含例句增删）与 `removePhrase`（级联删 examples / log）；验证：单测覆盖字段更新不动复习状态、删除级联、未找到报错
- [x] 2.3 实现 `listPhrases`（按 `added_at` 倒序、可选按 tag 筛选、返回例句数与 due）与 `getPhrase`（含例句列表）；验证：单测覆盖排序与筛选
- [x] 2.4 实现 `duePhrases`（独立到期队列，只查短语表，不含单词卡）、`answerPhrase`（复用 `scheduler.dart` 推进并写 `phrase_review_log`）、`phraseStats`；验证：单测覆盖答对推进档位 / 答错回第一档 / 写历史 / 统计四值
- [x] 2.5 打开连接统一 `PRAGMA foreign_keys = ON`、`singleInstance: false`（与 `notebook/repo.dart` 一致）；验证：删除短语级联删例句与复习历史

## 3. 独立导出

- [x] 3.1 `desktop/lib/export/phrase_apkg.dart`：独立 `_modelId` / `_deckId`（"Lupa::短语集"）、字段 Phrase/Literal/Meaning/Origin/Scene/Tags/Examples、guid `sha1("lupa::phrase::<text>")`；验证：导出 apkg 成功、guid 不以 `lupa::<word>` 单词前缀生成、可被 ganki 打包
- [x] 3.2 `desktop/lib/export/phrase_csv.dart`：UTF-8 带 BOM、列含 phrase/lit/meaning/origin/scene/scene_tag/tags/added/examples，例句拼装前转义；验证：CSV 可解析、含例句字段、标题列正确

## 4. 状态层

- [x] 4.1 `app_state.dart` 增加 `phraseEntries / phraseDue / phraseStats` 与 `addPhrase / updatePhrase / removePhrase / answerPhrase / exportPhraseApkg / exportPhraseCsv`，并在 `refresh()` 内拉短语统计；验证：state 单测覆盖刷新与 CRUD 后列表更新

## 5. UI 导航与短语页

- [x] 5.1 `app_shell.dart` 侧栏新增「短语集」入口并绑定 `Ctrl+I`；验证：`flutter test` 外壳冒烟 + 快捷键回调存在
- [x] 5.2 `desktop/lib/pages/phrase_page.dart`：列表（tag chips 按标签筛选 + 计数）、详情弹窗、记录 / 编辑表单（短语*、释义*、字面、典故、场景、场景标签、例句增删、tags 逗号分隔）；验证：UI 冒烟 + 手动走通记录 / 编辑 / 删除
- [x] 5.3 `desktop/lib/widgets/` 新增例句编辑行、短语 tag chip / 详情展示组件；验证：`flutter test` 组件冒烟

## 6. 短语复习页

- [x] 6.1 `desktop/lib/pages/phrase_review_page.dart`：独立入口、拉 `phraseDue`、正面短语 -> 背面字面 / 释义 / 典故 / 场景 / 例句、1234 评分推进并反馈下次间隔；验证：`flutter test` 冒烟 + 手动评分一轮

## 7. 验证与集成

- [x] 7.1 `flutter analyze` 零新增告警；`flutter test` 全绿（含新增短语用例）
- [x] 7.2 `flutter build windows --release` 成功，并确认复制进输出的 `data/schema.sql` 含三张新表
- [x] 7.3 端到端：临时库走通 记录短语 -> 复习评分 -> 导出 apkg / csv，且单词生词本功能不受影响
