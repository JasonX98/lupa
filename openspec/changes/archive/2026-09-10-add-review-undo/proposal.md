# 复习页支持撤销最近一次评分

## Why

复习评分是**不可逆**的数据写入：按下 `1`-`4` 立即写 revlog、推进调度并跳到下一张卡，用户没有任何回头路。误触的代价是真实的——尤其在与 `Ctrl+X` 切页组合时，隐藏页持焦会让评分打到看不见的卡上（见独立变更 `fix-shortcut-focus-and-docs`），而用户真实生词本里已经出现了 7 张卡「全部只被评过一次且已推进」的状态。学习数据在用户手里，就必须允许用户改错。

## What Changes

- 复习界面（单词复习与短语复习）新增 `0`（含小键盘 `0`）撤销最近一次评分：卡片状态与复习历史回到评分前，界面回到该卡的**翻面态**，用户可直接重评。
- 撤销能力落在仓库层而不是 UI：评分写入返回一份「回执」（复习历史行的 id + 评分前的卡片快照），撤销按回执精确回滚并删除那一条历史记录，不靠「取最新一行」之类的推断。
- 撤销范围：**只撤销最近一次**，且只在本次进入复习界面之后有效；离开页面（队列重载）后失效，不可撤销更早或跨会话的操作。
- 顺带把单词侧评分写入的两条语句包进一个事务（短语侧已是事务），使「更新卡片 + 追加历史」原子化——撤销同样需要原子。
- 可发现性：复习页正面提示行与 README 快捷键表补充 `0` 撤销的说明。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `notebook`: 新增「撤销最近一次复习」需求——评分写入 SHALL 可精确回滚到评分前状态，且只对最近一次生效。
- `desktop-app`: 新增「复习撤销交互」需求——`0` 键撤销最近一次评分，撤销后回到翻面态；无评分可撤销时按键无动作。

## Impact

- 仓库层：`desktop/lib/notebook/repo.dart`（`answerCard` 返回回执 + 事务 + 新增撤销函数）、`desktop/lib/phrase/repo.dart`（`answerPhrase` 同构）。
- 编排与界面：`desktop/lib/state/app_state.dart`、`desktop/lib/pages/review_page.dart`、`desktop/lib/pages/phrase_review_page.dart`。
- 调用点改签名适配：`desktop/tool/verify_notebook_repo.dart`（5 处位置解构）、`desktop/tool/verify_phrase_repo.dart`（8 处）、`desktop/tool/verify_e2e.dart`（1 处）。
- 文档：`README.md` 快捷键表新增 `0` 一行。
- 与其他变更的关系：`fix-shortcut-focus-and-docs` 会给同一个键处理函数加 `isActive` 守卫；两者都改 `_onKey`，建议该变更先落地以避免重复改动（非硬依赖）。
- 无新增依赖；不改 schema、不改调度算法；apkg 导出不受影响（导出不含 revlog）。

## Non-Goals

- 多级撤销栈（连续按 `0` 逐级回退）。
- 跨页面、跨词、跨会话的全局撤销，以及撤销「移除生词/删除短语」等其它操作。
- 历史脏数据清理与重置（属独立变更 `reset-review-history`）。
