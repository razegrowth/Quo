#!/usr/bin/env python3
"""History found by meaning (Meaning.swift), in a hidden probe: pages
visited, then searched for by what they were about.

Build first (`./build.sh`), then `python3 Tests/history_meaning.py`.
"""
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("history-meaning")

TITLES = {
    "hotels": "Hotels in Shinjuku, Tokyo - Best Prices for 2026",
    "flights": "Cheap Flights from Berlin to Tokyo Haneda (HND)",
    "ramen": "The 15 Best Ramen Shops in Tokyo, According to Locals",
    "pasta": "Creamy Lemon Garlic Pasta Recipe (Ready in 20 Minutes)",
    "curry": "Easy Weeknight Chicken Curry Recipe",
    "monstera": "How to repot a monstera plant without killing it",
    "mortgage": "Mortgage calculator: how much house can I afford?",
    "webb": "Webb finds hints of water vapour on a rocky exoplanet",
    "camera": "iPhone 17 Pro review: the best camera yet",
    "pr": "Fix crash when closing a split view pane · Pull Request #212",
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


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True)
        sv.launch()
        for name in TITLES:
            sv.sp("open", url=f"{HERE}/{name}")
            time.sleep(0.7)
        time.sleep(1.5)

        def look(query):
            found = sv.cmd({"do": "meaning", "query": query})
            print(f"  {query!r}: literal {found['literal']} · related {found['related'][:4]} · {found['ms']:.0f} ms")
            return found

        trip = look("japan trip")
        t.ok("“japan trip” matches nothing outright", trip["literal"] == [], trip)
        t.ok("but finds the Tokyo pages by meaning", sum("Tokyo" in x for x in trip["related"][:3]) >= 2, trip)
        t.ok("and not the recipes first", trip["related"] and "Recipe" not in trip["related"][0], trip)
        loan = look("home loan")
        t.ok("“home loan” finds the mortgage calculator", loan["related"] and "Mortgage" in loan["related"][0], loan)
        plant = look("houseplant care")
        t.ok("“houseplant care” finds the monstera", plant["related"] and "monstera" in plant["related"][0], plant)
        food = look("dinner ideas")
        t.ok("“dinner ideas” finds the recipes", food["related"] and "Recipe" in food["related"][0], food)
        tokyo = look("tokyo")
        t.ok("a word that matches outright is listed first, not again by meaning",
             len(tokyo["literal"]) == 3 and not any("Tokyo" in x for x in tokyo["related"]), tokyo)
        t.ok("it's quick", max(x["ms"] for x in (trip, loan, plant, food)) < 1500, [x["ms"] for x in (trip, loan, plant, food)])
        t.ok("two letters aren't searched by meaning", look("ja")["related"] == [])
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
