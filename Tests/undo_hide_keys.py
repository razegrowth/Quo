#!/usr/bin/env python3
"""⌘Z after Hide Elements, and ⇧⌘B, through the app's own key handling, in a
hidden probe (bench "keyeq").

Build first (`./build.sh`), then `python3 Tests/undo_hide_keys.py`. With
Settings › ⌘Z reopens a closed tab on and a tab just closed, ⌘Z after a
hide puts the hidden thing back (in the picker and after leaving it), and
doesn't reopen the tab; ⇧⌘B shows and hides the bookmarks bar.
"""
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("undo-hide-keys")

PAGE = b"""<!doctype html><title>page</title><style>body{margin:0}#ad{width:300px;height:120px;background:#c00}</style>
<div id=ad>Ad</div><p id=story>Story</p>"""


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *a): pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


def key(chars, code, shift=False):
    r = sv.cmd({"do": "keyeq", "chars": chars, "code": code, "mods": ["shift"] if shift else []})
    time.sleep(0.3)
    return r


def shown(tab):
    return sv.ev(tab, "getComputedStyle(document.getElementById('ad')).display !== 'none'")


def tabs():
    return len(sv.cmd({"do": "tabs"}).get("tabs", []))


def bar():
    r = subprocess.run(["defaults", "read", sv.SUITE, "bookmarks.bar"], capture_output=True, text=True)
    return r.stdout.strip()


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True, **{"tabs.undoReopens": True})
        sv.launch()
        tab = sv.sp("open", url=f"{BASE}/one")["resultID"]; time.sleep(0.8)
        sv.sp("open", url=f"{BASE}/two"); time.sleep(0.8)
        before = tabs()
        key("w", 13)                       # a tab just closed: ⌘Z would reopen it
        time.sleep(0.5)
        after_close = tabs()
        t.ok("⌘W closed a tab", after_close == before - 1, (before, after_close))
        sv.cmd({"do": "select", "id": tab}); time.sleep(0.4)

        key("h", 4, shift=True)            # ⇧⌘H: the picker
        sv.ev(tab, """(function(){var el=document.getElementById('ad'),r=el.getBoundingClientRect();
          var o={bubbles:true,cancelable:true,clientX:r.left+20,clientY:r.top+20};
          el.dispatchEvent(new PointerEvent('pointermove',o));el.dispatchEvent(new PointerEvent('pointerdown',o));return true})()""")
        time.sleep(0.8)
        t.ok("a click in the picker hides it", shown(tab) is False, shown(tab))
        key("z", 6)
        t.ok("⌘Z in the picker puts it back", shown(tab) is True, shown(tab))
        t.ok("and reopens no tab", tabs() == after_close, tabs())

        sv.ev(tab, """(function(){var el=document.getElementById('ad'),r=el.getBoundingClientRect();
          var o={bubbles:true,cancelable:true,clientX:r.left+20,clientY:r.top+20};
          el.dispatchEvent(new PointerEvent('pointermove',o));el.dispatchEvent(new PointerEvent('pointerdown',o));return true})()""")
        time.sleep(0.8)
        t.ok("hidden again", shown(tab) is False, shown(tab))
        key("h", 4, shift=True)            # ⇧⌘H again: out of the picker
        key("z", 6)
        t.ok("⌘Z just after leaving the picker puts it back", shown(tab) is True, shown(tab))
        t.ok("still no tab reopened", tabs() == after_close, tabs())

        # ⇧⌘B: the bookmarks bar, not Add This Page.
        start = bar()
        key("b", 11, shift=True)
        first = bar()
        key("b", 11, shift=True)
        second = bar()
        t.ok("⇧⌘B shows and hides the bookmarks bar", first != second and first in ("0", "1") and second in ("0", "1"),
             (start, first, second))
    finally:
        sv.finish()
        t.done()
    return t.failed


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
