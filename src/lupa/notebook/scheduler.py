"""Lupa 复习调度 — v1 固定间隔（Q5 拍板：C 固定间隔，v2 再接 FSRS）。

间隔档位：1 / 3 / 7 / 15 / 30 天。
答对（ease >= 2）推进下一档；答错（ease < 2）回到第一档。
纯函数约束 #2：不读 stdin / 不写 stdout。
"""
from __future__ import annotations

import time

# 固定间隔档位（天）
INTERVALS: tuple[int, ...] = (1, 3, 7, 15, 30)

# ease 取值约定（与 Anki 一致）：1=Again 忘了 / 2=Hard / 3=Good / 4=Easy
EASE_AGAIN = 1
EASE_HARD = 2
EASE_GOOD = 3
EASE_EASY = 4


def next_interval(current_ivl: int, ease: int) -> int:
    """根据当前间隔与评分，计算下一次间隔（天）。

    - 答错（ease=1）：回第一档（1 天）。
    - 答对：推进到比 current_ivl 更大的下一档；已在最高档则保持 30。
    - 新词（current_ivl=0）：答对进第一档。
    """
    if ease < EASE_HARD:
        return INTERVALS[0]
    for interval in INTERVALS:
        if interval > current_ivl:
            return interval
    return INTERVALS[-1]


def due_timestamp(current_ivl: int, ease: int, now: float | None = None) -> tuple[int, int]:
    """返回 (next_ivl, due_unix_seconds)。

    Anki 约定：review 卡的 due = 当天零点 + ivl 天的 unix 时间戳。
    v1 简化：now + ivl*86400。
    """
    next_ivl = next_interval(current_ivl, ease)
    ts = now if now is not None else time.time()
    return next_ivl, int(ts) + next_ivl * 86400
