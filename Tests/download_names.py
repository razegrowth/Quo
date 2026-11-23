#!/usr/bin/env python3
"""Tidier downloads (DownloadNames), in a hidden probe: vague names told from
clear ones, a PDF's text and a picture's words read on this Mac, a name
suggested on a real download's card, taken in one click, and nothing renamed
on its own.

Build first (`./build.sh`), then `python3 Tests/download_names.py`.
"""
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("download-names")

INVOICE = """<!doctype html><title>Invoice</title><body style="font:22px Helvetica;margin:60px">
<h1>INVOICE</h1><p>Acme Garden Supplies Ltd</p><p>Invoice number: INV-20419</p><p>Date: 14 March 2026</p>
<p>Bill to: Jo Bloggs, 12 Rua Augusta, Lisbon</p><p>2 x Terracotta pot, large .... 48.00 EUR</p><p>Total due: 48.00 EUR</p></body>"""
FILES = {}


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/invoice":
            body, kind, extra = INVOICE.encode(), "text/html; charset=utf-8", {}
        elif path == "/get":
            body = f'<!doctype html><a id="go" href="/document.pdf">Download</a>'.encode()
            kind, extra = "text/html", {}
        elif path == "/document.pdf":
            body, kind = FILES["pdf"], "application/pdf"
            extra = {"Content-Disposition": 'attachment; filename="document(3).pdf"'}
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header("Content-Type", kind)
        for k, v in extra.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=srv.serve_forever, daemon=True).start()
HERE = f"http://127.0.0.1:{srv.server_port}"


def dl(action=None, **f):
    return sv.cmd({"do": "dlname", **({"action": action} if action else {}), **f})


def main():
    t = sv.T()
    try:
        sv.setup()
        sv.launch()
        have = sv.cmd({"do": "intelligence", "action": "available"})["available"]
        print("  Apple Intelligence here:", have)
        scratch = Path(sv.SUPPORT) / "probe-files"
        scratch.mkdir(parents=True, exist_ok=True)

        # The invoice as a PDF and as a picture, made by Quo itself.
        page = sv.sp("open", url=f"{HERE}/invoice")["resultID"]
        time.sleep(1)
        pdf = scratch / "document(3).pdf"
        sv.cmd({"do": "pdf", "id": page, "path": str(pdf)})
        png = scratch / "IMG_2041.png"
        sv.cmd({"do": "shot", "id": page, "path": str(png), "width": 900})
        FILES["pdf"] = pdf.read_bytes()
        clear = scratch / "Acme invoice March 2026.pdf"
        clear.write_bytes(FILES["pdf"])

        # Vision's first look on a Mac loads its models, which takes a while.
        try:
            dl("suggest", path=str(png), canned="warm")
        except RuntimeError:
            time.sleep(10)
        r = dl("suggest", path=str(pdf), canned="Acme invoice")
        t.ok("“document(3).pdf” says nothing", r["unclear"], r)
        t.ok("a PDF's own text is read", "INV-20419" in r["text"], r["text"][:120])
        r = dl("suggest", path=str(png), canned="Acme invoice")
        t.ok("“IMG_2041.png” says nothing", r["unclear"], r)
        t.ok("a picture's words are read by Vision", "Acme" in r["text"] and "Lisbon" in r["text"], r["text"][:160])
        r = dl("suggest", path=str(clear), canned="Something else")
        t.ok("a clear name gets no suggestion", not r["unclear"] and r["suggestion"] is None, r)
        t.ok("the model's words made a file name, its extension kept",
             dl("suggest", path=str(pdf), canned='"Acme invoice: March/2026.pdf"\nmore')["suggestion"] == "Acme invoice March 2026.pdf", "")

        # A real download: its card offers a name, and nothing is renamed yet.
        dl(canned="Acme Garden invoice INV-20419")
        get = sv.sp("open", url=f"{HERE}/get")["resultID"]
        time.sleep(1)
        sv.cmd({"do": "tap", "id": get, "selector": "#go"})
        end = time.time() + 15
        state = dl()
        while time.time() < end and not any(a["suggestion"] for a in state["arrivals"]):
            time.sleep(0.5)
            state = dl()
        card = next((a for a in state["arrivals"] if a["suggestion"]), None)
        print("  card:", card)
        t.ok("a download's card offers a clearer name", card and card["suggestion"] == "Acme Garden invoice INV-20419.pdf", state)
        t.ok("and the file keeps its own name until you say", card and Path(card["path"]).name.startswith("document") and Path(card["path"]).exists(), card)
        taken = dl("take")
        renamed = taken.get("renamed")
        t.ok("one click renames it where it is", renamed and Path(renamed).name == "Acme Garden invoice INV-20419.pdf" and Path(renamed).exists(), taken)
        t.ok("the old name is gone", card and not Path(card["path"]).exists(), card)
        t.ok("the card shows the new name", any(a["name"] == "Acme Garden invoice INV-20419.pdf" for a in taken["arrivals"]), taken["arrivals"])
        t.ok("and so does the Downloads list", taken["kept"] and taken["kept"][0] == "Acme Garden invoice INV-20419.pdf", taken["kept"])

        if have:
            dl(model=True)
            r = dl("suggest", path=str(pdf))
            print("  the model's name for the PDF:", r["suggestion"], "|", r.get("said"))
            name = (r["suggestion"] or "").lower()
            t.ok("Apple's model names the invoice", name.endswith(".pdf") and "invoice" in name and ("acme" in name or "inv-20419" in name), r)
            r = dl("suggest", path=str(png))
            print("  and for the picture:", r["suggestion"], "|", r.get("said"))
            pic = (r["suggestion"] or "").lower()
            t.ok("and the picture of it", pic.endswith(".png") and "invoice" in pic and ("acme" in pic or "2026" in pic or "march" in pic), r)
        dl(on=False)
        t.ok("off, no suggestion", dl("suggest", path=str(pdf), canned="x y z")["suggestion"] is None)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
