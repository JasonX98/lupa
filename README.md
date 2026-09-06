# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典，重点不是"再多一个词典"，而是**把生词本和导出做到位**——你的学习数据回到你手里。

目前提供两个入口，共享同一份 SQLite 数据（词库 + 生词本 + 发音缓存）：

- **Windows 桌面应用**（Flutter，主力入口）
- **命令行工具**（Python，脚本化 / 批处理）

## 状态

**v0.2** — Windows 桌面版 GUI 全量可用（查词 / 生词本 / 复习 / 导出 + 明暗双主题），Python CLI 六命令稳定。桌面版导出的 apkg 与 CLI 版经 Anki 官方后端导入对比验证完全一致。

## 已拍板的产品决策

| 维度 | 决策 |
|---|---|
| 词库 | ECDICT 340 万词 → 按 `frq`（当代语料库频率）裁剪到 **3 万词** |
| AI | v1 纯离线；v2 接入 LLM 增量为可选 |
| 发音 | 联网拉音标 / TTS（默认有道）→ 缓存本地 SQLite；播放走内存字节直喂（不落临时文件） |
| 复习算法 | v1 **固定间隔** (1/3/7/15/30 天)；v2 引入 FSRS (MIT) |
| 同步 | 不做同步，本地优先 |
| 桌面端 | **全 Dart 重写**（已放弃"Flutter + FastAPI 中间层"方案），CLI 保留作参考实现 |

## Windows 桌面应用

### 运行

```bash
cd desktop
flutter pub get

# 数据目录（含 dict.sqlite / notebook.sqlite，与 CLI 共享）
set LUPA_HOME=D:\AppFile\Lupa\data

flutter run -d windows
# 或构建发布版
flutter build windows --release
```

依赖：Flutter SDK（Windows 桌面支持）、`LUPA_HOME` 指向数据目录。运行时依赖仅 `sqflite_common_ffi` / `audioplayers` / `ganki` 等，无 Python。

### 功能

- **查词**：前缀联想、英美音标、考试标签（柯林斯/牛津/词频）、词形变化、一键收藏、美/英朗读
- **生词本**：统计条（总词数/新词/复习中/今日到期/遗忘）、点词条目弹出详情卡片
- **复习**：到期队列逐卡作答，评分即时推进调度并写 revlog
- **导出**：Anki apkg + CSV（UTF-8 BOM），导出到 `LUPA_HOME/exports`
- 明暗双主题（「纸感 + 玉色」，WCAG AA 对比度达标）

### 快捷键

| 按键 | 作用 |
|---|---|
| `Ctrl+F` / `Ctrl+B` / `Ctrl+R` / `Ctrl+E` | 切到 查词 / 生词本 / 复习 / 导出 |
| `空格` | 复习页翻面 |
| `1` `2` `3` `4` | 复习页评分（忘了 / 艰难 / 良好 / 轻松） |

## 命令行工具

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
                               + audio/phonetic/ai 缓存表)
```

- **业务逻辑双语言对齐**：`notebook/repo` / `dict/query` / `scheduler` / `media/*` / `export/*` 在 Dart 与 Python 各有一份，行为契约以 Python 版为准；apkg 稳定 guid（`sha1("lupa::word")`）与 model/deck id 两版一致，混用不产生重复卡片。
- **导出一致性已验证**：`desktop/tool/anki_import_compare.py` 将两版 apkg 分别灌入全新 Anki collection（官方 `anki` 库，同一 Rust 导入后端），guid/字段/model/deck 全部一致。
- **验证脚本**：`desktop/tool/verify_*.dart` 六组，均走临时库、不污染真实数据；`verify_e2e.dart` 覆盖 查词→加词→复习→导出 全链路 15 项断言。

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
├── lib/data/              # config / notebook_db / schema.sql（复用 Python 版）
├── lib/dict|notebook|media|export/   # 与 Python 版同构的业务模块
├── lib/theme/             # 「纸感 + 玉色」设计 token（明暗双主题）
├── lib/state/             # AppState 编排层
├── lib/widgets/           # AppShell 侧栏 + 词详情卡片等
├── lib/pages/             # 查词 / 生词本 / 复习 / 导出 四页
└── tool/                  # apkg spike + verify_* 验证脚本 + Anki 导入对比
```

## 跨语言友好（v1 即约束）

1. `schema.sql` 仅用 SQLite ≥ 3.38 标准 SQL，不用 JSON1 / STRICT / RETURNING / virtual table。
2. 业务逻辑写成**纯函数**——不读 stdin / 不写 stdout。CLI 与 UI 只做参数解析和展示。
3. 媒体缓存键永远用三段式 `provider:word:format`（如 `youdao:abandon:mp3-us`），URL 单列字段。

## 许可

[MIT](LICENSE) © 2026 JasonX98 (liull621)
