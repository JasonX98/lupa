## 1. 归一化纯函数与数据契约

- [x] 1.1 在 `desktop/lib/phrase/` 下新增场景文本纯函数（拆条 / 丢弃空白条 / trim / 合并为 `\n` 分隔），无 UI 与 IO 依赖；验证：为其补单元测试覆盖空字符串、仅空白、首尾空行、连续空行、正常三条
- [x] 1.3 在 `desktop/lib/phrase/repo.dart` 的 insert / update 写入处包一层 `_normalizeScene`（归一化不只依赖 UI 调用方）；验证：`tool/verify_phrase_repo.dart` 1.3 直接向 repo 传带空行/空白的原始文本，落库为 `甲\n乙`
- [x] 1.2 在 `desktop/tool/verify_phrase_repo.dart` 的 2.2 段补断言：以三条场景 `addPhrase` → `getPhrase` 后 `split('\n')` 仍为三条且顺序不变，`updatePhrase` 改成两条后不残留旧条；验证：`dart run tool/verify_phrase_repo.dart` 该组断言通过（`repo.dart` / `schema.sql` 应无需改动）

## 2. 表单录入

- [x] 2.1 在 `desktop/lib/widgets/phrase_bits.dart` 新增 `SceneEditRow`（照 `ExampleEditRow` 范式：行内 `maxLines: null` 只做视觉换行 + 删除按钮 + hint）；验证：`flutter analyze` 无新增告警，表单内可增删行
- [x] 2.2 把 `desktop/lib/pages/phrase_page.dart` 的场景输入改为 N 行 + 「+ 加一条场景」，回车新增下一条，且按 design D3 在 `composing.isValid` 时放行给输入法；验证：英文下回车新增场景行，用中文输入法组字后回车不误触发新增
- [x] 2.3 表单栅格重排：`场景标签`（160px）与 `标签` 同行，`使用场景` 独占全宽行；验证：在 560px 弹窗宽度下一条长场景（含英文引文）能完整换行显示
- [x] 2.4 接线保存与回填：`_submit` 以 `join('\n')` 写入 `PhraseInput.scene`，`initState` 以 `split('\n')` 预填场景行；验证：保存三条场景后重新打开编辑，仍是三条且顺序一致，空白行不被保存

## 3. 展示分条

- [x] 3.1 详情弹窗（`phrase_page.dart:537` 一带）把场景从单段文本改为按条渲染（标签 pill + 每行一条）；验证：在 `desktop/test/phrase_ui_test.dart` 补断言，三条场景文本均可分别被找到
- [x] 3.2 复习页（`phrase_review_page.dart:340`）改为一致的分条渲染；验证：复习一张含三条场景的卡片，条目与详情弹窗呈现一致

## 4. 导出

- [x] 4.1 `desktop/lib/export/phrase_apkg.dart`：`_block()` 增加 HTML 转义，多行纯文本按 `<br>` 连接，场景改为 `<ul class="scene-list"><li>…</li></ul>` 并补对应 CSS；验证：`tool/verify_phrase_repo.dart` 3.1 段断言 apkg 字段含 `<li>`，且含 `<`、`&` 的内容被导出为 `&lt;`、`&amp;`
- [x] 4.2 补 CSV 多条场景断言（`phrase_csv.dart` 预期零改动）；验证：3.2 段断言场景列按行保留三条、表头与 BOM 不变

## 5. 集成验证
- [x] 5.1 依次运行 `dart run tool/verify_phrase_repo.dart`、`flutter test`、`flutter analyze`；验证：三者全绿且无新增告警
- [x] 5.2 数据层端到端（可自动化部分）：导出含三条场景（其中一条含 `<` 与英文引文）的短语 apkg 并读回字段，验证列表项 / 转义 / 换行保留与稳定 guid；验证：本文件 4.1 段断言 PASS。原任务的「从界面导出短语 → 导入 Anki」路径当前**对任何人都不可执行**（导出页只有生词本入口），已顺延到独立 change，见 proposal「顺延」
- [x] 5.3 更新 `desktop/pubspec.yaml` 的 `version`（0.2.1 → 0.2.2，遵循仓库"版本号以 pubspec 为唯一事实源"的约定）；验证：`grep version desktop/pubspec.yaml` 为 0.2.2，且 `flutter build windows --release` 成功产出 `Release/` 目录

## 6. 复习页尺寸健壮性（实现期实测到的既有缺陷，已并入本 change）

- [x] 6.1 新增 `desktop/lib/widgets/centered_scroll_view.dart`（空间够居中、不够则滚），并让 `phrase_review_page.dart` 与 `review_page.dart` 的 `_buildCard` 改用；验证：`flutter analyze` 无新增告警
- [x] 6.2 补回归测试 `desktop/test/review_layout_test.dart`：短语页在 800x600、单词页在 800x460（旧代码分别溢出 8px / 28px）下无 overflow 且评分可达并推进队列；窗口 1000x1000 时卡片与评分区居中且无需滚动；验证：拿掉修法后两条用例转红、恢复后全绿
