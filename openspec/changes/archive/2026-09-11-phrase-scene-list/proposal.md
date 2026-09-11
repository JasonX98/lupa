## Why

「使用场景」目前是全表单唯一既无行数、又无结构的字段：它被挤在「场景标签」右侧约 370px 的单行输入框里，稍长就看不全；而一个短语实际上常有**多条**互相独立的场景（如 `hear me out` 有「争论/分歧时」「分享大胆想法时」「解释误会时」三条），单值文本无法分条，导出到 Anki 也只能塌成一行。

## What Changes

- 表单「使用场景」改为**可增删的多条场景行**（与「例句」同一范式）：每条可视觉换行以看全内容，`Enter` 新增下一条场景。
- 场景数据仍存 `phrases.scene` 单一 `TEXT` 列，多条以 `\n` 分隔；**一条场景 = 一行**，UI 不产生行内换行，故分隔无歧义。
- 详情弹窗与复习页把场景按条展示（标签 pill + 每行一条），不再是一整段文本。
- Anki 导出：`场景` 字段改为 `<ul><li>` 列表；顺带修既有导出缺陷——`_block()` 补 HTML 转义（`<`、`&` 等），`典故` 与 `场景` 的多行改为 `<br>` / 列表项，避免 HTML 折叠换行。
- CSV 导出不变（多行单元格已由 csv 包自动加引号）。
- 顺手修一个在实现期实测到的既有缺陷：复习卡是固定设计高度（短语 460 / 单词 340），窗口被拖矮后（短语页客户区低于约 660px）评分区会被裁掉、无法评分。改为「空间够就居中、不够就滚动」，单词与短语两页共用同一处理。
- **无 schema 变更、无数据迁移**：老库老数据（单行场景）天然等于「一条场景」。

## Non-goals

- 不引入 `phrase_scenes` 子表，不做每场景独立标签 / 排序 / 查询。
- 不做可拖拽调高的文本框（自动增高已满足「看全内容」）。
- 不改动复习调度、统计、标签筛选与单词侧**业务行为**（复习页面只改尺寸健壮性，见下）。

## Capabilities

### New Capabilities
<!-- 无新增能力 -->

### Modified Capabilities

- `phrases`: 「记录短语」「编辑短语」需支持多条场景（分条录入与保存）；「导出短语为 Anki 牌组包」需把场景导出为列表并保证字段 HTML 安全、保留多行。
- `desktop-app`: 新增「复习界面在窗口尺寸变化下不裁剪内容」（单词与短语复习页在矮窗口下评分区可达）。

## Impact
- `desktop/lib/pages/phrase_page.dart`：表单场景区改为行列表（`Enter` 新增下一条）、保存 `join('\n')`、读入 `split('\n')`、详情弹窗分条渲染、表单栅格重排（场景标签与标签并排，使用场景独占全宽）。
- `desktop/lib/widgets/phrase_bits.dart`：新增场景编辑行组件（参照 `ExampleEditRow`）。
- `desktop/lib/pages/phrase_review_page.dart`：场景区与详情保持一致的分条展示；改用 `CenteredScrollView` 让矮窗口可滚动。
- `desktop/lib/widgets/centered_scroll_view.dart`：新增「空间够居中、不够则滚」的共用舞台（两页复习页共用）。
- `desktop/lib/pages/review_page.dart`：同上（单词复习页尺寸健壮性）。
- `desktop/lib/export/phrase_apkg.dart`：`场景` → `<ul class="scene-list"><li>`、新增 CSS、`_block()` 转义与换行处理。
- `desktop/test/phrase_ui_test.dart`、`desktop/test/review_layout_test.dart`、`desktop/tool/verify_phrase_repo.dart`：新增多条场景 round-trip、apkg 列表 / 转义断言与复习页矮窗口回归测试。
- 零改动：`desktop/lib/data/schema.sql`、`desktop/lib/data/notebook_db.dart`、`desktop/lib/export/phrase_csv.dart`（`lib/phrase/repo.dart` 只在 insert/update 写入处包一层归一化，见 design D2）。
- 待实测风险：中文输入法组字时 `Enter`（确认候选词）被误吞的可能，退路为「保存时把行内换行折叠为空格」。

## 顺延（不在本 change 范围）

- **导出页缺短语集入口**：短语导出**能力**已由 v0.2.1（归档 change `2026-09-10-phrases`）交付 —— `lib/export/phrase_apkg.dart` / `phrase_csv.dart` + `AppState.exportPhraseApkgTo` / `exportPhraseCsvTo`，有 `test/phrase_state_test.dart` 4.1 与 `tool/verify_phrase_repo.dart` 3.1/3.2 覆盖；但 `export_page.dart` 只提供生词本导出（全文件 0 处引用短语），短语集页也无导出按钮，用户无从触发。因此 `openspec/specs/phrases/spec.md` 的「WHEN 用户选择导出短语 Anki 牌组包」场景**当前不可满足**，缺口落在 `phrases` 与 `desktop-app`（「导出触发」只写生词本）两条规范的缝里。
- 后续独立 change（建议名 `add-phrase-export-ui`）需一并处理四个既有约束：`_doExport` 按 `stats['total']`（单词数）早退会误拦短语导出；文件名 `lupa-<stamp>.<ext>` 两处共用，同一分钟内先后导出会互相覆盖；导出页文案与 CSV 列数均为单词口径；计数需改用 `phraseStats['total']`。除 UI 外还需补 `desktop-app`「导出触发」delta。
- **README 描述漂移**（归后续 change 一并修正）：`README.md:62,63` 把「独立 apkg / csv 导出」列为短语集的既有功能，实际界面无入口。
- 本 change 原任务 5.2 的「从界面导出并导入 Anki」部分随之顺延；已完成的是数据层验证（读回 apkg 字段与 guid 稳定）。
