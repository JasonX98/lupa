# 修正快捷键的焦点归属与文档口径

## Why

README 把快捷键写成了用户契约（`Ctrl+F/B/R/I/E` 切页、空格翻面、`1-4` 评分），代码里也确实实现了这 7 个绑定；但没有任何一处守卫「键盘只作用于当前可见页」。`AppShell` 用 `IndexedStack` 常驻 7 个页面，未激活页面在树上仍然存活、仍然可交互、焦点节点仍然有效，而两个复习页的 `_onKey` 与 `_rate()` 都不检查 `isActive`。结果是：从单词复习页用 `Ctrl+I` 切走后按 `1-4`，会给**看不见的卡**静默写 revlog 并推进调度；从查词页用 `Ctrl+B` 切走后打字，字符会进入隐藏的搜索框并触发联想查询。这是一类会污染复习数据的静默缺陷，且全套快捷键目前零测试、零规格兜底（`openspec/specs/**` 中「键盘/焦点」零命中）。

## What Changes

- `AppShell` 让未激活页退出焦点链：隐藏页既不能持有焦点，也不能接收键事件，从结构上消除「隐藏页吃键」这一整类问题。
- 两个复习页的键处理增加 `isActive` 守卫，作为纵深防御：非激活状态下空格与数字键一律不处理、不写库。
- 新增基于 `sendKeyEvent` 的 UI 测试（现有 `test/` 与 `tool/` 从未发送过真实按键），覆盖五组切页快捷键，以及「切页后误按数字键不得评分/不得写 revlog」这条回归断言。
- 消除侧栏提示串（`'Ctrl+F'` 等）与 `SingleActivator` 绑定之间的双事实源，改为由同一份数据派生，避免二者漂移。
- 补 README 一句口径说明：复习页数字键需先翻面才生效（现有表格未写此前置条件，其余描述与代码一致，不改）。

非目标：不改复习算法与调度档位；不引入全局路由或重构页面切换机制；不为短语复习页/设置页新增快捷键；不改导出、媒体缓存、设置写回等无关模块。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `desktop-app`: 新增「键盘快捷键与焦点归属」需求，规定快捷键的生效范围限于当前可见页，并要求复习评分只能由当前页的用户操作触发。

## Impact

- 代码：`desktop/lib/widgets/app_shell.dart`（焦点排除 + 快捷键数据单点化）、`desktop/lib/pages/review_page.dart`、`desktop/lib/pages/phrase_review_page.dart`（`isActive` 守卫）。
- 测试：`desktop/test/` 新增外壳快捷键测试；沿用现有临时 `configHome`/`dataHome` 驱动 `AppState` 的既有模式，不碰真实数据。
- 文档：`README.md` 快捷键小节补一句前置条件；`openspec/specs/desktop-app/spec.md` 增加一条需求。
- 行为兼容性：不改变任何既有绑定的按键与目标页；改变的是「非当前页不再响应键盘」，即修复方向。
- 无新增依赖，不影响词库/生词本 schema 与导出产物。
