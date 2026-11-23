#!/usr/bin/env python3
"""Apple's Writing Tools in a page's text boxes (Tab.swift's page menu and
configuration), in a hidden probe: the items first in a text box's menu,
the page itself taking them, and none for words you can't edit. Nothing is
run or shown.

Build first (`./build.sh`), then `python3 Tests/writing_tools.py`.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("writing-tools")


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()
        have = sv.cmd({"do": "intelligence", "action": "available"})["available"]
        print("  Apple Intelligence here:", have)
        page = sv.page("words")
        js = """(() => { document.body.innerHTML = '<textarea id=t style="width:500px;height:200px;margin:40px;font:18px sans-serif">i has went to the store yesterday and buyed some apple</textarea><p id=p style="margin:40px;font:18px sans-serif">Words on the page that nobody can edit at all.</p>';
          const t = document.getElementById('t'); t.focus(); t.select(); const r = t.getBoundingClientRect(); return [r.left + 50, r.top + 30]; })()"""
        x, y = sv.ev(page, js)
        menu = sv.cmd({"do": "linkmenu", "id": page, "x": x, "y": y, "pick": "nothing"}).get("menu", [])
        tools = next((m for m in menu if m.startswith("Writing Tools ›")), "")
        if not have:
            t.ok("without Apple Intelligence, no Writing Tools", not tools, menu)
            return
        t.ok("a text box's menu has Writing Tools", bool(tools), menu)
        t.ok("first, as in Safari and Mail", menu and menu[0] == tools, menu[:3])
        t.ok("with Proofread and Rewrite", "Proofread" in tools and "Rewrite" in tools, tools)
        t.ok("only once", sum(m.startswith("Writing Tools") for m in menu) == 1, menu)
        found = sv.cmd({"do": "writingtools", "id": page})
        t.ok("the page is set for Writing Tools' full rewriting", found["behavior"] == 1, found["behavior"])
        actions = [i for i in found["items"] if i["action"] == "showWritingTools:"]
        t.ok("and takes its actions itself", actions and all(i["target"] == "PageView" and i["enabled"] for i in actions), actions[:2])

        js = """(() => { const p = document.getElementById('p'); const r = document.createRange(); r.selectNodeContents(p);
          const s = getSelection(); s.removeAllRanges(); s.addRange(r); const b = r.getBoundingClientRect(); return [b.left + 40, b.top + 10]; })()"""
        x, y = sv.ev(page, js)
        menu = sv.cmd({"do": "linkmenu", "id": page, "x": x, "y": y, "pick": "nothing"}).get("menu", [])
        t.ok("words you can't edit don't get them", not any(m.startswith("Writing Tools") for m in menu), menu[:4])

        # Its switch off: a page opened from then on offers none.
        sv.cmd({"do": "ui", "writingTools": False})
        off = sv.page("words")
        js = """(() => { document.body.innerHTML = '<textarea id=t style="width:500px;height:200px;margin:40px">some words</textarea>';
          const t = document.getElementById('t'); t.focus(); t.select(); const r = t.getBoundingClientRect(); return [r.left + 50, r.top + 30]; })()"""
        x, y = sv.ev(off, js)
        menu = sv.cmd({"do": "linkmenu", "id": off, "x": x, "y": y, "pick": "nothing"}).get("menu", [])
        t.ok("with its switch off, a text box's menu has none", not any(m.startswith("Writing Tools") for m in menu), menu[:4])
        t.ok("and the page doesn't rewrite in place", sv.cmd({"do": "writingtools", "id": off})["behavior"] != 1)
        sv.cmd({"do": "ui", "writingTools": True})
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
