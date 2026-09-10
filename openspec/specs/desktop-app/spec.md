# Desktop App Specification

## Purpose

为 Lupa 提供 Windows 桌面图形界面，把查词 / 生词本 / 复习 / 发音 / 导出这些能力以可视化交互呈现给普通用户，并确保用户数据全部保存在本地。

## Requirements

### Requirement: 查词界面
系统 SHALL 提供查词界面，用户输入单词后可看到该词的音标、中英释义、词形变化与考纲标签；未收录时给出提示。

#### Scenario: 展示词条
- **WHEN** 用户在查词界面输入一个词库中的单词
- **THEN** 界面展示该词的音标、中英释义、词形变化与考纲标签

#### Scenario: 未收录提示
- **WHEN** 用户输入一个词库中不存在的单词
- **THEN** 界面提示该词未收录

### Requirement: 生词本管理界面
系统 SHALL 提供生词本界面，支持查看生词列表、加入生词与移除生词。

#### Scenario: 展示生词列表
- **WHEN** 用户打开生词本界面
- **THEN** 界面按加入时间倒序展示生词，含状态、复习间隔与下次复习时间

#### Scenario: 加入生词
- **WHEN** 用户在生词本界面把一个词库中的单词加入生词本
- **THEN** 界面更新生词列表并提示已加入

#### Scenario: 移除生词
- **WHEN** 用户在生词本界面移除一个单词
- **THEN** 该词从生词本移除并更新列表

### Requirement: 复习交互
系统 SHALL 提供复习界面，逐卡展示单词并允许用户评分（忘了/Hard/Good/Easy），评分后推进该卡的调度。

#### Scenario: 逐卡答题
- **WHEN** 用户进入复习界面并对一张卡评分
- **THEN** 界面更新该卡的调度状态并显示下一次复习时间

### Requirement: 发音朗读
系统 SHALL 提供一键朗读单词发音的能力，并按口音区分美音/英音。

#### Scenario: 朗读单词
- **WHEN** 用户点击某单词的朗读按钮
- **THEN** 系统播放该词的发音

### Requirement: 导出触发
系统 SHALL 提供导出入口，一键导出生词本为 Anki 牌组包或 CSV。

#### Scenario: 导出 apkg
- **WHEN** 用户选择导出 Anki 牌组包
- **THEN** 系统生成一个可被 Anki 导入的 .apkg 文件

#### Scenario: 导出 CSV
- **WHEN** 用户选择导出 CSV
- **THEN** 系统生成一个 UTF-8 带 BOM 的 CSV 文件

### Requirement: 数据本地存储
系统 SHALL 将词库与生词本数据全部保存在本地，不依赖厂商云端，用户数据归用户所有。

#### Scenario: 离线可用
- **WHEN** 用户在没有网络的条件下使用应用
- **THEN** 查词与生词本功能仍可用，且用户数据保存在本地

### Requirement: 默认数据目录
系统 SHALL 按以下优先级解析数据目录：`settings.dataDir`（`config.json` 中的覆盖值）> `LUPA_HOME` 环境变量 > 可执行文件所在目录下的 `lupa_data/`。系统 SHALL 不再回退到用户主目录下的 `~/.lupa`。

#### Scenario: 未设环境变量时使用便携目录
- **WHEN** 用户未设置 `settings.dataDir` 与 `LUPA_HOME` 环境变量并启动应用
- **THEN** 系统在可执行文件旁的 `lupa_data/` 目录读写词库与生词本数据

#### Scenario: 环境变量优先
- **WHEN** 用户设置了 `LUPA_HOME` 环境变量且未设置 `settings.dataDir`
- **THEN** 系统在该环境变量指向的目录读写数据

#### Scenario: 设置覆盖优先
- **WHEN** 用户在 `config.json` 中设置了 `settings.dataDir`
- **THEN** 系统使用 `settings.dataDir` 指向的目录读写数据，即使 `LUPA_HOME` 已设置

#### Scenario: 无 `~/.lupa` 回退
- **WHEN** 用户未设置 `settings.dataDir` 与 `LUPA_HOME` 且可执行文件旁没有 `lupa_data/`
- **THEN** 系统不在用户主目录的 `~/.lupa` 下读写数据，而是在 `lupa_data/` 按需创建目录
