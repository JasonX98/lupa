## Context

Lupa 版本号分散在多处且不一致（Python `0.1.0`、Flutter pubspec `1.0.0+1`、UI 显示 `v1.0.0`、README `v0.2`）。动机见 `proposal.md - Why`。本 change 为纯配置/文档变更，无 spec 级行为变更（`skip_specs: true`）。

## Goals / Non-Goals

**Goals:**
- 所有版本号统一为 `x.y.z` 格式，数值统一为 `0.1.0`。
- 新增 `AGENTS.md`，作为 AI/协作者的项目入口说明。

**Non-Goals:**
- 不引入单一版本号来源/自动构建注入（Python 与 Flutter 是两套打包生态，强耦合代价大于收益）。
- 不改动运行时行为、数据模型、API。

## Decisions

### 1. 版本值 = `0.1.0`，格式 x.y.z（无 build 号）；README 状态标签改写（选 A）
- Python 侧权威：`src/lupa/__init__.py` 的 `__version__`，已是 `0.1.0`。
- Flutter 侧权威：`desktop/pubspec.yaml` 的 `version`，由 `1.0.0+1` → `0.1.0`（去掉 `+1`）。
- UI 显示：`desktop/lib/widgets/app_shell.dart` `v1.0.0` → `v0.1.0`。
- README：`v0.2` → `v0.1.0`（功能描述保留，仅版本标签统一）。
- **替代方案**：保留 `1.0.0+1` → 拒绝，带 build 号不符合 x.y.z 且与 UI/Python 冲突。
- **替代方案**：保持 README 为 `v0.2`（B 方案）→ 用户已选 A，统一为 `0.1.0`。

### 2. `AGENTS.md` 放仓库根目录，面向 AI/协作者
- 章节：项目定位 / 双入口与技术栈 / 常用命令 / 关键约束（schema.sql 双份同步、纯函数、三段式缓存键、apkg 稳定 guid、数据目录 LUPA_HOME 优先、版本号两处同步）/ 验证方式。
- **替代方案**：放 `desktop/` 或作为 `.claude`/`.cursor` 配置 → 拒绝。AGENTS.md 是仓库级约定，根目录最通用、各工具默认读取。

## Risks / Trade-offs

- **[版本来源仍分散]** → Python 与 Flutter 各有一个权威位置，后续可能再漂移。缓解：在 `AGENTS.md` 明确"两处版本号必须同步"。
- **[`pubspec.lock` 内嵌旧版本]** → 改 `pubspec.yaml` 后 `pubspec.lock` 可能仍带 `1.0.0+1`。缓解：改后重跑 `flutter pub get`。
- **[README 状态描述与 0.1.0 语义张力]** → 选 A 将"桌面版全量可用"标为 `v0.1.0`。缓解：README 保留功能描述，仅版本标签统一；后续版本号随功能演进递增。

## Migration Plan

1. 改 `desktop/pubspec.yaml` 版本为 `0.1.0`，重跑 `flutter pub get`。
2. 改 `desktop/lib/widgets/app_shell.dart` UI 显示为 `v0.1.0`。
3. 改 `README.md` 版本标签为 `v0.1.0`。
4. 生成根目录 `AGENTS.md`。
5. 验证：`flutter analyze` / `flutter test`；确认 UI 与文档显示 `0.1.0`；`lupa version` 输出 `0.1.0`。
6. 回滚：还原上述字符串即可，无数据迁移破坏。

## Open Questions

- 无。
