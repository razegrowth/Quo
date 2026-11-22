"""Start Browsing brings Arc's spaces and pins straight in.

Build first (`./build.sh`), then `python3 Tests/welcome_arc.py`. The Welcome
used to open Bring Things Over once it was done, every switch on and Bring
them in waiting, which read as if nothing had come over yet, so it was
pressed again. Now the spaces and pins come into the sidebar it reveals,
said once they're in, and the page stays shut. Done a second time, nothing
comes twice.
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("welcome-arc")

FAVOURITES = [("Example", "https://example.com/"), ("Mail", "https://mail.example.com")]


def arc():
    """Arc as this world will find it: a space, and two favourites above it."""
    root = f"{sv.SUPPORT}/Import/Arc"
    profile = f"{root}/User Data/Default"
    os.makedirs(profile, exist_ok=True)
    items = [{"id": "favBox", "childrenIds": []}]
    for n, (title, url) in enumerate(FAVOURITES):
        tab = f"fav-{n}"
        items[0]["childrenIds"].append(tab)
        items.append({"id": tab, "title": title,
                      "data": {"tab": {"savedURL": url, "savedTitle": title}}})
    sidebar = {"sidebar": {"containers": [{
        "spaces": [{"title": "Fixture", "profile": {"default": {}}, "containerIDs": []}],
        "topAppsContainerIDs": [{"default": {}}, "favBox"],
        "items": items,
    }]}}
    Path(f"{root}/StorableSidebar.json").write_text(json.dumps(sidebar))
    Path(f"{profile}/History").write_bytes(b"")


def pins():
    path = f"{sv.SUPPORT}/pins.json"
    if not os.path.exists(path): return []
    return [p for row in json.load(open(path)).values() for p in row]


def main():
    t = sv.T()
    try:
        sv.setup()
        arc()
        sv.launch()
        out = sv.cmd({"do": "welcome-arc", "profile": "Default"})
        for _ in range(25):
            if len(pins()) >= 2: break
            time.sleep(0.2)
        t.ok("Arc's favourites came in as pins", len(pins()) == 2, [p["home"] for p in pins()])
        t.ok("Bring Things Over stayed shut", out.get("importOpen") is False, out)
        t.ok("and it said what came", out.get("said", "").startswith("From Arc:"), out.get("said"))

        out = sv.cmd({"do": "welcome-arc", "profile": "Default"})
        time.sleep(0.5)
        t.ok("a second time adds nothing", len(pins()) == 2, [p["home"] for p in pins()])
        t.ok("and says they were here already", "here already" in out.get("said", ""), out.get("said"))
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
