## 1. 统一数据目录解析

- [x] 1.1 新建 `lib/data/data_home.dart`，实现唯一 `dataHome()`：`LUPA_HOME` 优先，否则 `<p.dirname(Platform.resolvedExecutable)>/lupa_data`，不再回退 `~/.lupa`。验证：写一次快速 Dart 探针，设与不设 `LUPA_HOME` 各打印一次路径，确认分别命中 `LUPA_HOME` 与 `<exe>/lupa_data`。
- [x] 1.2 让 `lib/data/notebook_db.dart` 的 `dataHome()` 与 `lib/data/config.dart` 的 `dataHomeOf()` 改为调用共享 `data_home.dart`，删除本地复制。验证：`flutter analyze` 无未使用/重复定义告警；两处解析结果与 1.1 探针一致。

## 2. 更新文案与文档

- [x] 2.1 更新 `lib/main.dart` 启动失败文案与 `lib/pages/search_page.dart` 未收录提示，将 `~/.lupa`/`LUPA_HOME/dict.sqlite` 改为 `lupa_data/` 相关表述。验证：构造未收录/启动失败场景，界面提示指向 `lupa_data/`。
- [x] 2.2 更新根 `README.md` 与打包说明：默认数据目录为 `lupa_data/`，移除 `启动 Lupa.bat` 步骤，注明"解压到可写目录"及 dev 需显式设 `LUPA_HOME`。验证：文档中不再出现 bat 步骤，且含 `lupa_data/` 默认说明。

## 3. 打包与随包数据

- [x] 3.1 生成发布 zip 结构：`lupa.exe` + 运行时 `data/`（含 `app.so`/`icudtl.dat`/`flutter_assets`/`schema.sql`）+ `lupa_data/`（含 `dict.sqlite`、`config.json`），不含 bat 脚本。验证：解包后文件清单符合上述结构。
- [x] 3.2 验证解压即用：不设 `LUPA_HOME`、不跑 bat，直接双击 `lupa.exe`，数据读写落在包内 `lupa_data/`。验证：首次运行后 `lupa_data/` 出现 `notebook.sqlite`、`config.json`，导出后出现 `exports/`。

## 4. 集成验证

- [x] 4.1 重跑 `tool/verify_*.dart`（均显式设 `LUPA_HOME`）与 `flutter test`，确认无回归。验证：全部 PASS（e2e 15/15、其余 verify_* ALL PASS、flutter test 3/3）。
- [x] 4.2 端到端确认便携默认与覆盖语义：设 `LUPA_HOME` 时优先（与 CLI 共享）；未设时走包内 `lupa_data/`。验证：两种场景各自正确读写，且不再访问 `~/.lupa`。
