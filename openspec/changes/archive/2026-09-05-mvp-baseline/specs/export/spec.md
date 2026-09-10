## Purpose

让 Lupa 用户的生词本数据可以带出系统：导出为 Anki 可导入的 .apkg 或任何工具可打开的 UTF-8 CSV，实现"数据归用户所有"。

## ADDED Requirements

### Requirement: Anki apkg 导出
系统 SHALL 支持把生词本导出为 Anki `.apkg` 包，字段含单词、音标、中英释义、词形变化与标签，并可在 Anki 中导入。

#### Scenario: 导出可导入的 apkg
- **WHEN** 用户导出当前生词本为 apkg
- **THEN** 系统生成一个可被 Anki 导入的 .apkg 文件，包含生词本全部单词与字段

#### Scenario: 同词重复导出稳定更新
- **WHEN** 用户对同一个单词多次导出 apkg
- **THEN** 该词在 Anki 端作为同一张卡更新，而非重复建卡

### Requirement: CSV 导出
系统 SHALL 支持把生词本导出为 UTF-8（带 BOM）的 CSV，含表头，字段与生词本一致。

#### Scenario: 导出可打开的 CSV
- **WHEN** 用户导出当前生词本为 CSV
- **THEN** 系统生成一个 UTF-8 带 BOM 的 CSV 文件，含表头与全部生词字段，Excel 打开不乱码
