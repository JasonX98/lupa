## Context

动机见 `proposal.md`，行为契约见 `specs/{notebook,phrases,desktop-app}/spec.md`。设计受以下现状约束：

- `answerCard`（`desktop/lib/notebook/repo.dart:252-296`）只返回 `(nextIvl, nextDue)`，撤销所需的三样东西都不在返回值里：复习历史行的 id、评分前快照（`type`/`due`/`ivl`/`reps`/`lapses`）、该次 `ease`。
- 同一函数的两条写语句（`UPDATE cards` + `INSERT INTO revlog`）**没有事务**；短语侧的 `answerPhrase`（`desktop/lib/phrase/repo.dart:365-396`）用了 `con.transaction`——两侧不对称。
- 页面内存里其实已有评分前快照：`NotebookEntry` 含 `cardType`/`queue`/`due`/`ivl`/`reps`/`lapses`（`repo.dart:27-42`），但没有任何东西能给出复习历史行的 id。
- 键处理现状：`_onKey` 中数字键被 `_revealed` 闸门挡住（未翻面时不响应）。评分后界面进入**下一张卡的未翻面态**，所以撤销必须在该状态下可用。
- 15 个调用点用位置解构 `final (ivl, due) = await answerCard(...)`：`tool/verify_notebook_repo.dart`（5 处）、`tool/verify_phrase_repo.dart`（8 处）、`tool/verify_e2e.dart`（1 处），以及 `state/app_state.dart` 与两个复习页。
- 相关变更 `fix-shortcut-focus-and-docs` 会给同一个 `_onKey` 加 `isActive` 守卫。

## Goals / Non-Goals

**Goals:**

- 把回滚逻辑留在仓库层，UI 只负责"记住最近一次回执并调用撤销"。
- 一次评分 = 一个原子写；撤销 = 一个原子写，两者都不会留下半成品状态。
- 语义边界清晰可测：只撤销最近一次、只在本轮有效、无内容可撤销时无动作。

**Non-Goals:**

- 多级撤销栈、跨页面/跨词的全局撤销、撤销「移除生词」「删除短语」等其它操作。
- 撤销栈的持久化（重启即失效，符合「只在本轮」）。
- 为撤销增加鼠标/按钮入口（本次仅键盘 + 提示文案）。
- 不改调度算法、不改 schema、不改导出产物。

## Decisions

### D1：评分写入返回「回执」，撤销按回执回滚

`answerCard` / `answerPhrase` 改为返回一份回执，撤销以回执为唯一依据恢复**绝对值**，不做任何推断。

备选与否决理由：

| 备选 | 为什么不选 |
|---|---|
| 事后从历史行推断（取 `MAX(id)`、用 `last_ivl` 反推） | `revlog.time` 恒为 0（无时间基准）、`revlog.type` 只存 0/1（把 `cardLearn` 与 `cardReview` 混为 1）、`due`/`reps` 根本不入库 → 无法精确还原 |
| 页面持快照 + 仓库删最新一行 | 把"该还原成什么"的业务判断搬进 UI，违反 AGENTS.md「业务逻辑纯函数、UI 只做参数解析与展示」 |

代价：返回类型变化需要适配 15 个调用点，其中 14 个在 `tool/` 验证脚本里——它们本就是仓库层契约的验证者，跟着契约更新是正确方向。

### D2：回执结构（`AnswerReceipt`）

字段：`revlogId`（复习历史行 id）、`ease`、评分前快照 `type`/`due`/`ivl`/`reps`/`lapses`，以及本次结果 `nextIvl`/`nextDue`。单词与短语各定义一个（短语侧用 `state` 代替 `type`），放在各自的 repo 文件里，避免为对称而引入共享抽象层。

`ease` 必须进回执：撤销后要按它回退界面的「记得/忘了」计数（`ease >= 2` 记 good，否则记 again），不能让 UI 自己重算。

### D3：撤销入口 `undoAnswer(nbPath, receipt)`，单事务 + 最近性校验

实现要点：

- 单事务内执行 `UPDATE cards SET type/due/ivl/reps/lapses = 回执前值` + `DELETE FROM revlog WHERE id = 回执.revlogId`。
- 纵深防御：事务内先校验 `MAX(revlog.id) WHERE cid = ?` 等于 `receipt.revlogId`，不等则拒绝（防止上层拿着过期回执删掉中间记录）。成本一行查询。
- 函数本身不负责「只能撤一次」——那是界面单槽的职责；仓库层只保证「给定回执能安全回滚」。

备选：只靠界面的单槽而不做校验。否决理由：`fix-shortcut-focus-and-docs` 已证明"靠上层记得"的实现方式会漏；校验成本极低。

### D4：顺带把单词侧评分写入包进事务

`answerCard` 现在的 `rawQuery` 读卡片 + `rawUpdate` + `rawInsert` 是三条独立语句。改为 `con.transaction`（读也在事务内用事务句柄）。

理由：撤销必须原子，而"写入本身原子"是它的前提——否则可能出现历史行已写、卡片未更新的中间态。这是**行为不变、健壮性提升**的附带修复，与 `answerPhrase` 对齐。

### D5：键处理位置与界面状态回退

- `0` / `numpad0` 的判定放在 `_revealed` 闸门**之前**：评分后处于下一张卡的未翻面态，撤销必须在此可用。
- 受 `isActive` 守卫约束（与 `fix-shortcut-focus-and-docs` 的规格一致）。
- 撤销成功后：`_index--`、`_revealed = true`（回到该卡翻面态）、按 `ease` 回退计数器、`_lastFeedback` 改为「已撤销「word」的评分」、清空撤销槽。
- `_submitting` 期间忽略新的 `0`，避免并发双击。
- `_reload()` 清空撤销槽 → 天然实现规格里的「撤销不跨会话」。

### D6：可发现性

复习页正面提示行在**存在可撤销评分时**追加「按 0 撤销上一次评分」；README 快捷键表新增 `0` 一行。新用户看到"空格键 显示答案"时不该同时看到撤销提示（没有东西可撤）。

## Risks / Trade-offs

- [返回类型变更触及 15 个调用点] → 全是同一模式的位置解构，按编译错误逐个改；`flutter analyze` + `flutter test` + 7 组 `tool/verify_*.dart` 三重把关。
- [撤销与「本轮」边界：评分后切走再切回会 `_reload()`，槽被清空] → 与规格「撤销不跨会话」一致，已在规格中写死。
- [撤销后未调用 `state.refresh()`，统计条可能短暂不同步] → 现有 `_rate` 同样不刷新（页面自持队列），保持一致；切页即刷新。
- [回执里的前值取自读取时刻，并发评分下可能失真] → 桌面单用户单窗口；D3 的 `MAX(id)` 校验兜住跨会话旧回执。
- [与 `fix-shortcut-focus-and-docs` 改同一文件的同一函数] → 建议该变更先落地；若顺序相反，本变更需在新增分支上补 `isActive` 守卫（tasks 中显式列为前置检查）。
- [短语侧 `answerPhrase` 已在事务内，撤销的 `DELETE` 必须同事务] → D3 明确要求单事务，测试覆盖「撤销后无残留历史行」。

## Migration Plan

无 schema 与数据迁移。发布前验收：`cd desktop && flutter analyze`、`flutter test`、7 组 `tool/verify_*.dart` 全绿（其中 `verify_notebook_repo.dart` 的「revlog 记录=5」断言需按新契约更新并仍成立）。回滚 = revert 提交，无持久化副作用（撤销是用户主动操作，回滚代码不会改变已发生的状态）。

## Open Questions

- 是否给撤销加鼠标/按钮入口（非键盘用户的可发现性）？可延后，不影响规格与实现。
- 单词与短语交错复习时是否需要统一的撤销槽（当前两页面各自独立）？可延后；按页面隔离与「独立队列」的既有设计一致。
