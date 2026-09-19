## MODIFIED Requirements

### Requirement: Anki apkg 导出
系统 SHALL 支持把生词本导出为 `.apkg` 包，字段含单词、音标、中英释义、词形变化、标签、AI 例句与 AI 搭配。导出 SHALL 使用稳定标识，使同一个词多次导出时被识别为同一张卡而非重复建卡。

#### Scenario: 导出可导入的 apkg
- **WHEN** 用户导出含 AI 例句与搭配的生词本为 apkg
- **THEN** 产出文件包含全部单词及其 AI 例句与搭配字段

#### Scenario: 同词重复导出稳定更新
- **WHEN** 用户对同一个单词多次导出 apkg
- **THEN** 该词以同一标识导出，不产生重复卡片

#### Scenario: 无 AI 内容的词正常导出
- **WHEN** 用户导出一个尚无任何 AI 例句与搭配的生词本
- **THEN** 产出文件包含全部单词，其 AI 例句与搭配字段为空

### Requirement: CSV 导出
系统 SHALL 支持把生词本导出为 UTF-8（带 BOM）的 CSV，含表头，字段与生词本一致；AI 例句与 AI 搭配 SHALL 作为两个新列追加在表头末尾，原有列的位置与含义 MUST 保持不变。

#### Scenario: 导出可打开的 CSV
- **WHEN** 用户导出当前生词本为 CSV
- **THEN** 系统生成一个 UTF-8 带 BOM 的 CSV 文件，含表头与全部生词字段，Excel 打开不乱码

#### Scenario: AI 列追加在末尾
- **WHEN** 用户导出 CSV
- **THEN** 表头的前七列与导出 AI 内容之前完全一致，新增的例句列与搭配列位于末尾

#### Scenario: 多行内容正确转义
- **WHEN** 某词的例句与搭配为多行内容
- **THEN** 单元格内容被正确引用，用电子表格软件打开时每条内容逐行可见
