## 1. 仓库层：回执与原子写

- [x] 1.1 在 `desktop/lib/notebook/repo.dart` 定义 `AnswerReceipt`（多一个 `prevDue`/`prevLapses` 字段与 `cardId`——撤销要知道撤哪张卡，实现所需），并把 `answerCard` 的三条语句改为在单事务内执行、返回回执；验证：`flutter analyze` 无新增告警（12 条 = 基线），`verify_notebook_repo.dart` 既有断言（`ivl=3`、`due` 更新、`revlog=5`）全部 PASS
- [x] 1.2 在 `desktop/lib/phrase/repo.dart` 对 `answerPhrase` 做同构改造：定义 `PhraseAnswerReceipt`，把查询也移进既有事务并返回回执；验证：`dart run tool/verify_phrase_repo.dart` → ALL PASS
- [x] 1.3 新增 `undoAnswerCard` / `undoAnswerPhrase`：单事务内按回执恢复绝对值并删除对应历史行，且先校验该回执对应的历史行仍是该卡最新一行；验证：`verify_notebook_repo.dart` 新增 11 条 PASS（撤销后 `ivl` 15→3、`reps` 5→4、`type` 回 Review、`revlog` 5→4、过期回执被拒、重复撤销被拒、被拒后状态不变、撤销后可重新评分），`verify_phrase_repo.dart` 新增 7 条 PASS

## 2. 适配调用点

- [x] 2.1 `desktop/lib/state/app_state.dart` 的 `answer` / `answerPhraseCard` 转发回执，并新增 `undoAnswer` / `undoAnswerPhrase`；验证：`flutter analyze` 0 error，无残留旧签名调用
- [x] 2.2 更新 `tool/verify_e2e.dart`（1 处）、`tool/verify_notebook_repo.dart`（5 处）、`tool/verify_phrase_repo.dart`（8 处）的位置解构；验证：7 组脚本中受影响的三组全绿——`verify_notebook_repo` ALL PASS、`verify_phrase_repo` ALL PASS、`verify_e2e` 15 passed / 0 failed
- [x] 2.3 额外发现第 15 个调用点 `desktop/test/phrase_state_test.dart:85`（原清单只统计了 `tool/` + `lib/`）；已适配；验证：该测试文件通过（全量 71 项全绿）

## 3. 界面

- [x] 3.1 单词复习页新增单槽撤销：`0` / `numpad0` 判定置于 `_revealed` 闸门与 `_current == null` 闸门**之前**；撤销成功后 `_index--`、回到该卡翻面态、按 `ease` 回退计数、更新反馈文案、清空槽；`_submitting` 期间忽略按键；`_reload()` 清空槽；验证：测试 4.1/4.2/4.3/4.5 通过
- [x] 3.2 短语复习页同构实现；验证：代码与单词页镜像 + `verify_phrase_repo.dart` 的撤销断言 PASS
- [x] 3.3 前置检查：两个复习页 `_onKey` 的 `isActive` 守卫已在变更 A 落地并保留；验证：守卫在位（测试 2.5b 仍绿，见变更 A）
- [x] 3.4 可发现性：仅当存在可撤销评分时，卡片正面追加「按 0 撤销上一次评分」；验证：测试 3.4 断言刚进页不显示、评分后显示、撤销后消失（拆掉撤销分支时该用例变红）

## 4. 测试

- [x] 4.1 新增 `desktop/test/review_undo_test.dart`：评分 → 撤销 → 断言卡片状态回到评分前、该卡复习历史条数为 0、界面回到翻面态；验证：测试 4.1 通过
- [x] 4.2 用例：撤销后重新评分，该卡历史只保留 1 条；验证：测试 4.2 通过（`ivl=3`、`reps=2`、`logs=1`）
- [x] 4.3 用例：连续按两次 `0`（两次之间不 settle，第二次落在 `_submitting` 窗口内）只撤一次；验证：测试 4.3 通过
- [x] 4.4 用例：评分 → 切到短语集 → 按 `0` 无副作用；切回复习页（队列重载、槽清空）后再按 `0` 仍无副作用；验证：测试 4.4 通过（重载后页面显示「没有到期的卡片」，即证明重载已落盘）
- [x] 4.5 用例：评分后界面处于下一张卡的未翻面态仍可撤销（测试 4.1 用两张卡覆盖）；最后一张评完进入完成页也可撤销（测试 4.5 单独覆盖）；验证：均通过
- [x] 4.6 反假测试校验：拆掉「闸门之前的撤销分支」+ 仓库层「最新一行」校验后重跑，确认测试确实会红；验证：见下
- [x] 4.7 回归：查词页快捷键未受撤销改动影响；验证：测试 4.6 通过

## 5. 文档与验收

- [x] 5.1 `README.md` 快捷键表新增 `0` 一行，并补撤销边界说明（只撤最近一次、离开复习页失效、会删掉那次复习记录）；验证：`git diff README.md` 仅新增该行与说明
- [x] 5.2 运行 `cd desktop && flutter analyze && flutter test`；验证：analyze 12 条 = 基线（0 error），测试 71/71 全绿
- [x] 5.3 手动冒烟（`flutter run -d windows`）：以测试 4.1–4.6 的真实按键断言替代（本环境无法人工按键）；结论：评分后按 `0` 回到该卡翻面态可直接重评、连按两次只撤一次、切页/重载后失效、完成页也能撤
- [x] 5.4 运行 `openspec validate add-review-undo --strict`；验证：valid

## 6. 反假测试校验实测记录

- [x] 6.1 拆掉 UI 撤销分支（含「闸门之前」的排序）→ `review_undo_test.dart` **5 红 2 绿**（红：3.4、4.1、4.2、4.3、4.5；绿：4.4「离开复习页后按 0 不生效」与 4.6 查词页回归）。绿的那两条是**负向用例**（断言「无副作用」），天然拦不住「功能缺失」——正向用例才是拦得住的那一层
- [x] 6.2 拆掉仓库层「最新一行」校验 → `verify_notebook_repo.dart` **4 条断言 FAIL**（含「4.4 过期回执被拒」并连带「被拒后状态不变」「撤销后可重新评分」「重新评分后 revlog=5」全红），证明该校验是必需的、且被断言覆盖
- [x] 6.3 恢复两处破坏后复跑：`flutter analyze` 回到基线、71 项全绿、`verify_notebook_repo` ALL PASS

## 7. 遗留缺口（已知，未覆盖）

- [x] 7.1 短语复习页的撤销**没有 UI 层用例**：其实现是单词页的镜像，仓库层由 `verify_phrase_repo.dart` 覆盖（撤销/拒绝/计数全部 PASS），但「按 `0` 后短语卡回到翻面态」这一交互没有被 widget 测试断言。若要补齐需在测试里先经短语集页进入短语复习（当前无 `Ctrl` 快捷键，需 tap 入口）
- [x] 7.2 `_submitting` 窗口的精确时序（真正的并发按键）无法在 fake-async 里确定性复现；测试 4.3 用「两次按键不 settle」逼近该窗口
