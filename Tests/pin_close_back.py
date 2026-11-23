#!/usr/bin/env python3
"""A tab a pin opened goes back to the pin when it closes, as in Arc, in a
hidden probe: with no other tabs beside the pins, with one, and with
Leave a new tab when the last tab closes on.

Build first (`./build.sh`), then `python3 Tests/pin_close_back.py` (-v for
every call). Driven through Quo's own MCP server with full control, which
reaches every tab and command the way a hand does: the pin's link is a real
click, the close is File › Close Tab.
"""
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pin-close-back")
APP = Path(__file__).resolve().parents[1] / "build" / "Search.app" / "Contents" / "MacOS" / "Search"
VERBOSE = "-v" in sys.argv


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        port = self.server.server_port
        name = self.path.strip("/") or "pin"
        # The pin's link goes to another site (localhost, not 127.0.0.1): a
        # pin's link out of its site opens beside it.
        body = (f"<!doctype html><title>{name}</title><h1>{name}</h1>"
                f"<a id=out href='http://localhost:{port}/away'>Out</a>").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Page)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


class Client:
    def __init__(self):
        self.p = subprocess.Popen([str(APP), "--mcp", "--world", sv.W], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.n = 0
        self.rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "probe"}})

    def rpc(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())["result"]

    def send(self, which, **args):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": "tools/call",
                                       "params": {"name": which, "arguments": args}}) + "\n")
        self.p.stdin.flush()
        return self.n

    def answer(self):
        out = json.loads(self.p.stdout.readline())["result"]
        return json.loads(out["content"][-1]["text"])

    def tool(self, which, **args):
        self.send(which, **args)
        said = self.answer()
        if VERBOSE:
            print(f"  {which} {json.dumps(args)[:90]} → {json.dumps(said)[:220]}")
        return said

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)


def tabs(a):
    return a.tool("get_state")["windows"][0]["tabs"]


def active(a):
    return next((t for t in tabs(a) if t.get("active")), None)


t = sv.T()


def main():
    a = None
    try:
        sv.setup(**{"agents": True, "agents.full": True, "pins.peek": True})
        sv.launch()
        a = Client()
        a.send("get_state")
        end = time.time() + 10
        while time.time() < end and sv.cmd({"do": "agents"}).get("state") != "asking":
            time.sleep(0.1)
        sv.cmd({"do": "agents", "action": "allow"})
        a.answer()
        a.tool("settings", action="set", key="pins.links", value="tab")

        pin = a.tool("open_tab", url=f"{BASE}/pin", foreground=True)["page"]
        a.tool("tab_action", page=pin, action="pin")
        # Every other tab closed: only the pin, and what it opens.
        for tab in tabs(a):
            if tab["page"] != pin and not tab.get("pinned"):
                a.tool("tab_action", page=tab["page"], action="close")

        def out_of_pin():
            a.tool("tab_action", page=pin, action="select")
            link = next(n for n in a.tool("read_page", page=pin)["nodes"] if n.get("name") == "Out")
            a.tool("click", element=link["element"])
            time.sleep(1)
            now = active(a)
            return now

        opened = out_of_pin()
        t.ok("a pin's link out of its site opens a tab, in front", opened and opened["page"] != pin and "/away" in opened["url"], opened)
        a.tool("run_command", command="file.closeTab")
        time.sleep(0.6)
        back = active(a)
        t.ok("closed, the last tab beside the pins goes back to the pin", back and back["page"] == pin, back)

        other = a.tool("open_tab", url=f"{BASE}/other", foreground=False)["page"]
        opened = out_of_pin()
        a.tool("run_command", command="file.closeTab")
        time.sleep(0.6)
        back = active(a)
        t.ok("and with another tab open, it still goes back to the pin", back and back["page"] == pin, back)
        a.tool("tab_action", page=other, action="close")

        a.tool("settings", action="set", key="tabs.newAfterLast", value=True)
        opened = out_of_pin()
        a.tool("run_command", command="file.closeTab")
        time.sleep(0.6)
        back = active(a)
        t.ok("with Leave a new tab on too: the pin, not an empty tab", back and back["page"] == pin, back)

        # A tab of your own, not from the pin, closed last beside the pins:
        # still the new tab that setting asks for.
        a.tool("open_tab", url=f"{BASE}/mine", foreground=True)
        a.tool("run_command", command="file.closeTab")
        time.sleep(0.6)
        left = active(a)
        t.ok("a tab that didn't come from the pin still leaves a new tab", left and left["page"] != pin and not left.get("pinned"), left)
    finally:
        if a:
            a.close()
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
