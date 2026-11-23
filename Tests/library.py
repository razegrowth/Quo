#!/usr/bin/env python3
"""The Library past the first space (Library.swift), in a hidden probe: two
fingers to the right bring it in, Downloads first; a short stroke snaps back,
a quick one carries; past all the way in it gives a little; two fingers back
put it away; the page beside the column gives way by the rail as it comes.

Build first (`./build.sh`), then `python3 Tests/library.py`.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("library")


def lib(action="state", **f):
    # A stroke right after another is let go by (SpaceSwipe.rest): a pause first.
    if action == "swipe":
        time.sleep(0.5)
    return sv.cmd({"do": "library", "action": action, **f})


def page_x():
    st = sv.sp("state")
    frames = st.get("paneFrames") or []
    return min(f["x"] for f in frames) if frames else None


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True)
        sv.launch()
        sv.page("a")
        s = lib()
        t.ok("a column on the left has a Library", s["available"] and not s["shown"] and s["reveal"] == 0, s)
        before = page_x()

        s = lib("swipe", steps=[3] * 10, every=0.03)
        t.ok("a short, slow stroke snaps back", not s["shown"] and s["reveal"] < 1 and s["peak"] > 20, s)

        s = lib("swipe", steps=[6] * 20, every=0.02)
        t.ok("a long stroke brings it in, all the way", s["shown"] and abs(s["reveal"] - s["total"]) < 1, s)
        t.ok("Downloads first", s["section"] == "downloads", s)
        time.sleep(0.3)
        after = page_x()
        t.ok("the page gives way by the rail", before is not None and after is not None and 86 <= after - before <= 98, (before, after))

        s = lib("swipe", steps=[8] * 25, every=0.016)
        t.ok("pushed past all the way in, it gives a little", 0 < s["peak"] - s["total"] <= 24, s)
        t.ok("and comes back to rest", s["shown"] and abs(s["reveal"] - s["total"]) < 1, s)

        for section in ["media", "spaces", "bookmarks", "archive", "downloads"]:
            s = lib("section", section=section)
            t.ok(f"its {section} section", s["section"] == section, s)

        s = lib("swipe", steps=[-3] * 8, every=0.03)
        t.ok("a short stroke back leaves it in", s["shown"] and abs(s["reveal"] - s["total"]) < 1, s)
        s = lib("swipe", steps=[-6] * 20, every=0.02)
        t.ok("two fingers back put it away", not s["shown"] and s["reveal"] < 1, s)
        time.sleep(0.3)
        t.ok("and the page has its room back", page_x() == before, (before, page_x()))

        # Two quick steps short of the 50 points a slow stroke needs: the
        # speed carries it (a hidden probe steps about every 22 ms).
        s = lib("swipe", steps=[22, 22], every=0.005)
        t.ok("a quick flick carries it in", s["shown"] and s["peak"] < 50, s)
        s = lib("close")
        t.ok("put away from its arrow or the foot", not s["shown"] and s["reveal"] == 0, s)
        s = lib("open", section="media")
        t.ok("opened from the foot to a section asked for", s["shown"] and s["section"] == "media", s)
        lib("close")

        # The column on the right: no Library, the swipe goes on as before.
        sv.quit()
        sv.setup(sidebar=True)
        import subprocess
        subprocess.run(["defaults", "write", sv.SUITE, "sidebar.position", "-string", "right"])
        sv.launch()
        s = lib()
        t.ok("the column on the right has none", not s["available"], s)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
