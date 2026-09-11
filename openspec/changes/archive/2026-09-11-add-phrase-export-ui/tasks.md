## 1. 导出层：命名分离与 tag 透传

- [x] 1.1 在 `desktop/lib/state/app_state.dart` 把 `exportFileName` 的单词口径显式化（生词本专用），并新增短语导出文件名基名 `lupa-phrases-<yyyyMMdd-HHmm>`；验证：`flutter analyze` 无新增告警，生词本分组导出的文件名仍为 `lupa-<stamp>.<ext>`（界面实测或程序断言）。
- [x] 1.2 `desktop/lib/export/phrase_apkg.dart` 的 `exportPhraseApkg` 增加 `String? tag`，非空时透传给 `listPhrases(..., tag: tag)`；验证：新增断言——含两个标签的短语集按单标签导出，读回 apkg 只含该标签短语。
- [x] 1.3 `desktop/lib/export/phrase_csv.dart` 的 `exportPhraseCsv` 增加 `String? tag` 并同样透传；验证：按标签导出的 CSV 数据行数等于该标签短语数，表头与 BOM 不变。
- [x] 1.4 `AppState.exportPhraseApkgTo` / `exportPhraseCsvTo` 增加可选具名参数 `{String? tag}` 并下传；验证：省略 `tag` 时 `desktop/test/phrase_state_test.dart` 4.1 原有断言仍全部通过（行为与今天一致）。

## 2. 导出页：分段入口 + 标签筛选

- [x] 2.1 在 `desktop/lib/pages/export_page.dart` 抽出 `_ExportCard`（图标 / 标题 / 说明 / 按钮文案 / 计数 / busy / result / error / onPressed），把现有生词本两张卡改为用它渲染；验证：生词本分组的界面与文案与今天逐字一致（`desktop/test/app_shell_shortcut_test.dart` 的导出页断言仍通过，并人工比对文案无改动）。
- [x] 2.2 顶部加一行 `PhraseFilterBar` 两段「生词本（`stats['total']`）/ 短语集（`phraseStats['total']`）」，分组状态为导出页局部 state；验证：新增 UI 冒烟断言切换分组后出现短语分组的两张导出卡，且切换分组不改变任何数据。
- [x] 2.3 短语分组的标签筛选（`全部` + `state.phraseTags`，带计数与 `phraseDotColor` 圆点）与分组控件**同行**（分组靠左、标签靠右对齐卡片边框，默认选中 `全部`），状态为导出页局部 state；验证：新 UI 测试断言切换标签后卡片计数更新、按钮仍可点、标签条与分组条同高且右边界贴合卡片边框，且短语集页的筛选状态不受影响。
- [x] 2.4 短语两张卡接 `exportPhraseApkgTo` / `exportPhraseCsvTo`（`tag: 当前所选`），结果行展示 report 的真实条数与路径，并复用现有「打开所在文件夹」；验证：临时数据目录下触发导出，`exports/lupa-phrases-<stamp>.<ext>` 存在且内容只含所选标签的短语。

## 3. 空态守卫与文案口径

- [x] 3.1 把导出守卫从单词总数改为**当前导出范围内的条数**：生词本为空 / 短语集为空 / 所选标签下 0 条分别给出提示，被拦下时不在导出目录产出文件；验证：UI 测试三条用例——空短语集点导出出现提示且 `exports/` 无新文件；短语集非空但选中空范围时同样被拦。
- [x] 3.2 头部与卡片文案按分组切换口径（「N 个词随时带走」/「M 条短语随时带走」；短语 CSV 卡说明改为 9 列）；验证：文案随分组切换，且列数说明与 `phraseCsvHeader` 一致。

## 4. 测试

- [x] 4.1 新增 `desktop/test/export_page_test.dart`（沿用 `test/phrase_ui_test.dart` 的临时 `configHome`/`dataHome` + `_settleDb` 范式，不用 `pumpAndSettle`，不碰真实数据）：覆盖分组切换、标签筛选、空态提示、导出产物文件名与内容；验证：`flutter test test/export_page_test.dart` 通过。
- [x] 4.2 `desktop/test/phrase_state_test.dart` 4.1 补「带 `tag` 导出只含该标签短语」（apkg 与 CSV 各一）；验证：`flutter test test/phrase_state_test.dart` 通过。
- [x] 4.3 命名隔离回归：在同一分钟内先导生词本 apkg、再导短语集 apkg，两份文件同时存在且先导出的内容不被改动；验证：该断言在 `export_page_test.dart` 中通过（对应 `desktop-app` 规格「同一分钟内先后导出两类不互相覆盖」）。

## 5. 文档与版本

- [x] 5.1 修正 `README.md:62` 一带对短语集导出的描述（补「入口在导出页的短语集分组」），使文档与界面一致；验证：按 README 描述能在界面上找到该入口。
- [x] 5.2 `AGENTS.md:73` 的版本号事实更新为 bump 后的值；验证：`grep -n "0\.2\.3" AGENTS.md` 有命中，且与 `desktop/pubspec.yaml` 的 `version` 一致。
- [x] 5.3 `desktop/pubspec.yaml` 的 `version` 由 `0.2.2` 升到 `0.2.3`；验证：`grep "^version" desktop/pubspec.yaml` 输出 `version: 0.2.3`。

## 6. 集成验证

- [x] 6.1 依次运行 `flutter analyze`、`flutter test`、`LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_phrase_repo.dart`、`LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_export.dart`；验证：四者全绿且无新增告警，`verify_export.dart` 的单词导出断言与产物文件名保持原样。
- [x] 6.2 `flutter build windows --release` 后用 Release 版手工跑一次：短语集分组分别导出 apkg 与 csv，确认文件名带 `lupa-phrases-` 前缀、apkg 可导入 Anki 且 guid 与单词卡不冲突；验证：`desktop/build/windows/x64/runner/Release/` 下构建成功，两份产物可被对应工具打开。（构建由本次自动化完成；Release 版界面点检与 Anki 导入由用户在机器上人工跑完，无异常）
