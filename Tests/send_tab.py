#!/usr/bin/env python3
"""Send a page between devices (SyncTabs.swift): a hidden probe Mac and a
stand-in iPhone sharing one sync folder.

Build first (`./build.sh`), then `python3 Tests/send_tab.py`. The iPhone is
played by a tabs file written into the folder as Quo for iPhone writes it;
the Mac is a hidden probe, never shown, removed afterwards with the folder.
"""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("sv_send", HERE / "split_view.py")
sv = importlib.util.module_from_spec(spec); spec.loader.exec_module(sv)
sv.use("send-tab")
t = sv.T()
shared = tempfile.mkdtemp(prefix="search-send-")
PERSONAL = "00000000-0000-0000-0000-0000000000A1"
SCOPE = f"tabs-profile-{PERSONAL}"
PHONE = "TEST-IPHONE-0001"


def text(v): return json.dumps(v, sort_keys=True, separators=(",", ":"))


def phone_file(sent):
    now = time.time()
    items = {"tabs": {"v": "[]", "t": now, "d": PHONE}, "spaces": {"v": "[]", "t": now, "d": PHONE},
             "kind": {"v": text("iphone"), "t": now, "d": PHONE}}
    if sent: items["sent"] = {"v": text(sent), "t": now, "d": PHONE}
    folder = next(p for p in Path(shared).rglob(SCOPE) if p.is_dir())
    (folder / f"{PHONE}.json").write_text(json.dumps(
        {"format": 1, "device": PHONE, "name": "Test iPhone", "scope": SCOPE, "written": now, "items": items}, sort_keys=True))
    return folder


def wait(cond, within=20):
    end = time.time() + within
    while time.time() < end:
        if cond(): return True
        time.sleep(0.5)
    return cond()


def urls(): return [x["url"] for x in sv.cmd({"do": "tabs"}).get("tabs", [])]


try:
    sv.setup()
    sv.launch()
    sv.page("a")
    state = sv.cmd({"do": "sync", "action": "folder", "path": shared})
    mac = state["device"]
    t.ok("the Mac syncs through the folder", state["way"] == "folder", state)
    t.ok("the Mac writes its tabs in the folder",
         wait(lambda: (sv.cmd({"do": "sync", "action": "now"}), any(p.is_dir() for p in Path(shared).rglob(SCOPE)))[1]),
         list(Path(shared).rglob("*")))
    folder = phone_file([])
    t.ok("the iPhone shows as somewhere to send to",
         wait(lambda: any(x["device"] == PHONE for x in sv.cmd({"do": "sync", "action": "now"}).get("targets", []))),
         sv.cmd({"do": "sync"}).get("targets"))

    page = "https://example.com/from-the-iphone"
    phone_file([{"id": "sent-1", "url": page, "title": "From the iPhone", "to": mac, "at": time.time()}])
    said = []
    def arrived():
        state = sv.cmd({"do": "sync", "action": "now"})
        if page in urls():
            said.append(sv.cmd({"do": "sync"}).get("said"))
            return True
        return False
    t.ok("a page the iPhone sent opens on the Mac", wait(arrived), urls())
    sv.cmd({"do": "sync", "action": "now"}); time.sleep(3); sv.cmd({"do": "sync", "action": "now"}); time.sleep(2)
    t.ok("and only once", urls().count(page) == 1, urls())
    t.ok("with a note naming the device", said[:1] == ["From Test iPhone"], said)

    sv.cmd({"do": "sync", "action": "send", "to": PHONE})
    mine = folder / f"{mac}.json"
    def sent():
        try: return json.loads(json.loads(mine.read_text())["items"].get("sent", {}).get("v") or "[]")
        except Exception: return []
    t.ok("a page sent from the Mac is in its file at once, for the iPhone", wait(lambda: any(s["to"] == PHONE for s in sent()), 8), sent())
    t.ok("saying so", sv.cmd({"do": "sync"}).get("said") == "Test iPhone".join(["Sent to ", ""]), sv.cmd({"do": "sync"}).get("said"))
    plain = next(x["id"] for x in sv.cmd({"do": "tabs"})["tabs"] if x["url"] == page)
    t.ok("an ordinary tab's page can be", sv.cmd({"do": "sync", "id": plain}).get("sendable") == page,
         sv.cmd({"do": "sync", "id": plain}).get("sendable"))
    shy = sv.cmd({"do": "open", "url": "https://example.com/private", "private": True})
    t.ok("a private tab's page can't be sent", sv.cmd({"do": "sync", "id": shy.get("id")}).get("sendable") == "",
         sv.cmd({"do": "sync", "id": shy.get("id")}))
finally:
    t.done()
    try: sv.finish()
    except Exception as e: print("finish:", e)
    subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
    shutil.rmtree(shared, ignore_errors=True)
sys.exit(1 if t.failed else 0)
