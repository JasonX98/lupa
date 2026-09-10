# Settings Module

## Why

Lupa 桌面版已有查词 / 生词本 / 复习 / 导出四个页面，但缺少一个统一设置入口。当前 `config.json` 只存服务商 URL，主题切换是一个无持久化的侧栏循环按钮。设计文档《Lupa 桌面版 UI 设计方案 v1.0》与高保真原型定义了四组设置页（外观 / 发音 / 复习 / 数据），需要落地。同时用户需要一个能"运行时切换数据目录"的能力，用于换机迁移或改用其它数据位置。

## What Changes

- 新增**设置页**（外观 / 发音 / 复习 / 数据四组），统一管理：主题、释义字号、显示英文释义、默认口音、TTS 与音标服务商 URL、媒体缓存统计与清理、调度算法、复习时自动朗读、数据目录、词库信息、备份生词本。
- 设置写入 `config.json` 的嵌套 `settings` 块；新增 `saveConfig()`，写回磁盘 + 更新内存配置 + `notifyListeners`。
- **BREAKING**：数据目录解析优先级改为 `settings.dataDir` 覆盖 > `LUPA_HOME` > `<exe>/lupa_data`。
- **BREAKING**：支持运行时切换数据目录，切换时把 `dict.sqlite` + `notebook.sqlite` + `exports/` 复制到目标目录（目标目录为空时提供"复制现有数据 / 新开空白生词本"两种选择）。
- 移除侧栏底部无持久化的主题循环切换按钮，主题统一走设置页。
- 新增媒体缓存统计（条数 / 体积 / 命中次数）与一键清理。
- 新增"备份生词本"（复制 `notebook.sqlite` 为带时间戳的备份文件）。

**Non-goals**（不在此变更内）：
- 每日新词上限（暂不实现，设置页不渲染该行，config 不含该键）。
- FSRS 调度（v2 规划，设置页仅展示"固定间隔"为当前选项）。
- 划词迷你窗（P2，另立变更）。
- 数据页导入功能（v1.1，另立变更）。
- 统计页与短语集（另立变更）。

## Capabilities

### New Capabilities
- `settings`: 设置页四组行为、`config.json` 的 `settings` 块契约、`saveConfig` 写回、数据目录运行时切换与复制、媒体缓存统计与清理、备份生词本。

### Modified Capabilities
- `desktop-app`: "默认数据目录"要求更新为支持 `settings.dataDir` 覆盖，解析优先级为 `settings.dataDir` > `LUPA_HOME` > `<exe>/lupa_data`。

## Impact

- `desktop/lib/data/config.dart` — `defaultConfig` 增加 `settings` 块；新增 `saveConfig()`。
- `desktop/lib/data/data_home.dart` — 数据目录解析顺序加入 `settings.dataDir` 覆盖。
- `desktop/lib/state/app_state.dart` — 设置状态（主题 / 字号 / 口音 / 英文释义 / 自动朗读）；`switchDataDir()`；设置读写。
- `desktop/lib/pages/settings_page.dart` — 新增，四组表单页。
- `desktop/lib/widgets/app_shell.dart` — 移除侧栏主题循环切换按钮，侧栏底部加"设置"入口。
- `desktop/lib/widgets/switch_lupa.dart`、`seg_control.dart` — 新增设计组件。
- `desktop/lib/data/notebook_db.dart` — 新增 `mediaCacheStats()` / `clearMediaCache()`。
- `desktop/lib/pages/search_page.dart` — 释义字号 / 是否显示英文释义，从设置取值。
- 备份生词本：数据层新增备份函数。
