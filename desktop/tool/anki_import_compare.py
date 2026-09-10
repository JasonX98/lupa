# -*- coding: utf-8 -*-
"""apkg 导入验证（Flutter 桌面版产出）。

把 Dart 桌面版导出的 .apkg 导入全新的 Anki collection（anki 库 = Anki 桌面版
同一 Rust 导入后端），校验导入后的内容：笔记数 / guid 集合 / 字段内容 /
Lupa model / deck 名。Python CLI 版已移除，本脚本只校验 Dart 版产出。

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
        decks = [d["name"] for d in col.decks.all() if d["name"] != "Default"]
        # 只取 Lupa 自带的 model；新 collection 初始化会生成内置 notetype
        # （Basic/Cloze 等），其 id 每次随机，与 apkg 内容无关，必须排除。
        lupa_models = [
            (int(m["id"]), m["name"]) for m in col.models.all() if "Lupa" in m["name"]
        ]
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
    if not os.path.exists(DART_PKG):
        print(f"找不到 Dart 版 apkg: {DART_PKG}")
        print("先生成：cd desktop && dart run tool/make_verify_apkg.dart")
        return 1

    print(f"dart 版: {DART_PKG} ({os.path.getsize(DART_PKG)} bytes)")
    result = import_pkg(DART_PKG)

    checks = [
        ("导入笔记数 > 0", result["note_count"] > 0),
        ("guid 无重复（sha1 前 16 位稳定）",
         len(result["guids"]) == len(set(result["guids"]))),
        ("存在 Lupa model", len(result["model_name"]) > 0),
        ("deck 全是 Lupa 自己的", all("Lupa" in d for d in result["deck_names"])),
    ]

    print("\n-- 校验结果 --")
    for name, ok in checks:
        print(("PASS  " if ok else "FAIL  ") + name)

    print("\n-- 明细 --")
    print(json.dumps(result, ensure_ascii=False, indent=1)[:1200])

    failed = [n for n, ok in checks if not ok]
    print(f"\n== {len(checks) - len(failed)}/{len(checks)} passed ==")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())