#!/usr/bin/env python3
"""The address bar's list as wide as the address bar (TabOffers.swift).

Build first, then `python3 Tests/address_list_width.py` from a worktree. With
the address bar above the page, what's typed in it brings up a list whose
edges are the field's box's own (its frame is 8 points wider either side,
for its shadow) and whose top is the box's bottom, one card with it as Dia
has, not one held to a tab's 460 points at the left. With the address in
the column instead, the list is the tab's size, as before.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("address-list-width")


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True, **{"sidebar.addressBar": True}); sv.launch()
        sv.page("temu"); sv.page("tello"); time.sleep(0.4)
        r = sv.cmd({"do": "tab-type", "text": "te", "clear": True})
        list_, box = r["list"], r["box"]
        t.ok("the list is up", r["listShown"] and list_ and box, r)
        if list_ and box:
            # The box the field is drawn in, not the text inside it: the two
            # are one card, the list hanging from the box's bottom edge.
            t.ok("its left edge is the box's", abs((list_[0] + 8) - box[0]) <= 0.5, (list_, box))
            t.ok("its right edge is the box's", abs((list_[0] + list_[2] - 8) - (box[0] + box[2])) <= 0.5, (list_, box))
            t.ok("its top is the box's bottom", abs((list_[1] + list_[3]) - box[1]) <= 0.5, (list_, box))
            t.ok("wider than a tab's list ever was", list_[2] > 460, list_)
        sv.quit()

        sv.setup(sidebar=True, **{"sidebar.addressBar": False}); sv.launch()
        sv.page("temu"); sv.page("tello"); time.sleep(0.4)
        r = sv.cmd({"do": "tab-type", "text": "te", "clear": True})
        t.ok("in the column: the list is a tab's size", r["listShown"] and r["list"] and 320 <= r["list"][2] <= 460, r.get("list"))
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
