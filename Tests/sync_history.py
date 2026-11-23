#!/usr/bin/env python3
"""History between two Macs, played by two hidden probes sharing one folder
(SyncHistory.swift): a page seen on one is in the other's history; a page
forgotten on one goes from the other; Clear History on one clears the other,
and a page visited after it stays.

Build first (`./build.sh`), then `python3 Tests/sync_history.py`. Both probes
are started hidden, never shown, and removed afterwards with the folder.
"""
import importlib.util
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


A, B = harness("synchist-a"), harness("synchist-b")
t = A.T()
shared = tempfile.mkdtemp(prefix="search-synchist-")


def history(sv):
    return sv.cmd({"do": "history"})["history"]


def has(sv, host):
    return any(host in u for u in history(sv))


def nudge():
    for sv in (A, B):
        sv.cmd({"do": "sync", "action": "now"})


def wait(cond, within=20):
    end = time.time() + within
    while time.time() < end:
        nudge()
        time.sleep(0.8)
        if cond(): return True
    return cond()


try:
    for sv in (A, B):
        sv.setup()
        subprocess.run(["defaults", "write", sv.SUITE, "sync.folder", shared])
    A.launch(); B.launch()
    # Each sees the other first: history goes only to a device that's there.
    t.ok("each Mac sees the other", wait(lambda: A.cmd({"do": "sync"})["others"] and B.cmd({"do": "sync"})["others"]),
         (A.cmd({"do": "sync"}), B.cmd({"do": "sync"})))
    A.cmd({"do": "history", "take": "https://alpha.example/"})
    t.ok("a page seen on A is in B's history", wait(lambda: has(B, "alpha.example")), history(B))
    B.cmd({"do": "history", "take": "https://beta.example/"})
    t.ok("and one seen on B in A's", wait(lambda: has(A, "beta.example")), history(A))
    t.ok("A keeps its own", has(A, "alpha.example"), history(A))
    time.sleep(1.2)
    A.cmd({"do": "history", "forget": "https://alpha.example/"})
    t.ok("a page forgotten on A goes from B", wait(lambda: not has(B, "alpha.example")), history(B))
    time.sleep(3)
    nudge(); time.sleep(1)
    t.ok("and doesn't come back to A", not has(A, "alpha.example"), history(A))
    B.cmd({"do": "history", "take": "https://gamma.example/"})
    t.ok("B's next page reaches A", wait(lambda: has(A, "gamma.example")), history(A))
    time.sleep(1.2)
    A.cmd({"do": "history", "clear": "all"})
    t.ok("Clear History on A clears B", wait(lambda: not has(B, "gamma.example") and not has(B, "beta.example")), history(B))
    time.sleep(1.2)
    B.cmd({"do": "history", "take": "https://delta.example/"})
    t.ok("a page visited on B after the clear reaches A", wait(lambda: has(A, "delta.example")), history(A))
    t.ok("and stays on B", has(B, "delta.example"), history(B))
    t.ok("nothing cleared comes back", not has(A, "gamma.example") and not has(A, "beta.example"), history(A))
finally:
    t.done()
    for sv in (A, B):
        try: sv.finish()
        except Exception as e: print("finish:", e)
        subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
    shutil.rmtree(shared, ignore_errors=True)
sys.exit(1 if t.failed else 0)
