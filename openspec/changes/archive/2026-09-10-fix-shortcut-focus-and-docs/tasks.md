## 1. 结构性修复：焦点只属于当前可见页

- [x] 1.1 在 `desktop/lib/widgets/app_shell.dart` 中处理隐藏页的焦点安全（实现 D1）：最初用 `ExcludeFocus(excluding: i != _page)` 包住 `IndexedStack` 子节点，**反假测试证明它非必需（拦不住程序化 requestFocus，拆掉后相关用例仍全绿），最终按 owner 决定移除**；验证：`flutter analyze` 无新增告警，键盘在查词/生词本/导出页均正常（见 4.3 与测试 2.6/2.6b）
- [x] 1.2 保留并对齐查词页（0）、单词复习页（2）、短语复习页（4）的「激活即 `requestFocus`」逻辑；验证：测试 2.6 断言切回查词页后 `hasAnyClients` 恢复为 true、搜索框重新持有焦点
- [x] 1.3 在 `desktop/lib/widgets/app_shell.dart` 中把快捷键定义收敛为单一数据源（`_nav`：按键 + 修饰键 + 目标页索引），侧栏提示串由 `_hintOf(activator)` 派生，`bindings` 由同一份 `_nav` 生成（实现 D3）；验证：测试 3.2 断言侧栏渲染出 `Ctrl+F/B/R/I/E`，且 `bindings` 中不再出现手写 `'Ctrl+X'` 字面量
- [x] 1.4 在 `desktop/lib/pages/review_page.dart` 与 `desktop/lib/pages/phrase_review_page.dart` 的 `_onKey` 入口增加 `if (!widget.isActive) return KeyEventResult.ignored;`（实现 D2）；验证：测试 2.5b 在守卫存在时通过、在守卫被拆掉时变红（见 5.4）

## 2. 回归测试：真实按键驱动

- [x] 2.1 新增 `desktop/test/app_shell_shortcut_test.dart`：临时 `configHome`/`dataHome` + `AppState.init()` + `pumpWidget(AppShell)`，并把「种子到期卡」抽成 `_seedDueCard` 辅助函数；验证：测试 2.1 断言 `state.due` 非空且首词为 `abandon`
- [x] 2.2 用例：依次发送 `Ctrl+F` / `Ctrl+B` / `Ctrl+R` / `Ctrl+I` / `Ctrl+E`，断言每次切换后目标页独有文案可见；验证：测试 2.2 通过（并实际抓出了「切页后焦点落空导致后续 Ctrl 全失灵」的缺陷，见 5.3）
- [x] 2.3 用例：单词复习页空格翻面后按 `3`，断言 revlog 增加 1 条且 `ivl` 按「记得」推进；验证：测试 2.3 通过（1 天 → 3 天，`reps` 2）。短语复习页未单独造用例：键处理与撤销路径同构，短语侧数据断言由 `tool/verify_phrase_repo.dart` 覆盖
- [x] 2.4 用例：未翻面时按 `1`-`4` 不评分，并追加正向对照（空格确实到达本页）；验证：测试 2.4 通过（`logs=0`、`ivl=1`、`reps=1`，且随后翻面成功）
- [x] 2.5 回归用例：`Ctrl+R` → 空格 → `Ctrl+I` → 按 `3` 与空格，断言 revlog 与卡片状态不变；验证：测试 2.5 通过
- [x] 2.5b 回归用例（新增）：不经外壳直接挂 `ReviewPage(isActive: false)` 并强行给焦点，断言空格不翻面、数字键不写库，并以 `isActive: true` 作正向对照；验证：测试 2.5b 通过，拆掉守卫后变红
- [x] 2.6 回归用例：查词页输入 → `Ctrl+B` → 断言隐藏搜索框交出输入连接且文本不变 → `Ctrl+F` 断言焦点归还；验证：测试 2.6 通过（拆掉 `ExcludeFocus` 后仍通过，原因见 5.4）
- [x] 2.6b 回归用例（新增）：在生词本页连按 8 次 Tab，断言焦点不会走进隐藏的搜索框；验证：测试 2.6b 通过（守行为，不隔离具体实现）
- [x] 2.7 反假测试校验：拆掉 `ExcludeFocus` 与 `isActive` 守卫后重跑，确认测试确实会红；验证：见 5.4 的实测记录
- [x] 2.8 测试等待策略修正（新增）：`_settle` 改为「runAsync 烧真实时间 + pump flush」、`_waitFor` 先过一帧再判定——fake-async zone 里只 pump 不推进真实时间，等待 sqflite 真实 IO 会假失败/挂死；验证：用例从挂死 9 分钟变为整套 29 秒跑完

## 3. 文档口径

- [x] 3.1 在 `README.md` 快捷键小节补充：`1`-`4` 需先翻面才生效（小键盘同样可用）、快捷键只在当前可见页生效、短语复习页与设置页当前无 `Ctrl` 绑定；验证：`git diff README.md` 仅新增该说明，既有 7 条绑定描述未改动
- [x] 3.2 核对侧栏提示文案与 README 表格、与代码 `bindings` 三者一致（D3 后应自动一致）；验证：测试 3.2 机器断言侧栏五条提示，人工比对与 README 表格逐条相同

## 4. 验证与收尾

- [x] 4.1 运行 `cd desktop && flutter analyze`；验证：14 条全部为既有问题（与改动前的 12 条基线相比，新增的 2 条已修掉，最终与基线一致）
- [x] 4.2 运行 `cd desktop && flutter test`；验证：62 → 71 项全绿（新增 `app_shell_shortcut_test.dart` 9 项）
- [x] 4.3 手动冒烟（`flutter run -d windows`）：验证方式以测试 2.2/2.3/2.4/2.5/2.6 的真实按键断言替代（本环境无法人工按键），结论：五组切页可用、复习页空格/数字键可用、离开复习页后按 `3` 无副作用、离开查词页后输入不落进隐藏框
- [x] 4.4 运行 `openspec validate fix-shortcut-focus-and-docs --strict`；验证：输出 valid

## 5. 实现期发现（原任务清单未列，已随本变更完成）

- [x] 5.1 复习页并发 `_reload` 防抖：启动时的重载还没返回、切页又发起一次，晚到的旧请求会把 `_revealed` 清回 false——「切到复习页后立刻按空格翻面」因此失效（测试 2.3/2.5 最初即因此变红）；修法：`_reloadSeq` 序号，只有最后一次发起的重载才落盘（两个复习页同构）；验证：测试 2.3/2.5 由红转绿
- [x] 5.2 移除隐藏复习页的 `Focus(autofocus: true)`：实测确认 `ExcludeFocus` **拦不住程序化 requestFocus**（`focus_manager.dart:1169` 的 `_doRequestFocus` 只检查 `canRequestFocus`），隐藏在 `IndexedStack` 里的复习页开机会抢走主焦点；改为只在本页 `isActive` 时显式请求焦点；验证：临时探针（`primary` 从复习页节点变为搜索框/外壳）+ 测试 2.6
- [x] 5.3 外壳切页时显式收回焦点：`autofocus` 是一次性的（`focus_scope.dart:623`），隐藏页被排除后焦点会掉到路由的 `ModalScope`，不收回则切页后 `Ctrl+X` 全部失灵（测试 2.2 最初即因此变红）；修法：`_go` 内同步 `_shellFocus.requestFocus()` + post-frame 兜底（`!_shellFocus.hasFocus` 时才补）——页面在自己的 post-frame 回调里随后把焦点要走，因此「有输入控件的页」仍由页面赢得焦点；验证：测试 2.2 全链通过
- [x] 5.4 反假测试校验实测记录：
  - 拆掉 `isActive` 守卫 + `ExcludeFocus` 后重跑 → **只有 2.5b 变红**，2.5/2.6/2.6b 仍绿；
  - 把 Tab 用例加严到 40 次后仍然如此（去掉 `ExcludeFocus` 也不红）；
  - 结论：**真正承担职责的是「外壳收回焦点」+「isActive 守卫」**；`ExcludeFocus` 未被测出独立必要性；
  - 最终处理：**已移除** `ExcludeFocus`，并在 `app_shell.dart` 注释里记下「实测拦不住程序化 requestFocus」以免被当防线加回；移除后全量 77 项仍全绿
- [x] 5.5 澄清一个设计期误判：`revlog` 无页面标记、`time` 恒 0，但 `r_id`（毫秒时间戳 XOR 16 位随机数）可反推 ±65.5 秒精度的时间窗——该结论不影响本变更，已记录到 `reset-review-history` 的 design
