# Dictionary Specification

## Purpose

为 Lupa 提供离线英文词库：把 ECDICT 全量库裁剪成可离线查询的高频词库，并支持精确查词、前缀联想与词库统计。

## Requirements

### Requirement: 词库构建（按频率裁剪）
系统 SHALL 从 ECDICT 源库构建 Lupa 词库，仅保留有当代语料库词频数据（`frq`）的词，并按其词频升序裁剪到指定的前 N 词（默认 3 万）。

#### Scenario: 构建后仅保留高频词
- **WHEN** 用户以默认 3 万词上限构建词库
- **THEN** 生成的词库只包含 `frq` 最高的前 3 万词，且每词含词形、音标、中英释义、词性、柯林斯星级、牛津标签、BNC/词频、词形变化等字段

#### Scenario: 排除无频率数据的词
- **WHEN** 源库中存在 `frq` 为空或为 0 的词
- **THEN** 这些词不被写入 Lupa 词库

### Requirement: 精确查词
系统 SHALL 支持按单词精确查询，且匹配大小写不敏感；未收录时返回"未收录"。

#### Scenario: 大小写不敏感命中
- **WHEN** 用户查询 `Abandon`
- **THEN** 系统返回 `abandon` 的词条（音标、中英释义、词形变化）

#### Scenario: 未收录
- **WHEN** 用户查询词库中不存在的单词
- **THEN** 系统报告该词未收录

### Requirement: 前缀联想
系统 SHALL 支持按前缀返回候选单词，且按词频（`frq` 升序，高频优先）排序。

#### Scenario: 返回前缀候选
- **WHEN** 用户请求某前缀的联想
- **THEN** 系统返回以该前缀开头的单词列表，高频词排在前面

### Requirement: 词库统计
系统 SHALL 提供词库统计，包含总词数、含音标词数、含英文释义词数。

#### Scenario: 展示词库规模
- **WHEN** 用户请求词库统计
- **THEN** 系统返回总词数、含音标数、含英解数

### Requirement: 本地词形还原
系统 SHALL 基于词库中已收录的词形变化数据提供本地词形还原：对查不到的输入，若它是某个已收录单词的词形变化（如过去式、过去分词、复数、比较级等），系统 SHALL 报告其原形并允许直接查看原形词条。该能力 MUST NOT 依赖网络或 AI。

#### Scenario: 还原不规则动词
- **WHEN** 用户查询 `went`
- **THEN** 系统报告它是 `go` 的过去式，并提供查看 `go` 的入口

#### Scenario: 还原名词复数
- **WHEN** 用户查询 `children`
- **THEN** 系统报告其原形为 `child`

#### Scenario: 还原过去分词
- **WHEN** 用户查询 `bought`
- **THEN** 系统报告其原形为 `buy`

#### Scenario: 精确命中优先于还原
- **WHEN** 用户查询一个本身已收录、同时也是另一词词形变化的词（如 `better` 同时是 `good` 的比较级）
- **THEN** 系统直接展示该词自身的词条，不把它报告为其他词的变化形式

#### Scenario: 无法还原时的行为
- **WHEN** 用户查询的词既不在词库中，也不是任何已收录词的已知词形
- **THEN** 系统报告未收录

#### Scenario: 离线可用
- **WHEN** 设备无网络且用户查询 `bought`
- **THEN** 系统仍能报告其原形为 `buy`
