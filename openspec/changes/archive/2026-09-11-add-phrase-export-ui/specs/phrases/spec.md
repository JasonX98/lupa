## MODIFIED Requirements

### Requirement: 导出短语为 Anki 牌组包
系统 SHALL 支持把短语集导出为独立的 Anki `.apkg`，使用独立 model/deck 与稳定 guid，不与单词导出混用。导出入口 SHALL 位于导出界面的短语集分组，导出内容 SHALL 为该分组当前所选范围内的全部短语。

#### Scenario: 导出短语 apkg
- **WHEN** 用户在导出界面的短语集分组选择导出短语 Anki 牌组包
- **THEN** 系统生成一个可被 Anki 导入的 `.apkg`，其卡片 guid 基于短语文本，与单词卡不重复

#### Scenario: 短语导出不含单词卡
- **WHEN** 用户在短语集分组导出短语 apkg
- **THEN** 包内只含短语牌组与短语卡，不含任何单词卡或生词本牌组

### Requirement: 导出短语为 CSV
系统 SHALL 支持把短语集导出为 UTF-8 带 BOM 的 CSV，含全部字段（含例句）。导出入口 SHALL 位于导出界面的短语集分组，导出内容 SHALL 为该分组当前所选范围内的全部短语。

#### Scenario: 导出短语 CSV
- **WHEN** 用户在导出界面的短语集分组选择导出短语 CSV
- **THEN** 系统生成一个含短语全部字段（含例句）的 UTF-8 带 BOM CSV

## ADDED Requirements

### Requirement: 短语导出支持按标签筛选

系统 SHALL 允许用户为短语导出选择范围：「全部」或短语集中的某个标签。选定某个标签后，导出的短语集 SHALL 只包含带该标签的短语，MUST NOT 混入其它标签或不带该标签的短语。导出范围的选择 SHALL 只影响导出内容，MUST NOT 改变短语集本身的数据，也 MUST NOT 依赖或改动短语集界面上的筛选状态。

#### Scenario: 按标签筛选导出

- **WHEN** 用户选择标签「口语」后导出短语 apkg 或 CSV
- **THEN** 产出内容只含带「口语」标签的短语

#### Scenario: 默认导出全部

- **WHEN** 用户未改变导出范围（仍为「全部」）并导出短语
- **THEN** 产出内容含短语集全部短语

#### Scenario: 标签筛选只作用于导出内容

- **WHEN** 用户在导出界面选择某个标签并导出，或导出后返回短语集界面
- **THEN** 短语集数据与短语集界面的筛选状态均不变

#### Scenario: 依次以不同标签导出

- **WHEN** 用户先后以两个不同标签导出短语
- **THEN** 每次产出只含该次所选标签的短语，前一次的结果不被混入
