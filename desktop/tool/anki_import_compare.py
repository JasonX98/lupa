# -*- coding: utf-8 -*-
"""apkg 导入一致性验证（openspec task 8.2）。

把 Python CLI 版与 Dart 桌面版导出的 .apkg 分别导入全新的 Anki collection
（anki 库 = Anki 桌面版同一 Rust 后端），逐项对比：
笔记数 / guid 集合 / 字段内容 / model id / deck 名。

运行：
  PYTHONPATH=<anki库目录> .venv/Scripts/python.exe desktop/tool/anki_import_compare.py

依赖：pip install --target <dir> anki
"""
import json
import os
import shutil
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PY_PKG = os.path.join(REPO, "desktop", "build", "lupa-python-verify.apkg")
DART_PKG = os.path.join(REPO, "desktop", "build", "lupa-desktop-verify.apkg")

from anki.collection import Collection  # noqa: E402
from anki import import_export_pb2  # noqa: E402


def import_pkg(apkg_path: str) -> dict:
    tmp = tempfile.mkdtemp(prefix="lupa-anki-")
    col = Collection(os.path.join(tmp, "c.anki2"))
    try:
        # 新后端（与 Anki 桌面版 23.10+ 同一 Rust 导入实现）
        request = import_export_pb2.ImportAnkiPackageRequest(package_path=apkg_path)
        col.import_anki_package(request)

        notes = list(col.db.execute("select guid, flds, mid from notes order by guid"))
        decks = [
            d["name"] for d in col.decks.all() if d["name"] != "Default"
        ]
        models = [(m["id"], m["name"]) for m in col.models.all()]
        # 只比对 Lupa 自带的 model；新 collection 初始化会生成内置 notetype
        # （Basic/Cloze 等），其 id 每次随机，与 apkg 内容无关，必须排除。
        lupa_models = [(int(i), n) for (i, n) in models if "Lupa" in n]
        return {
            "note_count": len(notes),
            "guids": sorted(r[0] for r in notes),
            "flds": sorted(r[1] for r in notes),
            "model_id": sorted(i for i, _ in lupa_models),
            "model_name": sorted(n for _, n in lupa_models),
            "deck_names": sorted(decks),
        }
    finally:
        col.close()
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    print(f"python 版: {PY_PKG} ({os.path.getsize(PY_PKG)} bytes)")
    print(f"dart   版: {DART_PKG} ({os.path.getsize(DART_PKG)} bytes)")

    py = import_pkg(PY_PKG)
    dart = import_pkg(DART_PKG)

    checks = [
        ("笔记数一致", py["note_count"] == dart["note_count"]),
        ("guid 集合一致", py["guids"] == dart["guids"]),
        ("字段内容一致", py["flds"] == dart["flds"]),
        ("model id 一致", py["model_id"] == dart["model_id"]),
        ("model 名一致", py["model_name"] == dart["model_name"]),
        ("deck 名一致", py["deck_names"] == dart["deck_names"]),
    ]

    print("\n-- 对比结果 --")
    for name, ok in checks:
        print(("PASS  " if ok else "FAIL  ") + name)

    print("\n-- 明细 --")
    print("python:", json.dumps(py, ensure_ascii=False, indent=1)[:1200])
    print("dart  :", json.dumps(dart, ensure_ascii=False, indent=1)[:1200])

    failed = [n for n, ok in checks if not ok]
    print(f"\n== {len(checks) - len(failed)}/{len(checks)} passed ==")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
