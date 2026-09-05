# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典命令行工具。
重点不是"再多一个词典"，而是**让生词本和导出都做到位**——你的学习数据回到你手里。

## 状态

**v0.1.0** — MVP 数据流水线已通：查词 / 生词本 / 复习 / 发音 / 导出（Anki apkg + CSV）。

## 已拍板的产品决策

| 维度 | 决策 |
|---|---|
| 第一版形态 | CLI（可选本地网页） |
| 词库 | ECDICT 340万词 → 按 `frq`（当代语料库频率）裁剪到 **3万词** |
| AI | v1 纯离线；v2 接入 LLM 增量为可选 |
| 发音 | 联网拉音标 / TTS（默认有道）→ 缓存本地 SQLite |
| 复习算法 | v1 **固定间隔** (1/3/7/15/30 天)；v2 引入 FSRS (MIT) |
| 同步 | 不做同步，本地优先 |
| 后期桌面端 | Flutter + 本地 FastAPI 中间层（业务规则 Python 写一份） |

## 快速开始

```bash
# 安装（开发模式，需 Python >= 3.13）
pip install -e .

# 数据目录（默认 ~/.lupa，指向已构建好的 dict.sqlite / notebook.sqlite）
set LUPA_HOME=D:\Projects\AISpace\LupaApp\data

lupa --help
```

## 命令一览

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

## 跨语言友好（v1 即约束）

1. `src/lupa/notebook/schema.sql` 仅用 SQLite ≥ 3.38 标准 SQL，不用 JSON1 / STRICT / RETURNING / virtual table。
2. 业务逻辑（`notebook/repo.py`、`dict/query.py`、`export/*.py`、`media/*.py`）写成**纯函数**——不读 stdin / 不写 stdout。Typer 只做参数解析和显示。
3. 媒体缓存键永远用三段式 `provider:word:format`（如 `youdao:abandon:mp3-us`），URL 单列字段。

## 项目结构

```
src/lupa/
├── cli.py              # Typer 入口（只做参数解析 + 输出）
├── config.py           # 配置加载（服务商 URL 可配置）
├── notebook/
│   ├── schema.sql      # 生词本 + 媒体缓存 schema（notes/cards/revlog + 3 缓存表 + meta）
│   ├── repo.py         # 生词本 CRUD / 复习答题（纯函数）
│   └── scheduler.py    # 固定间隔调度（v2 换 FSRS 只改这里）
├── dict/
│   ├── build.py        # ECDICT → 3万词裁剪 → dict.sqlite（一次性脚本）
│   └── query.py        # 查词/联想/统计（纯函数）
├── export/
│   ├── csv.py          # CSV 导出（UTF-8 BOM）
│   └── apkg.py         # genanki 封装（Anki Legacy 2，稳定 guid）
└── media/
    ├── phonetic.py     # 音标获取 + phonetic_cache（纯函数）
    └── tts.py          # TTS 下载 + audio_cache（纯函数）
```

## 许可

[MIT](LICENSE) © 2026 JasonX98 (liull621)
