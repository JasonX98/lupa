# 清理并重置被误写的复习历史

## Why

`fix-shortcut-focus-and-docs` 修复的「隐藏页持焦静默评分」缺陷在此前的版本里已经污染了真实数据：用户生词本中 7 张卡**全部只被评过一次、`ivl` 全是第一档、新词数为 0**，本该停留在新词状态的卡被算作「复习中、1 天后到期」，于是从「新词/今日到期」队列里消失。同时 `revlog` 没有外键、移除生词时不清理历史，已留下 2 条孤儿记录。数据归用户所有，就必须提供一条把数据改回来的路径。

## What Changes

- 仓库层新增「按范围重置复习进度」能力：命中卡片的调度状态打回新词（`type=0`、`ivl=0`、`due=0`、`reps=0`、`lapses=0`），并删除其复习历史记录；短语侧提供同构能力。
- 范围支持三种：单个词、时间窗口、全部。时间窗口依据 `cards.mod`（该卡最后一次评分的精确时间）与 `revlog.r_id` 反推的时间（毫秒时间戳与 16 位随机数异或，精度约 ±65 秒）判定。
- 新增维护脚本 `desktop/tool/reset_review_state.dart`：默认 **dry-run** 只打印将受影响的词与记录条数，显式 `--apply` 才写入；写入前复用现有 `backupNotebook` 自动备份。
- 数据卫生：移除生词时一并删除该词的复习历史（现会残留孤儿行），并清理存量孤儿记录。
- 不新增 UI、不改 schema、不改调度算法。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `notebook`: 修改「移出生词本」——移除单词时 SHALL 一并删除其复习历史记录；新增「按范围重置复习进度」需求——按词/时间窗口/全部把卡片打回新词并清除其历史记录。

## Impact

- 仓库层：`desktop/lib/notebook/repo.dart`（移除时清历史、新增重置函数）、`desktop/lib/phrase/repo.dart`（短语侧同构重置）。
- 工具：新增 `desktop/tool/reset_review_state.dart`；`AGENTS.md` 的验证脚本清单需补一行。
- 用户数据：脚本会修改 `notebook.sqlite`（先备份，默认 dry-run）；**不涉及导出产物**（apkg/csv 不含 revlog）。
- 对 UI 无影响：统计条（`notebookStats`）与复习队列只读 `cards`，重置后卡片重新出现在新词队列里。

## Non-Goals

- 不做 UI 重置入口（生词本按钮 / 设置页入口）。
- 不尝试识别「哪一次评分是误按」——数据上无解：`revlog` 不记录当时可见页，`time` 列恒为 0，且同一分钟内的多次评分互相不可区分。因此只提供「按范围重置」。
- 不重建/回放历史（评分前的 `due` 等信息不可恢复，重置语义就是「打回新词」）。
- 不修改 `revlog.time` 的语义（在 Anki 里它是答题耗时毫秒，不是时间戳，保持 0）。
