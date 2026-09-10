## 1. 统一版本号

- [x] 1.1 将 `desktop/pubspec.yaml` 的 `version: 1.0.0+1` 改为 `version: 0.1.0`，重跑 `flutter pub get` 同步 `pubspec.lock`。验证：`grep "^version" desktop/pubspec.yaml` 输出 `0.1.0`，`flutter pub get` 无错。
- [x] 1.2 将 `desktop/lib/widgets/app_shell.dart` 的 UI 显示 `v1.0.0` 改为 `v0.1.0`。验证：`flutter test` 通过且界面/源码显示 `v0.1.0`。
- [x] 1.3 将 `README.md` 的 `v0.2` 版本标签改为 `v0.1.0`（保留功能描述）。验证：`grep -rn "v0\." README.md` 不再出现 `v0.2`，且为 `v0.1.0`。
- [x] 1.4 确认 Python 侧版本一致：`pyproject.toml`、`src/lupa/__init__.py`、`src/lupa/notebook/schema.sql` 与 `desktop/lib/data/schema.sql` 的 meta 均为 `0.1.0`。验证：上述各处 `grep` 结果一致为 `0.1.0`。

## 2. 生成 AGENTS.md

- [x] 2.1 在仓库根目录生成 `AGENTS.md`，含项目定位、双入口与技术栈、常用命令、关键约束（schema.sql 双份同步、纯函数、三段式缓存键、apkg 稳定 guid、数据目录 LUPA_HOME 优先、版本号两处同步）、验证方式。验证：`AGENTS.md` 存在且覆盖上述章节，文档中的命令（`flutter run -d windows`、`flutter test`、`lupa --help`）可直接照抄执行。

## 3. 集成验证

- [x] 3.1 重跑 `flutter test` 与 `lupa version`，确认桌面 UI 与 CLI 版本均为 `0.1.0`。验证：`lupa version` 输出 `Lupa v0.1.0`，`flutter test` 全 PASS。
