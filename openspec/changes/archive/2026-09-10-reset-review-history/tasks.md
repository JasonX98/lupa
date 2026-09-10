## 1. 仓库层

- [x] 1.1 `desktop/lib/notebook/repo.dart` 的 `removeWord` 在**同一事务**内先取该词的 card id，删笔记（cards 走外键级联）后显式删除这些 cid 的复习历史（`revlog` 没有外键）；验证：`verify_notebook_repo.dart` 新增断言「4.5 移除后无残留历史」PASS
- [x] 1.2 新增命中判定纯函数：`ridTimeWindowMillis`（还原 65.536 秒宽时间窗）、`resetHitDetail`（两个来源分别是否命中）、`hitsResetWindow`（并集判定）、`resetHitBasis`（依据文案）；时间依据取 `cards.mod`（仅当该卡历史条数为 1 时）与 `r_id` 窗口的**并集**，相交即命中；验证：`test/reset_range_test.dart` 6 个用例覆盖窗口宽度、mod 精确性、历史 >1 时禁用 mod、收窄窗口排除边缘、无历史新词、依据文案
- [x] 1.3 新增 `planReviewReset` / `applyReviewReset`（**实现细化**：原任务写作单个 `resetReviewState`，但设计 D2/D4 要求 dry-run 能打印计划 → 拆成「只读计划 + 单事务应用」，CLI 先打印计划再决定是否写入）；应用时单事务内把命中卡写成新词状态（`type=0`、`queue=0`、`due=0`、`ivl=0`、`factor=0`、`reps=0`、`lapses=0`、`left=0`）并删除其复习历史，不追加任何新历史；验证：`verify_notebook_repo.dart` 的 4.5 段 PASS（全量计划 2 卡 / 5 行 → 应用后新词=2、复习中=0、重新进入到期队列、窗口外不命中）
- [x] 1.4 `desktop/lib/phrase/repo.dart` 新增同构的 `PhraseResetPlan` / `planPhraseReset` / `applyPhraseReset`（短语侧时间依据用 `phrase_review_log.ts`，精确，不需要 r_id 窗口）；验证：`verify_phrase_repo.dart` 的 2.5c 段 PASS（计划命中、删除行数一致、重置后全为新短语、历史清空、重新进入到期队列）
- [x] 1.5 新增孤儿清理 `planOrphanRevlog`（cid 不在 cards 中的行）+ `applyOrphanRevlogCleanup`（单事务，不触碰卡片状态），与重置互为独立开关；验证：`verify_notebook_repo.dart` 断言「识别孤儿 1 行 / 清理 1 行 / 不影响卡片状态 / 清理后无孤儿」PASS

## 2. 维护脚本

- [x] 2.1 新增 `desktop/tool/reset_review_state.dart`：解析 `--word`（可重复）/ `--since` / `--until` / `--all` / `--phrases` / `--orphans` / `--apply` / `--help`，打印解析出的数据目录与库文件绝对路径，**默认 dry-run** 输出命中清单（词 + 依据）与将删除的行数；验证：真实数据上 `--all --orphans` dry-run 打印 7 张卡 + 7 行历史 + 2 行孤儿；时间窗版本打印每个命中的依据；不传范围时报参数错误并退出码 2
- [x] 2.2 `--apply` 前调用 `backupNotebook` 并打印备份路径，再进事务写入；验证：代码路径存在且备份函数为既有实现（`lib/data/data_files.dart`）；真实数据上的实际 apply 见 2.4（待确认）
- [x] 2.3 数据库被占用时捕获错误、提示「数据库被占用：请先关闭 Lupa 再重试」并以非零码退出，不做重试循环；验证：错误分支检查 `locked`/`busy`/`in use` 关键字并 exit(1)
- [x] 2.4 真实数据演练：dry-run 核对后执行 `--all --orphans --apply`——备份 `lupa-backup-20260910-220226.sqlite`（复核：7 张卡 1 learn + 6 review、9 行 revlog、7 张 `ivl>0`，与重置前一致，可还原）；应用后只读复核真实库：**7 张卡全部 type=0、ivl/due/reps/lapses/queue 全为 0、revlog 0 行、孤儿 0 行**（重置前为 9 行、其中 2 行孤儿）

## 3. 测试

- [x] 3.1 新增 `desktop/test/reset_range_test.dart`（纯函数边界，1 秒跑完）：窗口宽度与包住真实时刻、只有 1 条历史时用 mod、历史 >1 条时禁用 mod、窗口相交 vs 包含、收窄窗口排除边缘、无历史新词、依据文案三分支；验证：6/6 PASS
- [x] 3.2 在 `tool/verify_notebook_repo.dart` 与 `tool/verify_phrase_repo.dart` 增加重置与孤儿清理的端到端断言（含「重置不写入新历史」「移除生词后无残留历史」）；验证：两个脚本均 ALL PASS，且 7 组 `tool/verify_*.dart` 全绿
- [x] 3.3 反假测试校验：把命中判定从「窗口相交」改成「窗口严格包含」后重跑 → **2 条边界用例变红**（「历史 >1 条时禁用 mod」与「依据文案」），恢复后 6/6 绿；验证：见上

## 4. 文档与验收

- [x] 4.1 `AGENTS.md` 补「复习数据维护脚本」小节（默认 dry-run、`--apply` 才写入、自动备份、±1 分钟精度）；验证：diff 仅新增该小节
- [x] 4.2 `README.md` 补「复习数据修复」小节（脚本用法、默认 dry-run、备份与恢复方式、±1 分钟精度与「同一分钟内评分不可区分」、`--orphans`）；验证：与脚本 `--help` 输出逐条一致
- [x] 4.3 运行 `cd desktop && flutter analyze && flutter test`；验证：analyze 12 条 = 基线（0 error / 0 新增告警），测试 **77/77 全绿**
- [x] 4.4 运行 7 组 `dart run tool/verify_*.dart`；验证：`verify_dict_query`（total=30000、大小写不敏感、未收录 null、前缀联想、exchange 解析全 PASS）、`verify_notebook_db` PASS/DONE、`verify_notebook_repo` ALL PASS、`verify_media` ALL PASS、`verify_export` ALL PASS、`verify_e2e` 15 passed / 0 failed、`verify_phrase_repo` ALL PASS。注：`verify_dict_query` 首次并发执行时报 dartdev 栈（同时跑 `flutter test` 时 `.dart_tool/build` 被争用），单独重跑 PASS——环境噪声，非代码问题
- [x] 4.5 运行 `openspec validate reset-review-history --strict`；验证：valid

## 5. 实现期说明（与原任务的偏差，均已按设计意图落地）

- [x] 5.1 原任务写的单个 `resetReviewState` 拆成 `plan*` + `apply*`（理由见 1.3）：dry-run 必须是**只读**的，且 CLI 要能打印「将影响哪些词、依据是什么」——这正是设计 D3/D4 的核心取舍（宁可多重置 66 秒边缘，也把不确定性交给 dry-run 清单来抵消）
- [x] 5.2 时间窗实现细节：目标区间用 `[since, until)`（毫秒），`r_id` 窗为左闭右开，判定为 `lo < untilMs && hi > sinceMs`（相交）。单调用例最初写成「依赖时间戳低位」的不确定写法，已改为**相对窗口边界**构造，避免用例飘
- [x] 5.3 短语侧比单词侧更精确：`phrase_review_log.ts` 是真实秒级时间戳，因此短语命中判定直接用 `ts` 落窗，无需 r_id 反推
