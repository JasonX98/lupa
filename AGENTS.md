# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典，重点不是"再多一个词典"，而是**把生词本和导出做到位**——你的学习数据回到你手里。唯一入口是 Windows 桌面应用，数据全部落在本地 SQLite（词库 + 生词本 + 短语集 + 发音缓存）。

## 项目定位

- **数据主权**：本地生词本 + 完整导出（Anki apkg / CSV）是一等公民，数据归用户所有。
- **离线优先**：查词 / 生词本 / 复习不依赖网络；仅音标 / TTS 联网拉取并落库缓存。
- **Flutter 为唯一实现**：业务逻辑全部以 Dart（桌面）为事实源；Python CLI 已移除。

## 技术栈

| 入口 | 目录 | 技术栈 |
|---|---|---|
| Windows 桌面应用 | `desktop/` | Flutter / Dart；`ganki`、`sqflite_common_ffi`、`sqlite3`、`audioplayers` |

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
LUPA_HOME=D:\AppFile\Lupa\data dart run tool/verify_phrase_repo.dart # 短语建库/CRUD/调度/导出
```

## 关键约束

1. **`schema.sql` 唯一事实源**：以 `desktop/lib/data/schema.sql` 为准。仅用 SQLite ≥ 3.38 标准 SQL（不用 JSON1 / STRICT / RETURNING / virtual table）。
2. **业务逻辑写成纯函数**：不读 stdin / 不写 stdout。CLI 与 UI 只做参数解析与展示。
3. **媒体缓存键永远三段式**：`provider:word:format`（如 `youdao:abandon:mp3-us`），URL 单列字段。
4. **apkg 稳定 guid**：单词 `sha1("lupa::word")`、短语 `sha1("lupa::phrase::<text>")`；各自独立 model/deck，混用不产生重复卡片。
5. **数据目录**：`LUPA_HOME` 环境变量优先；未设时默认 `<exe>/lupa_data`（便携默认，解压即用）。
6. **版本号**：`desktop/pubspec.yaml` 的 `version` 为唯一事实源，统一为 `x.y.z`（当前 `0.2.1`）。
7. **发行 zip 位置**：桌面发布 zip（`Lupa-<version>-windows.zip`）统一放在 `desktop/build/windows/x64/runner/Release/`（`flutter build windows --release` 的输出目录），不放在仓库根目录。

## 验证

- **桌面端**：`flutter test`（主题/词形/外壳）+ `desktop/tool/verify_*.dart` 七组（headless，走真实词库 + 临时生词本库）。
- **导出一致性**：`desktop/tool/anki_import_compare.py` 用官方 `anki` 库校验 Dart 版 apkg 的导入产出（笔记 / guid / 字段 / model / deck）。

## 数据目录结构

```
LUPA_HOME（或 <exe>/lupa_data）
├── dict.sqlite       词库（只读，应用不自建）
├── notebook.sqlite   生词本 + 短语集 + audio/phonetic/ai 缓存表
├── config.json       服务商 URL 配置（首次运行自动生成）
└── exports/          导出产物（apkg/csv，自动创建）
```
