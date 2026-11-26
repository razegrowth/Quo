#!/usr/bin/env python3
"""With a password manager's extension on, Quo's own filling steps aside
(Browser.passwordManagerHere), in a hidden probe, on fill_more.py's pages.

Build first (`./build.sh`), then `python3 Tests/password_manager_yield.py`.
The password manager is the bench's stand-in ("fill" "manager"), so no
extension is downloaded; cards are kept in memory on a test run.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402
import fill_more as fm  # noqa: E402  (its pages, served, and its helpers)

sv.use("password-manager-yield")


def main():
    t = sv.T()
    try:
        sv.setup(sidebar=True)
        sv.launch()
        fm.fill("addcard", name="Ada Lovelace", number="4242 4242 4242 4242", month=4, year=30)

        # Without one: Quo's own, as before.
        tab = fm.open_("signup")
        r = fm.focus(tab, "pw")
        t.ok("no password manager: a strong password is offered", any("strong" in x for x in r["rows"]), r)
        tab = fm.open_("checkout")
        r = fm.focus(tab, "number")
        t.ok("no password manager: the card is offered", any("card" in x for x in r["rows"]), r)

        # 1Password on: nothing of Quo's own hangs from the box.
        m = fm.fill("manager", name="1Password")
        t.ok("1Password taken as on", m["manager"] == "1Password", m)
        tab = fm.open_("signup")
        r = fm.focus(tab, "pw")
        t.ok("with 1Password: no strong password from Quo", not any("strong" in x for x in r["rows"]), r)
        tab = fm.open_("checkout")
        r = fm.focus(tab, "number")
        t.ok("with 1Password: no card from Quo", not any("card" in x for x in r["rows"]), r)

        # Turned off in Settings: both, as before.
        fm.fill("yield", on=False)
        tab = fm.open_("signup")
        r = fm.focus(tab, "pw")
        t.ok("Let a password manager take over off: Quo's strong password is back", any("strong" in x for x in r["rows"]), r)
        fm.fill("yield", on=True)

        # 1Password turned off again: Quo's own comes back.
        m = fm.fill("manager")
        t.ok("no password manager again", m["manager"] is None, m)
        tab = fm.open_("signup")
        r = fm.focus(tab, "pw")
        t.ok("and Quo's strong password is offered again", any("strong" in x for x in r["rows"]), r)
    finally:
        sv.finish()
        t.done()
    return t.failed


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
