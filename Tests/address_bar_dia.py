#!/usr/bin/env python3
"""The address bar above the page, as Dia has it (AddressBar.swift).

Build first, then `python3 Tests/address_bar_dia.py` from a worktree. A click
on the field is to type, the whole address selected, with no site card under
it; the site menu button (its buttons up as under the pointer) brings the
card up as a menu without an edit, and again puts it away; a click to type
puts it away too. The bar's
look at rest, under the pointer, and with the menu up is pictured, checked by
eye: the window's picture doesn't hold the menu, which is pictured alone.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("address-bar-dia")
OUT = sys.argv[1] if len(sys.argv) > 1 else None


def bar(**f):
    return sv.cmd({"do": "addressbar", **f})


def picture(name):
    if OUT:
        sv.cmd({"do": "picture", "path": f"{OUT}/bar-{name}.png", "page": False})


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True, **{"sidebar.addressBar": True}); sv.launch()
        sv.page("watch"); time.sleep(0.6)
        picture("rest")

        r = bar(hover=True)
        t.ok("under the pointer: the site menu button is there", r["anchor"], r)
        picture("hover")

        r = bar(menu=True, picture=f"{OUT}/bar-menu.png" if OUT else None)
        t.ok("the site menu: the card comes up", r["card"] and r["menu"], r)
        t.ok("…without an edit", not r["editing"], r)
        r = bar(menu=True)
        t.ok("the button again: it goes", not r["card"], r)

        bar(menu=True)
        r = bar(hover=False, click=True)
        t.ok("a click to type: editing", r["editing"], r)
        t.ok("…no card under it, and the menu put away", not r["card"], r)
        picture("click")
        sv.cmd({"do": "press", "code": 53, "chars": "\u001b", "mods": []}); time.sleep(0.4)

    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
