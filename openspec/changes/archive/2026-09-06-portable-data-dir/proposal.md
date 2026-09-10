## Why

当前桌面版必须设 `LUPA_HOME` 环境变量（或跑 `启动 Lupa.bat`）才能定位数据目录，对"解压即用"的普通用户门槛太高。把默认数据目录改为可执行文件旁的 `lupa_data/` 并让词库随包分发，即可做到**解压 → 双击 exe → 用**，无需任何脚本或环境变量。

## What Changes

- 桌面端数据目录默认值改为 `<exe>/lupa_data`：未设 `LUPA_HOME` 时使用（便携）；设了仍优先（保留与 Python CLI 共享数据的能力）。
- **移除 `~/.lupa` 兜底**：不再作为默认回退路径。
- **统一两处 dataHome**：把 `lib/data/notebook_db.dart` 的 `dataHome()` 与 `lib/data/config.dart` 的 `dataHomeOf()` 合并为单一共享 helper（`lib/data/data_home.dart`），消除并行复制的漂移风险。
- **`schema.sql` 保持从 `<exe>/data/schema.sql` 读取**（Flutter 运行时数据目录），不改。
- 打包：zip 不再需要 `启动 Lupa.bat`；`lupa_data/` 随包分发（含 `dict.sqlite`），用户解压即用。
- 更新相关错误文案（`main.dart`、`search_page.dart`）与 README/打包说明。

## Capabilities

### New Capabilities
- 无。

### Modified Capabilities
- `desktop-app`: 新增"默认数据目录"需求——未设 `LUPA_HOME` 时，数据默认存于可执行文件旁的 `lupa_data/`，且不再回退到 `~/.lupa`。属 spec 级行为变更。

## Impact

- **代码**：`lib/data/notebook_db.dart`（`dataHome`）、`lib/data/config.dart`（`dataHomeOf`）、新增 `lib/data/data_home.dart`、`lib/main.dart` 与 `lib/pages/search_page.dart` 的错误文案。
- **打包**：zip 结构去掉 `启动 Lupa.bat`；`lupa_data/` 随包（含 `dict.sqlite`，可含 `config.json`）。用户须把包解压到可写目录。
- **BREAKING**：无。保留 `LUPA_HOME` 优先，CLI 共享不受影响；`~/.lupa` 弃用属路径变更，若已有数据在 `~/.lupa`，将其 `LUPA_HOME` 指向该目录或迁到新 `lupa_data/` 即可（现有文档/CI 均用 `LUPA_HOME`，实际影响面很小）。
