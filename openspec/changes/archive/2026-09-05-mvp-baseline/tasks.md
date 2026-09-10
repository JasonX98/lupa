## 1. 规范工件收尾

- [ ] 1.1 运行 `openspec validate mvp-baseline`，确认 proposal / 4 个 spec / design / tasks 工件结构合法、无零 delta 报错
- [ ] 1.2 核对 4 个 capability 的 `spec.md` 与 proposal 的 Capabilities 一一对应（dictionary / notebook / media / export）

## 2. 基线一致性核对

- [ ] 2.1 逐条对照 `src/lupa/{dict,notebook,media,export}/**` 实际实现与 spec 需求，确认描述无出入
- [ ] 2.2 确认 `design.md` 记录的架构决策与 README、`schema.sql` 注释一致

> **本 change 为纯文档基线化，不写实现代码。** 以下项属于后续独立 change，不作为本 change 的 apply 任务：补齐测试、复核调度时间语义（`now + ivl*86400` vs Anki 零点）、统一缓存键文档表述。
