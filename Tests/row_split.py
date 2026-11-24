#!/usr/bin/env python3
"""A tab let go on the right half of another's row splits them, as Arc did
(TabDrag's `.row`), and a split stands as one row, its pages side by side.

Build first, then `python3 Tests/row_split.py` from a worktree. The hand is
put on a row's real place in the column (Bench `rowsplit`), and the drag's
own update and finish run there: its left half splits nothing (it is where
rows reorder), its right half shows the split and, let go, makes it, the
carried page on the right. Into a group, the carried tab joins the group;
onto a pair, it joins the pair; never onto itself or a pin. And a split row
is drawn as one line, its pages side by side (picture checked by eye).
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("row-split")


def rs(source, target, **f):
    return sv.cmd({"do": "rowsplit", "source": source, "target": target, **f})


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True, **{"tabs.groups": True}); sv.launch()
        a, b, c, d, e = (sv.page(n) for n in ("a", "b", "c", "d", "e"))
        time.sleep(0.5)

        left = rs(c, a, at=0.25)
        t.ok("the left half of a row splits nothing", left["drop"] == "outside" and left["shown"] == "", left)
        right = rs(c, a, at=0.75)
        t.ok("its right half shows the split", right["shown"] == a and right["showing"], right)
        t.ok("…and would split there", right["drop"] == "row:" + a, right)
        t.ok("…nothing made until let go", right["splits"] == [], right["splits"])

        own = rs(a, a, at=0.75)
        t.ok("never onto its own row", own["drop"] != "row:" + a, own)

        made = rs(c, a, at=0.8, drop=True)
        t.ok("let go: a and c side by side, c on the right", made["splits"] == [[a, c]], made["splits"])

        # A third page onto the pair's row joins the pair.
        time.sleep(0.4)
        # The pair's whole row is the row: its right half is the right page.
        third = rs(e, c, at=0.5, drop=True)
        t.ok("onto a pair: it joins it", any(len(s) == 3 and e in s for s in third["splits"]), third["splits"])

        # Into a group: the carried tab goes into the target's group.
        sv.cmd({"do": "group", "id": b, "new": True, "name": "Work"})
        time.sleep(0.4)
        grouped = rs(d, b, at=0.8, drop=True)
        work = next(g for g in sv.cmd({"do": "group"})["groups"] if g["name"] == "Work")
        t.ok("onto a grouped tab: they split", [b, d] in grouped["splits"], grouped["splits"])
        t.ok("…and the carried tab joins the group", d in work["tabs"] and b in work["tabs"], work)

    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
