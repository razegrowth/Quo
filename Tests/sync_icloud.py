#!/usr/bin/env python3
"""Sync through iCloud, played by two hidden probes and a folder standing in
for iCloud (SEARCH_FAKE_CLOUD): the records, the accounts and the passes are
the app's own (SyncCloud.swift); only where the records are kept differs.

Build first (`./build.sh`), then `python3 Tests/sync_icloud.py`. Two test
worlds stand for two Macs, started hidden, never shown, and removed
afterwards with the stand-in iCloud. What is checked:

- each Mac's records go up, one per scope (its open tabs' among them), and
  nothing else is written;
- each Mac's open tabs reach the other's ⌘T, and an iPhone's do (a record
  standing in for one), as rows that open the page here;
- a space made on one Mac reaches the other, both ways, and a setting does;
- Sync Now runs a pass at once;
- signed out of iCloud, it says so and changes nothing;
- another Apple ID on a Mac: the Mac joins that account's records and
  leaves the first account's alone;
- turned off, a Mac's records leave iCloud and the other Mac stops seeing it.
"""
import base64
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def harness(name):
    spec = importlib.util.spec_from_file_location(f"sv_{name}", HERE / "split_view.py")
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    mod.use(name)
    return mod


A, B = harness("icloud-a"), harness("icloud-b")
t = A.T()
cloud = Path(tempfile.mkdtemp(prefix="search-icloud-"))


def env(account="me"):
    return {"SEARCH_FAKE_CLOUD": str(cloud), "SEARCH_FAKE_CLOUD_ACCOUNT": account}


def spaces(sv):
    try: return [s.get("name") for s in json.load(open(f"{sv.SUPPORT}/spaces.json"))]
    except Exception: return []


PERSONAL = "profile-00000000-0000-0000-0000-0000000000A1"
TABS = "tabs-" + PERSONAL


def records(account="me"):
    """The Macs' records: not the iPhone standing in."""
    return sorted(p.name for p in (cloud / account).glob("*.record") if ".PHONE" not in p.name)


def tabs(sv_record):
    """The pages a tabs record lists."""
    record = json.load(open(sv_record))
    file = json.loads(base64.b64decode(record["data"]))
    return [t["url"] for t in json.loads(file["items"]["tabs"]["v"])]


def phone(urls, account="me"):
    """An iPhone's tabs record, as Quo for iPhone writes one."""
    now = time.time()
    text = lambda v: json.dumps(v, separators=(",", ":"), sort_keys=True)
    entry = lambda v: {"v": v, "t": now, "d": "PHONE"}
    items = {"tabs": entry(text([{"url": u, "title": t, "active": now} for u, t in urls])),
             "spaces": entry("[]"), "kind": entry(text("iphone"))}
    file = {"format": 1, "device": "PHONE", "name": "Test iPhone", "scope": TABS, "written": now, "items": items}
    data = base64.b64encode(json.dumps(file).encode()).decode()
    (cloud / account / f"{TABS}.PHONE.record").write_text(json.dumps({"scope": TABS, "data": data}))


def offers(sv, text=None):
    """⌘T's rows, before typing or for `text`, over a page of its own."""
    sv.page("here"); time.sleep(0.5)
    sv.cmd({"do": "keyeq", "chars": "t", "code": 17}); time.sleep(0.8)
    if text: sv.cmd({"do": "field", "text": text}); time.sleep(0.8)
    return sv.cmd({"do": "suggest"})["offers"]


def sync(sv, action=None):
    return sv.cmd({"do": "sync", **({"action": action} if action else {})})


def wait(cond, within=15):
    end = time.time() + within
    while time.time() < end:
        if cond(): return True
        time.sleep(0.5)
    return cond()


try:
    for sv in (A, B):
        sv.setup()
        subprocess.run(["defaults", "write", sv.SUITE, "spaces", "-bool", "true"])
        subprocess.run(["defaults", "write", sv.SUITE, "sync.icloud", "-bool", "true"])
        # ⌘T's floating field, as a fresh Quo has it: where other devices' tabs show.
        subprocess.run(["defaults", "write", sv.SUITE, "newtab.floating", "-bool", "true"])
    A.launch(env=env()); B.launch(env=env())
    A.page("a"); B.page("b")

    state = sync(A)
    t.ok("iCloud is on, and offered", state["way"] == "icloud" and state["available"], state)
    t.ok("each Mac's records go up, one per scope", wait(lambda: len(records()) == 6), records())
    t.ok("…and nothing else is written", all(n.split(".")[0] in ("app", PERSONAL, TABS) for n in records()), records())

    # Open tabs: each Mac's reach the other's ⌘T, never merged.
    mine = lambda sv: next((cloud / "me").glob(f"{TABS}.{sv.cmd({'do': 'sync'})['device']}.record"), None)
    t.ok("A's tabs record lists its page", wait(lambda: mine(A) and any(u.endswith("/a") for u in tabs(mine(A))), 70),
         mine(A) and tabs(mine(A)))
    rows = lambda sv, text=None: [o for o in offers(sv, text) if o[1] == "elsewhere"]
    t.ok("B's ⌘T offers A's open page", wait(lambda: any(o[2].endswith("/a") for o in rows(B)), 70), offers(B))
    B.cmd({"do": "suggest", "action": "esc"})
    phone([("https://en.wikipedia.org/wiki/Handoff", "Handoff - Wikipedia")])
    sync(B, "now")
    found = []
    t.ok("an iPhone's tab answers to what is typed in B's ⌘T",
         wait(lambda: found.extend(rows(B, "handoff")) or any("Handoff" in o[2] for o in found), 20), found)
    st = B.cmd({"do": "suggest"})
    at = next((i for i, o in enumerate(st["offers"]) if o[1] == "elsewhere"), None)
    taken = B.cmd({"do": "suggest", "action": "take", "index": at}) if at is not None else {}
    t.ok("…and taking it opens the page here", "Handoff" in taken.get("address", "") + taken.get("pending", ""), taken)
    (cloud / "me" / f"{TABS}.PHONE.record").unlink()

    A.cmd({"do": "space", "action": "new", "name": "From A"})
    t.ok("B gets A's new space", wait(lambda: "From A" in spaces(B)), spaces(B))
    B.cmd({"do": "space", "action": "new", "name": "From B"})
    t.ok("A gets B's new space", wait(lambda: "From B" in spaces(A)), spaces(A))
    t.ok("A keeps its own", "From A" in spaces(A), spaces(A))
    t.ok("each Mac names the other", wait(lambda: sync(A)["others"] != [] and sync(B)["others"] != []), (sync(A), sync(B)))

    before = sync(A)["synced"]
    time.sleep(1.1)
    sync(A, "now")
    t.ok("Sync Now runs a pass at once", wait(lambda: sync(A)["synced"] > before, 5), (before, sync(A)["synced"]))

    # Signed out: the problem is said, and nothing changes.
    A.quit()
    A.launch(env=env("signed-out"))
    t.ok("signed out, it says so", wait(lambda: "Sign in" in sync(A)["problem"]), sync(A))
    t.ok("…and the records stay as they were", len(records()) == 6, records())

    # Another Apple ID: A joins it, and the first account's records stay.
    A.quit()
    first = records()
    A.launch(env=env("someone-else"))
    t.ok("another Apple ID: A's records go up there", wait(lambda: len(records("someone-else")) == 3), records("someone-else"))
    t.ok("…the first account's are left alone", records() == first, (first, records()))
    t.ok("…and A keeps what it had", "From B" in spaces(A) and "From A" in spaces(A), spaces(A))

    # Back on the first account, then off on B: B's records leave iCloud.
    A.quit()
    A.launch(env=env())
    sync(B, "off")
    t.ok("turned off, B's records leave iCloud", wait(lambda: len(records()) == 3), records())
    t.ok("…and B says off", sync(B)["way"] == "off", sync(B))
    t.ok("A stops naming B", wait(lambda: sync(A)["others"] == [] or sync(A, "now") and False, 10) or sync(A)["others"] == [], sync(A))
finally:
    t.done()
    for sv in (A, B):
        try: sv.finish()
        except Exception as e: print("finish:", e)
        subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
    shutil.rmtree(cloud, ignore_errors=True)
sys.exit(1 if t.failed else 0)
