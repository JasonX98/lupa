# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典，重点不是"再多一个词典"，而是**把生词本和导出做到位**——你的学习数据回到你手里。当前两个入口共享同一份 SQLite 数据（词库 + 生词本 + 发音缓存）。

## 项目定位

- **数据主权**：本地生词本 + 完整导出（Anki apkg / CSV）是一等公民，数据归用户所有。
- **离线优先**：查词 / 生词本 / 复习不依赖网络；仅音标 / TTS 联网拉取并落库缓存。
- **双语言对齐**：业务逻辑在 Dart（桌面）与 Python（CLI）各一份，行为契约以 Python 版为准。

## 双入口与技术栈

| 入口 | 目录 | 技术栈 |
|---|---|---|
| Windows 桌面应用（主力） | `desktop/` | Flutter / Dart；`ganki`、`sqflite_common_ffi`、`sqlite3`、`audioplayers` |
| 命令行工具（参考实现） | `src/lupa/` | Python ≥ 3.13；Typer；`genanki`（apkg 生成） |

## 常用命令

### 桌面应用
```bash
cd desktop
flutter pub get
flutter run -d windows          # 运行（需 Flutter SDK + Windows 桌面支持）
flutter test                    # 冒烟测试（主题/词形/外壳）
flutter analyze                 # 静态检查
flutter build windows --release # 发布构建 → build/windows/x64/runner/Release/
```

### 发布发行包
```bash
cd desktop
flutter build windows --release   # 产出 build/windows/x64/runner/Release/
# 发行 zip 统一放该构建输出目录，不在仓库根：
#   desktop/build/windows/x64/runner/Release/Lupa-<version>-windows.zip
```
说明：构建已自动把 `data/schema.sql`（首次建库模板）与 `lupa_data/dict.sqlite`（词库，缺失时跳过）复制进输出目录，见 `desktop/windows/runner/copy_data_files.cmake`；打包时对 `Release/` 目录打 zip 即可，解压即用。

### 验证脚本（`desktop/tool/`，均走临时库、不污染真实数据）
```bash
cd desktop
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_dict_query.dart   # 查词/前缀/统计
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_notebook_db.dart  # 建库/schema
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_notebook_repo.dart# CRUD/调度/revlog
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_media.dart        # 音标/TTS 缓存
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_export.dart       # apkg/csv
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_e2e.dart          # 端到端 15 断言
```

### CLI（Python）
```bash
pip install -e .                # 开发模式安装
set LUPA_HOME=D:\AppFile\Lupa\data   # 指向已构建好的 dict.sqlite / notebook.sqlite
lupa --help
lupa search <word>   | lupa add <word> | lupa rm <word>
lupa list | lupa review | lupa stats | lupa say <word>
lupa export -f apkg|csv | lupa info | lupa version
```

## 关键约束

1. **`schema.sql` 双份必须同步**：`src/lupa/notebook/schema.sql` 与 `desktop/lib/data/schema.sql` 是同一份；改一处必须同步另一处。仅用 SQLite ≥ 3.38 标准 SQL（不用 JSON1 / STRICT / RETURNING / virtual table）。
2. **业务逻辑写成纯函数**：不读 stdin / 不写 stdout。CLI 与 UI 只做参数解析与展示。
3. **媒体缓存键永远三段式**：`provider:word:format`（如 `youdao:abandon:mp3-us`），URL 单列字段。
4. **apkg 稳定 guid**：`sha1("lupa::word")`，model/deck id 两版一致，混用不产生重复卡片。
5. **数据目录**：`LUPA_HOME` 环境变量优先；未设时默认 `<exe>/lupa_data`（便携默认，解压即用）。与 Python CLI 靠 `LUPA_HOME` 共享同一份数据。
6. **版本号两处同步**：`src/lupa/__init__.py` 的 `__version__` 与 `desktop/pubspec.yaml` 的 `version` 必须一致，统一为 `x.y.z`（当前 `0.2.0`）。
7. **发行 zip 位置**：桌面发布 zip（`Lupa-<version>-windows.zip`）统一放在 `desktop/build/windows/x64/runner/Release/`（`flutter build windows --release` 的输出目录），不放在仓库根目录。

## 验证

- **桌面端**：`flutter test`（主题/词形/外壳）+ `desktop/tool/verify_*.dart` 六组（headless，走真实词库 + 临时生词本库）。
- **导出一致性**：`desktop/tool/anki_import_compare.py` 将 Python 与 Dart 两版 apkg 分别灌入全新 Anki collection（官方 `anki` 库），比对 guid / 字段 / model / deck 完全一致。
- **CLI**：`lupa version` 输出 `Lupa v0.2.0`，`lupa info` 展示词库状态。

## 数据目录结构

```
LUPA_HOME（或 <exe>/lupa_data）
├── dict.sqlite       词库（只读，应用不自建）
├── notebook.sqlite   生词本 + audio/phonetic/ai 缓存表
├── config.json       服务商 URL 配置（首次运行自动生成）
└── exports/          导出产物（apkg/csv，自动创建）
```
