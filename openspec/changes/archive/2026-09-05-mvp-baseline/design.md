## Context

MVP 数据流水线已实现（见 proposal.md - Why），本设计文档记录**已成立**的架构决策，作为基线，而非新的实现计划。约束来源于 README、`src/lupa/notebook/schema.sql` 与各模块注释；这些决策已在代码中落地，这里只做固化，不引入新方案。

## Goals / Non-Goals

**Goals:**
- 固化支撑 4 个 capability（dictionary / notebook / media / export）的跨模块架构决策。
- 明确"跨语言友好"与"纯函数边界"这两条贯穿性约束的具体形态，作为后续变更（FSRS、LLM、桌面端）的对照基线。

**Non-Goals:**
- 不设计新功能（v2 的 FSRS、LLM 增量、桌面端均为后续独立 change）。
- 不改变现有实现，不重排模块结构。

## Decisions

### 1. 跨语言友好三约束（为 Flutter 铺路）
- **标准 SQL**：`schema.sql` 仅用 SQLite ≥ 3.38 标准语法，不用 JSON1 / STRICT / RETURNING / virtual table / 窗口函数；需要更强特性时必须在文件头声明并说明 Flutter 端兼容性。
- **纯函数边界**：业务逻辑（`dict/query.py`、`notebook/repo.py`、`export/*.py`、`media/*.py`）不读 stdin / 不写 stdout，`cli.py` 的 Typer 只做参数解析与显示。
- **三段式缓存键**：媒体缓存键统一为 `provider:word:format`，切换服务商无需迁移数据。
- 备选：单进程纯 Python、不追求跨语言 —— 被否，因产品已拍板后期桌面端用 Flutter，业务规则需 Python 一份。

### 2. 生词本采用 Anki schema11 三表（notes / cards / revlog）
- 直接复用行业事实标准的表结构，导出 `.apkg` 时字段可复用；复习历史与卡片状态分离，便于调算法与导出。
- 备选：自研精简表 —— 被否，会损失 Anki 兼容与导出便利。

### 3. 调度 v1 固定间隔，v2 换 FSRS
- v1 用 `1/3/7/15/30` 天固定档位（`scheduler.py`），答对推进、答错回退；v2 接入 FSRS 只需替换 `scheduler`，其余不动。
- 备选：v1 直接上 FSRS —— 被否，MVP 先求简单可验证。

### 4. 媒体：联网优先 + 本地缓存
- 音标 / TTS 走服务商 URL（默认有道），结果落 `phonetic_cache` / `audio_cache`，命中缓存优先返回，未命中联网并落库。
- 服务商 URL 全部走 `config.json`，不硬编码，用户可替换。

### 5. 导出 apkg 的稳定 guid
- note guid 用单词 hash（`lupa::<word>`），同词重复导出在 Anki 端更新而非重复建卡。

## Risks / Trade-offs

- **调度时间语义**：`due_timestamp` 用 `now + ivl*86400`，而非 Anki 的"当天零点 + ivl 天"，跨天复习会随复习时刻漂移 → 记录为 v1 已知简化，v2 换 FSRS 时一并复核。
- **测试缺失**：`tests/` 目前近乎为空，纯函数设计本应利于单测 → 列入 tasks 待办。
- **缓存键与文档字面偏离**：约束 #3 写的是三段式，但 `tts.py` 实际生成 `youdao:abandon:mp3-us`（口音并入 format 段，实为四段）→ 有意的取舍（同词英美音需分开缓存），spec 已按此描述。
