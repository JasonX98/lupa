## Context

动机见 `proposal.md`，行为契约见 `specs/desktop-app/spec.md`。设计受以下现状约束：

- `AppShell` 用 `IndexedStack` 承载 7 个页面（`desktop/lib/widgets/app_shell.dart:69`）。本机 Flutter 3.44.9 的 `IndexedStack` 把每个子节点包成 `Visibility(maintainState: true, maintainInteractivity: true, maintainSize: true, maintainAnimation: true, ...)`（`packages/flutter/lib/src/widgets/basic.dart:4885-4892`），因此隐藏页依然挂在元素树上、仍可交互、焦点节点依然存活。
- 页面切换靠 `setState` 改 `_page` 索引，页面状态被有意常驻（搜索词、复习队列进度、滚动位置）。
- 只有查词页（0）、单词复习页（2）、短语复习页（4）在激活时 `requestFocus`；生词本（1）、短语集（3）、导出（5）、设置（6）不声明也不归还焦点。
- 两个复习页的 `Focus.onKeyEvent` 回调（`_onKey`）与写库出口 `_rate()` 都不检查 `isActive`。
- `CallbackShortcuts` 的语义是「其后代持有焦点时才拦截按键」；`AppShell` 因此包了一个 `Focus(autofocus: true)` 保证链路上总有后代持焦。
- 历史证据：commit `e8ea389` 已修过同类问题的一半（「进入」方向：切回查词页/切到复习页时归还焦点），提交信息明确记录了「空格全打进隐藏输入框」。
- 测试基础设施：`desktop/test/*_ui_test.dart` 已用临时 `configHome`/`dataHome` 驱动 `AppState` + `AppShell`，但全库从未发送过真实按键（`test/`、`tool/` 中 `sendKeyEvent` 零命中）。

## Goals / Non-Goals

**Goals:**

- 键盘作用域 = 当前可见页：隐藏页不能持有焦点，也不能因按键改变状态或写库。
- 焦点归属在页面切换后是确定的、可预测的，而不是「谁最后拿过就归谁」。
- 快捷键的按键与提示文案只有一个事实源。
- 用真实按键的自动化测试固定上述行为，使回归可被发现而不是靠人工点。

**Non-Goals:**

- 不把 `IndexedStack` 换成路由/`PageView`，页面常驻语义保持不变。
- 不为短语复习页、设置页新增快捷键绑定（已确认：暂不补，见 Open Questions 结论）。
- 不做复习撤销（`0` 键）与历史数据清理：已拆为独立变更 `add-review-undo` 与 `reset-review-history`。
- 不做焦点遍历顺序、键盘无障碍（Screen Reader）层面的改造。
- 不触碰 `scheduler` 纯函数、调度档位与导出产物。

## Decisions

### D1：切页时由外壳收回焦点，页面按 `isActive` 守卫自己

把每个 `IndexedStack` 子节点包成 `ExcludeFocus(excluding: i != _page, child: pages[i])`，并让外壳在每次切页时主动接管焦点。

理由：`IndexedStack` 下的隐藏页仍挂在元素树上（见 Context），必须让它们退出焦点链；`ExcludeFocus` 的语义正好是「该子树不可聚焦」（`focus_scope.dart:916-939`）。

**实现期修正（重要，与初始设计不同）**：真正承担职责的是下面三层，而 `ExcludeFocus` **不是**主防线：

1. **切页时外壳收回焦点**（`_go` 内同步 `_shellFocus.requestFocus()` + post-frame 兜底）——这是最关键的：`autofocus` 是一次性的（`focus_scope.dart:623`），隐藏页被排除后焦点会掉到路由的 `ModalScope`，而 `CallbackShortcuts` 只在「后代持有焦点」时生效，不收回则切页后所有 `Ctrl+X` 立即失灵（测试 2.2 实测变红）。
2. **隐藏页不得 autofocus**：实测确认 `ExcludeFocus` 拦不住程序化请求——`FocusNode._doRequestFocus`（`focus_manager.dart:1169-1175`）只看 `canRequestFocus`，不看祖先的 `descendantsAreFocusable`。因此藏在 `IndexedStack` 里的复习页原本会在启动时抢走主焦点；改为只在本页 `isActive` 时显式请求焦点（测试 2.6 的启动断言覆盖）。
3. **页面自身 `isActive` 守卫**：唯一被反假测试证明为必需的机制（拆掉后测试 2.5b 立即变红）。

**最终决定（实现后拍板）：已移除 `ExcludeFocus`**。反假测试未能测出它的独立必要性：拆掉它（含把 Tab 用例加严到 40 次）后 2.5/2.6/2.6b 仍全部通过；实际删除后全量 77 项测试仍全绿。因此实现只保留上述三层，并在代码注释里记下这个实测结论（避免后人再把它当防线加回来）。

备选与取舍：

| 备选 | 为什么不选 |
|---|---|
| 每个页面各加一个根 `FocusNode` + `isActive` 收发 | 7 处样板，新增页面漏写一个就复活缺陷（本变更只给两个复习页补了守卫） |
| 换成 `Navigator` / `PageView` | 改变页面常驻语义（搜索词、复习进度会被回收），超出本次范围 |
| `Offstage` / `TickerMode` | 只解决绘制与动画，不解决焦点与按键路由（且隐藏页仍可命中指针无关） |
| 依赖外壳 `Focus(autofocus: true)` 自动兜底 | 实测不成立：autofocus 只在节点挂载时生效一次，不会在「焦点落空」后重试 |

附带修复（实现期发现，属同一缺陷类）：

- **并发 `_reload` 防抖**：启动时的重载未返回、切页又发起一次，晚到的旧请求会把 `_revealed` 清回 false，表现为「刚切到复习页就按空格翻面无效」。修法为 `_reloadSeq` 序号（两个复习页同构）。
- **移除复习页的 `Focus(autofocus: true)`**：见上第 2 点。

### D2：复习页 `_onKey` 增加 `isActive` 守卫（纵深防御）

两个复习页的键处理入口 `_onKey` 首行加 `if (!widget.isActive) return KeyEventResult.ignored;`。

理由：D1 是来自父级的结构约束；`_onKey` 的守卫让「非激活页不因按键改状态/写库」由页面自身保证，覆盖空格带来的状态变更与 `1-4` 带来的写库两条路径（`_rate()` 是唯一写库出口，守卫放在入口即可覆盖它）。

备选：只在 `_rate()` 内守卫（漏掉「空格翻隐藏卡」这类状态变更）；完全不加守卫（把数据安全单点押在 `AppShell` 的实现正确性上）。

### D3：快捷键定义单点化

现状 `app_shell.dart` 里 `'Ctrl+F'` 等提示串（`:28-34`）与 `SingleActivator` 绑定（`:56-60`）是两份手写数据。改为以一份列表为单点（每项含 `LogicalKeyboardKey`、修饰键、提示文案、目标页索引），侧栏提示与 `bindings` 都从它派生。

备选：加一条测试断言两份数据一致——治标，仍然要人维护两份。

### D4：测试用真实按键，断言可观察结果

新增 `desktop/test/app_shell_shortcut_test.dart`，复用现有「临时 `configHome`/`dataHome` + `AppState.init()`」模式（见 `test/phrase_ui_test.dart:1-30`），用 `tester.sendKeyEvent` / `sendKeyDownEvent` 发真实按键。

断言对象是外部可观察结果：当前可见页（用目标页独有文案定位）、搜索框 controller 文本、生词本仓库中该卡的 `ivl` 与 revlog 条数。不断言 widget 内部字段。

必须包含的回归用例（对应用户实际踩到的路径）：

1. 五组 `Ctrl+F/B/R/I/E` 各自切到目标页。
2. 复习页：空格翻面后按 `3`，revlog 增加 1 条且 `ivl` 按「记得」推进。
3. 复习页未翻面时按 `1-4`，revlog 不变、`ivl` 不变。
4. **回归**：`Ctrl+R` 进入复习 → 空格翻面 → `Ctrl+I` 切走 → 按 `3`，revlog 不变、`ivl` 不变。
5. **回归**：查词页输入 → `Ctrl+B` 切走 → 输入字符，查词页搜索框文本不变。

时序注意：`autofocus` 与 `requestFocus` 在帧末生效，按键前需 `await tester.pump()`；沿用现有约定用 `pump()` 单帧而非 `pumpAndSettle()`（页面含异步 DB 加载与转圈）。用例 2/3/4 需要先经仓库层种一张到期卡。

## Risks / Trade-offs

- [隐藏页被 `ExcludeFocus` 强制失焦后，切回该页时光标不回来] → 保留并对齐 0/2/4 页已有的「激活即 `requestFocus`」；设置页的 URL 输入框不自动聚焦，属可接受（用户点击即聚焦）。
- [点空白处/切页后无后代持焦 → `CallbackShortcuts` 整体失灵] → 已实测：`autofocus` 不会兜底（只在挂载时生效一次），改为在 `_go` 里显式收回焦点；测试 2.2 覆盖。
- [`ExcludeFocus` 让隐藏页不可交互，可能影响依赖 `maintainInteractivity` 的隐藏行为] → 当前无任何代码依赖隐藏页交互；测试用例 4/5 正是这条约束的正向表达。
- [键盘/焦点类 widget 测试对时序敏感，容易假失败] → 断言前统一 `pump()`；失败先排查时序，不靠放宽断言绕过。**实测踩坑**：flutter_test 跑在 fake-async zone，只 `pump()` 不推进真实时间，等待 sqflite 真实 IO 的 `await` 会永不返回（曾导致用例挂死 9 分钟）——必须 `tester.runAsync` 烧真实时间再 pump flush。
- [用例 2/3/4 若库里没有到期卡会空转通过] → 测试内显式 seed 一张到期卡，并在断言前验证队列非空。
- [记忆化：`ExcludeFocus` 是本次唯一的跨页面结构改动，回滚面小] → 单独提交，便于 revert。

## Migration Plan

无数据、schema 或配置迁移。纯前端行为修正：改 `app_shell.dart` + 两个复习页 + README 一句说明 + 新增测试。回滚策略为 revert 对应提交；无持久化副作用需要清理（被误写的 revlog 记录不会因回滚而消失，但本变更不做数据修复，见下条）。

## Open Questions

（无。三个原问题已结论如下，且都不改变本变更的规格与任务分解。）

### 已结论：不为短语复习页/设置页补 `Ctrl` 绑定

维持现状。已写入 Non-Goals；侧栏与 README 均不出现这两处的快捷键提示，行为与文档一致。

### 已结论：复习撤销（`0`）拆为独立变更 `add-review-undo`

它是新增能力而非本次修正，且需要改仓库层写入路径的返回契约（`answerCard` 现在只返回 `(nextIvl, nextDue)`，无 revlog 行 id、无评分前快照），影响 `repo` / `app_state` / 两个复习页 / 6 个 `tool/` 调用点。用户已拍板：**只撤销最近一次**，作用域限本页本轮。

### 已结论：历史脏数据清理拆为独立变更 `reset-review-history`

采用「按范围重置（含时间窗口）+ 数据卫生」两条，已确认不做 UI 能力。关键约束：`revlog` 不记录当时可见页，`time` 列恒为 0，时间只能由 `r_id`（毫秒时间戳 XOR 16 位随机数）反推出 ±65.5 秒精度的窗口；真正需要重置的是 `cards` 而非 `revlog` 行。详细信息见该变更的 design.md。
