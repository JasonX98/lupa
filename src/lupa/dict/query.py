"""Lupa 词库查询 — 纯函数，操作 data/dict.sqlite。

跨语言友好 #2：本模块所有函数不读 stdin / 不写 stdout，返回值即结果。
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class DictEntry:
    """一条词条（与 dict.sqlite 的 dict 表一一对应）。"""

    word: str
    sw: str
    phonetic: str
    definition: str      # 英文释义
    translation: str     # 中文释义
    pos: str             # 词性，如 'n:1/v:1'
    collins: int         # 柯林斯星级 0-5
    oxford: int          # 牛津 3000: 0/1
    tag: str             # 标签，如 'zk gk cet4 cet6 ky toefl'
    bnc: int             # BNC 词频排名
    frq: int             # 当代语料库词频排名（越小越高频）
    exchange: str        # 词形变化，格式 'd:xx/p:xx/i:xx/3:xx/s:xx/r:xx/t:xx'
    audio: str           # 音频地址（官方库多为空，实际发音走 media 模块）

    @property
    def exchanges(self) -> dict[str, str]:
        """词形变化解析为字典：{'d': 'abandoned', 'p': ..., 'i': ..., '3': ...}。

        键含义：d=过去式 p=过去分词 i=现在分词 3=三单 s=复数 r=比较级 t=最高级。
        """
        result: dict[str, str] = {}
        if not self.exchange:
            return result
        for part in self.exchange.split("/"):
            if ":" in part:
                key, _, value = part.partition(":")
                result[key] = value
        return result


def _connect(db_path: str | Path) -> sqlite3.Connection:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    return con


def query_word(db_path: str | Path, word: str) -> DictEntry | None:
    """按单词精确查询（大小写不敏感）。查不到返回 None。"""
    con = _connect(db_path)
    try:
        row = con.execute(
            "SELECT * FROM dict WHERE word = ? COLLATE NOCASE", (word.strip(),)
        ).fetchone()
        return DictEntry(**row) if row else None
    finally:
        con.close()


def suggest_prefix(db_path: str | Path, prefix: str, limit: int = 10) -> list[str]:
    """前缀联想，返回单词列表（frq 升序 = 高频优先）。"""
    con = _connect(db_path)
    try:
        rows = con.execute(
            "SELECT word FROM dict WHERE word LIKE ? || '%' "
            "ORDER BY frq ASC LIMIT ?",
            (prefix.strip(), limit),
        ).fetchall()
        return [r[0] for r in rows]
    finally:
        con.close()


def random_words(db_path: str | Path, limit: int = 5) -> list[DictEntry]:
    """随机取 N 个词（学习/测试用）。"""
    con = _connect(db_path)
    try:
        rows = con.execute(
            "SELECT * FROM dict ORDER BY RANDOM() LIMIT ?", (limit,)
        ).fetchall()
        return [DictEntry(**r) for r in rows]
    finally:
        con.close()


def dict_stats(db_path: str | Path) -> dict[str, int]:
    """词库统计：总词数、含音标数、含英解数。"""
    con = _connect(db_path)
    try:
        total = con.execute("SELECT COUNT(*) FROM dict").fetchone()[0]
        with_phonetic = con.execute(
            "SELECT COUNT(*) FROM dict WHERE phonetic != ''"
        ).fetchone()[0]
        with_definition = con.execute(
            "SELECT COUNT(*) FROM dict WHERE definition != ''"
        ).fetchone()[0]
        return {
            "total": total,
            "with_phonetic": with_phonetic,
            "with_definition": with_definition,
        }
    finally:
        con.close()
