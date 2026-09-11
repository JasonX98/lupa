## Context

动机见 `proposal.md`。设计只处理下面这些现状约束：

- **能力齐、入口缺**：`lib/export/phrase_apkg.dart` / `phrase_csv.dart` 与 `AppState.exportPhraseApkgTo` / `exportPhraseCsvTo` 已存在并通过 `test/phrase_state_test.dart` 4.1、`tool/verify_phrase_repo.dart` 3.1/3.2；`export_page.dart` 全文件 0 处引用短语。
- **导出页是单词口径写死的**：`_doExport({required bool apkg})` + `_busyApkg/_resultApkg/_errorApkg/_busyCsv/_resultCsv/_errorCsv` 六个字段；早退守卫读 `stats['total']`（单词数）；文案写「N 个词」；CSV 卡说明写「7 列」（短语 CSV 是 9 列）。
- **文件名两处共线**：`exportFileName('apkg')` 出 `lupa-<stamp>.apkg`，CSV 名由 `_stampBase()` 从 apkg 名截出来，两类目标共用同一条命名线。
- **筛选的两个数据源不同**：`AppState.phraseTags` 来自 DB 全量（`SELECT tags FROM phrases`），`AppState.phraseEntries` 是 `limit: 500` 的客户端列表——短语集页的标签计数就是基于后者算的。
- **导出页没有 `isActive`**：不像 `PhrasePage` 在 `didUpdateWidget` 里刷新；但 `addPhraseEntry/updatePhraseEntry/removePhraseEntry` 都会 `await refresh()`，所以计数不会因切页而陈旧，本轮不需要给导出页加激活刷新。
- **控件有两套语言**：`SegControl`（设置页，选中=浅底主色字）与 `PhraseFilterBar`（短语页标签条，选中=实心主色底）。两者容器 padding/圆角接近，但选中态不同。
- **导出模块的现状风格**：`export/*.dart` 是不依赖 UI 的纯函数 + IO（收路径、给 report），`AppState` 只做编排。

## Goals / Non-Goals

**Goals:**

- 让短语导出在界面上真正可达，且**用户一眼能看出"这次导出的是哪一份数据"**。
- 消除跨目标文件覆盖这一**数据丢失**风险（不是美观问题）。
- 让"选了范围却导不出东西"的失败路径有明确提示，而不是产出空 deck / 仅表头 CSV。
- 保持导出模块"纯函数 + 窄接口"的现状：新增能力只加一个可空参数，不引入筛选对象/查询构造器。

**Non-Goals:**

- 不做短语 apkg 的 Anki 端一致性校验（`tool/anki_import_compare.py`），另开一轮。
- 不做范围过滤的其它维度（今日到期、时间窗、选中行）。
- 不改单词导出的行为、文案、命名。
- 不在短语集页加导出按钮；不把短语页的筛选状态提升为全局状态。
- 不重构 `export/apkg.dart` / `export/csv.dart`（单词侧只共享新抽出的命名函数）。

## Decisions

### D1 布局：顶部分段「生词本 | 短语集」，而不是四卡平铺

被考虑的三种：

```
(i) 四张卡平铺                        (ii) 顶部分段（选中）
+---------------------------+         +-------------------------------+
| [apkg 生词本]             |         | [生词本 248]  [全部 12][口语 5] |  <- 同一行
| [csv  生词本]             |         | [apkg 卡]                     |     标签靠右
| [apkg 短语集]             |         | [csv  卡]                     |
| [csv  短语集]  页面很长     |         | 圆角即卡片区 640 宽           |
+---------------------------+         +-------------------------------+

(iii) 2x2 网格
+-------------+-------------+
| apkg 词     | csv 词      |
| apkg 短语   | csv 短语    |
+-------------+-------------+
```

选 (ii)。理由：**导出的语义是“选一份数据带走”**，顶层切换让“当前这份是什么”始终只有一个答案（平铺时用户要自己在四张卡之间对照文案才敢点）；页面高度不变长；四个按钮同时可见时，误点风险与“到底导了哪个”的疑问都更高。(iii) 除了同样存在并列问题，还把两组卡片挤成两列，说明文字必然缩行。

**实现期修订（看实际界面后的反馈）**：分组控件与标签筛选同一行——分组靠左、标签靠右，标签的右边界与卡片右边界（即 640 宽列宽的右沿）对齐。理由：两行各占一行的写法多戴一顶“这行是什么”的疑问帽，而且两行事一左一右看起来像两个并列的筛选器；同一行后“左选数据源、右选范围”一眼可读。标签多到放不下时只让标签这一侧横向滚动，分组控件位置不动。

### D2 标签筛选状态归导出页自持，默认「全部」

被考虑的另一种是让导出页**跟随短语集页最后选中的标签**。放弃理由：`PhrasePage._filter` 是页面私有 state，跟随它需要把它提升到 `AppState`（或加传值链路），而这会制造一类难解释的现象——用户在短语集页筛了「口语」，过一会儿在导出页导出，得到的是"上次筛过的子集"而不是全部，且页面上看不到筛选是从哪来的。导出页自持（默认「全部」）是无隐藏耦合的读法，也符合"入口唯一"这一前提。

### D3 两层都用 `PhraseFilterBar`，不用 `SegControl`

顶层与标签层同为"横排可选项 + 计数"的语义，用同一组件最稳，顶层的计数还顺带解决了"哪一组有多少条"。

被否的方案是「顶层 `SegControl` + 标签 `PhraseFilterBar`」：两者选中态不同（浅底主色字 vs 实心主色底），叠在一起是两套视觉语言相邻，将来大概率被"顺手统一"掉其中一处，造成无意义的 churn。代价是顶层看起来也像筛选条——但顶层的语义本就是"选一组数据导出"，可接受。

（`PhraseFilterBar` 现有能力已够用：`label` / `count` / `dot` 均可选，`onSelect` 回传 value。）

### D4 命名冲突只解"跨目标"，同目标重复导出仍然覆盖

- **跨目标**（真风险）：单词 `lupa-<stamp>.<ext>`，短语 `lupa-phrases-<stamp>.<ext>`。两者不再共用 `_stampBase()` 这条路。
- **同目标**（接受覆盖）：短语集在同一分钟内先导「全部」再导「口语」会覆盖前一份。选择接受，理由是与单词导出现状一致（重复导出覆盖自己是既有语义），且加"文件已存在则加序号"会给一个罕见动作引入命名不确定性——用户下一次找不到自己那份文件在哪。

这条取舍写进 design 是为了不让它沉默地存在；若日后有用户反馈，再去重更便宜。

### D5 计数：标签 chip 走客户端（与短语页同源），权威条数由 report 给

```
「全部」计数   <- phraseStats['total']                      准（DB count）
「某标签」计数 <- phraseEntries（limit 500）客户端过滤后 length  与短语页同一算法、同一误差
导出后权威条数 <- exportXxx().count（report）                准（导出真实写入的条数）
```

不新增 `count-by-tag` 查询：那会引入第二套计数实现，与短语页 chip 的数字不一致反而更糟。误差只在 >500 条短语时出现，且结果行会用 report 的真实条数兜住，所以 spec 里也没有承诺"卡片上的数字一定等于导出条数"。

### D6 `tag` 透传的边界：一个可空参数，`null`/空串 = 全部

```
export_page.dart
   |
   v  String? tag
AppState.exportPhraseApkgTo(path, {tag}) / exportPhraseCsvTo(path, {tag})
   |
   v
exportPhraseApkg(nbPath, outPath, {limit, deckName, tag})
exportPhraseCsv (nbPath, outPath, {limit, tag})
   |
   v
listPhrases(nbPath, {limit, tag})        <- 已支持，repo 零改动
```

不引入 `PhraseExportScope` 之类的值对象：本轮只有一个维度（标签），一个可空字符串足够，且**删除该参数时行为与今天完全一致**，回退成本为零。

### D7 页面内聚：一个卡片组件 + 一份任务描述

四张卡片的差异只有「图标 / 标题 / 说明 / 按钮文案 / 计数 / runner」，因此抽一个 `_ExportCard`（收 busy / result / error / onPressed / 计数文案），把 `bool apkg` 的 if/else 换成按任务描述查 `_TaskState`。这样"新增一种格式"是加一条描述，而不是再抄一遍六个字段与两处分支。

### D8 空态守卫判「有效范围」，不判总数

`stats['total'] == 0` 这类写法在筛选存在后不够用：短语集有 12 条但选中标签下 0 条时，总数非空 → 守卫放行 → 产出空 deck / 仅表头 CSV。改为按**当前导出范围内的条数**判零，提示分两种文案（整体为空 / 该标签下为空）。

### D9 版本与文档漂移归本 change

`0.2.2 → 0.2.3`（`pubspec.yaml` 是版本唯一事实源）；`README.md:62` 的短语集导出描述、`AGENTS.md:73` 的版本号事实一并修正——上一轮交接单已明确把这两处漂移指给本 change。

## Risks / Trade-offs

- [短语数超过 500 时标签 chip 计数偏低] → 结果行以 report 的真实条数展示；`count-by-tag` 留给后续（见 D5）。
- [同分钟内同目标重复导出覆盖前一份] → 已知并接受的取舍（见 D4）；跨目标覆盖已由命名前缀消除。
- [顶层分段看起来像筛选，"生词本/短语集"被误读为过滤条件] → 顶层 segment 带计数、卡片区标题与说明保持单词/短语各自口径，形成语义锚点。
- [短语导出的 `limit: 10000` 与界面 500 条上限不一致，用户可能以为"导的是看到的这些"] → 不在 UI 文案里承诺条数等于列表条数；结果行给真实条数。
- [导出页 UI 测试要跨 sqflite ffi 隔离区] → 沿用 `test/phrase_ui_test.dart` 的 `_settleDb`（`runAsync` + `pump` 轮询）范式，禁用 `pumpAndSettle`。
- [`desktop-app`「导出触发」是 MODIFIED，归档时会整块替换原需求] → 已按"复制完整原块再改"写入 delta，`openspec validate --strict` 通过。
- [两层控件 + 抽卡片组件会让 `export_page.dart` 变动较大] → 本轮不顺手改单词导出的文案与行为，diff 尽量只落在结构与新增分支上，便于 review 时区分"搬"与"改"。

## Migration Plan

无 schema 变更、无数据迁移、无配置变更：短语表结构与 `notebook.sqlite` 不动，已导出的文件留在 `exports/` 不受影响。回滚 = revert 相关提交（旧导出页只服务生词本，短语导出仍可从代码层调用）。发布时 `version` 由 `0.2.2` 升到 `0.2.3`，按仓库惯例重新产出 `Release/` 与发行 zip。

## Open Questions

- 结果行文案是否要带上所选标签（如「已导出 12 条 · 口语」）——纯文案，不影响 spec、方案与任务拆分，实现时定即可。
