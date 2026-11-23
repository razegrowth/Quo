#!/usr/bin/env python3
"""Apple's model in Quo (Intelligence.swift), in a hidden probe: shorter tab
names, Tidy Tabs and a link's card, on pages served here.

Build first (`./build.sh`), then `python3 Tests/intelligence.py`. The model
parts need a Mac with Apple Intelligence on; without it they're skipped and
only what works everywhere (a sort put into groups, a card from the page's
own description) is checked.
"""
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("intelligence")

ARTICLE = """<!doctype html><html><head>
<title>How the James Webb telescope found water vapour on a rocky exoplanet | Space Weekly</title>
<meta name="description" content="Astronomers using JWST detected water vapour around GJ 486 b, a rocky planet 26 light years away.">
</head><body><nav>Home News Science</nav>
<h1>Webb finds hints of water vapour on a rocky exoplanet</h1>
<p>Astronomers using the James Webb Space Telescope have found signs of water vapour around GJ 486 b, a rocky planet about 30 percent larger than Earth, orbiting a red dwarf 26 light years away.</p>
<p>The planet is too hot to hold liquid water on its surface, at around 430 degrees Celsius, but the signal could mean it keeps a thin atmosphere despite the star's flares.</p>
<p>The team cautions that the vapour might instead come from cool starspots on the star itself. Further observations with Webb's other instruments are planned for next year to tell the two apart.</p>
<footer>Copyright Space Weekly</footer></body></html>"""

TITLES = {
    "doc": "Untitled document - Google Docs",
    "q3": "Q3 2026 Growth Plan: Paid Acquisition, Lifecycle Email and Referral Experiments - Google Docs",
    "short": "Hacker News",
    "tokyo-hotels": "Hotels in Shinjuku, Tokyo - Best Prices for 2026 - Booking.com",
    "tokyo-flights": "Cheap Flights from Berlin to Tokyo Haneda (HND) - Google Flights",
    "tokyo-ramen": "The 15 Best Ramen Shops in Tokyo, According to Locals - Time Out Tokyo",
    "pr": "Fix crash when closing a split view pane by edin · Pull Request #212 · razegrowth/quo",
    "issue": "Tab sync loses pinned tabs after restart · Issue #198 · razegrowth/quo",
    "ci": "CI · Workflow runs · razegrowth/quo · GitHub Actions",
    "pasta": "Creamy Lemon Garlic Pasta Recipe (Ready in 20 Minutes) - Bon Appétit",
    "curry": "Easy Weeknight Chicken Curry Recipe - BBC Good Food",
}


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?")[0].strip("/")
        if name == "article":
            body, kind = ARTICLE.encode(), "text/html; charset=utf-8"
        elif name == "file.pdf":
            body, kind = b"%PDF-1.4\n" + b"0" * 4000, "application/pdf"
        elif name == "missing":
            self.send_response(404); self.end_headers(); return
        elif name in ("setcookie", "private", "gate", "login", "hop", "echo"):
            signed = "s=1" in (self.headers.get("Cookie") or "")
            port = self.server.server_port
            if name == "setcookie":
                body = b"<!doctype html><title>Signed in</title><p>Signed in.</p>"
                self.send_response(200); self.send_header("Set-Cookie", "s=1; Path=/"); self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
            if name in ("private", "gate") and not signed:
                if name == "private":
                    self.send_response(404); self.end_headers(); return
                self.send_response(302); self.send_header("Location", f"/login?next=/{name}"); self.end_headers(); return
            if name == "hop":
                self.send_response(302); self.send_header("Location", f"http://localhost:{port}/echo"); self.end_headers(); return
            title = {"private": "Private repo: quo-secret", "gate": "Gated planning doc", "login": "Sign in",
                     "echo": "cookie: " + ("yes" if signed else "no")}[name]
            body = f"<!doctype html><title>{title}</title><p>{title}. " .encode() + b"Some words about the private repository and what it holds for the team. " * 6 + b"</p>"
            kind = "text/html; charset=utf-8"
        else:
            title = TITLES.get(name, name)
            body, kind = f"<!doctype html><title>{title}</title><h1>{title}</h1><p>{title}</p>".encode(), "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=srv.serve_forever, daemon=True).start()
HERE = f"http://127.0.0.1:{srv.server_port}"


def ai(action, **f):
    return sv.cmd({"do": "intelligence", "action": action, **f})


def open_(name):
    tab = sv.sp("open", url=f"{HERE}/{name}")["resultID"]
    time.sleep(0.5)
    return tab


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True)
        sv.launch()
        have = ai("available")["available"]
        print("  Apple Intelligence here:", have)

        # A card from the page: title and site always; a summary from the
        # model, or the page's own description without it.
        card = ai("preview", url=f"{HERE}/article")["card"]
        t.ok("a link's card has the page's title", card and "James Webb" in card["title"], card)
        t.ok("and its site", card and card["site"].startswith("127.0.0.1"), card)
        summary = (card or {}).get("summary") or ""
        if have:
            t.ok("Apple's model says what it says", "water" in summary.lower() and len(summary) > 40 and "Astronomers using JWST detected" not in summary, summary)
        else:
            t.ok("without the model, the page's description", summary.startswith("Astronomers using JWST"), summary)
        pdf = ai("preview", url=f"{HERE}/file.pdf")["card"]
        t.ok("a PDF says it's a PDF, unread", pdf and (pdf["failed"] or "").startswith("A PDF"), pdf)
        gone = ai("preview", url=f"{HERE}/missing")["card"]
        t.ok("a page that isn't there says so", gone and (gone["failed"] or "").startswith("Not there"), gone)

        # Refused to a stranger, then read as you with the site's cookies.
        hidden = ai("preview", url=f"{HERE}/private")["card"]
        t.ok("signed out, a private page says it may be private", hidden and (hidden["failed"] or "") == "Not there, or private", hidden)
        gated = ai("preview", url=f"{HERE}/gate")["card"]
        t.ok("signed out, a sign-in wall says so", gated and (gated["failed"] or "").startswith("Private, or you need"), gated)
        open_("setcookie"); time.sleep(0.6)
        ai("dismiss")
        hidden = ai("preview", url=f"{HERE}/private?again")["card"]
        t.ok("signed in, a private page is read", hidden and hidden["failed"] is None and "quo-secret" in hidden["title"], hidden)
        gated = ai("preview", url=f"{HERE}/gate?again")["card"]
        t.ok("signed in, past the sign-in wall", gated and gated["failed"] is None and gated["title"] == "Gated planning doc", gated)
        hop = ai("preview", url=f"{HERE}/hop")["card"]
        t.ok("cookies never follow a redirect to another host", hop and hop["title"] == "cookie: no", hop)
        t.ok("Escape or leaving the link puts it away", ai("dismiss")["card"] is None)

        # A sort put into groups, the model aside: two groups, a tab in two
        # groups only once, a group of one not made.
        names = list(TITLES)
        ids = {n: open_(n) for n in names}
        # Numbered as Tidy Tabs numbers them: the loose tabs, blank ones aside.
        loose = [x["title"] for x in sv.cmd({"do": "intelligence", "action": "titles"})["tabs"] if x["title"] and x["group"] is None]
        def at(title_key):
            return next(i + 1 for i, x in enumerate(loose) if x == TITLES[title_key])
        sort = [{"name": "Tokyo trip", "members": [at("tokyo-hotels"), at("tokyo-flights"), at("tokyo-ramen")]},
                {"name": "Quo", "members": [at("pr"), at("issue"), at("tokyo-ramen")]},
                {"name": "Alone", "members": [at("pasta")]}]
        made = ai("apply", groups=sort)
        by = {g["name"]: g["titles"] for g in made["groups"]}
        t.ok("a sort makes its groups, named", set(by) == {"Tokyo trip", "Quo"}, made)
        t.ok("each tab in one group only", TITLES["tokyo-ramen"] in by.get("Tokyo trip", []) and TITLES["tokyo-ramen"] not in by.get("Quo", []), by)
        t.ok("a group of one isn't made", "Alone" not in by and made["moved"] == 5, made)

        if not have:
            print("  (no Apple Intelligence: shorter names and Tidy Tabs not checked)")
            return
        # Tidy Tabs, asked of the model: the rest of the loose tabs.
        tidy = ai("tidy", wait=40)
        tidied = {g["name"]: g["titles"] for g in tidy["groups"]}
        print("  tidied:", {k: len(v) for k, v in tidied.items()}, "·", tidy["said"])
        new = {k: v for k, v in tidied.items() if k not in ("Tokyo trip", "Quo")}
        recipes = next((v for v in new.values() if TITLES["pasta"] in v), [])
        t.ok("Tidy Tabs puts the recipes together", TITLES["curry"] in recipes, tidied)
        t.ok("and says what it did", "group" in tidy["said"] or "Nothing" in tidy["said"], tidy["said"])

        # Shorter names: off, the page's title; on, a few words for the long
        # ones, the short ones left alone.
        off = {x["title"]: x["row"] for x in ai("titles", on=False)["tabs"]}
        t.ok("off, the row says the page's title", off[TITLES["q3"]] == TITLES["q3"], off)
        rows = {x["title"]: x for x in ai("titles", on=True, wait=40)["tabs"]}
        q3 = rows[TITLES["q3"]]["row"]
        t.ok("on, a long title is a few words", len(q3) < 41 and len(q3.split()) <= 6 and q3 != TITLES["q3"], q3)
        t.ok("a short title stays as it is", rows[TITLES["short"]]["row"] == "Hacker News", rows[TITLES["short"]])
        print("  names:", {k[:28]: v["row"] for k, v in rows.items()})
        off = {x["title"]: x["row"] for x in ai("titles", on=False)["tabs"]}
        t.ok("turned off again, the titles come back", off[TITLES["q3"]] == TITLES["q3"], off)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
