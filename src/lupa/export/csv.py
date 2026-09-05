"""Lupa 导出模块 — CSV。

主格式（Q3 相关决策：数据归自己，CSV 可 diff / 可进 Git / 任何工具能开）。
纯函数约束 #2：export_csv() 返回统计，不直接写 stdout。
"""
from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

from lupa.notebook.repo import FIELD_SEP, ensure_notebook, list_words

CSV_HEADER = [
    "word", "phonetic", "translation", "definition", "exchange", "tags", "added_at",
]


@dataclass(frozen=True)
class ExportReport:
    """导出结果统计。"""

    count: int
    path: str
    size_bytes: int


def export_csv(
    nb_path: str | Path,
    out_path: str | Path,
    limit: int = 10_000,
) -> ExportReport:
    """导出生词本为 UTF-8 CSV（带 BOM，Excel 直接打开不乱码）。"""
    ensure_notebook(nb_path)
    entries = list_words(nb_path, limit=limit, include_suspended=True)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        for e in entries:
            writer.writerow([
                e.word, e.phonetic, e.translation, e.definition,
                e.exchange.replace(FIELD_SEP, " | ") if e.exchange else "",
                e.tags, e.added_at,
            ])

    return ExportReport(
        count=len(entries),
        path=str(out),
        size_bytes=out.stat().st_size,
    )
