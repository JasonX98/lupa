## MODIFIED Requirements

### Requirement: 导出触发
系统 SHALL 提供导出界面，以「生词本」与「短语集」两个分组分别提供 Anki 牌组包与 CSV 导出入口；用户 SHALL 能在两个分组之间切换并分别导出。每个导出动作 MUST 只导出一个目标，MUST NOT 把生词本与短语集合并进同一次导出。当所选导出范围内没有条目时（生词本为空、短语集为空、或所选标签下无短语），系统 SHALL 拦下该次导出并给出提示，MUST NOT 产出空文件。

#### Scenario: 导出 apkg
- **WHEN** 用户在生词本分组选择导出 Anki 牌组包
- **THEN** 系统生成一个可被 Anki 导入的 .apkg 文件，含生词本全部单词

#### Scenario: 导出 CSV
- **WHEN** 用户在生词本分组选择导出 CSV
- **THEN** 系统生成一个 UTF-8 带 BOM 的 CSV 文件

#### Scenario: 导出短语 apkg
- **WHEN** 用户在短语集分组选择导出 Anki 牌组包
- **THEN** 系统生成一个可被 Anki 导入的 .apkg 文件，其内容为该分组当前所选范围内的短语

#### Scenario: 导出短语 CSV
- **WHEN** 用户在短语集分组选择导出 CSV
- **THEN** 系统生成一个 UTF-8 带 BOM 的 CSV 文件，其内容为该分组当前所选范围内的短语

#### Scenario: 切换分组不改变数据
- **WHEN** 用户在导出界面切换到另一个分组
- **THEN** 生词本与短语集的数据、以及所选导出范围均保持不变

#### Scenario: 生词本为空时导出被拦下
- **WHEN** 生词本为空时用户选择导出 Anki 牌组包或 CSV
- **THEN** 系统提示生词本为空并提示先收藏单词，且导出目录中不产生新文件

#### Scenario: 短语集为空时导出被拦下
- **WHEN** 短语集为空时用户在短语集分组选择导出 Anki 牌组包或 CSV
- **THEN** 系统提示短语集为空并提示先记录短语，且导出目录中不产生新文件

#### Scenario: 所选标签下无短语时导出被拦下
- **WHEN** 短语集非空但用户在短语集分组选中的标签下没有任何短语，且用户选择导出
- **THEN** 系统提示该标签下暂无短语并提示换个标签或选全部，且导出目录中不产生新文件

## ADDED Requirements

### Requirement: 导出产物命名按目标区分
系统 SHALL 使生词本导出与短语集导出的产出文件名互不相同，从而两类导出在同一分钟内先后执行时不会互相覆盖。文件名 SHALL 采用 `lupa-<yyyyMMdd-HHmm>.<ext>`（生词本）与 `lupa-phrases-<yyyyMMdd-HHmm>.<ext>`（短语集）。

#### Scenario: 生词本导出文件名
- **WHEN** 用户导出生词本为 apkg 或 CSV
- **THEN** 产出文件的主名称为 `lupa-<yyyyMMdd-HHmm>`，扩展名与所选格式一致

#### Scenario: 短语集导出文件名
- **WHEN** 用户在短语集分组导出 apkg 或 CSV
- **THEN** 产出文件的主名称为 `lupa-phrases-<yyyyMMdd-HHmm>`，扩展名与所选格式一致

#### Scenario: 同一分钟内先后导出两类不互相覆盖
- **WHEN** 用户导出生词本 apkg 后，在同一分钟内又导出短语集 apkg
- **THEN** 导出目录中同时存在两份文件，先导出的文件内容不被改动
