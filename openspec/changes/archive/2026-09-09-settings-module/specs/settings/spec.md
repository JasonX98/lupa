## Purpose

为 Lupa 桌面版提供统一的设置模块，让用户配置外观、发音、复习与数据相关行为，并持久化到本地 `config.json`；同时支持运行时切换数据目录、管理媒体缓存与备份生词本。

## ADDED Requirements

### Requirement: 提供设置界面
系统 SHALL 提供设置界面，按外观 / 发音 / 复习 / 数据四组呈现可配置项。

#### Scenario: 打开设置页
- **WHEN** 用户点击侧栏"设置"入口
- **THEN** 界面展示四组设置表单

### Requirement: 配置持久化
系统 SHALL 将用户设置写入 `config.json` 的 `settings` 块，并在应用启动时读取该块应用设置。

#### Scenario: 修改设置后持久化
- **WHEN** 用户修改任一设置项
- **THEN** 该设置写入 `config.json` 的 `settings` 块，且界面立即反映该值

#### Scenario: 启动时加载设置
- **WHEN** 应用启动
- **THEN** 系统从 `config.json` 的 `settings` 块读取设置并应用

### Requirement: 主题设置
系统 SHALL 提供主题选择（跟随系统 / 浅色 / 深色），该选择持久化到 `config.json`，并统一在设置页管理。

#### Scenario: 切换主题
- **WHEN** 用户在设置页选择"深色"
- **THEN** 界面切换为深色主题，且该选择写入 `config.json`

#### Scenario: 侧栏不提供主题切换
- **WHEN** 用户查看侧栏底部
- **THEN** 侧栏显示"设置"入口，不显示主题循环切换按钮

### Requirement: 释义字号
系统 SHALL 允许用户设置释义字号（范围 12–18px，默认 14px），并影响查词页释义的渲染字号。

#### Scenario: 调整释义字号
- **WHEN** 用户将释义字号设为 18px
- **THEN** 查词页中文与英文释义按 18px 渲染

### Requirement: 显示英文释义
系统 SHALL 提供"显示英文释义"开关，关闭后查词页不再渲染英文释义。

#### Scenario: 关闭英文释义
- **WHEN** 用户关闭"显示英文释义"
- **THEN** 查词页只显示中文释义，不显示英文释义

### Requirement: 默认口音
系统 SHALL 允许设置默认口音（美音 / 英音），影响发音按钮与复习自动朗读所使用的口音。

#### Scenario: 设置默认口音
- **WHEN** 用户将默认口音设为"英音"
- **THEN** 发音按钮与复习自动朗读默认播放英音

### Requirement: 服务商地址可配置
系统 SHALL 允许用户编辑 TTS 与音标服务商地址，保存后立即生效于后续发音与音标请求。

#### Scenario: 修改 TTS 地址
- **WHEN** 用户修改 TTS 服务商地址并保存
- **THEN** 后续朗读使用新地址

### Requirement: 媒体缓存统计与清理
系统 SHALL 展示媒体缓存统计（条数 / 体积 / 命中次数），并允许用户一键清理音标与音频缓存。

#### Scenario: 展示缓存统计
- **WHEN** 用户打开发音组
- **THEN** 界面展示已缓存条数、总体积与命中次数

#### Scenario: 清理缓存
- **WHEN** 用户点击"清理缓存"
- **THEN** 系统清空音标与音频缓存，并更新统计

### Requirement: 调度算法选择
系统 SHALL 在复习组展示调度算法选择，当前仅提供"固定间隔"，"FSRS"标记为 v2 规划。

#### Scenario: 查看调度算法
- **WHEN** 用户打开复习组
- **THEN** 界面显示"固定间隔"为当前选项，且"FSRS"标注为 v2 规划

### Requirement: 复习时自动朗读
系统 SHALL 提供"复习时自动朗读"开关，开启后复习卡翻面时自动播放该词发音。

#### Scenario: 开启自动朗读
- **WHEN** 用户开启"复习时自动朗读"
- **THEN** 复习卡翻面时自动播放该词发音

### Requirement: 数据目录运行时切换
系统 SHALL 允许用户运行时切换数据目录；当目标目录为空时提供"复制现有数据"或"新开空白生词本"两种选择；切换后应用使用新目录的数据。

#### Scenario: 切换到已有数据目录
- **WHEN** 用户选择已包含 `notebook.sqlite` 的目录
- **THEN** 应用直接切换到该目录，不复制数据

#### Scenario: 切换到空目录并复制
- **WHEN** 用户选择空目录并选择"复制现有数据"
- **THEN** 应用把 `notebook.sqlite`、`dict.sqlite` 与 `exports/` 复制到新目录并切换

#### Scenario: 切换到空目录并新开
- **WHEN** 用户选择空目录并选择"新开空白生词本"
- **THEN** 应用在新目录创建空白生词本并切换

### Requirement: 备份生词本
系统 SHALL 允许用户一键备份生词本，复制 `notebook.sqlite` 为带时间戳的备份文件。

#### Scenario: 备份生词本
- **WHEN** 用户点击"立即备份"
- **THEN** 系统生成一份带时间戳的 `notebook.sqlite` 备份文件
