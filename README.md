# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典，重点不是"再多一个词典"，而是**把生词本和导出做到位**——你的学习数据回到你手里。

目前提供两个入口，共享同一份 SQLite 数据（词库 + 生词本 + 短语集 + 发音缓存）：

- **Windows 桌面应用**（Flutter，主力入口）
- **命令行工具**（Python，脚本化 / 批处理）

## 状态

**v0.2.1** — 新增**短语集**：独立的短语数据模型（`phrases` / `phrase_examples` / `phrase_review_log` 三表，`schema_version` 1 → 2 并带旧库迁移）、记录 / 编辑 / 详情弹窗 / 标签 chips 筛选，以及**独立复习队列**与**独立 apkg / csv 导出**（自有 model / deck / guid `sha1("lupa::phrase::<text>")`，与单词导出完全隔离）。复习调度改为**按评分分级**推进固定档位：忘了回第一档、模糊保持当前档、记得前进一档、简单前进两档（单词与短语共用同一实现）。侧栏「复习」更名「**单词复习**」以区分短语复习。

## 已拍板的产品决策

| 维度 | 决策 |
|---|---|
| 词库 | ECDICT 340 万词 → 按 `frq`（当代语料库频率）裁剪到 **3 万词** |
| AI | v1 纯离线；v2 接入 LLM 增量为可选 |
| 发音 | 联网拉音标 / TTS（默认有道）→ 缓存本地 SQLite；播放走内存字节直喂（不落临时文件） |
| 复习算法 | v1 **固定间隔** (1/3/7/15/30 天)，**按评分分级推进**（忘了/模糊/记得/简单 → 回第一档/保持/前进一档/前进两档）；v2 引入 FSRS (MIT) |
| 同步 | 不做同步，本地优先 |
| 桌面端 | **全 Dart 重写**（已放弃"Flutter + FastAPI 中间层"方案）；CLI 仅作参考实现，已列入移除计划 |

## Windows 桌面应用

### 运行

```bash
cd desktop
flutter pub get

# 便携默认：数据目录在应用旁的 lupa_data/（含 dict.sqlite / notebook.sqlite），解压即用
# 如需与 Python CLI 共享同一份数据，再显式设置 LUPA_HOME：
set LUPA_HOME=D:\AppFile\Lupa\data

flutter run -d windows
# 或构建发布版
flutter build windows --release
```

依赖：Flutter SDK（Windows 桌面支持）。数据目录默认在应用旁的 `lupa_data/`——发布 zip 解压到可写目录即可直接双击使用；开发调试或与 CLI 共享数据时设 `LUPA_HOME`。运行时依赖仅 `sqflite_common_ffi` / `audioplayers` / `ganki` 等，无 Python。

### 发布 zip

`flutter build windows --release` 后打包即得便携发行包（免安装、免环境变量）。发行 zip 统一放在构建输出目录：`desktop/build/windows/x64/runner/Release/Lupa-<version>-windows.zip`。

```
Lupa-v0.2.1-windows.zip
└── Lupa-v0.2.1-windows/         # 解压后进入此文件夹，双击 lupa.exe
    ├── lupa.exe  + 运行时 DLL   # 双击即用
    ├── data/                    # 含 schema.sql（首次建库模板）
    └── lupa_data/               # 词典 dict.sqlite（解压即用，随包；notebook 首次运行自动创建）
```

### 功能

- **查词**：前缀联想、英美音标、考试标签（柯林斯/牛津/词频）、词形变化、一键收藏、美/英朗读
- **生词本**：统计条（总词数/新词/复习中/今日到期/遗忘）、点词条目弹出详情卡片
- **单词复习**：到期队列逐卡作答，评分即时推进调度并写 revlog；空格/点击**3D 翻面**显示释义
- **短语集**：记录短语（短语\*、释义\*、字面直译、典故来源、使用场景、场景标签、多条例句、标签），标签 chips 筛选 + 详情弹窗；**独立复习队列**（不与单词卡混排，入口在短语集右上角）与**独立 apkg / csv 导出**
- **导出**：Anki apkg + CSV（UTF-8 BOM），导出到数据目录 `exports/`；单词与短语各自独立 model / deck / guid
- **设置**：外观 / 发音 / 复习 / 数据四组写回 `config.json`；数据目录可**运行时切换**（复制现有 / 新开空白），媒体缓存可统计与一键清理，生词本可一键备份
- 明暗双主题（「纸感 + 玉色」，WCAG AA 对比度达标）；考试标签按类型配色（柯林斯/牛津/考纲/自定义）

### 快捷键

| 按键 | 作用 |
|---|---|
| `Ctrl+F` / `Ctrl+B` / `Ctrl+R` / `Ctrl+I` / `Ctrl+E` | 切到 查词 / 生词本 / 单词复习 / 短语集 / 导出 |
| `空格` | 单词复习 / 短语复习 翻面 |
| `1` `2` `3` `4` | 复习页评分（忘了 / 模糊 / 记得 / 简单） |

## 命令行工具

> CLI 是 MVP 时代的参考实现，已列入移除计划：不含短语集等新增能力，版本号冻结在 `0.2.0`。

### 快速开始

```bash
# 安装（开发模式，需 Python >= 3.13）
pip install -e .

# 数据目录（默认 ~/.lupa，指向已构建好的 dict.sqlite / notebook.sqlite）
set LUPA_HOME=D:\Projects\AISpace\LupaApp\data

lupa --help
```

### 命令一览

| 命令 | 作用 |
|---|---|
| `lupa search <word>` | 查词（音标/考试标签/中英双解/词形变化） |
| `lupa add <word> --tags "cet6"` | 加入生词本 |
| `lupa rm <word>` | 移出生词本 |
| `lupa list` | 查看生词本与复习排期 |
| `lupa review` | 交互式复习（`--speak` 每卡自动朗读） |
| `lupa stats` | 生词本统计 |
| `lupa say <word>` | 朗读（`--accent us/uk`，mp3 缓存到 audio_cache） |
| `lupa phonetic <word>` | 联网查美/英音标（缓存到 phonetic_cache） |
| `lupa cache-stats` | 发音/音标缓存统计 |
| `lupa export` | 导出：`-f apkg`（默认）/ `-f csv` |
| `lupa info` / `lupa version` | 词库状态 / 版本 |

发音服务商 URL 在 `data/config.json`（首次运行自动生成默认值），可自行替换，不硬编码。

## 架构

```
┌────────────────────┐      ┌────────────────────┐
│  desktop/ (Flutter) │      │  src/lupa/ (Python) │
│  Windows GUI        │      │  CLI（参考实现）     │
└─────────┬──────────┘      └─────────┬──────────┘
          │      同一份数据             │
          └──────────┬────────────────┘
                     ▼
   LUPA_HOME: dict.sqlite (3万词词库)
              notebook.sqlite (notes/cards/revlog
                               + phrases/phrase_examples/phrase_review_log
                               + audio/phonetic/ai 缓存表)
```

- **Flutter 为唯一事实源**：业务逻辑以 Dart（`notebook/repo` / `dict/query` / `scheduler` / `phrase/repo` / `media/*` / `export/*`）为准；`src/lupa/`（Python CLI）是 MVP 时代的参考实现，已列入移除计划，后续功能不再与其同步。apkg 稳定 guid 单词用 `sha1("lupa::word")`、短语用 `sha1("lupa::phrase::<text>")`，各自独立 model / deck，混用不产生重复卡片。
- **导出一致性已验证**：`desktop/tool/anki_import_compare.py` 曾用官方 `anki` 库比对 Python 与 Dart 两版 apkg；Python 版移除后，该脚本只校验 Dart 版产出。
- **验证脚本**：`desktop/tool/verify_*.dart` 七组（新增 `verify_phrase_repo.dart`：短语建表 / 旧库迁移 / CRUD / 调度 / 导出），均走临时库、不污染真实数据；`verify_e2e.dart` 覆盖 查词→加词→复习→导出 全链路 15 项断言。

### 项目结构

```
src/lupa/                  # Python CLI
├── cli.py                 # Typer 入口（只做参数解析 + 输出）
├── config.py              # 配置加载（服务商 URL 可配置）
├── notebook/              # schema.sql / repo.py / scheduler.py
├── dict/                  # build.py（裁剪词库）/ query.py
├── export/                # csv.py / apkg.py（genanki）
└── media/                 # phonetic.py / tts.py

desktop/                   # Flutter Windows 桌面版
├── lib/data/              # data_home / config / notebook_db / schema.sql（唯一事实源，含短语三表）
├── lib/dict|notebook|media|export/   # 单词侧业务模块（repo / query / scheduler / media / export）
├── lib/phrase/            # 短语仓库层（独立三表 CRUD / 到期队列 / 统计，复用 scheduler 纯函数）
├── lib/theme/             # 「纸感 + 玉色」设计 token（明暗双主题）
├── lib/state/             # AppState 编排层
├── lib/widgets/           # AppShell 侧栏 + 词详情卡片 + 短语组件等
├── lib/pages/             # 查词 / 生词本 / 单词复习 / 短语集 / 短语复习 / 导出 / 设置
└── tool/                  # apkg spike + verify_* 验证脚本 + Anki 导入对比
```

## 跨语言友好（v1 即约束）

1. `schema.sql` 仅用 SQLite ≥ 3.38 标准 SQL，不用 JSON1 / STRICT / RETURNING / virtual table。
2. 业务逻辑写成**纯函数**——不读 stdin / 不写 stdout。CLI 与 UI 只做参数解析和展示。
3. 媒体缓存键永远用三段式 `provider:word:format`（如 `youdao:abandon:mp3-us`），URL 单列字段。

## 许可

[MIT](LICENSE) © 2026 JasonX98 (liull621)
