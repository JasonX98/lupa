## Why

Lupa 的词卡只有词库带来的骨架：音标、中英释义、词形变化。ECDICT 本身**没有例句、也没有搭配**——3 万词库里这两个字段是零。用户查到了词、看清了释义，却看不到它怎么用。而 3 万词之外还有大量词够不着：`went` / `children` / `bought` 这些高频变形词都不在其中，查不到就是一句「未收录」，没有任何出路。

## What Changes

- 引入 **AI 作为可选的在线增量**（默认 DeepSeek，OpenAI 兼容接口）：词库命中时补例句与搭配；词库未命中时生成整卡。默认关闭，不填密钥时应用行为与今天完全一致。
- 例句**按词性分组**：`record` 的 `n. / vt. / vi. / a.` 各有例句；分组键来自本地 `dict.translation` 的行前缀，可作为硬约束校验模型输出。
- schema v2 → v3：新增 `word_ai_groups` + `word_ai_examples` 两张旁表承载 AI 例句与搭配；`ai_cache` 的 `model` 与 token 用量落为真列。
- **BREAKING**（数据层）：「加入生词本」不再要求词必须在词库中——非词库词经 AI 生成整卡后可入生词本。`notebook` 的「词未收录 → 拒绝」被改写为「词库词可直接加入，非词库词须先经 AI 生成整卡」。
- **BREAKING**（导出契约）：apkg 的 model 从 6 字段增至 8 字段（`Examples` / `Collocations`）；CSV 从 7 列增至 9 列——新列**追加在末尾**，前 7 列位置不变。
- **BREAKING**（界面行为）：查词界面的「未收录」不再只是一句提示，改为三段式——本地词形还原 → 生词本回退 → AI 生成入口。
- 新增**本地词形还原**（零成本、零网络）：借 `dict.exchange` 反向索引把 `went` / `children` / `bought` / `took` 还原到原形。实测 24522 词的 exchange 可提取 52036 对词形，其中 31597 个变形词自身不在词库。**该能力不依赖 AI 开关**。
- 新增设置第五组「AI」：服务商 / 模型 / Base URL / 密钥 / 超时、自动补齐开关、AI 缓存统计与清理。
- 新增 `LUPA_AI_KEY` 环境变量（优先于 `config.json` 中的明文密钥）。
- 顺手修正**版本号四处漂移**：`version.dart` 落后一个补丁且是设置页脚显示值、`README.md` 落后两个补丁、`schema.sql` 的 `lupa_version` 唯一消费者是个恒真断言。
- **零新增 pub 依赖**：AI 客户端用 `dart:io HttpClient` 手写，与既有 `media/phonetic.dart` / `media/tts.dart` 同构。

## Non-goals

- 不在本次让复习卡展示 AI 例句（独立的界面范围扩张）。
- 不在生词本列表展开例句，只保留紧凑列表。
- 不修 `d` / `p` 词形标签反了的既有缺陷（已确认单独开 change）。
- 不做 AI 例句的用户手改、不做多 AI 服务商并存与切换、不做例句发音、不做由例句自动生成 cloze 卡、不做 FSRS。
- 不整理设置页既有的信息架构（「发音」组里的服务商地址归位留作独立小改动）。
- 不删除 `desktop/tool/anki_import_compare.py`，也不以它作为验收条件。
- 不改动既有主规格文件 `openspec/specs/**`（由后续 sync / archive 流程处理）。

## Capabilities

### New Capabilities

- `ai`: AI 单词补齐与生成——按词性分组的例句与搭配、三段式缓存键（`<provider>/<model>:<word>:<feature>`）、词性覆盖校验 L1–L5 与修复重试、失败分类与降级、请求预算、密钥与配置解析。

### Modified Capabilities

- `dictionary`: 新增「本地词形还原」需求（`dict.exchange` 反向索引，`went` → `go`），与精确查词 / 前缀联想并列；「精确查词」的既有语义不变。
- `desktop-app`: 「查词界面」的未收录行为由「提示未收录」改为三段式（本地还原 → 生词本回退 → AI 入口）；新增 AI 段落的呈现要求（骨架先行、四态、不阻塞骨架卡）。
- `notebook`: 「加入生词本」不再要求词在词库中；新增 AI 例句/搭配旁表的读写与级联删除；新增卡片来源标记（词库 vs AI 生成）。
- `export`: apkg 增加例句与搭配字段；CSV 追加例句与搭配列；apkg 需求不再以「可被 Anki 导入」作为验收断言。
- `settings`: 新增 AI 分组（启用 / 服务商 / 模型 / Base URL / 密钥 / 超时 / 自动补齐 / AI 缓存统计与清理）；新增密钥解析优先级（`LUPA_AI_KEY` > `config.json`）。

## Impact

**新增文件**

- `desktop/lib/ai/`（新目录）：`client.dart`（POST `/chat/completions` + 退避 + 超时 + `AiError`/kind）、`prompt.dart`（提示词与 `prompt_version`）、`card.dart`（`AiCard` 模型 + L1–L5 校验纯函数）、`pos.dart`（词性解析纯函数 + 16 种白名单）、`repo.dart`（`ai_cache` 读写）、`enrich.dart`（缓存 → 请求 → 校验 → 修复重试编排）。
- `desktop/lib/dict/lemma.dart`：逆向 exchange 索引的词形还原纯函数 + 查询。
- `desktop/tool/verify_ai.dart`：本地 stub `HttpServer` + 13 条剧本断言（含默认路径与可选 `--live`）。
- `desktop/test/`：`ai_card_test.dart`、`ai_pos_test.dart`、`lemma_test.dart`、`ai_ui_test.dart`、`version_test.dart`。

**修改文件**

- `desktop/lib/data/schema.sql`：v3 两表 + `ai_cache` 四列 + 顶部注释降级 Anki 措辞 + `lupa_version` 处理。
- `desktop/lib/data/notebook_db.dart`：v3 迁移分支（事务包裹 + 逐列 `PRAGMA table_info` 保护）；`AiCacheStats` 与清理函数。
- `desktop/lib/data/config.dart`：`defaultConfig` 增 `providers.deepseek` 与 `settings.ai`。
- `desktop/lib/notebook/repo.dart`：抽 `_insertNote`；新增 `addAiWord`；`NotebookEntry` 增 `aiGroups`；批量取 AI 组；`removeWord` 级联。
- `desktop/lib/state/app_state.dart`：AI 编排（缓存优先 → 请求 → 落库）、设置项读写、AI 缓存统计、`LUPA_AI_KEY` 解析。
- `desktop/lib/pages/search_page.dart`：AI 段落四态、渲染优先级、未收录三段式、自动补齐触发点。
- `desktop/lib/pages/settings_page.dart`：第五组「AI」。
- `desktop/lib/widgets/word_detail_dialog.dart`：展示 AI 例句与搭配。
- `desktop/lib/widgets/word_bits.dart`：AI 例句/搭配渲染小组件。
- `desktop/lib/export/apkg.dart`：model 6 → 8 字段 + join + 渲 HTML。
- `desktop/lib/export/csv.dart`：`csvHeader` 7 → 9 列 + 序列化纯函数。
- `desktop/lib/version.dart`、`desktop/pubspec.yaml`：版本升至 `0.3.0`。
- `desktop/tool/verify_dict_query.dart`：加词形还原断言（对真实词库 3 万词）。
- `desktop/tool/verify_notebook_db.dart`、`desktop/tool/verify_phrase_repo.dart`：`schema_version` 断言 2 → 3。
- `README.md`、`AGENTS.md`：功能清单、版本号、Anki 措辞降级、验证清单。

**零改动**

- `desktop/lib/dict/query.dart`（保持纯查询，词形还原走独立的 `lemma.dart`）、`desktop/lib/pages/notebook_page.dart`、`desktop/lib/media/**`、`desktop/lib/phrase/**`、`desktop/lib/notebook/scheduler.dart`。

**待实测风险**

- 提示词能否让真实模型稳定产出符合 schema 的 JSON——L2（词性覆盖）与 L5（例句含词）通过率只能靠 `--live` 实测，stub 测不出提示词质量。
- DeepSeek 前缀缓存的真实命中率（影响成本，不影响正确性）。
- 词性解析遇上 `[领域]` 混排行（如 `n. [棒](投手投出的)快球`）时的处理是否正确。

## 顺延（不在本 change 范围）

- **词形标签反了的既有缺陷**：`word_bits.dart:15` 与 `export/apkg.dart:78` 把 `d` / `p` 映射反了（ECDICT 实际是 `p` = 过去式、`d` = 过去分词；`go` 的 exchange 为 `p:went/d:gone` 可证）。用户查 `go` 会看到「过去式 gone · 过去分词 went」。`test/widget_test.dart:23` 恰好用 `abandon`（`d` 与 `p` 值相同）当用例，掩盖了它。**单独开 change 修。**
- **「发音」组信息架构**：`settings_page.dart` 的「发音」组里混着 TTS/音标服务商地址与媒体缓存统计，归位到「在线服务」是独立改动。
- **`desktop-app` 与实现的既有不一致**：`notebook_page.dart` 里其实没有「加入生词」入口（只有统计头 / 列表 / 移除 / 复习），但 `desktop-app` 规格的「生词本管理界面」写的是「支持查看生词列表、加入生词与移除生词」。本次不动。
- **`anki_import_compare.py` 的去留**：本次只把 `AGENTS.md` 里的措辞降级为「可选的历史校验工具，不再是验收条件」，是否彻底移除留待后续判断。
