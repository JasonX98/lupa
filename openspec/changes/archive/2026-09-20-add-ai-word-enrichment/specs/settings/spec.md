## MODIFIED Requirements

### Requirement: 提供设置界面
系统 SHALL 提供设置界面，按外观 / 发音 / 复习 / AI / 数据五组呈现可配置项。

#### Scenario: 打开设置页
- **WHEN** 用户点击侧栏"设置"入口
- **THEN** 界面展示五组设置表单

## ADDED Requirements

### Requirement: AI 补齐配置
系统 SHALL 在设置界面提供 AI 分组，含启用开关、服务商、模型、服务基地址、密钥、请求超时与「查词时自动补齐」开关；配置 SHALL 持久化到 `config.json`，其中服务商连接信息与用户行为开关分属不同的配置块。

#### Scenario: 配置持久化
- **WHEN** 用户修改 AI 分组中的任一配置项
- **THEN** 该配置写入 `config.json`，重启应用后仍然生效

#### Scenario: 默认关闭
- **WHEN** 用户首次运行应用
- **THEN** AI 处于关闭状态，应用不发起任何 AI 请求

#### Scenario: 已开启但密钥为空时不请求
- **WHEN** AI 已开启但密钥为空
- **THEN** 系统不发起 AI 请求，并在 AI 分组提示需要填写密钥

#### Scenario: 自动补齐可关闭
- **WHEN** 用户关闭「查词时自动补齐」
- **THEN** 查词时不再自动发起 AI 请求，改由用户在该词的 AI 内容区块手动触发

### Requirement: AI 密钥来源
系统 SHALL 按 `LUPA_AI_KEY` 环境变量优先于 `config.json` 中密钥的顺序解析 AI 密钥；界面 SHALL 明确告知密钥以明文保存在 `config.json`，且密钥输入 SHALL 默认以掩码显示。

#### Scenario: 环境变量优先
- **WHEN** 用户设置了 `LUPA_AI_KEY` 且 `config.json` 中也存有密钥
- **THEN** 系统使用环境变量中的密钥

#### Scenario: 明文保存提示
- **WHEN** 用户查看 AI 分组
- **THEN** 界面说明密钥以明文保存在 `config.json` 中，密钥输入框默认以掩码显示

#### Scenario: 回落到配置文件
- **WHEN** 用户未设置 `LUPA_AI_KEY` 但 `config.json` 中存有密钥
- **THEN** 系统使用 `config.json` 中的密钥

### Requirement: AI 缓存统计与清理
系统 SHALL 展示 AI 缓存的条数、命中次数、累计 token 用量与其中不合格条目的数量，并 SHALL 提供独立的清理入口；清理 AI 缓存 MUST NOT 影响任何已保存生词卡片中的例句与搭配。

#### Scenario: 展示缓存统计
- **WHEN** 用户查看 AI 分组
- **THEN** 界面展示缓存条数、命中次数、累计 token 用量与不合格条目数

#### Scenario: 清理缓存
- **WHEN** 用户点击清理 AI 缓存
- **THEN** 系统清空 AI 缓存并更新统计

#### Scenario: 清理不影响已保存内容
- **WHEN** 用户清理 AI 缓存后查看一个此前已保存且含 AI 例句的词
- **THEN** 该词在生词本中的例句与搭配仍然完整可见

#### Scenario: 清理入口独立于媒体缓存
- **WHEN** 用户查看设置界面
- **THEN** 「清理 AI 缓存」与「清理媒体缓存」是两个各自独立的操作
