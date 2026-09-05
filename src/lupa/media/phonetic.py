"""Lupa 音标服务 — 联网取美/英音标，结果落 phonetic_cache（Q4：联网优先 + 本地缓存）。

缓存键三段式（跨语言友好 #3）：{provider}:{word}:{fmt}，fmt = us / uk。
纯函数约束 #2：不读 stdin / 不写 stdout；联网异常抛出，不吞错。
"""
from __future__ import annotations

import json
import sqlite3
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


class PhoneticFetchError(RuntimeError):
    """音标获取失败。"""


@dataclass(frozen=True)
class PhoneticResult:
    """一次音标查询的结果。"""

    word: str
    uk: str
    us: str
    from_cache: bool


def _http_get_json(url: str, timeout: float = 10.0) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def _cache_get(nb_path: str | Path, key: str) -> str | None:
    con = sqlite3.connect(str(nb_path))
    try:
        row = con.execute(
            "SELECT phonetic FROM phonetic_cache WHERE cache_key = ?", (key,)
        ).fetchone()
        if row is None:
            return None
        con.execute(
            "UPDATE phonetic_cache SET hit_count = hit_count + 1 WHERE cache_key = ?",
            (key,),
        )
        con.commit()
        return row[0]
    finally:
        con.close()


def _cache_put(
    nb_path: str | Path,
    key: str,
    word: str,
    provider: str,
    fmt: str,
    url: str,
    phonetic: str,
) -> None:
    con = sqlite3.connect(str(nb_path))
    try:
        con.execute(
            """
            INSERT INTO phonetic_cache (cache_key, word, provider, fmt, url,
                                        phonetic, fetched_at, hit_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(cache_key) DO UPDATE SET
                phonetic = excluded.phonetic,
                url = excluded.url,
                fetched_at = excluded.fetched_at
            """,
            (key, word, provider, fmt, url, phonetic, int(time.time())),
        )
        con.commit()
    finally:
        con.close()


def fetch_online(
    word: str,
    phonetic_url: str,
    timeout: float = 10.0,
) -> dict[str, str]:
    """联网查音标。返回 {"uk": ..., "us": ...}。失败抛 PhoneticFetchError。"""
    try:
        data = _http_get_json(phonetic_url.format(word=urllib.request.quote(word)), timeout)
    except Exception as e:  # noqa: BLE001 — 网络异常统一转为领域错误
        raise PhoneticFetchError(f"音标请求失败: {e}") from e

    entry = (
        data.get("simple", {}).get("word")
        or data.get("ec", {}).get("word")
        or [{}]
    )
    entry = entry[0] if entry else {}
    uk = (entry.get("ukphone") or "").strip()
    us = (entry.get("usphone") or "").strip()
    if not uk and not us:
        raise PhoneticFetchError(f"接口未返回音标: {word}")
    return {"uk": uk, "us": us}


def get_phonetic(
    nb_path: str | Path,
    word: str,
    phonetic_url: str,
    provider: str = "youdao",
    use_cache: bool = True,
) -> PhoneticResult:
    """查音标：缓存优先，未命中联网并落库。纯函数。"""
    word = word.strip()
    uk_key = f"{provider}:{word.lower()}:uk"
    us_key = f"{provider}:{word.lower()}:us"

    uk = us = None
    if use_cache:
        uk = _cache_get(nb_path, uk_key)
        us = _cache_get(nb_path, us_key)
    if uk and us:
        return PhoneticResult(word=word, uk=uk, us=us, from_cache=True)

    online = fetch_online(word, phonetic_url)
    uk = uk or online["uk"]
    us = us or online["us"]
    _cache_put(nb_path, uk_key, word, provider, "uk", phonetic_url, uk)
    _cache_put(nb_path, us_key, word, provider, "us", phonetic_url, us)
    return PhoneticResult(word=word, uk=uk, us=us, from_cache=False)
