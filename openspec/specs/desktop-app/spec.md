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

### Requirement: 键盘快捷键与焦点归属

系统 SHALL 提供键盘快捷键：`Ctrl+F` / `Ctrl+B` / `Ctrl+R` / `Ctrl+I` / `Ctrl+E` 分别切换到查词 / 生词本 / 单词复习 / 短语集 / 导出界面；复习界面（单词复习与短语复习）SHALL 支持空格翻面与 `1` `2` `3` `4` 数字键评分（对应 忘了 / 模糊 / 记得 / 简单，小键盘数字等价）。

键盘 SHALL 只作用于当前可见界面：非当前界面的组件 MUST NOT 接收键盘输入，也 MUST NOT 因键盘输入改变应用状态或持久化数据。切换界面后，键盘焦点 SHALL 交由新界面接管，MUST NOT 留在已隐藏的界面。

#### Scenario: 快捷键切换界面

- **WHEN** 用户按下 `Ctrl+B`
- **THEN** 界面切换到生词本

#### Scenario: 复习翻面与评分

- **WHEN** 用户在当前可见的复习界面按下空格翻面后按下 `3`
- **THEN** 该卡按「记得」评分，界面推进该卡的调度状态并写入复习记录

#### Scenario: 未翻面时数字键不评分

- **WHEN** 用户在当前可见的复习界面、卡片尚未翻面时按下 `1`-`4`
- **THEN** 该卡不产生评分，调度状态与复习记录保持不变

#### Scenario: 离开复习界面后数字键不评分

- **WHEN** 用户在复习界面翻面后切换到其它界面，并按下 `1`-`4`
- **THEN** 复习卡片的调度状态与复习记录保持不变

#### Scenario: 离开查词界面后输入不进入隐藏搜索框

- **WHEN** 用户在查词界面输入内容后切换到其它界面，并在其它界面输入字符
- **THEN** 隐藏的查词界面搜索框内容与查询结果均不改变

### Requirement: 复习撤销交互

复习界面（单词复习与短语复习）SHALL 支持按 `0`（含小键盘 `0`）撤销最近一次评分。撤销后界面 SHALL 回到被撤销卡片的翻面态，使用户可直接重新评分。不存在可撤销评分时，该按键 SHALL 不产生任何动作。

#### Scenario: 按 0 撤销最近一次评分

- **WHEN** 用户在当前可见的复习界面按下 `0`，且存在可撤销的评分
- **THEN** 该次评分被撤销，界面回到被撤销卡片的翻面态

#### Scenario: 撤销后可直接重新评分

- **WHEN** 用户撤销后按下 `1`-`4`
- **THEN** 系统按新评分推进该卡调度，且只保留这一条复习记录

#### Scenario: 无可撤销评分时按键无动作

- **WHEN** 用户在复习界面按下 `0`，而本次会话尚无评分
- **THEN** 界面与数据均不发生变化

#### Scenario: 非当前界面不响应撤销

- **WHEN** 用户离开复习界面后按下 `0`
- **THEN** 复习数据保持不变
