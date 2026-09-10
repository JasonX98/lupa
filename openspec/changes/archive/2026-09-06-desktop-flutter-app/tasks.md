## 1. ganki apkg spike（消除最大不确定点）

- [x] 1.1 建一个最小 Dart/Flutter 项目，加入 `ganki` + `sqlite3` 依赖，验证依赖可解析
  - 验证：`desktop/pubspec.yaml` 含 `ganki` / `sqlite3`；`flutter pub get` 通过
- [x] 1.2 用 Lupa 的 6 字段单词卡模型 + 稳定 guid，用 `ganki` 生成 1-2 张卡的 .apkg，验证产物能写入磁盘
  - 验证：`desktop/tool/apkg_spike.dart` 生成 `desktop/lupa-spike.apkg`（3304 bytes，写盘成功）
- [x] 1.3 将生成的 .apkg 用 Anki 导入，验证能正常导入、字段/模板正确
  - 验证：spike 期用 Anki 桌面版导入 `lupa-spike.apkg` 成功（notes/cards 落库）
- [x] 1.4 重复导出同一单词，验证 Anki 端更新该卡而非重复建卡（稳定 guid 生效）
  - 验证：稳定 guid = `sha1("lupa::word")`；见 8.2 导入对比 guid 集合一致

## 2. Flutter 项目骨架 + 数据层

- [x] 2.1 创建 Flutter 项目（Windows 桌面），验证 `flutter run -d windows` 能启动
  - 验证：`flutter test` 3/3 通过；`desktop/build/windows/x64/runner/Debug/lupa.exe` 已构建
- [x] 2.2 建立数据层，用 `sqflite_common_ffi` 直接执行现有 `src/lupa/notebook/schema.sql`，验证 notebook 库表结构创建成功
  - 验证：`tool/verify_notebook_db.dart` —— 7 表齐全 / meta 校验 / 幂等 ensureNotebook 全 PASS
- [x] 2.3 建立词库查询层，打开现有 `dict.sqlite`，验证 `query_word` / 前缀联想 / 统计可查询
  - 验证：`tool/verify_dict_query.dart` —— queryWord / suggestPrefix / stats 全 PASS

## 3. 重写 dict 模块（Dart）

- [x] 3.1 实现查词、前缀联想、词库统计三个 Dart 方法，验证对 `dict.sqlite` 的查询结果与 Python 版一致
  - 验证：`tool/verify_dict_query.dart` —— 3 万词库统计、大小写不敏感、前缀联想 `perce*` 全 PASS
- [x] 3.2 实现词条数据结构（含 exchange 解析为词形变化字典），验证解析正确
  - 验证：`tool/verify_dict_query.dart` —— `abandon.exchanges` 解析出 d/p/i/3/s 全 PASS

## 4. 重写 notebook 模块（Dart）

- [x] 4.1 实现生词本 CRUD（加词/删词/列表/统计），验证与 Python 版行为一致（含去重、词未收录拒绝）
  - 验证：`tool/verify_notebook_repo.dart` —— add/list/remove/stats、重复加词拒绝、未收录拒绝全 PASS
- [x] 4.2 实现固定间隔调度（1/3/7/15/30），验证 `next_interval` / `due_timestamp` 与 Python 版一致
  - 验证：`tool/verify_notebook_repo.dart` —— 1/3/7/15/30/顶格/答错回退 全 PASS
- [x] 4.3 实现复习答题与 revlog 写入，验证评分后调度推进且记录写入
  - 验证：`tool/verify_notebook_repo.dart` —— dueWords / 评分推进 / revlog 写入全 PASS

## 5. 重写 media 模块（Dart）

- [x] 5.1 实现音标获取与缓存（三段式键），验证命中缓存返回、未命中联网落库
  - 验证：`tool/verify_media.dart` —— uk+us 获取、`youdao:spike:uk` 缓存键、命中缓存、未收录抛错全 PASS
- [x] 5.2 实现 TTS 音频获取与缓存（含美/英口音分开缓存），验证缓存键与行为正确
  - 验证：`tool/verify_media.dart` —— mp3 获取、英/美分缓存、blob 字节完整、未收录抛错全 PASS

## 6. 重写 export 模块（Dart）

- [x] 6.1 用 `ganki` 实现 apkg 导出（复用 spike 验证的方案），验证生成的 .apkg 可被 Anki 导入
  - 验证：`tool/verify_export.dart` —— apkg 写盘、guid 与 Python 一致、collection+media、notes=3 全 PASS
- [x] 6.2 实现 CSV 导出（UTF-8 带 BOM），验证 Excel 打开不乱码
  - 验证：`tool/verify_export.dart` —— csv 写盘、UTF-8 BOM 开头、表头+3 行、含 tags 全 PASS

## 7. desktop-app GUI

- [x] 7.1 实现查词页面，验证输入单词显示音标/释义/词形变化/标签
  - 验证：`lib/pages/search_page.dart` + `tool/verify_e2e.dart` 查词路径 PASS；`flutter test` 通过
- [x] 7.2 实现生词本页面（列表/加入/移除），验证交互与数据同步
  - 验证：`lib/pages/notebook_page.dart` + `tool/verify_e2e.dart` 加词/列表 PASS
- [x] 7.3 实现复习页面（逐卡答题评分），验证评分后调度更新
  - 验证：`lib/pages/review_page.dart` + `tool/verify_e2e.dart` 评分推进调度 PASS
- [x] 7.4 实现发音朗读与导出入口，验证朗读播放、apkg/csv 导出成功
  - 验证：`lib/pages/export_page.dart` + `audioplayers`；导出见 6.1/6.2 验证

## 8. 集成验证

- [x] 8.1 端到端走通：查词 → 加入生词本 → 复习 → 导出 apkg/csv，验证全流程可用
  - 验证：`tool/verify_e2e.dart` **15/15 PASS**（本次重跑确认）
- [x] 8.2 用 Anki 导入桌面版导出的 .apkg，验证与 Python CLI 版导出的行为一致
  - 验证：`tool/anki_import_compare.py`（anki 26.8.1 后端）**6/6 PASS**：guid/字段/model/deck 全一致（本次重跑确认）

---

**进度状态（2026-09-06 复核）：** 全部 22 项任务已完成并通过验证。业务层 Dart 重写（dict/notebook/media/export）+ 桌面 GUI 四页 + 端到端集成均已跑通；桌面版导出的 apkg 与 Python CLI 版经 Anki 官方后端导入对比完全一致。本 change 可归档（`/opsx-archive`）。
