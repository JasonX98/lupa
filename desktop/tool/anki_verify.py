import json
import sys

# 探测：确认 --run 脚本环境里 aqt/anki 可用
result = {"ok": False, "reason": ""}
try:
    from aqt import mw
    from anki.importing.apkg import AnkiPackageImporter

    apkg = r"D:\Projects\AISpace\LupaApp\desktop\lupa-spike.apkg"
    imp = AnkiPackageImporter(mw.col, apkg)
    imp.run()
    notes = mw.col.db.scalar("select count(*) from notes")
    cards = mw.col.db.scalar("select count(*) from cards")
    result = {
        "ok": True,
        "imported": int(imp.imported),
        "notes_after": int(notes),
        "cards_after": int(cards),
    }
except Exception as e:  # noqa: BLE001
    result = {"ok": False, "reason": f"{type(e).__name__}: {e}"}

print("ANKI_IMPORT_RESULT " + json.dumps(result, ensure_ascii=False))
sys.stdout.flush()
