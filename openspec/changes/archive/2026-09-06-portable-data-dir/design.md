## Context

桌面端目前通过 `LUPA_HOME` 环境变量（未设则回退 `~/.lupa`）定位数据目录，该解析逻辑在 `lib/data/notebook_db.dart` 的 `dataHome()` 与 `lib/data/config.dart` 的 `dataHomeOf()` 里**各写了一份**。发布需要 `启动 Lupa.bat` 设 `LUPA_HOME` 才能定位包内数据，对"解压即用"的用户门槛高。动机见 `proposal.md - Why`。

当前数据目录含：`dict.sqlite`（词库，只读）、`notebook.sqlite`（生词本 + 3 个缓存表）、`config.json`、`exports/`。`schema.sql` 是只读建库模板，从 `<exe>/data/schema.sql` 读取（Flutter 运行时数据目录），不走数据目录。

## Goals / Non-Goals

**Goals:**
- 未设 `LUPA_HOME` 时，数据默认落在可执行文件旁的 `lupa_data/`，实现解压即用。
- 移除 `~/.lupa` 兜底，消除"要不要设环境变量"的困惑。
- 把两处 dataHome 收敛为单一共享 helper，杜绝并行逻辑漂移。

**Non-Goals:**
- 不做正规安装器/Program Files 安装（本 change 面向便携 zip；安装器与 `%LOCALAPPDATA%` 留待后续）。
- 不改变 Python CLI 的行为（CLI 的 `data_home()` 与 `LUPA_HOME` 语义不变，二者靠 `LUPA_HOME` 共享）。
- 不把 `schema.sql` 挪进 `lupa_data/`（见 Decision 3）。

## Decisions

### 1. 默认数据目录 = `<exe>/lupa_data`，删 `~/.lupa` 兜底
- 解析顺序：`LUPA_HOME`（若设置且非空）> `<p.dirname(Platform.resolvedExecutable)>/lupa_data`。
- 基准用 `p.dirname(Platform.resolvedExecutable)`：发布版 `resolvedExecutable` 即 `lupa.exe`，`lupa_data` 落在包根目录，直观且可写。
- **替代方案**：保留 `~/.lupa` 兜底 → 拒绝。没有可写性探测时它是死代码（`lupa_data` 总能解析出来）；加探测则复杂度不值。
- **替代方案**：用 `%LOCALAPPDATA%/Lupa` → 拒绝。数据落到系统目录，不满足"解压即用/便携"，且用户无法直接看到自己的数据。

### 2. 统一两处 dataHome → 共享 helper
- 新建 `lib/data/data_home.dart`，导出唯一 `dataHome()`；`notebook_db.dart` 与 `config.dart` 都改为调用它。
- 依赖图核实：`config.dart` 不 import `notebook_db.dart`，`notebook_db.dart` 也不 import `config.dart`——`config.dart` 里"避免循环依赖"的注释已过时，可安全收敛。
- **替代方案**：保留两份并各自改 → 拒绝。改一处漏一处即行为漂移，正是本次要消除的隐患。

### 3. `schema.sql` 留在 `data/`
- 维持 `loadSchemaSql()` 现状：`lib/data/schema.sql`（dev/验证）> `<exe>/data/schema.sql`（打包）。
- **替代方案**：挪进 `lupa_data/` → 拒绝。`schema.sql` 是随应用分发的**只读模板**，属应用资源而非用户业务数据；留在 `data/`（与 `app.so`/`icudtl.dat`/`flutter_assets` 同目录）更自然，也无需改候选路径。

## Risks / Trade-offs

- **[解压到只读位置]** → 装在 Program Files 等只读目录时 `lupa_data/` 不可写，无兜底。缓解：使用说明明确"解压到可写目录"；若后续上安装器再引入 AppData（超出本 change）。
- **[`resolvedExecutable` 在 `dart run` 下指向 Dart VM]** → 用 `dart run tool/verify_*.dart` 跑验证脚本时，`resolvedExecutable` 是 `dart.exe`，`lupa_data` 会解析到 Dart 目录，属误路径。缓解：验证脚本均显式设 `LUPA_HOME`（现有运行命令已如此），`flutter test` 不触发数据初始化；此路径仅影响未设 `LUPA_HOME` 的裸跑。
- **[旧 `~/.lupa` 数据"看不见"]** → 移除兜底后，曾依赖 `~/.lupa` 且未设 `LUPA_HOME` 的用户数据不再被读取。缓解：把旧目录迁到新 `lupa_data/` 或设 `LUPA_HOME` 指向之；现有文档/CI 均用 `LUPA_HOME`，实际影响面很小。
- **[dev 模式默认数据位置改变]** → `flutter run` 时 `resolvedExecutable` 指向 `build/.../Debug/lupa.exe`，`lupa_data` 落到构建目录。缓解：dev 流程已设 `LUPA_HOME`；README 注明 dev 应显式设 `LUPA_HOME`。

## Migration Plan

1. 代码：新增 `lib/data/data_home.dart`，改 `notebook_db.dart` / `config.dart` 调用之；更新 `main.dart`、`search_page.dart` 错误文案。
2. 打包：zip 去掉 `启动 Lupa.bat`；`lupa_data/` 随包（含 `dict.sqlite`，可含 `config.json`）；`data/` 保留 `schema.sql`。
3. 验证：重跑 `tool/verify_*.dart`（均设 `LUPA_HOME`）+ `flutter test`；端到端确认解压即用（无 env、无 bat）。
4. 回滚：改回 `dataHome()` 默认分支即可，无数据迁移破坏。

## Open Questions

- 无。三项决议已定；其余为可延后细节（如 UI 是否展示当前数据路径，属体验优化，可后续单独处理）。
