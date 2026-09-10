## Context

动机见 `proposal.md`，行为契约见 `specs/{notebook,phrases}/spec.md`。设计受以下事实约束（均在本次探查中实测确认）：

- `revlog`（`desktop/lib/data/schema.sql:66-80`）**无外键、无级联**；`removeWord` 只删笔记，卡片由 `cards` 的 FK 级联删除，复习历史成为孤儿。实测存量 2 行孤儿（`cid=2`、`cid=4`）。
- 短语侧是对照组：`phrase_review_log` 带 `FOREIGN KEY (phrase_id) REFERENCES phrases(id) ON DELETE CASCADE`（`schema.sql:166-175`），且连接启用了 `foreign_keys`（`repo.dart:324` 注释「启用外键级联」）——所以短语移除已自动清历史，单词侧缺的正是这一步。
- 时间线索：`revlog.time` 恒为 0（`repo.dart:287` 硬编码）；`cards.mod` = 该卡**最后一次**评分的精确秒级时间；`revlog.r_id = 毫秒时间戳 ^ random(0x10000)`（`repo.dart:82-83`），抹掉低 16 位得到 65.536 秒宽的时间窗。实测 9 行历史全部落在对应 `cards.mod` 的窗口内。
- UI 完全不读 `revlog`（唯一读者是 `tool/verify_notebook_repo.dart`）；统计条与复习队列只读 `cards`。因此**重置必须落在 `cards` 上**，只删历史行用户感知不到。
- 可复用件：`backupNotebook`（README 已承诺「生词本可一键备份」）、`tool/` 脚本「走临时库验证」的既有模式、`AGENTS.md` 的验证脚本约定。

## Goals / Non-Goals

**Goals:**

- 提供一条可复现、可审查、**默认不写入**的数据修复路径，让用户能把被误推进的卡打回新词。
- 单词与短语两侧对称。
- 把「时间窗口」的固有不确定性显式暴露给用户（dry-run 打印具体词表），而不是藏起来。

**Non-Goals:**

- UI 入口（生词本按钮 / 设置页入口）。
- 识别「哪一次评分是误按」——数据上无解，只能按范围重置。
- 重建历史（回放 revlog 恢复旧状态）。
- 修改 `revlog.time` 语义（Anki 里它是答题耗时毫秒，保持 0）。
- 给 `revlog` 加外键（需新库 + 迁移，本次用显式 DELETE 达成等价效果）。

## Decisions

### D1：重置语义 = 「打回新词 + 删光该卡历史」

不是「恢复到某次评分前」。理由：评分前的 `due` 与更早的历史不可恢复（`due` 不在历史表里，`last_ivl` 只够还原 `ivl`），而「回到新词」既可精确实现又可精确验证。

备选「恢复到最近一次评分前」：`due` 无法还原 → 不可行，放弃。

### D2：三层结构（纯函数 / 仓库函数 / 薄 CLI）

- **纯函数**：命中判定 —— 输入（卡片元数据、历史记录、范围），输出（是否命中）。可脱离数据库单测。
- **仓库函数**：`resetReviewState(nbPath, {words | since | all})`，单事务内 `UPDATE cards`（写新词值）+ `DELETE FROM revlog WHERE cid IN (...)`。
- **CLI**：`tool/reset_review_state.dart` 只做参数解析、打印报告、调用上述函数。

符合 AGENTS.md 约束 2「业务逻辑纯函数，UI/CLI 只做参数解析与展示」。

### D3：时间窗口判定取「两个时间来源的并集」，并偏向多命中

- `cards.mod` 作为精确依据，**仅当该卡历史条数为 1 时**有效（否则 `mod` 只代表最后一次评分）。
- `revlog.r_id` 的 65.536 秒窗口与目标窗口**有交集**即命中（约 ±65 秒精度）。
- 两者取并集，任一命中即重置。

取舍：宁可多重置窗口边缘 66 秒内的卡，也不漏掉脏数据。理由——重置是幂等且可再次执行的，而漏清会让用户反复执行仍"清不干净"，且无从判断原因；不确定性由 dry-run 的词表抵消。

备选「严格包含（偏向少命中）」：否决，如上。

### D4：默认 dry-run，`--apply` 才写，写入前自动备份

CLI 形态：

```
dart run tool/reset_review_state.dart
    (--word <w> | --since <ISO8601> [--until <ISO>] | --all)
    [--phrases] [--orphans] [--apply]
```

- 默认打印：解析到的数据目录与库文件绝对路径、每个命中的词及其命中依据（`mod` / `r_id` 窗口 / 两者）、将删除的历史条数。
- `--apply` 时先 `backupNotebook` 并打印备份路径，再进事务写入。
- 走 `LUPA_HOME` 优先级（与 `AppState` 同源），不读 stdin（AGENTS.md 约束 2）——破坏性操作由 `--apply` 显式表态。

备选「默认写入 + `--dry-run` 开关」：默认破坏性，否决。备选「交互式 y/n 确认」：违反不读 stdin 的约束，否决。

### D5：数据卫生分两件做，不给 revlog 加外键

- 新增：`removeWord` 在事务内显式删除该词的复习历史（新库不再产生孤儿）。
- 清理：脚本 `--orphans` 删除 `cid` 已不在 `cards` 中的历史行。
- 不加外键：改 `schema.sql`（唯一事实源）+ `schema_version` 3 + 旧库迁移路径，风险与收益不匹配，留作独立变更。

### D6：孤儿清理与重置互为独立开关

`--orphans` 与 `--word/--since/--all` 各自独立，避免"只想清孤儿却重置了卡片"。二者共用一次 dry-run 报告与同一个事务边界，便于审查。

## Risks / Trade-offs

- [±65 秒精度可能连带重置窗口边缘的卡] → dry-run 打印完整词表；`--apply` 前自动备份；可用 `--until` 收窄窗口；文档与脚本输出都写明「同一分钟内的评分不可区分」。
- [`cards.mod` 仅在历史条数 == 1 时等于该次评分时间] → 实现中显式判断条数，并在 dry-run 报告中标注每个命中的依据。
- [重置会丢掉真实学习进展] → 语义即「打回新词」（规格中有「重置不可恢复」场景）；默认 dry-run + 自动备份；README/AGENTS 记录恢复方式。
- [脚本指向错误数据目录] → 运行时打印解析出的目录与库文件绝对路径；按 `LUPA_HOME` 优先级解析（与 `AppState` 同源），dry-run 报告即为核对依据。
- [对正在运行的应用执行写入] → 建议先关闭应用；数据库被占用时捕获错误并提示「请关闭 Lupa 后重试」，不做重试循环。
- [短语侧对称性遗漏] → 单词与短语开关分离，规格各自有场景，测试各自覆盖。

## Migration Plan

无 schema 迁移。执行顺序：1) dry-run 复核词表 → 2) `--apply`（自动备份） → 3) 打开应用确认这些词回到新词队列、统计「新词」数回升。回滚：用脚本打印的备份文件覆盖 `notebook.sqlite`。

## Open Questions

- 是否把「重置」做成 UI 能力（生词本条目操作 / 设置页入口）？可延后，宜先看使用频率。
- 是否为 `revlog` 补外键并出 `schema_version` 3 迁移？可延后，属独立变更（触碰唯一事实源与旧库迁移路径）。
- 移除生词时是否询问「是否同时清除复习历史」？可延后；当前决定为「默认清除」，与短语侧既有行为对齐。
