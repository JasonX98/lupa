# Lupa / 璐帕

> **看清词，留住词，归你所有。**

Lupa 是一款英语学习离线词典命令行工具。
重点不是"再多一个词典"，而是**让生词本和导出都做到位**——你的学习数据回到你手里。

## 状态

**v0.1.0** — 项目骨架初始化，CLI 待完善。

## 已拍板的产品决策

| 维度 | 决策 |
|---|---|
| 第一版形态 | CLI（可选本地网页） |
| 词库 | ECDICT 76万词 → 按 `frq`（当代语料库频率）裁剪到 **3万词** |
| AI | v1 纯离线；v2 接入 LLM 增量为可选 |
| 发音 | 联网拉音标 / TTS → 缓存本地 SQLite |
| 复习算法 | v1 **固定间隔** (1/3/7/15/30 天)；v2 引入 FSRS (MIT) |
| 同步 | 不做同步，本地优先 |
| 后期桌面端 | Flutter + 本地 FastAPI 中间层（业务规则 Python 写一份） |

## 开发

```bash
# 安装（开发模式）
pip install -e ".[dev]"

# CLI 帮助
lupa --help
```

## 跨语言友好（v1 即约束）

1. `src/lupa/notebook/schema.sql` 仅用 SQLite ≥ 3.38 标准 SQL，不用 JSON1 / STRICT / RETURNING / virtual table。
2. 业务逻辑（`notebook/repo.py`、`dict/query.py`、`export/*.py`）写成**纯函数**——不读 stdin / 不写 stdout。Typer 只做参数解析和显示。
3. 媒体缓存键永远用三段式 `provider:word:format`（如 `youdao:abandon:mp3`），URL 单列字段。

## 项目结构

```
src/lupa/
├── cli.py              # Typer 入口（只做参数解析 + 输出，业务调用下方纯函数）
├── notebook/
│   ├── schema.sql      # 用户生词本 + 媒体缓存 schema（6 表）
│   └── repo.py         # CRUD 纯函数（待写）
├── dict/
│   ├── build.py        # ECDICT CSV → SQLite 一次性脚本（待写）
│   └── query.py        # 查词纯函数（待写）
├── export/
│   ├── csv.py          # CSV 导出（待写）
│   └── apkg.py         # genanki 封装（待写）
└── media/
    ├── phonetic.py     # 音标 API（待写）
    └── tts.py          # TTS API（待写）
```

## 许可

[MIT](LICENSE) © 2026 JasonX98 (liull621)
