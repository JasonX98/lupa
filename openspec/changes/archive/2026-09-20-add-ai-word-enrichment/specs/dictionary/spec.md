## ADDED Requirements

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
