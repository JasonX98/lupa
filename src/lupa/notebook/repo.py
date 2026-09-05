"""Lupa 生词本 CRUD — 纯函数，操作 data/notebook.sqlite。

schema 见 schema.sql（notes / cards / revlog / phonetic_cache / audio_cache / ai_cache）。
跨语言友好 #2：所有函数不读 stdin / 不写 stdout。
"""
from __future__ import annotations

import sqlite3
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from lupa.notebook.scheduler import due_timestamp

_SCHEMA_PATH = Path(__file__).parent / "schema.sql"

# 默认笔记模型 id（v1 只有一种模型：单词 -> 音标/释义/变形）
MODEL_ID = 1

# 默认牌组 id
DECK_ID = 1

# 字段分隔符（Anki 惯例 \x1f）
FIELD_SEP = "\x1f"

# 卡片状态常量（抄 Anki CardType/CardQueue，事实标准）
CARD_NEW = 0
CARD_LEARN = 1
CARD_REVIEW = 2
QUEUE_NEW = 0
QUEUE_SUSPENDED = -1


@dataclass(frozen=True)
class NotebookEntry:
    """生词本条目（notes 行 + cards 调度状态 + 词库内容）。"""

    note_id: int
    card_id: int
    word: str
    phonetic: str
    translation: str
    definition: str
    exchange: str
    tags: str
    card_type: int      # 0=New 1=Learn 2=Review 3=Relearn
    queue: int
    due: int
    ivl: int
    reps: int
    lapses: int
    added_at: int


class WordNotInDictError(LookupError):
    """词不在词库中。"""


class DuplicateWordError(Exception):
    """词已在生词本中。"""


def _connect(db_path: str | Path) -> sqlite3.Connection:
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def ensure_notebook(db_path: str | Path) -> None:
    """应用 schema.sql（幂等：库已存在则跳过）。"""
    p = Path(db_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists():
        return
    con = _connect(p)
    try:
        con.executescript(_SCHEMA_PATH.read_text(encoding="utf-8"))
        con.commit()
    finally:
        con.close()


def _gen_anki_id() -> int:
    """生成 Anki 兼容 id（毫秒时间戳 + 随机，int64 内）。"""
    return int(time.time() * 1000) ^ (uuid.uuid4().int & 0xFFFF)


def _csum(flds: str) -> int:
    """Anki csum：首字段 sha1 前 8 位十六进制转整数。"""
    import hashlib

    first = flds.split(FIELD_SEP)[0].strip().lower()
    return int(hashlib.sha1(first.encode("utf-8")).hexdigest()[:8], 16)


def _check_dict_word(dict_db: str | Path, word: str) -> sqlite3.Row:
    """确认词在词库中并返回词条行。"""
    con = _connect(dict_db)
    try:
        row = con.execute(
            "SELECT * FROM dict WHERE word = ? COLLATE NOCASE", (word.strip(),)
        ).fetchone()
    finally:
        con.close()
    if row is None:
        raise WordNotInDictError(word)
    return row


def add_word(
    nb_path: str | Path,
    dict_db: str | Path,
    word: str,
    tags: str = "",
) -> int:
    """加入生词本。成功返回 note 内部 id。

    Raises:
        WordNotInDictError: 词不在词库。
        DuplicateWordError: 词已在生词本。
    """
    entry = _check_dict_word(dict_db, word)
    ensure_notebook(nb_path)

    flds = FIELD_SEP.join(
        [entry["word"], entry["phonetic"] or "", entry["translation"] or "",
         entry["definition"] or "", entry["exchange"] or ""]
    )
    now = int(time.time())
    n_id = str(_gen_anki_id())

    con = _connect(nb_path)
    try:
        dup = con.execute(
            "SELECT id FROM notes WHERE sfld = ? COLLATE NOCASE",
            (word.strip(),),
        ).fetchone()
        if dup:
            raise DuplicateWordError(word)

        cur = con.execute(
            """
            INSERT INTO notes (n_id, m_id, mod, usn, tags, flds, sfld, csum, flags, data)
            VALUES (?, ?, ?, 0, ?, ?, ?, ?, 0, '')
            """,
            (n_id, MODEL_ID, now, tags.strip(), flds, word.strip(), _csum(flds)),
        )
        note_id = cur.lastrowid

        con.execute(
            """
            INSERT INTO cards
                (c_id, n_id, did, ord, mod, usn, type, queue, due,
                 ivl, factor, reps, lapses, left, odue, odid, flags, data)
            VALUES (?, ?, ?, 0, ?, 0, ?, ?, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, '')
            """,
            (str(_gen_anki_id()), note_id, DECK_ID, now, CARD_NEW, QUEUE_NEW),
        )
        con.commit()
        return note_id
    finally:
        con.close()


def remove_word(nb_path: str | Path, word: str) -> bool:
    """删除生词（notes 级联删 cards）。返回是否删除了。"""
    con = _connect(nb_path)
    try:
        cur = con.execute(
            "DELETE FROM notes WHERE sfld = ? COLLATE NOCASE", (word.strip(),)
        )
        con.commit()
        return cur.rowcount > 0
    finally:
        con.close()


def _row_to_entry(row: sqlite3.Row) -> NotebookEntry:
    flds = (row["flds"] or "").split(FIELD_SEP)
    # flds: word, phonetic, translation, definition, exchange
    padded = (flds + [""] * 5)[:5]
    return NotebookEntry(
        note_id=row["note_id"],
        card_id=row["card_id"],
        word=padded[0],
        phonetic=padded[1],
        translation=padded[2],
        definition=padded[3],
        exchange=padded[4],
        tags=row["tags"] or "",
        card_type=row["type"],
        queue=row["queue"],
        due=row["due"],
        ivl=row["ivl"],
        reps=row["reps"],
        lapses=row["lapses"],
        added_at=row["mod"],
    )


def list_words(
    nb_path: str | Path,
    limit: int = 50,
    include_suspended: bool = False,
) -> list[NotebookEntry]:
    """列出生词（加入时间倒序）。"""
    ensure_notebook(nb_path)
    con = _connect(nb_path)
    try:
        sql = """
            SELECT n.id AS note_id, n.flds, n.tags, n.mod,
                   c.id AS card_id, c.type, c.queue, c.due, c.ivl,
                   c.reps, c.lapses
            FROM notes n JOIN cards c ON c.n_id = n.id
        """
        if not include_suspended:
            sql += " WHERE c.queue >= 0"
        sql += " ORDER BY n.mod DESC LIMIT ?"
        return [_row_to_entry(r) for r in con.execute(sql, (limit,))]
    finally:
        con.close()


def due_words(nb_path: str | Path, limit: int = 20) -> list[NotebookEntry]:
    """今天到期待复习的词（due <= now，含新卡）。"""
    ensure_notebook(nb_path)
    now = int(time.time())
    con = _connect(nb_path)
    try:
        rows = con.execute(
            """
            SELECT n.id AS note_id, n.flds, n.tags, n.mod,
                   c.id AS card_id, c.type, c.queue, c.due, c.ivl,
                   c.reps, c.lapses
            FROM notes n JOIN cards c ON c.n_id = n.id
            WHERE c.queue >= 0 AND (c.type = 0 OR c.due <= ?)
            ORDER BY c.type ASC, c.due ASC LIMIT ?
            """,
            (now, limit),
        ).fetchall()
        return [_row_to_entry(r) for r in rows]
    finally:
        con.close()


def answer_card(
    nb_path: str | Path,
    card_id: int,
    ease: int,
) -> tuple[int, int]:
    """对一张卡打分（1-4），推进调度。返回 (next_ivl, next_due)。

    同时写入 revlog（复习历史）。纯函数。
    """
    ensure_notebook(nb_path)
    now = int(time.time())
    con = _connect(nb_path)
    try:
        card = con.execute(
            "SELECT ivl, reps, type FROM cards WHERE id = ?", (card_id,)
        ).fetchone()
        if card is None:
            raise LookupError(f"card 不存在: {card_id}")

        last_ivl = card["ivl"]
        next_ivl, next_due = due_timestamp(last_ivl, ease, now)
        new_type = CARD_REVIEW if ease >= 2 else CARD_LEARN

        con.execute(
            """
            UPDATE cards
            SET ivl = ?, due = ?, type = ?, reps = reps + 1,
                lapses = lapses + ?, mod = ?
            WHERE id = ?
            """,
            (next_ivl, next_due, new_type,
             1 if ease < 2 else 0, now, card_id),
        )
        con.execute(
            """
            INSERT INTO revlog (r_id, cid, usn, ease, ivl, last_ivl, factor, time, type)
            VALUES (?, ?, 0, ?, ?, ?, 0, 0, ?)
            """,
            (_gen_anki_id(), card_id, ease, next_ivl, last_ivl,
             0 if card["type"] == 0 else 1),
        )
        con.commit()
        return next_ivl, next_due
    finally:
        con.close()


def notebook_stats(nb_path: str | Path) -> dict[str, int]:
    """生词本统计。"""
    ensure_notebook(nb_path)
    con = _connect(nb_path)
    try:
        now = int(time.time())
        return {
            "total": con.execute(
                "SELECT COUNT(*) FROM notes").fetchone()[0],
            "new": con.execute(
                "SELECT COUNT(*) FROM cards WHERE type = 0").fetchone()[0],
            "review": con.execute(
                "SELECT COUNT(*) FROM cards WHERE type = 2").fetchone()[0],
            "due": con.execute(
                "SELECT COUNT(*) FROM cards WHERE queue >= 0 "
                "AND (type = 0 OR due <= ?)", (now,)).fetchone()[0],
            "lapses": con.execute(
                "SELECT COALESCE(SUM(lapses), 0) FROM cards").fetchone()[0],
        }
    finally:
        con.close()
