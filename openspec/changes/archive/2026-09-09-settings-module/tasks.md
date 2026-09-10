# Settings Module — Tasks

> 默认决策（可覆盖）：备份生词本写入**数据目录根**（`dataHome()/lupa-backup-<时间戳>.sqlite`）；「复制现有数据」时**一并拷贝 `exports/`**（与 spec 场景一致）。

## 1. Config 层

- [x] 1.1 在 `desktop/lib/data/config.dart` 的 `defaultConfig` 增加 `settings` 块默认值（`theme:"system"` / `defFontSize:14` / `showEnglish:true` / `defaultAccent:"us"` / `reviewAutoRead:false` / `dataDir:null`），并验证 `loadConfig()` 在旧 config（无 `settings` 键）下仍返回含默认 `settings` 的合并结果（改用深合并，settings 缺键补默认）
- [x] 1.2 新增 `saveConfig()`：写回合并后的整份 config 到磁盘、刷新数据目录覆盖缓存；验证写回后文件内容与内存一致（内存更新 + notify 在 4.2 接 AppState 时完成）
- [x] 1.3 确认 `dataDir` 仅在显式更改数据目录时写入，不在写其它设置时固化为当前路径；用单测断言该行为（test/settings_config_test.dart）

## 2. 数据目录解析

- [x] 2.1 修改 `desktop/lib/data/data_home.dart` 的 `dataHome()`，解析顺序改为 `settings.dataDir` > `LUPA_HOME` > `<exe>/lupa_data`；新增 `configHome()` 拆分 config.json 与数据目录（LUPA_HOME 优先分支由 verify_e2e 以真实 LUPA_HOME 覆盖）
- [x] 2.2 为 `dataHome()` 补充单测（覆盖三优先级 + 未设覆盖时走 LUPA_HOME/便携目录），验证解析结果正确（test/settings_config_test.dart 的 dataHome 与 resolveDataDirOverride 组）

## 3. 数据层新增函数

- [x] 3.1 在 `desktop/lib/data/notebook_db.dart` 新增 `mediaCacheStats()`，返回 `audio_cache` / `phonetic_cache` 的条数、体积（`SUM(size_bytes)`）与命中次数；用临时库验证统计正确
- [x] 3.2 新增 `clearMediaCache()`，清空 `audio_cache` 与 `phonetic_cache`；验证清理后统计归零
- [x] 3.3 新增 `backupNotebook(nbPath)`（`desktop/lib/data/data_files.dart`），把 `notebook.sqlite` 复制为带时间戳的备份文件（默认存数据目录根）；验证生成文件且内容与源一致
- [x] 3.4 新增 `copyDataDir(src, dst)`，复制 `notebook.sqlite` + `dict.sqlite` + `exports/`；验证目标目录三件套齐全
- [x] 3.5 扩展 `desktop/tool/verify_media.dart` 覆盖 `mediaCacheStats` / `clearMediaCache`，并新增对备份 / 复制函数的验证；运行通过（临时库，不污染真实数据）

## 4. AppState 设置状态

- [x] 4.1 `AppState.init()` 从 `config['settings']` 读取 `theme` / `defFontSize` / `showEnglish` / `defaultAccent` / `reviewAutoRead` 并写入状态；验证启动后状态与 config 一致（test/settings_state_test.dart）
- [x] 4.2 为各设置新增 setter（`setTheme` / `setDefFontSize` / `setShowEnglish` / `setDefaultAccent` / `setReviewAutoRead`），写 config + `saveConfig()` + `notifyListeners`；验证变更持久化
- [x] 4.3 新增 `switchDataDir(newDir)`：校验目标目录、按需复制或新开、重解析 `nbPath`/`dictDb`、写 `settings.dataDir` 并 `saveConfig()`、`refresh()`、清空 `_phonetics` 缓存；用临时目录验证完整切换
- [x] 4.4 新增数据目录差异提示（当 `LUPA_HOME` 已设且与 `settings.dataDir` 不同时）；提取纯函数 `dataDirDivergent` 单测 true/false 分支

## 5. 设置页 UI

- [x] 5.1 新增 `desktop/lib/widgets/switch_lupa.dart`（38×22 开关），验证默认 / 开 / 关三态与拨动动画
- [x] 5.2 新增 `desktop/lib/widgets/seg_control.dart`（三段选择），验证选中态与回调
- [x] 5.3 新增 `desktop/lib/pages/settings_page.dart`，按外观 / 发音 / 复习 / 数据四组渲染全部设置项；验证四组齐全且各控件回显当前设置
- [x] 5.4 数据目录行接入文件选择器（`file_selector` 的「更改」）与打开文件夹（「打开」）；选中空目录时弹「复制现有数据 / 新开空白」，非空目录直接切换
- [x] 5.5 验证设置页在 `flutter test` 冒烟中可构建、四组渲染正确（test/settings_ui_test.dart）

## 6. 外壳与页面接入

- [x] 6.1 `desktop/lib/widgets/app_shell.dart` 移除侧栏底部主题循环切换按钮，侧栏底部加「设置」入口；验证侧栏不再有主题按钮且能进入设置页
- [x] 6.2 `desktop/lib/pages/search_page.dart` 按 `defFontSize` / `showEnglish` 渲染释义；验证改字号与关闭英文释义后查词页呈现变化
- [x] 6.3 复习页接入「复习时自动朗读」：翻面时按 `defaultAccent` 自动 `speak`；验证开启后翻面自动朗读
- [x] 6.4 发音按钮与复习自动朗读使用 `defaultAccent` 作为默认口音（查词页默认口音按钮排前）


## 7. 回归验证

- [x] 7.1 运行 `flutter analyze`，无新增错误 / 警告（12 issues = 基线，无新增）
- [x] 7.2 运行 `flutter test`，全部通过（19 passed）
- [x] 7.3 运行 `desktop/tool/verify_*.dart` 六组（含扩展后的 media 组），全部通过（dict_query / notebook_db / notebook_repo / export / e2e 15/15 / media 含 3.1-3.4）
- [x] 7.4 端到端流程：改主题 → 改字号 → 关英文释义 → 改默认口音 → 清理缓存 → 备份生词本 → 切换到新目录（复制）→ 再切回；已用 headless 等价测试覆盖（test/settings_state_test.dart「7.4」）。GUI 点击冒烟建议发布前由人工补跑一次
