## Why

Lupa v0.1.0 MVP 数据流水线已经跑通（查词 / 生词本 / 复习 / 发音 / 导出），但它的能力与约束目前只散落在 README、代码注释和一次性的产品决策里，没有形成一份可审查、可演进的规范基线。没有基线，后续的变更（如 v2 接入 FSRS、LLM 增量、桌面端）就没有稳定的"现状"可对照，容易把已拍板的约束（跨语言友好、纯函数、三段式缓存键）悄然破坏。

## What Changes

本次只做**文档化/基线化**，不引入任何新功能、不改动实现代码：

- 新增 4 个 capability 规范，把 MVP 已实现并拍板的能力固化为需求描述。
- 用 `design.md` 记录已成立的架构决策（跨语言友好三约束、纯函数边界、Anki schema11 兼容、三段式缓存键）。
- 用 `tasks.md` 记录基线沉淀后暴露的后续待办（如补齐测试、复核调度时间语义）。
- **BREAKING**：无。纯增量文档，不影响任何现有行为。

## Capabilities

### New Capabilities
- `dictionary`: 词库——ECDICT 源库按 `frq` 频率裁剪到 3 万词，提供查词 / 前缀联想 / 词库统计。
- `notebook`: 生词本——Anki schema11 兼容的 notes/cards/revlog，支持增删查、固定间隔调度（1/3/7/15/30 天）与复习答题。
- `media`: 发音与音标——联网有道取音标 / TTS 音频，结果以三段式缓存键落入本地缓存表。
- `export`: 导出——生词本导出为 Anki apkg（稳定 guid）与 UTF-8 CSV。

### Modified Capabilities
- 无（当前 `openspec/specs/` 下尚无主 spec，本次是首次建立基线）。

## Impact

- **代码**：无改动（纯规划工件）。
- **OpenSpec 工件**：`proposal.md`、`specs/{dictionary,notebook,media,export}/spec.md`、`design.md`、`tasks.md`。
- **约束来源**：需求语义以 README 与 `src/lupa/notebook/schema.sql`、`src/lupa/{dict,notebook,media,export}/**` 的实际实现为准，本提案只做描述，不改变实现。
