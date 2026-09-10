# Settings Module — Design

## Context

当前 `config.json` 只存 `default_provider` + `providers`（URL 模板），由 `desktop/lib/data/config.dart` 以**浅合并**加载（遍历 `defaultConfig` 顶层键，用户文件按顶层整块覆盖）。`data_home()`（`desktop/lib/data/data_home.dart`）按 `LUPA_HOME` > `<exe>/lupa_data` 解析数据目录。`AppState` 里的 `themeMode` 是纯内存值，未持久化；侧栏底部有一个 `light→dark→system` 循环切换按钮。

关键事实：数据层每个函数**按操作开关数据库**（`_openNb` 用 `singleInstance: false`，函数内开、`finally` 关；`ensureNotebookDb` 缺则建）。**不存在长期连接**——这使"运行时切换数据目录"只需改两个路径字符串并刷新，无需拆连接。

## Goals / Non-Goals

**Goals:**
- 设置页四组（外观 / 发音 / 复习 / 数据）落地，统一管理。
- 设置写入 `config.json` 的嵌套 `settings` 块，`saveConfig()` 写回 + 更新内存 + 通知。
- 数据目录解析优先级改为 `settings.dataDir` > `LUPA_HOME` > `<exe>/lupa_data`（方案甲）。
- 运行时切换数据目录，且支持复制数据（`notebook.sqlite` + `dict.sqlite` + `exports/`）到新目录。
- 媒体缓存统计与一键清理；备份生词本。
- 移除侧栏主题循环切换，主题统一走设置页。

**Non-Goals:**
- 每日新词上限（设置页不渲染该行，config 不含该键）。
- FSRS 调度（仅展示"固定间隔"，FSRS 标注 v2）。
- 划词迷你窗、导入功能、统计页、短语集（另立变更）。
- Python CLI 与 Dart 侧共享行为契约（Python 仅作 MVP 验证，不作为后续契约）。

## Decisions

### 1. 配置 schema：嵌套 `settings` 块
采用嵌套块，避免污染 `providers`：

```json
{
  "default_provider": "youdao",
  "providers": { "youdao": { "phonetic_url": "...", "tts_url": "..." } },
  "settings": {
    "theme": "system",
    "defFontSize": 14,
    "showEnglish": true,
    "defaultAccent": "us",
    "reviewAutoRead": false,
    "dataDir": null
  }
}
```

- `settings` 是**扁平对象**，现有浅合并（顶层整块覆盖）可兼容——`defaultConfig` 需补 `settings` 默认值，否则浅合并会把它丢掉。
- 备选：顶层拍平。否决——会与 `default_provider`/`providers` 混在一层，语义不清，也难扩展。

### 2. `saveConfig()` 写回策略
新增 `saveConfig()`：把**合并后的整份 config**（默认 + 用户覆盖）写回磁盘、更新内存 `config` 字段、`notifyListeners`。

- 写"整份合并结果"而非"仅增量"，使 `config.json` 更可读、可直接文本编辑，符合设计文档意图。
- `dataDir` 只在用户**显式更改数据目录**时写入，**不得**在写其它设置时顺手把它固化为当前解析路径——否则会把来自 `LUPA_HOME` 的路径"钉死"，破坏共享契约。
- 备选：只写增量键。否决——增量写法难读，且合并后写回更一致。

### 3. 数据目录优先级（方案甲）
`dataHome()` 解析顺序改为：
1. `settings.dataDir`（config 覆盖，用户显式设置）
2. `LUPA_HOME` 环境变量
3. `<exe>/lupa_data`

- 选方案甲而非乙，因为用户要求"运行时切换真正可用"。
- 代价：Python CLI 只读 `LUPA_HOME`，不跟随 `settings.dataDir`。因 Python 仅作 MVP 验证，此代价可接受；设置页在 `LUPA_HOME` 已设且与覆盖不同时，给出分歧提示。

### 4. 数据目录运行时切换
`switchDataDir(newDir)` 流程：
1. 校验目标目录。
2. 目标已含 `notebook.sqlite` → 直接切换。
3. 目标为空 → 弹选择：「复制现有数据」（拷贝 `notebook.sqlite` + `dict.sqlite` + `exports/`）或「新开空白生词本」（仅建空白 `notebook.sqlite`）。
4. 重新解析 `nbPath` / `dictDb`，写 `settings.dataDir` 并 `saveConfig()`。
5. `refresh()` 重拉统计 / 列表 / 到期队列。
6. 清空 `_phonetics` 内存缓存（音标缓存为 DB 背书，切库后旧词条无意义）。

- 由于数据层无长期连接，切换不需要拆连接；各操作按新路径开关库即可。
- **`dict.sqlite` 跟随复制**（用户决定）：空目录选"复制"时一并拷贝，避免新目录缺词库导致查词中断。

### 5. 媒体缓存统计与清理
在 `desktop/lib/data/notebook_db.dart` 新增：
- `mediaCacheStats()`：`audio_cache`（条数、`SUM(size_bytes)`、`SUM(hit_count)`）+ `phonetic_cache`（条数、命中次数）。
- `clearMediaCache()`：清空 `audio_cache` 与 `phonetic_cache`。

### 6. 备份生词本
新增数据层函数，把 `notebook.sqlite` 复制为带时间戳的备份文件（如 `lupa-backup-20260906-1015.sqlite`），存于数据目录或 `exports/`。

### 7. 主题入口统一
移除 `app_shell.dart` 底部 `light→dark→system` 循环按钮；侧栏底部加「设置」入口（指向设置页）。主题只在设置页改。

## Risks / Trade-offs

- **[方案甲导致 Python 与 Dart 数据目录分歧]** → 设置页在 `LUPA_HOME` 已设且与覆盖不同时给出提示；用户如需 CLI 共享，应保持两者一致。
- **[写回整份 config 覆盖用户手改的未知键]** → 浅合并只保留 `defaultConfig` 已知顶层键；若用户手工加了未知键会被丢弃。缓解：写回时保留用户文件未知顶层键，或文档说明仅受支持的键会被保留。当前 MVP 阶段可接受，记录为已知限制。
- **[复制数据到空目录涉及 8MB dict.sqlite]** → 仅当用户选"复制现有数据"时执行一次；复制前提示体积。
- **[切换后 `_phonetics` 缓存残留]** → `switchDataDir()` 显式清空，避免跨库混用。

## Migration Plan

1. 先改 `config.dart`（`defaultConfig` 加 `settings` + `saveConfig()`），保持兼容（无 `settings` 键时用默认值）。
2. 改 `data_home.dart` 解析顺序，老用户（已有 `config.json` 无 `settings`）仍走 `LUPA_HOME`/便携目录。
3. 加数据层函数（`mediaCacheStats` / `clearMediaCache` / 备份）。
4. 建 `settings_page.dart` 与组件，接 `AppState`。
5. 改 `app_shell.dart`（移除主题循环按钮，加设置入口）。
6. 改 `search_page.dart` 按设置渲染字号/英文释义。
7. 用 `desktop/tool/verify_*.dart` 与 `flutter test` 回归。

## Open Questions

- 备份文件存放位置：数据目录根还是 `exports/`？（二者均可，后续定；不影响 specs/任务拆分）
- 复制数据到空目录时，`exports/` 是否也拷贝？当前设计倾向一并拷贝，可后续细化。
