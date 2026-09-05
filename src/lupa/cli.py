"""Lupa CLI — Typer 入口。

约束（跨语言友好 #2）：本模块只做参数解析、调用纯函数、格式化输出。
业务逻辑一律在 lupa.dict.query / lupa.notebook.repo / lupa.export 等模块。
"""
from __future__ import annotations

import os
import time
from pathlib import Path

import typer

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
