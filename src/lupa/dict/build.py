"""Lupa 词库构建 — ECDICT 全量库 -> Lupa 裁剪版 dict.sqlite

用法：
    python -m lupa.dict.build --source data/ecdict.db --target data/dict.sqlite --top 30000

数据源：ECDICT 1.0.28 release 的 sqlite 版（340 万词，github.com/skywind3000/ECDICT）。
裁剪规则（Q2 拍板）：按 frq 字段（当代语料库频率，数值越小越高频）升序取前 N 词。

纯函数约束（跨语言友好 #2）：核心逻辑在 build_dict()，不读 stdin / 不写 stdout。
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path

# 裁剪后保留的字段（丢弃源库的 detail 大 JSON 字段）
_FIELDS = (
    "word, sw, phonetic, definition, translation, "
    "pos, collins, oxford, tag, bnc, frq, exchange, audio"
)


@dataclass(frozen=True)
class BuildReport:
    """构建结果统计。"""

    total_source: int        # 源库总词数
    selected: int            # 实际入库词数
    target_path: str         # 目标库路径
    size_bytes: int          # 目标库文件大小


def build_dict(
    source_path: str | Path,
    target_path: str | Path,
    top_n: int = 30_000,
) -> BuildReport:
    """从 ECDICT 源库裁剪 top_n 高频词到目标库。

    Args:
        source_path: ECDICT 原始 sqlite 库路径（含 stardict 表）。
        target_path: 生成的 Lupa dict.sqlite 路径（不存在则创建，存在则重建）。
        top_n: 保留词数上限，按 frq 升序（frq 越小越高频）。

    Returns:
        BuildReport 统计信息。
    """
    src = Path(source_path)
    dst = Path(target_path)
    if not src.exists():
        raise FileNotFoundError(f"源库不存在: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        dst.unlink()

    con = sqlite3.connect(str(dst))
    try:
        con.execute("ATTACH DATABASE ? AS src", (str(src),))
        con.execute(
            f"""
            CREATE TABLE dict (
                word        TEXT PRIMARY KEY,
                sw          TEXT NOT NULL DEFAULT '',
                phonetic    TEXT NOT NULL DEFAULT '',
                definition  TEXT NOT NULL DEFAULT '',
                translation TEXT NOT NULL DEFAULT '',
                pos         TEXT NOT NULL DEFAULT '',
                collins     INTEGER NOT NULL DEFAULT 0,
                oxford      INTEGER NOT NULL DEFAULT 0,
                tag         TEXT NOT NULL DEFAULT '',
                bnc         INTEGER NOT NULL DEFAULT 0,
                frq         INTEGER NOT NULL DEFAULT 0,
                exchange    TEXT NOT NULL DEFAULT '',
                audio       TEXT NOT NULL DEFAULT ''
            )
            """
        )
        # 跨语言友好 #1：仅标准 SQL。frq 空串视为 0（无频率数据）。
        con.execute(
            f"""
            INSERT INTO dict ({_FIELDS})
            SELECT
                IFNULL(word, ''),
                IFNULL(sw, ''),
                IFNULL(phonetic, ''),
                IFNULL(definition, ''),
                IFNULL(translation, ''),
                IFNULL(pos, ''),
                IFNULL(collins, 0),
                IFNULL(oxford, 0),
                IFNULL(tag, ''),
                IFNULL(bnc, 0),
                IFNULL(frq, 0),
                IFNULL(exchange, ''),
                IFNULL(audio, '')
            FROM src.stardict
            WHERE word IS NOT NULL AND word != ''
              AND frq IS NOT NULL AND CAST(frq AS INTEGER) > 0
            ORDER BY CAST(frq AS INTEGER) ASC
            LIMIT ?
            """,
            (top_n,),
        )
        con.execute("CREATE INDEX idx_dict_sw ON dict(sw)")
        con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        con.execute(
            "INSERT INTO meta (key, value) VALUES ('dict_top_n', ?)",
            (str(top_n),),
        )
        con.commit()

        total = con.execute("SELECT COUNT(*) FROM src.stardict").fetchone()[0]
        selected = con.execute("SELECT COUNT(*) FROM dict").fetchone()[0]
        return BuildReport(
            total_source=total,
            selected=selected,
            target_path=str(dst),
            size_bytes=dst.stat().st_size,
        )
    finally:
        try:
            con.rollback()
            con.execute("DETACH DATABASE src")
        except sqlite3.Error:
            pass  # 事务失败后 DETACH 可能报 locked，close 时自动清理
        con.close()


def query_word(db_path: str | Path, word: str) -> dict | None:
    """已迁移到 lupa.dict.query.query_word，此处保留兼容别名。"""
    from lupa.dict.query import query_word as _q

    return _q(db_path, word)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ECDICT -> Lupa dict.sqlite")
    parser.add_argument("--source", default="data/ecdict.db", help="ECDICT 源库路径")
    parser.add_argument("--target", default="data/dict.sqlite", help="目标库路径")
    parser.add_argument("--top", type=int, default=30_000, help="保留高频词数")
    args = parser.parse_args()

    report = build_dict(args.source, args.target, args.top)
    # 唯一允许 print 的地方：CLI 入口（约束 #2 的边界在 __main__）
    print(
        f"源库 {report.total_source} 词 -> 入库 {report.selected} 词 -> "
        f"{report.target_path} ({report.size_bytes / 1048576:.1f} MB)"
    )
