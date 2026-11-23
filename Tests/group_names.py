#!/usr/bin/env python3
"""Groups named as you make them (GroupNames, Intelligence.swift), in a
hidden probe: a new group named from its tabs, named again as tabs join, a
name you give kept, the switch, then Apple's model itself.

Build first (`./build.sh`), then `python3 Tests/group_names.py`.
"""
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("group-names")

TITLES = {
    "hotels": "Hotels in Shinjuku, Tokyo - Best Prices for 2026 - Booking.com",
    "flights": "Cheap Flights from Berlin to Tokyo Haneda (HND) - Google Flights",
    "ramen": "The 15 Best Ramen Shops in Tokyo, According to Locals",
    "pasta": "Creamy Lemon Garlic Pasta Recipe - Bon Appétit",
    "curry": "Easy Weeknight Chicken Curry Recipe - BBC Good Food",
}


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        title = TITLES.get(self.path.strip("/").split("?")[0], "Page")
        body = f"<!doctype html><title>{title}</title><h1>{title}</h1>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=srv.serve_forever, daemon=True).start()
HERE = f"http://127.0.0.1:{srv.server_port}"


def group(**f):
    return sv.cmd({"do": "group", **f})


def names():
    return [g["name"] for g in group()["groups"]]


def main():
    t = sv.T()
    try:
        sv.setup(**{"tabs.groups": True, "sidebar": True})
        sv.launch()
        have = sv.cmd({"do": "intelligence", "action": "available"})["available"]
        print("  Apple Intelligence here:", have)
        ids = {}
        for name in TITLES:
            ids[name] = sv.sp("open", url=f"{HERE}/{name}")["resultID"]
            time.sleep(0.4)
        time.sleep(1)

        # A stand-in for the model: every group gets "Trip".
        made = group(id=ids["hotels"], new=True, canned="Trip")
        first = made["groups"][0]
        t.ok("a new group starts with its plain name", first["name"].startswith("Group "), first)
        time.sleep(1.2)
        t.ok("then it's named from its tabs", names() == ["Trip"], names())

        # A tab joining asks again; a stand-in with a new answer says so.
        group(id=ids["flights"], name="Trip", canned="Tokyo trip")
        time.sleep(1.2)
        t.ok("named again as tabs join", names() == ["Tokyo trip"], names())

        # Named by you: kept, whatever joins.
        group(name="Tokyo trip", rename="Japan")
        group(id=ids["ramen"], name="Japan", canned="Something else")
        time.sleep(1.2)
        t.ok("a name you give is kept as tabs join", names() == ["Japan"], names())

        # Off: groups keep their plain names.
        group(autoName=False)
        made = group(id=ids["pasta"], new=True, canned="Dinner")
        time.sleep(1.2)
        t.ok("off, a new group keeps its plain name", any(n.startswith("Group ") for n in names()), names())
        group(autoName=True)
        plain = next(n for n in names() if n.startswith("Group "))
        group(id=ids["curry"], name=plain, canned="Dinner")
        time.sleep(1.2)
        t.ok("on again, a plain-named group is named when tabs join", "Dinner" in names(), names())

        if not have:
            print("  (no Apple Intelligence: the model itself not checked)")
            return
        # The model itself: the recipes regrouped from scratch.
        group(id=ids["pasta"], name="none", model=True)
        group(id=ids["curry"], name="none")
        group(id=ids["pasta"], new=True)
        group(id=ids["curry"], name=next(n for n in names() if n.startswith("Group ")))
        end = time.time() + 30
        while time.time() < end and any(n.startswith("Group ") for n in names()):
            time.sleep(0.5)
        print("  named by the model:", names())
        food = [n for n in names() if n not in ("Japan",)]
        t.ok("Apple's model names the recipes", food and not food[0].startswith("Group ") and len(food[0]) <= 40, names())
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
