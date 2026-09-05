"""Lupa CLI — Typer 入口。

约束（跨语言友好 #2）：本模块只做参数解析、调用纯函数、格式化输出。
业务逻辑一律在 lupa.dict.query / lupa.notebook.repo / lupa.export 等模块。
"""
from __future__ import annotations

import os
import time
from pathlib import Path

import typer

from lupa.config import load_config, provider_config
from lupa.dict.query import dict_stats, query_word, suggest_prefix
from lupa.notebook import repo as nb
from lupa import __version__

app = typer.Typer(
    name="lupa",
    help="Lupa / 璐帕 — 看清词，留住词，归你所有。",
    no_args_is_help=True,
)


def data_home() -> Path:
    """数据目录：LUPA_HOME 环境变量优先，默认 ~/.lupa。"""
    env = os.environ.get("LUPA_HOME")
    return Path(env) if env else Path.home() / ".lupa"


def dict_db() -> Path:
    return data_home() / "dict.sqlite"


def notebook_db() -> Path:
    return data_home() / "notebook.sqlite"


@app.command()
def search(
    word: str = typer.Argument(..., help="要查询的单词"),
    suggest: int = typer.Option(0, "--suggest", "-s", help="同时显示前缀联想数量"),
) -> None:
    """查词（大小写不敏感）。"""
    db = dict_db()
    if not db.exists():
        typer.secho(
            f"词库不存在: {db}\n先运行 lupa build 或参考 README 构建词库。",
            fg=typer.colors.RED,
        )
        raise typer.Exit(code=1)

    entry = query_word(db, word)
    if entry is None:
        typer.secho(f"未收录: {word}", fg=typer.colors.YELLOW)
        if suggest:
            words = suggest_prefix(db, word, limit=suggest)
            if words:
                typer.echo("你可能想查: " + ", ".join(words))
        raise typer.Exit(code=1)

    # 标题行：单词 + 音标
    header = entry.word
    if entry.phonetic:
        header += f"  /{entry.phonetic}/"
    tags = []
    if entry.oxford:
        tags.append("牛津3000")
    if entry.collins:
        tags.append(f"柯林斯{entry.collins}星")
    if entry.tag:
        tags.append(entry.tag)
    if tags:
        header += f"  [{', '.join(tags)}]"
    typer.secho(header, fg=typer.colors.CYAN, bold=True)

    if entry.translation:
        typer.echo(entry.translation)
    if entry.definition:
        typer.echo(f"  -- {entry.definition}")

    # 词形变化
    ex = entry.exchanges
    if ex:
        labels = {
            "d": "过去式", "p": "过去分词", "i": "现在分词", "3": "三单",
            "s": "复数", "r": "比较级", "t": "最高级",
        }
        parts = [f"{labels.get(k, k)} {v}" for k, v in ex.items()]
        typer.secho("变形: " + " | ".join(parts), fg=typer.colors.MAGENTA)

    if suggest:
        words = suggest_prefix(db, word, limit=suggest)
        if words:
            typer.secho("联想: " + ", ".join(words), fg=typer.colors.BLUE)


@app.command()
def info() -> None:
    """查看词库统计。"""
    db = dict_db()
    if not db.exists():
        typer.secho(f"词库不存在: {db}", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    stats = dict_stats(db)
    typer.echo(f"词库路径: {db}")
    typer.echo(f"总词数:   {stats['total']:,}")
    typer.echo(f"含音标:   {stats['with_phonetic']:,}")
    typer.echo(f"含英解:   {stats['with_definition']:,}")


@app.command()
def version() -> None:
    """显示版本。"""
    typer.echo(f"Lupa v{__version__}")


# ---------- 生词本 ----------


@app.command()
def add(
    word: str = typer.Argument(..., help="要加入生词本的单词"),
    tags: str = typer.Option("", "--tags", "-t", help="标签，空格分隔"),
) -> None:
    """加入生词本。"""
    db, ndb = dict_db(), notebook_db()
    if not db.exists():
        typer.secho("词库不存在，先构建词库。", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    try:
        nb.add_word(ndb, db, word, tags)
    except nb.WordNotInDictError:
        typer.secho(f"词库未收录: {word}", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)
    except nb.DuplicateWordError:
        typer.secho(f"已在生词本中: {word}", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)
    entry = query_word(db, word)
    typer.secho(f"已加入生词本: {entry.word}", fg=typer.colors.GREEN)


@app.command(name="rm")
def remove(
    word: str = typer.Argument(..., help="要移除的单词"),
) -> None:
    """从生词本移除。"""
    if nb.remove_word(notebook_db(), word):
        typer.secho(f"已移除: {word}", fg=typer.colors.GREEN)
    else:
        typer.secho(f"生词本中没有: {word}", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)


@app.command(name="list")
def list_words_cmd(
    limit: int = typer.Option(50, "--limit", "-n", help="最多显示条数"),
    all: bool = typer.Option(False, "--all", "-a", help="含已暂停卡片"),
) -> None:
    """列出生词本（新加入在前）。"""
    entries = nb.list_words(notebook_db(), limit=limit, include_suspended=all)
    if not entries:
        typer.echo("生词本为空。用 lupa add <word> 添加。")
        return
    typer.echo(f"{'单词':<20}{'状态':<10}{'间隔':<8}{'下次复习':<20}标签")
    for e in entries:
        state = {0: "新词", 1: "学习中", 2: "复习中"}.get(e.card_type, "?")
        due = "-" if e.card_type == 0 else time.strftime("%m-%d %H:%M", time.localtime(e.due))
        typer.echo(f"{e.word:<20}{state:<10}{e.ivl:>3}天    {due:<20}{e.tags}")


@app.command()
def stats() -> None:
    """生词本统计。"""
    s = nb.notebook_stats(notebook_db())
    typer.echo(f"生词总数: {s['total']}")
    typer.echo(f"新词:     {s['new']}")
    typer.echo(f"复习中:   {s['review']}")
    typer.echo(f"今日期待: {s['due']}")
    typer.echo(f"累计忘记: {s['lapses']}")


@app.command()
def review(
    limit: int = typer.Option(20, "--limit", "-n", help="本次最多复习张数"),
    speak: bool = typer.Option(False, "--speak", "-s", help="每张卡自动朗读（有道 TTS）"),
) -> None:
    """交互式复习：逐词答题，固定间隔调度（1/3/7/15/30 天）。"""
    from lupa.notebook.scheduler import EASE_AGAIN, EASE_EASY, EASE_GOOD, EASE_HARD

    ndb = notebook_db()
    if not Path(ndb).exists():
        typer.secho("生词本为空。先 lupa add <word>。", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)

    cards = nb.due_words(ndb, limit=limit)
    if not cards:
        typer.secho("今日没有待复习的词。", fg=typer.colors.GREEN)
        raise typer.Exit()

    speaker = None
    if speak:
        cfg = load_config(data_home())
        pcfg = provider_config(cfg)
        nb_path = data_home() / "notebook.sqlite"
        nb.ensure_notebook(nb_path)
        from lupa.media import tts

        def speaker(word: str) -> None:
            try:
                r = tts.get_audio(nb_path, word, "us", pcfg["tts_url"])
                os.startfile(tts.blob_to_tempfile(r.blob))
            except Exception as e:  # noqa: BLE001 — 发音失败不阻断复习
                typer.secho(f"  (发音失败: {e})", fg=typer.colors.YELLOW)

    typer.echo(f"待复习 {len(cards)} 张卡。评分: 1=忘了 2=Hard 3=Good 4=Easy，s=跳过 q=退出\n")

    ease_map = {"1": EASE_AGAIN, "2": EASE_HARD, "3": EASE_GOOD, "4": EASE_EASY}
    state_names = {0: "新词", 1: "学习中", 2: "复习中", 3: "重学"}

    reviewed = 0
    again = 0
    skip = 0
    for i, e in enumerate(cards, 1):
        # 正面：单词 + 音标 + 状态
        state = state_names.get(e.card_type, "?")
        front = e.word
        if e.phonetic:
            front += f"  /{e.phonetic}/"
        typer.secho(f"[{i}/{len(cards)}] ({state}, 间隔{e.ivl}天)  {front}",
                    fg=typer.colors.CYAN, bold=True)
        if speaker:
            speaker(e.word)
        typer.prompt("想起来了就回车", default="", show_default=False)

        # 背面：释义
        if e.translation:
            typer.echo(e.translation)
        if e.definition:
            typer.echo(f"  -- {e.definition}")
        if e.exchange:
            typer.echo(f"  变形: {e.exchange}")

        while True:
            raw = typer.prompt(
                typer.style("评分 [1/2/3/4] s=跳过 q=退出", fg=typer.colors.YELLOW),
                default="3", show_default=True,
            ).strip().lower()
            if raw in ease_map or raw in ("s", "q"):
                break
            typer.secho("无效输入，请输入 1-4 / s / q", fg=typer.colors.RED)

        if raw == "q":
            typer.echo("\n提前结束。")
            break
        if raw == "s":
            skip += 1
            typer.echo()
            continue

        next_ivl, next_due = nb.answer_card(ndb, e.card_id, ease_map[raw])
        reviewed += 1
        if ease_map[raw] == EASE_AGAIN:
            again += 1
            typer.secho(f"  -> 忘了，明天见", fg=typer.colors.RED)
        else:
            due = time.strftime("%m-%d %H:%M", time.localtime(next_due))
            typer.secho(f"  -> 下次 {next_ivl} 天后 ({due})", fg=typer.colors.GREEN)
        typer.echo()

    typer.secho(
        f"本次完成: 答题 {reviewed}，跳过 {skip}，忘了 {again}。剩余待复习: "
        f"{len(nb.due_words(ndb, limit=9999))}",
        fg=typer.colors.CYAN if reviewed else typer.colors.YELLOW,
    )


# ---------- 发音 / 音标（Q4：联网优先 + 本地缓存） ----------


def _media_paths() -> tuple[Path, dict]:
    home = data_home()
    cfg = load_config(home)
    ndb = home / "notebook.sqlite"
    nb.ensure_notebook(ndb)
    return ndb, cfg


@app.command()
def say(
    word: str = typer.Argument(..., help="要朗读的单词"),
    accent: str = typer.Option("us", "--accent", "-a", help="口音: us | uk"),
    provider: str = typer.Option(None, "--provider", "-p", help="服务商（默认取配置）"),
) -> None:
    """朗读单词（联网 TTS，结果缓存到本地）。"""
    import os

    from lupa.media.tts import TtsFetchError, blob_to_tempfile, get_audio

    ndb, cfg = _media_paths()
    name = provider or cfg["default_provider"]
    try:
        pcfg = provider_config(cfg, name)
        audio = get_audio(ndb, word, accent, pcfg["tts_url"], provider=name)
    except KeyError as e:
        typer.secho(str(e), fg=typer.colors.RED)
        raise typer.Exit(code=1)
    except TtsFetchError as e:
        typer.secho(str(e), fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)

    src = "(缓存)" if audio.from_cache else "(联网)"
    typer.secho(f"{audio.word} [{audio.accent}] {src} {audio.size_bytes / 1024:.1f} KB",
                fg=typer.colors.GREEN)
    path = blob_to_tempfile(audio.blob)
    os.startfile(path)  # Windows 默认播放器异步播放


@app.command()
def phonetic(
    word: str = typer.Argument(..., help="要查音标的单词"),
    provider: str = typer.Option(None, "--provider", "-p", help="服务商（默认取配置）"),
) -> None:
    """查美/英音标（ECDICT 音标之外联网补充，结果缓存）。"""
    from lupa.media.phonetic import PhoneticFetchError, get_phonetic

    ndb, cfg = _media_paths()
    name = provider or cfg["default_provider"]
    try:
        pcfg = provider_config(cfg, name)
        r = get_phonetic(ndb, word, pcfg["phonetic_url"], provider=name)
    except KeyError as e:
        typer.secho(str(e), fg=typer.colors.RED)
        raise typer.Exit(code=1)
    except PhoneticFetchError as e:
        typer.secho(str(e), fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)

    src = "缓存" if r.from_cache else "联网"
    typer.secho(f"{r.word}  [{src}]", fg=typer.colors.CYAN, bold=True)
    typer.echo(f"  英: /{r.uk}/")
    typer.echo(f"  美: /{r.us}/")


@app.command(name="cache-stats")
def cache_stats() -> None:
    """发音/音标缓存统计。"""
    import sqlite3

    ndb = data_home() / "notebook.sqlite"
    if not ndb.exists():
        typer.echo("暂无缓存。")
        return
    con = sqlite3.connect(str(ndb))
    try:
        n_audio, hits_audio = con.execute(
            "SELECT COUNT(*), COALESCE(SUM(hit_count),0) FROM audio_cache"
        ).fetchone()
        n_ph, hits_ph = con.execute(
            "SELECT COUNT(*), COALESCE(SUM(hit_count),0) FROM phonetic_cache"
        ).fetchone()
        size = con.execute(
            "SELECT COALESCE(SUM(size_bytes),0) FROM audio_cache").fetchone()[0]
    finally:
        con.close()
    typer.echo(f"发音缓存: {n_audio} 条 / {size / 1024:.1f} KB / 命中 {hits_audio} 次")
    typer.echo(f"音标缓存: {n_ph} 条 / 命中 {hits_ph} 次")


# ---------- 导出 ----------


@app.command()
def export(
    fmt: str = typer.Option("apkg", "--format", "-f", help="导出格式: apkg | csv"),
    out: Path = typer.Option(None, "--out", "-o", help="输出文件路径"),
) -> None:
    """导出生词本（默认 Anki apkg）。"""
    from lupa.export.apkg import export_apkg
    from lupa.export.csv import export_csv

    ndb = notebook_db()
    if not Path(ndb).exists():
        typer.secho("生词本为空。先 lupa add <word>。", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)

    if fmt == "apkg":
        target = out or Path("lupa-export.apkg")
        report = export_apkg(ndb, target)
    elif fmt == "csv":
        target = out or Path("lupa-export.csv")
        report = export_csv(ndb, target)
    else:
        typer.secho(f"未知格式: {fmt}（支持 apkg / csv）", fg=typer.colors.RED)
        raise typer.Exit(code=1)

    typer.secho(
        f"已导出 {report.count} 词 -> {report.path} ({report.size_bytes / 1024:.1f} KB)",
        fg=typer.colors.GREEN,
    )


if __name__ == "__main__":
    app()
