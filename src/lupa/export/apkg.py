"""Lupa 导出模块 — Anki .apkg（genanki）。

设计要点（参考调研案例 anki_packager）：
- 固定 model_id / deck_id（随机但持久，保证多次导出在 Anki 中合并而非重复建 deck）
- note guid 用单词 hash（稳定）：同词重复导出，Anki 端更新而非重复建卡
- 字段与 notes.flds 五段对齐：word / phonetic / translation / definition / exchange
纯函数约束 #2：export_apkg() 返回统计，不直接写 stdout。
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

import genanki

from lupa.notebook.repo import FIELD_SEP, ensure_notebook, list_words

# 固定 id（对 genanki：随机但每次运行相同 -> Anki 端稳定合并）
_MODEL_ID = 1607392319      # Lupa 单词卡模型
_DECK_ID = 2059400110       # Lupa::生词本

_CSS = """
.card {
    font-family: "Microsoft YaHei", sans-serif;
    font-size: 22px;
    text-align: center;
    color: #333;
    background-color: #fdfdfd;
}
.word { font-size: 40px; font-weight: bold; color: #1a1a2e; }
.phonetic { color: #666; font-size: 20px; margin-top: 8px; }
.answer-block { text-align: left; margin: 16px auto 0; max-width: 480px; }
.meaning { margin: 6px 0; line-height: 1.55; }
.en { color: #555; font-style: italic; font-size: 18px; }
.exchange { color: #8a4fbd; font-size: 17px; margin-top: 12px; }
"""

# 模板：正面单词，背面音标 + 中英释义 + 变形
_MODEL = genanki.Model(
    _MODEL_ID,
    "Lupa 单词卡",
    fields=[
        {"name": "Word"},
        {"name": "Phonetic"},
        {"name": "Translation"},
        {"name": "Definition"},
        {"name": "Exchange"},
        {"name": "Tags"},
    ],
    templates=[
        {
            "name": "单词 -> 释义",
            "qfmt": '<div class="word">{{Word}}</div>',
            "afmt": (
                '{{FrontSide}}<hr id="answer">'
                '<div class="answer-block">'
                '<div class="phonetic">{{Phonetic}}</div>'
                '<div class="meaning">{{Translation}}</div>'
                '<div class="en">{{Definition}}</div>'
                '<div class="exchange">{{Exchange}}</div>'
                "</div>"
            ),
        },
    ],
    css=_CSS,
)


@dataclass(frozen=True)
class ExportReport:
    """导出结果统计。"""

    count: int
    path: str
    size_bytes: int


def _stable_guid(word: str) -> str:
    """同词稳定 guid：Anki 重复导入时更新而非重复建卡。"""
    return hashlib.sha1(f"lupa::{word}".encode("utf-8")).hexdigest()[:16]


def _fmt_exchange(exchange: str) -> str:
    if not exchange:
        return ""
    labels = {
        "d": "过去式", "p": "过去分词", "i": "现在分词", "3": "三单",
        "s": "复数", "r": "比较级", "t": "最高级",
    }
    parts = []
    for seg in exchange.split("/"):
        if ":" in seg:
            key, _, value = seg.partition(":")
            if value:
                parts.append(f"{labels.get(key, key)} {value}")
    return "<br>".join(parts)


def _fmt_phonetic(phonetic: str) -> str:
    return f"/{phonetic}/" if phonetic.strip() else ""


def export_apkg(
    nb_path: str | Path,
    out_path: str | Path,
    limit: int = 10_000,
    deck_name: str = "Lupa::生词本",
) -> ExportReport:
    """导出生词本为 Anki .apkg（Legacy 2 格式，genanki 默认）。"""
    ensure_notebook(nb_path)
    entries = list_words(nb_path, limit=limit, include_suspended=True)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    deck = genanki.Deck(_DECK_ID, deck_name)
    for e in entries:
        flds = [e.word, e.phonetic, e.translation, e.definition, e.exchange]
        word = flds[0]
        phonetic = _fmt_phonetic(e.phonetic)
        translation = (e.translation or "").strip()
        definition = (e.definition or "").strip().replace("\n", "<br>")
        tags = e.tags.split() if e.tags else []
        note = genanki.Note(
            model=_MODEL,
            fields=[word, phonetic, translation, definition,
                    _fmt_exchange(e.exchange), e.tags],
            guid=_stable_guid(word),
            tags=tags,
        )
        deck.add_note(note)

    genanki.Package(deck).write_to_file(str(out))
    return ExportReport(
        count=len(entries),
        path=str(out),
        size_bytes=out.stat().st_size,
    )
