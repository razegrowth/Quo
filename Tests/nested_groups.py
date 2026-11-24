#!/usr/bin/env python3
"""Groups in groups (TabGroup.parent), as Dia 1.57 nests them, in a hidden probe.

Build first, then `python3 Tests/nested_groups.py` from a worktree. A group
goes inside another and comes out again; the row keeps each group's tabs
before the groups inside it; folding the outer group folds what's inside,
and still shows the tab in front from deep inside; New Group Inside makes a
group with an empty tab in it; eight levels and no more; never into itself;
Ungroup lifts what's inside up a level; Close Group closes what's inside
too, and one ⇧⌘T brings it all back, nested as it was; and the nesting
survives a relaunch.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("nested-groups")


def g(**f):
    return sv.cmd({"do": "group", **f})


def find(state, name):
    return next((x for x in state["groups"] if x["name"] == name), None)


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True, **{"tabs.groups": True}); sv.launch()
        a, b, c, d, e = (sv.page(n) for n in ("a", "b", "c", "d", "e"))
        g(id=a, new=True, name="Production")
        g(id=b, name="Production")
        g(id=c, new=True, name="Post")
        g(id=d, name="Post")

        s = g(name="Post", nest="Production")
        post = find(s, "Post")
        t.ok("Post goes inside Production", s["nested"] and post and post["parent"] == "Production" and post["depth"] == 1, s["groups"])
        names = [x["name"] for x in s["groups"]]
        t.ok("groups in tree order: Production, then Post", names.index("Production") < names.index("Post"), names)
        row = s["row"]
        t.ok("the row: Production's own tabs, then Post's, then the loose one",
             [x for x in row if x in (a, b, c, d, e)] == [a, b, c, d, e], row)

        s = g(name="Production", nest="Post")
        t.ok("never into a group inside itself", not s["nested"] and find(s, "Production")["parent"] is None, s["groups"])

        # Folded: Post isn't drawn, nothing inside is shown...
        sv.sp("select", id=e)
        s = g(name="Production", fold=True)
        t.ok("folding Production hides Post", not find(s, "Post")["drawn"], s["groups"])
        t.ok("…and no tab inside it is shown", not ({a, b, c, d} & set(s["shown"])), s["shown"])
        # ...except the tab in front, even from inside Post.
        sv.sp("select", id=c)
        s = g()
        if find(s, "Production")["collapsed"]:
            t.ok("folded, it still shows the tab in front from inside Post", find(s, "Production")["visible"] == [c], s["groups"])
        else:
            t.ok("going to a tab inside opens the groups it's in", not find(s, "Post")["collapsed"], s["groups"])
        s = g()
        if find(s, "Production")["collapsed"]:
            g(name="Production", fold=True)

        # New Group Inside: a new group in Post, with an empty tab in it, in front.
        s = g(name="Post", newInside=True)
        made = [x for x in s["groups"] if x["parent"] == "Post"]
        t.ok("New Group Inside makes a group in Post", len(made) == 1 and made[0]["depth"] == 2, s["groups"])
        t.ok("…with one tab in it, in front", made and len(made[0]["tabs"]) == 1 and s["active"] == made[0]["tabs"][0], (made, s["active"]))
        g(name=made[0]["name"], rename="Refs")

        # Eight levels at most.
        deep = "Refs"
        for level in range(3, 9):
            s = g(name=deep, newInside=True)
            child = next((x for x in s["groups"] if x["parent"] == deep), None)
            if not child:
                break
            g(name=child["name"], rename=f"L{level}")
            deep = f"L{level}"
        s = g()
        deepest = max(s["groups"], key=lambda x: x["depth"])
        t.ok("eight levels deep", deepest["depth"] == 7, [(x["name"], x["depth"]) for x in s["groups"]])
        s = g(name=deepest["name"], newInside=True)
        t.ok("…and no ninth", not any(x["parent"] == deepest["name"] for x in s["groups"]), [(x["name"], x["depth"]) for x in s["groups"]])

        # Ungroup Refs: what it held goes up into Post.
        refs_tab = find(g(), "Refs")["tabs"][0]
        s = g(name="Refs", ungroup=True)
        t.ok("Ungroup: Refs is gone", find(s, "Refs") is None, s["groups"])
        t.ok("…its tab is in Post now", refs_tab in find(s, "Post")["tabs"], find(s, "Post"))
        t.ok("…and the group inside it is in Post now", find(s, "L3")["parent"] == "Post", find(s, "L3"))

        # Out again to the top.
        s = g(name="L3", nest="top")
        t.ok("out to the top", s["nested"] and find(s, "L3")["parent"] is None and find(s, "L4")["parent"] == "L3", s["groups"])

        # Survives a relaunch, nesting and all.
        sv.sp("save"); sv.quit(); sv.launch(); time.sleep(0.6)
        s = g()
        t.ok("after a relaunch, Post is still inside Production", find(s, "Post") and find(s, "Post")["parent"] == "Production", s["groups"])

        # Close Group on Production takes Post too; one ⇧⌘T brings both back nested.
        s = g(name="Production", close=True)
        t.ok("Close Group closes the groups inside it", find(s, "Production") is None and find(s, "Post") is None, s["groups"])
        st = sv.sp("state")
        t.ok("…and their tabs", not ({a, b, c, d} & {x["id"] for x in st["tabs"]}), [x["id"] for x in st["tabs"]])
        sv.sp("reopen"); time.sleep(0.6)
        s = g()
        t.ok("one ⇧⌘T: both back", find(s, "Production") is not None and find(s, "Post") is not None, s["groups"])
        t.ok("…Post inside Production again", find(s, "Post") and find(s, "Post")["parent"] == "Production", s["groups"])
        t.ok("…each with its tabs", find(s, "Production") and len(find(s, "Production")["tabs"]) == 2
             and find(s, "Post") and len(find(s, "Post")["tabs"]) == 2, s["groups"])

        # Emptied of its own tabs, a group with a group inside it stays.
        prod = find(s, "Production")["tabs"]
        for tab in prod:
            g(id=tab, name="none")
        s = g()
        t.ok("a group holding only a group stays", find(s, "Production") is not None and find(s, "Post")["parent"] == "Production", s["groups"])
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
