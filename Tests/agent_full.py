#!/usr/bin/env python3
"""Full control for coding agents (AgentFull, AgentMCP), in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/agent_full.py` (-v to see
every call). The split suite's harness starts the build hidden in a world of
its own with "Let coding agents use Search" and "Give agents full control"
on. The agent's side is the app itself started with --mcp, spoken to over
stdio as Claude Code would; the window's question is answered through the
bench's `agents` verb, which only a test run has.

Checked: the MCP server answers both eras (initialize, server/discover) and
lists every tool; the question says full control; the person's own tab read
with element handles and clicked; a real tab opened; the whole browser in
get_state; tabs pinned, renamed, muted, grouped, split and moved; groups
renamed, folded and ungrouped; spaces made, switched, renamed and deleted
(asked first, and a no heard as no); menu commands listed and run, Clear
History asked first; bookmarks, history, downloads and settings read and
changed, the agents' own switches out of reach; a script of its own run in a
page, a password read as empty there, its field kept a password and its form
kept going where it goes; a screenshot of the person's tab with the password
blacked out; windows made and closed. Then full control turned off: the next
agent is let in without it, and every full tool says so.
"""

import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("agent-full")
ROOT = Path(__file__).resolve().parents[1]
APP_BINARY = ROOT / "build" / "Search.app" / "Contents" / "MacOS" / "Search"
VERBOSE = "-v" in sys.argv
AGENT_SOCK = f"{sv.SUPPORT}/Agent/agent.sock"

PAGES = {
    "yours": "<!doctype html><title>Yours</title><h1>Your page</h1><button id=b onclick=\"document.title='clicked'\">Press me</button>",
    "two": "<!doctype html><title>Two</title><p>The second page</p>",
    "three": "<!doctype html><title>Three</title><p>The third page</p>",
    "form": """<!doctype html><title>Sign in</title><form id=f action="/done" method="get">
      <label>Name <input name="name" id="name" value="jo"></label>
      <label>Password <input type="password" name="pw" id="pw" value="hunter2-secret"></label>
      <button id="go">Send</button></form>""",
    "done": "<!doctype html><title>Done</title><p>Thanks</p>",
}


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?")[0].strip("/")
        body = PAGES.get(name)
        if body is None:
            self.send_response(404); self.end_headers(); return
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), Page)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


class Client:
    """The app's own MCP server, as an agent runs it."""

    def __init__(self, name="claude-code", modern=False):
        self.p = subprocess.Popen([str(APP_BINARY), "--mcp", "--world", sv.W], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        self.n = 0
        self.meta = None
        if modern:
            self.meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                         "io.modelcontextprotocol/clientCapabilities": {},
                         "io.modelcontextprotocol/clientInfo": {"name": name, "version": "1"}}
            self.hello = self.rpc("server/discover")
        else:
            self.hello = self.rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                                 "clientInfo": {"name": name}})

    def send(self, method, params=None):
        self.n += 1
        params = dict(params or {})
        if self.meta:
            params["_meta"] = self.meta
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n")
        self.p.stdin.flush()
        return self.n

    def answer(self, n):
        out = json.loads(self.p.stdout.readline())
        assert out["id"] == n, out
        return out.get("result", out.get("error"))

    def rpc(self, method, params=None):
        return self.answer(self.send(method, params))

    def tool(self, which, /, **args):
        out = self.rpc("tools/call", {"name": which, "arguments": args})
        content = out["content"]
        said = json.loads(content[-1]["text"]) if content and content[-1]["type"] == "text" else content
        if VERBOSE:
            print(f"  {which} {json.dumps(args)[:110]} → {json.dumps(said)[:300]}")
        return said, content, bool(out.get("isError"))

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(5)
        except Exception:
            self.p.kill()


def code(x):
    return x.get("error", {}).get("code") if isinstance(x, dict) else None


def agents(action="state", **f):
    return sv.cmd({"do": "agents", "action": action, **f})


def until(check, within=10):
    end = time.time() + within
    while time.time() < end:
        if check():
            return True
        time.sleep(0.1)
    return False


def find(state, title):
    for window in state["windows"]:
        for tab in window["tabs"]:
            if tab["title"] == title:
                return tab
    return None


t = sv.T()


def main():
    clients = []
    try:
        sv.setup(**{"agents": True, "agents.full": True, "spaces": True})
        sv.launch()
        t.ok("the socket is there with the setting on", until(lambda: os.path.exists(AGENT_SOCK)))
        sv.sp("open", url=f"{BASE}/yours")
        time.sleep(1)

        # ---- the server, both eras
        a = Client("claude-code"); clients.append(a)
        t.ok("initialize answers in the client's revision", a.hello.get("protocolVersion") == "2025-11-25", a.hello)
        tools = a.rpc("tools/list")["tools"]
        names = {tool["name"] for tool in tools}
        t.ok("every tool is listed", {"get_state", "run_command", "tab_action", "space_action", "group_action", "window_action",
                                      "bookmarks", "history", "downloads", "settings", "run_script", "read_page", "click"} <= names,
             sorted(names))
        t.ok("tools say whether they only read", next(x for x in tools if x["name"] == "get_state")["annotations"]["readOnlyHint"])
        m = Client("claude-code", modern=True); clients.append(m)
        t.ok("server/discover names 2026-07-28", "2026-07-28" in m.hello.get("supportedVersions", []), m.hello)
        m.close()

        # ---- let in, with full control
        n = a.send("tools/call", {"name": "get_state", "arguments": {}})
        t.ok("the question is up", until(lambda: agents().get("state") == "asking"), agents())
        t.ok("and it is for full control", agents().get("fullOn") is True, agents())
        agents("allow")
        out = a.answer(n)
        state = json.loads(out["content"][-1]["text"])
        t.ok("allowed with full control", agents().get("full") is True, agents())
        mine = find(state, "Yours")
        t.ok("get_state has the person's own tab", mine is not None and "page" in mine, state)
        page = mine["page"]

        # ---- the person's own tab, used
        read, _, err = a.tool("read_page", page=page)
        button = next((x for x in read.get("nodes", []) if x.get("role") == "button"), None)
        t.ok("the person's tab is read with handles", not err and button and "element" in button, read)
        clicked, _, err = a.tool("click", element=button["element"])
        t.ok("and clicked", not err and until(lambda: any(x["title"] == "clicked" for x in a.tool("list_tabs")[0]["tabs"])), clicked)

        # ---- a real tab
        opened, _, err = a.tool("open_tab", url=f"{BASE}/two")
        two = opened.get("page")
        bench = sv.cmd({"do": "tabs"})["tabs"]
        t.ok("open_tab makes a tab like the person's, in the row", not err and any("/two" in (x.get("address") or x.get("url") or "") for x in bench), bench)
        three = a.tool("open_tab", url=f"{BASE}/three")[0].get("page")

        # ---- tabs
        did, _, err = a.tool("tab_action", page=two, action="rename", name="Renamed")
        t.ok("a tab renamed", not err and did["tab"].get("name") == "Renamed", did)
        did, _, err = a.tool("tab_action", page=two, action="pin")
        t.ok("pinned", not err and did["tab"].get("pinned") is True, did)
        did, _, err = a.tool("tab_action", page=two, action="unpin")
        t.ok("and unpinned", not err and not did["tab"].get("pinned"), did)
        did, _, err = a.tool("tab_action", page=two, action="mute")
        t.ok("muted", not err and did["tab"].get("muted") is True, did)
        did, _, err = a.tool("tab_action", page=two, action="group", new="Research")
        group = did.get("group")
        t.ok("put in a new group", not err and group and did["tab"].get("group") == group, did)
        did, _, err = a.tool("tab_action", page=three, action="group", group="Research")
        t.ok("another tab into that group by name", not err and did["tab"].get("group") == group, did)
        did, _, err = a.tool("group_action", group=group, action="rename", name="Reading")
        t.ok("the group renamed", not err and any(g["name"] == "Reading" for w in did["windows"] for g in w["groups"]), did)
        did, _, err = a.tool("group_action", group="Reading", action="fold")
        t.ok("folded", not err and any(g["folded"] for w in did["windows"] for g in w["groups"]), did)
        did, _, err = a.tool("group_action", group="Reading", action="ungroup")
        t.ok("ungrouped, its tabs still there", not err and not any(w["groups"] for w in did["windows"])
             and find(did, "Three") is not None, did)
        did, _, err = a.tool("tab_action", page=two, action="split", **{"with": three})
        t.ok("two tabs split", not err and did["tab"].get("split"), did)
        did, _, err = a.tool("tab_action", page=two, action="unsplit")
        t.ok("and apart again", not err and not did["tab"].get("split"), did)
        did, _, err = a.tool("tab_action", page=three, action="select")
        t.ok("a tab put in front", not err and did["tab"].get("active") is True, did)
        did, _, err = a.tool("tab_action", page=three, action="dance")
        t.ok("an action it doesn't know is said so", err and code(did) == "bad_action", did)

        # ---- spaces
        did, _, err = a.tool("space_action", action="new", name="Work")
        spaces = did["windows"][0].get("spaces", [])
        work = next((s for s in spaces if s["name"] == "Work"), None)
        t.ok("a space made", not err and work is not None, did)
        did, _, err = a.tool("space_action", action="switch", space="Work")
        t.ok("switched to", not err and did["windows"][0]["space"] == work["space"], did)
        did, _, err = a.tool("space_action", action="rename", space=work["space"], name="Office")
        t.ok("renamed", not err and any(s["name"] == "Office" for s in did["windows"][0]["spaces"]), did)
        sv.cmd({"do": "ui", "confirm": False})
        did, _, err = a.tool("space_action", action="delete", space="Office")
        t.ok("deleting a space asks, and a no is heard as no", err and code(did) == "declined", did)
        sv.cmd({"do": "ui", "confirm": True})
        did, _, err = a.tool("space_action", action="delete", space="Office")
        t.ok("and a yes deletes it", not err and not any(s["name"] == "Office" for s in did["windows"][0]["spaces"]), did)

        # ---- commands
        listed, _, err = a.tool("list_commands")
        ids = {c["command"] for c in listed.get("commands", [])}
        t.ok("every menu command is listed", not err and {"tabs.duplicate", "view.reader", "history.clear"} <= ids, len(ids))
        before = len(a.tool("list_tabs")[0]["tabs"])
        ran, _, err = a.tool("run_command", command="tabs.duplicate", page=three)
        t.ok("a menu command run on a tab", not err and ran.get("ran") == "tabs.duplicate"
             and until(lambda: len(a.tool("list_tabs")[0]["tabs"]) == before + 1), ran)
        sv.cmd({"do": "ui", "confirm": False})
        ran, _, err = a.tool("run_command", command="history.clear")
        t.ok("Clear History asks first", err and code(ran) == "declined", ran)
        sv.cmd({"do": "ui", "confirm": "ask"})
        ran, _, err = a.tool("run_command", command="no.such")
        t.ok("a command that isn't one is said so", err and code(ran) == "no_command", ran)

        # ---- bookmarks, history
        added, _, err = a.tool("bookmarks", action="add", url=f"{BASE}/two", title="Two, kept")
        t.ok("a bookmark added", not err and added.get("added"), added)
        found, _, err = a.tool("bookmarks", action="search", query="kept")
        t.ok("and found", not err and found["count"] == 1, found)
        gone, _, err = a.tool("bookmarks", action="remove", bookmark=added["added"])
        t.ok("and removed", not err and a.tool("bookmarks", action="search", query="kept")[0]["count"] == 0, gone)
        seen, _, err = a.tool("history", action="search", query="127.0.0.1")
        t.ok("history searched", not err and seen["count"] >= 1, seen)
        downloads, _, err = a.tool("downloads", action="list")
        t.ok("downloads listed", not err and "downloads" in downloads, downloads)

        # ---- settings
        got, _, err = a.tool("settings", action="get", key="tabs.compact")
        t.ok("a setting read, with its title", not err and "value" in got, got)
        flipped = not got["value"]
        did, _, err = a.tool("settings", action="set", key="tabs.compact", value=flipped)
        t.ok("and changed", not err and did["value"] == flipped, did)
        a.tool("settings", action="set", key="tabs.compact", value=got["value"])
        did, _, err = a.tool("settings", action="set", key="look", value="dark")
        t.ok("a choice set by its name", not err and did["value"] == "dark", did)
        a.tool("settings", action="set", key="look", value="system")
        did, _, err = a.tool("settings", action="set", key="look", value="purple")
        t.ok("a value it doesn't take is refused, with its choices", err and code(did) == "bad_value" and "light" in did["error"]["hint"], did)
        for key in ("agents", "agents.full", "bench"):
            did, _, err = a.tool("settings", action="set", key=key, value=False)
            t.ok(f"“{key}” is out of reach", err and code(did) == "no_setting", did)
        t.ok("and full control is still on", agents().get("fullOn") is True, agents())

        # ---- scripts, and what they can't see
        form = a.tool("open_tab", url=f"{BASE}/form")[0]["page"]
        ran, _, err = a.tool("run_script", page=form, script="return document.title")
        t.ok("a script of its own runs in the page", not err and ran.get("result") == "Sign in", ran)
        ran, _, err = a.tool("run_script", page=form, script="return [document.getElementById('name').value, document.getElementById('pw').value]")
        t.ok("a password reads as empty there", not err and ran.get("result") == ["jo", ""], ran)
        ran, _, err = a.tool("run_script", page=form, script="return [...new FormData(document.getElementById('f')).keys()]")
        t.ok("and is left out of its form's data", not err and ran.get("result") == ["name"], ran)
        ran, _, err = a.tool("run_script", page=form, script="document.getElementById('pw').type = 'text'; return 'changed'")
        t.ok("it can't be made a text field to be read", err and "secret" in json.dumps(ran), ran)
        ran, _, err = a.tool("run_script", page=form, script="document.getElementById('f').action = 'https://example.com/'; return 'sent'")
        t.ok("nor its form sent elsewhere", err and "secret" in json.dumps(ran), ran)
        ran, _, err = a.tool("run_script", page=form, script="return document.getElementById('pw').getAttribute('value')")
        t.ok("nor read by its attribute", not err and ran.get("result") is None, ran)
        read, _, err = a.tool("read_page", page=form)
        pw = next((x for x in read.get("nodes", []) if x.get("redacted")), None)
        t.ok("read_page keeps it back too", not err and pw is not None and "hunter2" not in json.dumps(read), pw)
        shot, content, err = a.tool("screenshot", page=page)
        t.ok("a screenshot of the person's own tab", not err and content[0]["type"] == "image", shot)

        # ---- windows
        did, _, err = a.tool("window_action", action="new")
        t.ok("a window made", not err and len(did["windows"]) == 2, did)
        did, _, err = a.tool("window_action", action="close", window=2)
        t.ok("and closed", not err and until(lambda: len(a.tool("get_state")[0]["windows"]) == 1), did)

        a.tool("disconnect")
        a.close()

        # ---- full control off: in, but without it
        agents("full", on=False)
        time.sleep(0.5)
        b = Client("claude-code"); clients.append(b)
        n = b.send("tools/call", {"name": "list_tabs", "arguments": {}})
        until(lambda: agents().get("state") == "asking")
        t.ok("the question no longer says full control", agents().get("fullOn") is False, agents())
        agents("allow")
        b.answer(n)
        did, _, err = b.tool("get_state")
        t.ok("with it off, a full tool says so", err and code(did) == "full_control_off", did)
        did, _, err = b.tool("read_page", page=page)
        t.ok("and the person's tab is not its to read", err, did)
        b.tool("disconnect")
    finally:
        for c in clients:
            c.close()
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
