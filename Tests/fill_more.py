#!/usr/bin/env python3
"""Strong passwords, cards, Handoff and Listen to Page, in a hidden probe, on
pages served here (Cards.swift, Handoff.swift, Listen.swift).

Build first (`./build.sh`), then `python3 Tests/fill_more.py`. Cards are kept
in memory on a test run, Touch ID answers as the probe says, the card is a
test number, and reading aloud is at no volume.
"""
import re
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("fill-more")

PAGES = {
    "signup": """<title>Create your account</title><form action="/register">
      <input id=email type=email name=email placeholder=Email>
      <input id=pw type=password name=password placeholder=Password>
      <input id=pw2 type=password name=confirm placeholder="Confirm password">
      <button>Sign up</button></form>""",
    "login": """<title>Sign in</title><form action="/session">
      <input id=email type=email name=email autocomplete=username>
      <input id=pw type=password name=password autocomplete=current-password>
      <button>Sign in</button></form>""",
    "checkout": """<title>Checkout</title><form action="/pay">
      <input id=name autocomplete=cc-name>
      <input id=number autocomplete=cc-number inputmode=numeric>
      <input id=exp autocomplete=cc-exp placeholder="MM / YY">
      <input id=csc autocomplete=cc-csc>
      <button>Pay</button></form>""",
    "checkout2": """<title>Pay</title><form action="/pay">
      <label for=number>Card number</label><input id=number name=cardnumber>
      <label for=month>Expiry month</label><select id=month name=exp_month><option value="">MM</option>
        <option>01</option><option>02</option><option>03</option><option>04</option><option>05</option><option>06</option>
        <option>07</option><option>08</option><option>09</option><option>10</option><option>11</option><option>12</option></select>
      <label for=year>Expiry year</label><select id=year name=exp_year><option value="">YYYY</option>
        <option>2028</option><option>2029</option><option>2030</option><option>2031</option></select>
      <label for=cvv>CVV</label><input id=cvv name=cvv>
      <button>Pay</button></form>""",
    "article": """<title>Tide pools</title><nav><a href=/>Home</a> <a href=/x>News</a></nav>
      <article><h1>Life in a tide pool</h1>
      <p>Tide pools are rocky hollows that hold seawater when the tide goes out, and they are home to anemones, crabs and snails.</p>
      <p>Twice a day the sea covers them again, so everything living there has to cope with sun, waves and changing salt.</p>
      <p>The best time to visit is at low tide, early in the morning, when the pools are calm and the light is soft.</p></article>
      <footer>Copyright</footer>""",
}


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        body = ("<!doctype html><meta charset=utf-8>" + PAGES.get(self.path.strip("/").split("?")[0], "<title>other</title><p>other")).encode()
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


def fill(action="rows", **f):
    return sv.cmd({"do": "fill", "action": action, **f})


def open_(name):
    tab = sv.sp("open", url=f"{HERE}/{name}")["resultID"]
    time.sleep(0.8)
    return tab


def focus(tab, box):
    sv.ev(tab, f"document.getElementById('{box}').focus(); true")
    time.sleep(0.6)
    return fill()


def value(tab, box):
    return sv.ev(tab, f"document.getElementById('{box}').value")


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True)
        sv.launch()

        # Strong passwords.
        tab = open_("signup")
        r = focus(tab, "pw")
        strong = (r["rows"][0] if r["rows"] else {}).get("strong", "")
        t.ok("a sign-up's password box offers a strong one first", bool(strong), r)
        t.ok("three runs of six, a capital and a digit", re.fullmatch(r"[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}", strong)
             and re.search(r"[A-Z]", strong) and re.search(r"[0-9]", strong), strong)
        r2 = focus(tab, "pw2")
        t.ok("the same one under the box that asks again", (r2["rows"][0] if r2["rows"] else {}).get("strong") in (strong, None) or r2["rows"], r2)
        focus(tab, "pw")
        fill("pick", index=0)
        t.ok("picked: the password and the box that asks again", value(tab, "pw") == strong and value(tab, "pw2") == strong,
             (value(tab, "pw"), value(tab, "pw2")))
        t.ok("and the email box left alone", value(tab, "email") == "", value(tab, "email"))
        tab = open_("login")
        r = focus(tab, "pw")
        t.ok("a sign-in's password box offers none", not any("strong" in x for x in r["rows"]), r)

        # Cards.
        bad = fill("addcard", name="Ada Lovelace", number="4242 4242 4242 4241", month=4, year=30)
        t.ok("a mistyped number isn't kept", bad["added"] == "invalid", bad)
        good = fill("addcard", name="Ada Lovelace", number="4242 4242 4242 4242", month=4, year=30)
        t.ok("a test card is kept, named by its kind and last four", good["added"] == "kept" and good["cards"] == ["Visa •••• 4242"], good)
        time.sleep(0.5)
        tab = open_("checkout")
        r = focus(tab, "number")
        t.ok("a checkout's number box offers the card", r["rows"] and r["rows"][0].get("card") == "Visa •••• 4242", r)
        t.ok("with its name and expiry", r["rows"] and "Ada Lovelace" in r["rows"][0].get("detail", "") and "04/30" in r["rows"][0].get("detail", ""), r)
        fill("allow", on=False)
        fill("pick", index=0)
        t.ok("Touch ID refused: nothing filled", value(tab, "number") == "", value(tab, "number"))
        fill("allow", on=True)
        focus(tab, "name")
        r = fill()
        t.ok("the name box offers it too", r["rows"] and r["rows"][0].get("card"), r)
        fill("pick", index=0)
        t.ok("picked: the number", value(tab, "number") == "4242424242424242", value(tab, "number"))
        t.ok("the name and the expiry as MM/YY", value(tab, "name") == "Ada Lovelace" and value(tab, "exp") == "04/30",
             (value(tab, "name"), value(tab, "exp")))
        t.ok("the security code left for you, the caret in its box",
             value(tab, "csc") == "" and sv.ev(tab, "document.activeElement.id") == "csc", sv.ev(tab, "document.activeElement.id"))
        tab = open_("checkout2")
        r = focus(tab, "number")
        t.ok("a form read by its labels offers it", r["rows"] and r["rows"][0].get("card"), r)
        fill("pick", index=0)
        t.ok("month and year chosen in their lists", value(tab, "number") == "4242424242424242" and value(tab, "month") == "04"
             and value(tab, "year") == "2030", (value(tab, "number"), value(tab, "month"), value(tab, "year")))
        r = focus(tab, "cvv")
        t.ok("the code's box offers no card", not any("card" in x for x in r["rows"]), r)
        fill("clearcards")
        tab = open_("checkout")
        r = focus(tab, "number")
        t.ok("with no card kept, nothing is offered", not r["rows"], r)

        # Handoff.
        h = fill("handoff")
        t.ok("Handoff offers the page in front", h["offered"] == f"{HERE}/checkout", h)

        # Listen to Page.
        tab = open_("article")
        l = fill("listen", act="start")
        t.ok("Listen to Page reads the article", l["state"] == "reading" and len(l["parts"]) >= 3, l)
        t.ok("its title, and not the navigation or the footer", l["title"] == "Life in a tide pool"
             and not any(p in ("Home", "News", "Copyright") for p in l["parts"]), l)
        l = fill("listen", act="pause")
        t.ok("paused", l["state"] == "paused", l)
        l = fill("listen", act="pause")
        t.ok("and going on", l["state"] == "reading", l)
        sv.cmd({"do": "go", "id": tab, "url": f"{HERE}/other"})
        time.sleep(1.0)
        l = fill("listen")
        t.ok("going elsewhere in the tab stops it", l["state"] == "idle", l)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
