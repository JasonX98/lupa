## Context

见 `proposal.md` 的 Why。设计只受以下**实测**事实约束（本轮全部通过查询真实 `dict.sqlite` / `notebook.sqlite` 得出）：

- `dict.sqlite` 共 30000 词（ECDICT 按 `frq` 裁剪）。表结构里**没有例句、没有搭配**字段——这两个是 ECDICT 自身就没有的东西，不是裁剪掉的。
- `translation` 按 `\n` 分行，每行以词性缩写开头（`vt. 放弃, 抛弃...\nn. 放任, 无拘束...`）。全量 3 万词统计出的前缀白名单共 **18 种**：`n. a. vt. vi. adv. v. prep. pron. interj. num. conj. abbr. int. pl. aux. vbl. art. pref.`。注意最长的 token 是 6 个字母的 `interj.`（按「1..4 字母」的正则会漏掉它），`art.` / `pref.` 也是统计才发现的两个缺口；另有 1 处数据瑕疵 `na.`（`floodwaters`）刻意不收。
- 词性组数分布：1 组 21953 词、2 组 4452、3 组 1795、4 组 253、5 组 34、6 组 3，**0 组 1508 词**。
- **0 组词的构成与直觉不符**：只有 91 词含大写（`Mr` / `TV` / `PM` / `DNA` 这类缩写与专名），其余 **1417 词是小写内容词**，其中 1033 词的释义只带领域标签（`online` → `[计] 联机`、`funding` → `[经] 债务转期`、`download` / `laptop` / `globalization`），384 词连标签都没有（`etc` / `proven` / `mantra`）。它们没有词性前缀的原因不在「不是英语词」，而在 ECDICT 对这些条目只给了领域释义。
- `pos` 字段是 **WordNet 单字母体系**（`n/j/v/r/i/u/m/p/c/d/a`），与 `translation` 的前缀缩写体系**互不对应**：`serene` 的 `pos='j:100'` 而 `translation='a. 宁静的...'`；`present` 的 `pos` 有 `j` 没有 `a`，`translation` 有 `a.` 没有 `j.`。
- `exchange` 字段可反向建词形索引：24522 词有值，可提取 **52036 对**（变形 → 原形）；去重后 37521 个变形词形，其中 **31597 个（84.2%）自身不在词库**（`went` / `children` / `bought` / `took` / `mice` / `ran` 均属此类）。
- `notes.flds` 是 5 段 `0x1F` 拼接（`word / phonetic / translation / definition / exchange`），且 `addWord` 把词库内容**复制**进去——它已经是快照而非引用。`_rowToEntry` 用 `sublist(0, 5)` **硬编码 5 段**（`repo.dart:203`）。
- `ai_cache` 表在 v2 就建好了，含 `cache_key` / `word` / `provider` / `feature` / `prompt_version` / `payload` / `hit_count`，**零消费方**。这是当初为 LLM 增量预留的口子。
- 媒体层（`media/phonetic.dart`、`media/tts.dart`）用 `dart:io HttpClient` 手写，项目**零 HTTP 依赖**，错误统一为 `XxxFetchError` + message 字符串。
- `config.json` 分两块：顶层 `providers.{name}`（连接信息，由 `providerConfig()` 读）与 `settings.*`（用户行为，由 `AppState` 读）；`loadConfig` 是**深合并**，用户文件只需写覆盖键。
- `schema.sql` 是唯一建库模板，仅用 SQLite ≥ 3.38 标准 SQL；旧库迁移靠 `>>> PHRASE_TABLES_V2 >>>` marker 区块 + 抬 `meta.schema_version`（`notebook_db.dart:88`），且**当前迁移没有事务**。
- 全项目 **0 处** stub/mock HTTP：`verify_media.dart` 的注释直说「未命中缓存时会真实联网」。但 `setConfigHomeOverride` 已在 9 个测试文件里用于把 config 指到临时目录，是现成注入点。
- `_openNb` 已经 `PRAGMA foreign_keys = ON`，`cards` 靠 `ON DELETE CASCADE` 随 `notes` 删除；`revlog` 因为没有外键才需要手写删除。
- 版本号四处漂移：`pubspec.yaml` = `0.2.3`（声明为唯一事实源）、`AGENTS.md` = `0.2.3`、`README.md` = `v0.2.1`、`version.dart` = `0.2.2`（且它是设置页脚显示值）、`schema.sql` 的 `lupa_version` = `0.2.1`（唯一消费者是 `verify_notebook_db.dart:37` 的恒真断言）。

## Goals / Non-Goals

**Goals:**

- 让词卡从「只有释义」变成「释义 + 按词性分组的例句 + 搭配」，且这部分内容**随卡片落库、随导出带出**。
- 让词库未收录的词有出路，同时**不把「未收录」变成 AI 的唯一入口**——本地能解决的（词形变化）先用本地解决。
- 全程保持**离线优先**：AI 只是可选增量，付一次钱永久可用；不启用 AI 时应用行为与今天逐位一致。
- 让 AI 输出的正确性**可校验**（而不是盲信模型），并把校验做成可单测的纯函数。
- 让 AI 路径**可离线验证**，不需要真实密钥。

**Non-Goals:**

- 不追求「AI 例句一定比人写的好」。目标是「有例可看」，不是「例句质量最优」。
- 不做多 AI 服务商并存与运行时切换（配置结构支持，UI 只暴露一家）。
- 不把 AI 内容做成可手改的（旁表结构为它留了位，本次不做编辑 UI）。
- 不在复习卡展示 AI 例句（独立界面范围）。
- 不为 1534 个「解析不出词性」的词做任何 AI 补齐。

## Decisions

### D1. AI 内容落在旁表 `word_ai_groups` + `word_ai_examples`，而非 `flds` 的 JSON 段

- **选择**：新增两张旁表，`note_id` 关联 `notes`；`word_ai_groups.kind` 区分词性组（`sense`）与搭配组（`collocation`）；`word_ai_examples` 挂 `group_id`。
- **理由**：需求本身是**三级结构**（词性 → 多条例句 → `{en, zh}`），而 `flds` 的一个字段只有 3 个可用控制字符（`0x1C/0x1D/0x1E`，`0x1F` 是段间分隔符）——正好差一级。塞进一个字段就必须上 JSON，而 JSON 会把结构压成不可读不可查的 blob。旁表还带来三个具体好处：与既有 `phrases` + `phrase_examples` **完全同构**（`_loadExamples` 批量取法可直接照抄，`phrase_apkg.dart` 的 join 导出可参照）、每条例句可独立增删改（「用户想改 AI 写得别扭的句子」在语言学习应用里几乎必然被提出）、AI 增量再生可以只删该词的组而不动卡片核心。
- **替代方案 A（扩展 `flds` 到 7 段 + 段内控制字符迷你格式）**：无 schema 迁移、导出是直接字段映射、`notes` 单行自足。但层级不够（见上），若降级为「每词性只给 1 条例句」+「搭配不带例句」才能跑，而需求明确要「搭配及例句」，故放弃。
- **替代方案 C（扩展 `flds` + 段内存 JSON）**：绕开层级限制且免迁移，但 `notes` 里出现不可读 blob、SQL 不可查、单条例句不可编辑、整段只能一起替换。用一个不透明 blob 换一次迁移，收益不抵。
- **替代方案 D（只做查看期叠加，AI 内容仅存 `ai_cache`）**：零 schema 变更、最省事。但 `ai_cache` 按词索引、与笔记无关联，导出时读不到，**AI 内容将无法带出系统**。proposal 的 What Changes 明确要求 AI 内容随导出带出，故排除。

### D2. `ai_cache` 键把模型折进 provider 段；feature 只分两个

- **选择**：`cache_key = <provider>/<model>:<word小写>:<feature>`；`feature` 取 `enrich`（词库命中且有词性集合）、`enrich-plain`（词库命中但无词性集合，降级补齐）或 `define`（词库未命中整卡）；`prompt_version` 列承载「提示词版本 + 输出结构版本」；`payload` 存信封 `{"card": ..., "raw": ..., "model": ..., "usage": ...}`。
- **理由**：键仍是三段式（符合项目既有约定），但把四个失效维度各归其位——换模型靠 provider 段天然分家、改提示词与改输出结构靠 `prompt_version`（这两者同生共死，改结构必然改提示词）。`describe` 与 `enrich` 分成两个 feature 而不是一个 `card`，是因为两者产物语义不同：同一个词今天不在词库、明天进了词库，若共用一个 feature 会互相串味。payload 用信封而非裸响应，是为了既保住「读取端稳定」（读 `card`）又不丢调试信息（`raw`）与成本可见性（`usage`）。
- **替代方案 A（provider 段只放 `deepseek`，接受「换模型不失效」）**：少一次调用，但用户切到更强模型后看到的仍是旧模型的缓存，会得出「换模型也没变好」的错误结论——这种误解自己很难发现，故排除。
- **替代方案 B（feature 拆成 `examples` / `collocations` / `define` 三个）**：可定向重生，但要三次往返（三倍等待），且例句与搭配本来互相依存（搭配的例句要落在同一语境），拆开反而要重复交代上下文。更关键的是 **DeepSeek 的磁盘缓存按「完整前缀单元」精确匹配**——一个 feature 对应一个 system prompt 就是一个前缀单元，拆得越细前缀复用面越小。「只重生搭配」用「删缓存 + 重发一次」即可满足，不必为此拆 feature。
- **补充（D4 实施期确定）**：降级补齐用**第三个 feature 值 `enrich-plain`**，而不是复用 `enrich`。这不与上面的推理矛盾——D2 反对的是把**同一个任务**的产物拆成多次请求；降级补齐是**另一个任务**（不分组、system prompt 不同），它本来就自带一个前缀单元，与叫什么名字无关。分开的实际收益是 `prompt_version` 生命周期独立（改分组提示词不会连坐降级提示词的缓存）、设置页统计能区分两类产物。
- **替代方案 C（payload 只存原始响应 / 只存规范化结构）**：前者让读取端必须容忍模型的自由发挥，后者丢失排查依据与用量数据。两者都省不了一列，故取信封。

### D3. 非词库词：三段式入口 + 模型自证 + 独立保存路径

- **选择**：未收录时依次尝试 ① 本地词形还原 → ② 生词本回退 → ③ AI 生成入口（显式按钮，非自动）；AI 生成的 `define` 输出必须含 `is_known_word` 与 `canonical`，由纯函数校验；保存路径对外保留 `addWord`（词库词）与新增 `addAiWord`（AI 词）两个函数，内部共用 `_insertNote`；卡片来源存 `notes.data` 的 JSON 信封。
- **理由**：
  - **入口三段式的核心动机不是省钱，是正确性**。AI 字典最经典的失败是「很乐意给拼错的词编一个像模像样的释义」：用户输入 `serendipty`，模型会给出可信的释义，用户收藏并背下一个拼错的词。词库命中的词没有这个风险（3 万词库已校验），风险只存在于未命中路径。所以正确顺序是先问「你是不是打错了 / 这是某个词的变化形式」，再问 AI。
  - **模型自证把「编造」从静默失败变成一次显式校验**，而且校验是纯函数，能进 `verify_ai.dart`。
  - `addWord` 保留不动，是为了让 `verify_e2e.dart` 的 15 条既有断言与 `notebook` 规格里「重复加入」的语义零改动；把 `_insertNote` 抽出来共用，避免「重复检查 + flds 组装 + 两条 INSERT」被复制两份。
  - `notes.data` 是 `TEXT NOT NULL DEFAULT ''` 且**从未被写过**的列。用它存 provenance 让 `notes` 表结构不变，`verify_phrase_repo.dart:400` 那个手写 `notes` DDL 的测试桩也不用跟着改；且这个信息未来会长（provider / model / prompt_version / generated_at），JSON 免去反复加列。
- **替代方案 A（泛化为 `addWordFromCard(snapshot)` 单一路径）**：最干净，但 `WordNotInDictError` 的语义消失，现有 spec 与 e2e 断言要一起改——为一次能力扩展付一次既有验证的返工，不值。
- **替代方案 B（provenance 用 `notes` 新列或独立表）**：单列装不下多字段，独立表与 `word_ai_groups` 一对一天然重叠。且两者都会让 `notes` 表结构变更，牵连测试桩与 INSERT 路径。

### D4. 词性覆盖以 `translation` 行前缀为准，硬约束 + 0 组不补齐

- **选择**：`lib/ai/pos.dart` 提供纯函数，从 `translation` 逐行解析 18 种白名单前缀，跳过无前缀行（`[计] 因特网...`）；解析出 ≥1 组时作为硬约束下发并要求模型覆盖；0 组时按词形分两类（见下）。每词性返回 1–2 条例句（上限 2 防模型刷量）。
- **理由**：**绝不能用 `pos` 字段**——它是 WordNet 单字母体系，与 `translation` 的 ECDICT 缩写体系不对应，拿它校验必然错配（`serene` 是最好的反例）。以 `translation` 前缀为准还有一个决定性好处：**它和用户看到的释义行是同一套**，用户看到 4 行释义就期望 4 组例句，分组键与视觉分组天然对齐。
- **0 组分两类**（实施期实测修正）：0 组共 1508 词，其中仅 91 词含大写（`Mr` / `TV` / `DNA` 这类缩写与专名），**1417 词是全小写的内容词**——1033 词的释义只带领域标签（`online` → `[计] 联机`、`funding` → `[经] 债务转期`、`download` / `laptop` / `globalization`），384 词连标签都没有（`etc` / `proven` / `mantra`）。它们没有词性前缀的原因不在「不是英语词」，而在 ECDICT 对这些条目只给了领域释义；若一律不补齐，恰好丢掉最需要例句的那批现代词。因此：
  - 含大写 → 视为缩写或专名，**不发起请求**（模型不该给 `DNA` 编一个词性）
  - 全小写 → 视为内容词，**降级补齐**：不要求按词性分组，只要求 1–2 条通用例句 + 搭配；校验退化为 L1 结构 + L4 自证 + L5 例句含词（跳过 L2 覆盖与 L3 自洽——既无本地参照，也不要求模型自报词性）

  分类由纯函数 `enrichMode(word, translation)` 判定（`full` / `degraded` / `none`），可单测。且**「不补齐」必须是渲染层的早退分支，不是「请求了但丢弃结果」**，否则照样花钱。
- **替代方案 A（软建议，只把词性集合写进提示词不校验）**：省掉重试，但 `record` 这种 4 词性词会静默漏掉一两个——而「多词性都要有例句」正是需求的核心。
- **替代方案 B（按义项而非词性分组）**：更细，但 `record` 的 `n.` 一行就有 5 个义项，`present` 更多，会要求十几条例句，token 与等待都失控。

### D5. 渲染优先级：已保存快照 > `ai_cache` > 请求

- **选择**：查词页渲染一个词时的取值顺序为 ① 已在生词本 → 用旁表快照（不发 AI 请求）② 否则 `ai_cache` 命中 → 用它 ③ 否则按「自动补齐」开关决定请求或显示按钮。
- **理由**：解决「生词本里是 V1、查词页是 V2」的分叉。放在生词本里的那份必须是稳定的——背单词时看到的内容随 API 波动对记忆是负面的。让查词页也对已保存的词优先读快照，就得到「存了什么就看到什么」，且附带两个好处：已保存的词**完全离线可见**、**不会重复付费**。
- **自动补齐**：做成设置项、默认开，但触发点严格限定在 `_submit()` 拿到词条之后——**联想防抖与批量预热一律不触发**，否则打字过程中每个前缀都会烧钱。
- **替代方案 A（两边各显示各的）**：用户会以为「我存的那份被改了」。
- **替代方案 B（生词本也读 `ai_cache`，旁表只存手改过的）**：内容随 API 波动，最不该在所有方案里选。

### D6. 配置拆两块，密钥明文 + 环境变量优先

- **选择**：`providers.deepseek = { base_url, model, api_key, timeout_sec }`（连谁）+ `settings.ai = { enabled: false, provider, autoEnrich: true }`（要不要用）；`enabled` 默认 `false`；密钥按 `LUPA_AI_KEY` > `config.json` 解析，只支持这一个环境变量名；新增第五组「AI」，**「发音」组原样不动**。
- **理由**：与既有 `providers.youdao` 同构，`providerConfig()` 直接复用，将来加第二家天然支持；行为开关跟着用户走、连接信息跟着服务商走，语义不混。`enabled` 默认 false 是因为首次运行没有密钥，默认开会让用户第一次查词就撞错误弹窗——正确的引导顺序是「填密钥 → 提示可启用」。密钥选明文 + 环境变量的组合，是因为**便携性是这个产品的定位**：拷一份 `config.json` + `lupa_data` 到 U 盘就能用，密钥进 OS 凭据管理器会断掉这条路径；不想把密钥写进文件的人有 `LUPA_AI_KEY` 这个出口。UI 必须显式告知「明文保存在 config.json」。
- **替代方案 A（全塞 `settings.ai`）**：与 `youdao` 的连接信息分居两处，`providerConfig()` 复用不了。
- **替代方案 B（密钥进 Windows 凭据管理器 / DPAPI）**：最安全，但要加依赖且破坏便携迁移路径。
- **替代方案 C（顺手把「发音」组的服务商地址归位到「在线服务」组）**：信息架构更正确，但让一次「加 AI」背上「重做设置页 IA」的包袱。留作独立小改动。

### D7. 错误分类 + 总请求预算封顶

- **选择**：`AiError implements Exception` 带 `AiErrorKind` 枚举（`auth` / `rateLimit` / `network` / `timeout` / `server` / `malformed` / `invalid`）；网络层重试 1 次（固定退避 2s，若服务商给出 ≤5s 的 `Retry-After` 则遵守）；校验层重试 1 次（回灌缺项）；**一次用户触发最多 3 次 HTTP 请求**。
- **理由**：项目既有家法是「单类型 + message」，对音标够用，但 AI 的不同错误需要**不同行为**（401 不该重试、429 该退避、畸形 JSON 重试无意义），不能靠 message 字符串分叉。`AiError` 保留了既有 `XxxFetchError` 的形状（仍是一个 `implements Exception` 的类、仍有 `message`），只是把「怎么处理」变成可判定的。总预算封顶是因为网络重试与校验重试会**相乘**——不封顶时最坏路径是 4 次请求，其中两次可能都撞 429。
- **替代方案 A（不重试）**：DeepSeek 偶发 5xx 会让用户看到「失败」，太脆。
- **替代方案 B（指数退避 1s/2s/4s 最多 3 次）**：最坏等待 7 秒，查词场景不能忍。

### D8. 验证：本地 stub 为默认，`--live` 为可选

- **选择**：`tool/verify_ai.dart` 起 `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`（随机端口），把端口写进临时目录的 `config.json`，用 `setConfigHomeOverride` 注入；stub 具备两个能力：**按第 N 次请求返回不同剧本**、**记录收到的请求体**；13 条剧本；另加 `--live` 模式（显式给密钥才跑真实 API）。
- **理由**：AI 验证不能要求每次都掏付费密钥。而 stub 与 live 测的东西**根本不重叠**：stub 测代码路径、重试次数、降级行为、落库形状、导出拼接（可重复、可进 CI）；live 测提示词到底能不能让真实模型产出符合 schema 的内容——**stub 只会返回我们写死的「正确答案」，等于自己给自己出题**。所以两者都要有，但默认走 stub。剧本需要「按第 N 次返回不同响应」才能测重试，需要「记录请求体」才能断言回灌内容里含缺失的词性。
- **注入点全部现成**：`setConfigHomeOverride` 已在 9 个测试文件里使用，`loadConfig` 是深合并（临时 config 只需写 `providers.deepseek.base_url` 一个键），且 `dart:io HttpClient` 默认 `findProxy` 为 `DIRECT`，localhost 直连不受系统代理影响。不需要任何新机制、新依赖。
- **替代方案（只做 stub / 只做 live）**：前者永远测不出提示词质量，后者不可重复、需要密钥、不能进 CI。

### D9. v3 迁移必须包事务且逐列保护

- **选择**：`ensureNotebookDb` 的 v3 分支包在事务里，且对 `ai_cache` 的 4 条 `ALTER TABLE ADD COLUMN` 先查 `PRAGMA table_info(ai_cache)` 再执行；新表用 `CREATE TABLE IF NOT EXISTS` + marker 区块（照抄 `PHRASE_TABLES_V2` 机制）。
- **理由**：**SQLite 没有 `ADD COLUMN IF NOT EXISTS`**。现有 v2 迁移没有事务（`notebook_db.dart:88`），如果 v3 的 4 条 ALTER 中途失败，`schema_version` 仍是 2，重跑就会撞 `duplicate column name` —— 库会永久卡在「迁移不完整且无法重试」的状态。v2 那次是纯 `CREATE TABLE IF NOT EXISTS`（天然幂等）所以侥幸没事，v3 不行。
- **替代方案（沿用无事务写法）**：省 5 行代码，换一个不可恢复的迁移死角，不划算。

### D10. AI 客户端手写，零新增依赖

- **选择**：`lib/ai/client.dart` 用 `dart:io HttpClient` 发 `POST <base_url>/chat/completions`，带 `response_format: {type: 'json_object'}`、退避重试与超时；不引入任何 pub 包。
- **理由**：API 面积极小（1 个端点、4 个字段、非流式），项目已有两个同构的手写 provider（`phonetic.dart` / `tts.dart`），引入 SDK 会造成风格分叉并带进传递依赖。校验与修复重试是本项目的自有逻辑，任何 SDK 都帮不上。DeepSeek 兼容 OpenAI 协议，且支持 `response_format: {'type': 'json_object'}`。
- **替代方案 A（`openai_dart`）**：纯 Dart、`OpenAIConfig(baseUrl:)` 可配、要求 Dart ≥ 3.12（项目正好 `^3.12.2`），是好选项。它省下约 170 行，其中 80 行是 SSE 流式解析——而本设计**明确不做流式**（结构化 JSON 与流式天生别扭，半截 JSON 无法解析）。为省 90 行而带 3 个传递依赖并锁死 Dart 下限，不划算。
- **替代方案 B（`dart_openai`）**：GitHub README 明确列出支持 DeepSeek，但为非官方包，且刚从 6.1.1 跳到 8.0.0，changelog 需另行核实。
- **提示词布局约束（由前缀缓存反推）**：DeepSeek 的磁盘缓存默认开启且按前缀匹配，因此 `messages` 里**固定不变的生成规范放 system 且放前面**，词的相关信息放 user 放后面——这样长 system 提示词能被所有词请求复用。

## Risks / Trade-offs

- [提示词质量只能靠 `--live` 实测] → stub 的 13 条剧本全部通过也不代表真实模型能稳定产出符合 schema 的 JSON。缓解：`--live` 跑一批多词性词，观测 L2 覆盖率、L5 通过率、平均请求次数与前缀缓存命中率；若平均请求次数 > 1.5 说明提示词需要改。
- [模型偶发不遵守限制] → 「每词性 ≤2 条例句」的上限可能被模型无视。缓解：校验层把「超过 2 条」按截断处理而非判定失败（多给了不是错误，只是浪费 token）。
- [v3 迁移写坏用户的库] → 见 D9，事务 + 逐列 pragma 保护。另：迁移前不自动备份（既有 v2 也没有），但 `settings` 里已有「立即备份生词本」入口。
- [清理 AI 缓存被用户误解为「会删掉我的例句」] → 必须在 UI 文案里明说「清理的不是你保存的例句」。spec 里已把它写成可测场景（清理后已保存例句仍完整可见）。
- [AI 例句挤占卡片视觉空间] → 一个 4 词性词可能有 8 条例句。缓解：AI 区块默认折叠或置于词库内容之后，且生词本列表不展开（已写入 spec）。
- [中文输入英文例句的引号/破折号被模型写成全角] → 不影响校验，但影响复制的可读性。属于提示词调优范畴，不阻塞。
- [词性解析遇上 `[领域]` 混排行] → `n. [棒](投手投出的)快球` 这类行前缀仍是 `n.`，解析正确；但纯领域行（`[计] 因特网...`）必须跳过，否则会把 `[计]` 误当词性。已由白名单 + 前缀正则覆盖，靠第 13 条全量回归断言守住。
- [`desktop-app` 的「导出触发」仍带「可被 Anki 导入」措辞，本次未改] → 该需求的行为未变，只改措辞会迫使整块重述（它含 7 个场景），风险大于收益。记入后续清理清单，与「发音组归位」「`anki_import_compare.py` 去留」一并处理。
- [版本号一致性单测会随每次发版失败] → 这正是它的目的：把「唯一事实源」从口头约定变成可执行断言。发版时同时改 `pubspec.yaml` 与 `version.dart` 两处是刻意保留的成本（比引入构建期代码生成便宜得多）。

## Migration Plan

- **数据迁移**：`schema_version` 2 → 3。纯增量——新增 `word_ai_groups` / `word_ai_examples` 两张表（`CREATE TABLE IF NOT EXISTS` + marker 区块），`ai_cache` 加 4 列（`model` / `prompt_tokens` / `completion_tokens` / `cache_hit_tokens`，均带 `DEFAULT`）。**不改动任何现有表的结构与数据**，`notes` / `cards` / `revlog` / `phrases` 全部不动。
- **老数据兼容**：老笔记没有 AI 内容，`NotebookEntry.aiGroups` 读出为空列表，UI 走「无 AI 内容」分支，apkg/CSV 的 AI 字段为空。无需回填。
- **回滚**：还原代码即可。新表与 `ai_cache` 的新列在旧版本里不被读取；老版本不会因为多出一张表或几列而失败。回滚后已保存的 AI 例句不出现在界面与导出里（但数据仍在库中，重新升级即可恢复）。
- **零依赖变更**：`pubspec.yaml` 只改 `version`，不加任何依赖，因此不存在依赖冲突或平台插件风险。
- **验证顺序**：`dart run tool/verify_notebook_db.dart`（v3 迁移 + 幂等重跑）→ `dart run tool/verify_dict_query.dart`（词形还原全量回归）→ `dart run tool/verify_ai.dart`（13 条 stub 剧本）→ `dart run tool/verify_e2e.dart`（既有 15 条断言必须全绿，证明未破坏主链路）→ `dart run tool/verify_export.dart`（9 列 / 8 字段）→ `flutter test` → `flutter analyze`。
- **发布**：`version` 0.3.0；`flutter build windows --release` 后打包 `Release/` 为 `Lupa-0.3.0-windows.zip`。

## Open Questions

- **`--live` 用哪批词做提示词回归**：可以从生词本取 20 个多词性词，也可以固定一批（`record` / `present` / `abandon` / `serene` / `go` / `went` / `Mr` 等覆盖各分支）。属于验证脚本的参数选择，不影响 spec、方案或任务拆分，实现期定即可。
- **AI 区块在查词页默认展开还是折叠**：取决于实机上一个 4 词性词的视觉体量。属于纯呈现调优，spec 只要求「不阻塞骨架卡」，两种都满足。
- **`usage` 里除 token 外是否还记录延迟**：有助于观测，但不是任何 spec 场景的前提。
