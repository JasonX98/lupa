## Why

短语导出的**能力**早在 v0.2.1 就已落地（`lib/export/phrase_apkg.dart` / `phrase_csv.dart` + `AppState.exportPhraseApkgTo` / `exportPhraseCsvTo`，有 `test/phrase_state_test.dart` 4.1 与 `tool/verify_phrase_repo.dart` 3.1/3.2 覆盖），但 `export_page.dart` 全文件 0 处引用短语：用户**从界面够不到这份能力**，`openspec/specs/phrases/spec.md` 的「WHEN 用户选择导出短语 Anki 牌组包」场景因此不可满足。缺口卡在 `phrases` 与 `desktop-app`（「导出触发」只写生词本）两条规范的缝里，本 change 把它补上，并一并解掉上一轮交接单（归档 change `2026-09-11-phrase-scene-list` 的「顺延」段）列出的四项既有约束。

## What Changes

- **导出页改为顶部分段入口**：`生词本 | 短语集`。生词本分组原样保留（两张卡、文案、行为一字不改）；短语集分组提供 Anki `.apkg` 与 CSV 两个入口，复用同一套「结果行 + 打开所在文件夹」。
- **短语集分组带标签筛选**（默认「全部」）：导出内容随所选标签变化，与短语集页的筛选互不影响（导出页自持该状态，不提升 `PhrasePage._filter`）。
- **导出函数补 `tag` 透传**：`exportPhraseApkg` / `exportPhraseCsv` / `AppState.exportPhraseApkgTo` / `AppState.exportPhraseCsvTo` 各增一个可空 `String? tag`；`listPhrases` 底层**已支持** `tag` 过滤，无需改 repo。`tag` 为空时行为与今天完全一致。
- **文件名按目标分离**：短语导出为 `lupa-phrases-<stamp>.<ext>`，与单词的 `lupa-<stamp>.<ext>` 不再共用一条命名线，消除「同一分钟内先导单词再导短语互相覆盖」的隐患。
- **空态守卫改判「当前导出范围」**：守卫从单词数（`stats['total']`）改为所选范围内的条数，范围为空时拦下并提示（短语集整体为空 / 所选标签下无短语，两种文案）。
- **修正既有文档漂移**：`README.md:62` 把短语集的「独立 apkg / csv 导出」写成既有功能（界面无入口）；`AGENTS.md:73` 的版本号停在 `0.2.1`（`pubspec.yaml` 已是 `0.2.2`）。
- 版本号 `0.2.2 → 0.2.3`（遵循仓库「`desktop/pubspec.yaml` 的 `version` 为唯一事实源」的约定）。
- **无 schema 变更、无数据迁移**：不碰 `data/schema.sql`、`notebook_db.dart`，短语表结构不变。

## Capabilities

### New Capabilities
<!-- 无新增能力：导出页入口是既有 `desktop-app` 与 `phrases` 能力的行为补齐 -->

### Modified Capabilities

- `desktop-app`：「导出触发」从「一键导出生词本」扩为**生词本 + 短语集**两个分组（分段入口），并补「导出范围为空时被拦下并提示」的场景。
- `phrases`：「导出短语为 Anki 牌组包」与「导出短语为 CSV」把「用户在哪儿选」落定到**导出页短语集分组**；新增**按标签筛选导出**（内容只含该标签下的短语）这一此前规范完全未覆盖的行为。

## Impact

**代码**
- `desktop/lib/pages/export_page.dart`：改为顶部分段（生词本 / 短语集）+ 短语分组标签筛选；抽出可复用的导出卡片，替掉现有 `_busyApkg/_resultApkg/_errorApkg/_busyCsv/_resultCsv/_errorCsv` 六个字段的写法。
- `desktop/lib/export/phrase_apkg.dart`、`desktop/lib/export/phrase_csv.dart`：各增 `String? tag` 并透传给 `listPhrases`。
- `desktop/lib/state/app_state.dart`：`exportPhraseApkgTo` / `exportPhraseCsvTo` 增 `tag` 参数；新增短语导出文件名基名（`lupa-phrases-<stamp>`），使 `exportFileName` 的单词口径不再被短语复用。

**零改动**：`desktop/lib/phrase/repo.dart`（`listPhrases` 已支持 `tag`）、`desktop/lib/data/schema.sql`、`desktop/lib/data/notebook_db.dart`、`desktop/lib/pages/phrase_page.dart`（导出入口只在导出页，短语集页不加按钮）、单词导出链路（`export/apkg.dart` / `export/csv.dart`）。

**测试**
- `desktop/test/phrase_state_test.dart` 4.1：补「带 `tag` 导出只含该标签短语」断言。
- 导出页 UI 冒烟（沿用 `test/phrase_ui_test.dart` 的临时家目录 + `_settleDb` 范式）：分段切换出现短语分组、标签筛选切换、空范围点击被拦下。

**文档**
- `README.md`：修正短语集导出描述的漂移（补「导出页短语集分组」的入口说明）。
- `AGENTS.md`：版本号事实更新为 bump 后的值。

**验证**：`flutter test`、`flutter analyze`、`dart run tool/verify_phrase_repo.dart`、`dart run tool/verify_export.dart` 全绿且无新增告警。

## Non-goals

- **不做短语 apkg 的 Anki 端一致性校验**：`tool/anki_import_compare.py`（官方 `anki` 库）目前只覆盖单词导出，短语侧留到下一轮独立 change。
- 不做「只导出今日到期」之类的范围过滤（原型里的 v2 项，单词侧也未实现）。
- 不改动单词导出的行为、文案与文件命名。
- 不在短语集页加导出按钮（入口唯一落在导出页）。
- 不提升 `PhrasePage` 的标签筛选状态到 `AppState`（导出页自持筛选，默认「全部」）。
- 不引入"文件已存在则加序号"的命名去重：同一目标在同一分钟内重复导出仍然覆盖（与单词导出现状一致，见 design D4）。
