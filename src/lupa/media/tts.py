"""Lupa TTS 服务 — 有道 dictvoice 音频下载，blob 落 audio_cache（Q4：联网优先 + 本地缓存）。

缓存键三段式（跨语言友好 #3）：{provider}:{word}:{fmt}，fmt = mp3（口音由 url 参数区分，
同词英美音分两条缓存：fmt 记 mp3，键里 word 后附口音标记）。
纯函数约束 #2：不读 stdin / 不写 stdout。
"""
from __future__ import annotations

import sqlite3
import tempfile
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


class TtsFetchError(RuntimeError):
    """TTS 获取失败。"""


@dataclass(frozen=True)
class AudioResult:
    """一次 TTS 查询的结果。"""

    word: str
    accent: str          # uk / us
    size_bytes: int
    from_cache: bool
    blob: bytes


def _accent_param(accent: str) -> str:
    """口音 -> 有道 dictvoice 的 type 参数。1=英音 2=美音。"""
    return {"uk": "1", "us": "2"}[accent.lower()]


def _cache_get(nb_path: str | Path, key: str) -> bytes | None:
    con = sqlite3.connect(str(nb_path))
    try:
        row = con.execute(
            "SELECT blob FROM audio_cache WHERE cache_key = ?", (key,)
        ).fetchone()
        if row is None:
            return None
        con.execute(
            "UPDATE audio_cache SET hit_count = hit_count + 1 WHERE cache_key = ?",
            (key,),
        )
        con.commit()
        return bytes(row[0])
    finally:
        con.close()


def _cache_put(
    nb_path: str | Path,
    key: str,
    word: str,
    provider: str,
    url: str,
    blob: bytes,
) -> None:
    con = sqlite3.connect(str(nb_path))
    try:
        con.execute(
            """
            INSERT INTO audio_cache (cache_key, word, provider, fmt, url,
                                     blob, size_bytes, fetched_at, hit_count)
            VALUES (?, ?, ?, 'mp3', ?, ?, ?, ?, 0)
            ON CONFLICT(cache_key) DO UPDATE SET
                blob = excluded.blob,
                url = excluded.url,
                size_bytes = excluded.size_bytes,
                fetched_at = excluded.fetched_at
            """,
            (key, word, provider, url, blob, len(blob), int(time.time())),
        )
        con.commit()
    finally:
        con.close()


def fetch_online(
    word: str,
    accent: str,
    tts_url: str,
    timeout: float = 15.0,
) -> bytes:
    """联网取发音 mp3。失败抛 TtsFetchError。"""
    from urllib.parse import quote

    url = tts_url.format(word=quote(word), accent=_accent_param(accent))
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            blob = resp.read()
    except Exception as e:  # noqa: BLE001
        raise TtsFetchError(f"TTS 请求失败: {e}") from e
    # dictvoice 对未收录词可能返回极小空响应
    if len(blob) < 512:
        raise TtsFetchError(f"TTS 返回内容异常（{len(blob)} 字节）: {word}")
    return blob


def get_audio(
    nb_path: str | Path,
    word: str,
    accent: str,
    tts_url: str,
    provider: str = "youdao",
    use_cache: bool = True,
) -> AudioResult:
    """取发音：缓存优先，未命中联网并落库。accent = uk / us。纯函数。"""
    word = word.strip()
    accent = accent.lower()
    # 同词英美音分开缓存：口音并入 fmt 段（如 youdao:abandon:mp3-us）
    key = f"{provider}:{word.lower()}:mp3-{accent}"

    if use_cache:
        blob = _cache_get(nb_path, key)
        if blob:
            return AudioResult(word, accent, len(blob), True, blob)

    blob = fetch_online(word, accent, tts_url)
    url = tts_url.format(word=word, accent=_accent_param(accent))
    _cache_put(nb_path, key, word, provider, url, blob)
    return AudioResult(word, accent, len(blob), False, blob)


def blob_to_tempfile(blob: bytes, suffix: str = ".mp3") -> Path:
    """把音频 blob 写到临时文件，返回路径（供播放器打开）。"""
    fd, path = tempfile.mkstemp(suffix=suffix, prefix="lupa-")
    with open(fd, "wb") as f:
        f.write(blob)
    return Path(path)
