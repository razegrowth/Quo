# Quo

A fast, quiet browser for the Mac, with all the Arc habits I couldn't give up.

**[Download Quo →](https://github.com/razegrowth/Quo/releases/latest)** · macOS 14 or later · free

---

## Why I made it

I loved Arc. Spaces, pinned tabs that remember their site, tabs down the side, the little window for links from other apps. Then Arc stopped getting better, and everything that tried to replace it was another heavy Chromium browser with an AI sidebar bolted on.

That's when I found [Search](https://github.com/driceroland/Search), a tiny WebKit browser by Office Commun, and honestly loved it. It was fast and quiet in a way nothing else was. The team has a very clear idea of what Search should be though, and keeping it small means saying no to a lot of things, some of which I really wanted. Totally fair, it's their browser.

The big one was an address bar above the page while the tabs are down the side. I keep the sidebar open all day and wanted the whole address in front of me, like Dia or Chrome. The Search team decided against it, and that one feature is basically why this fork exists.

So I forked it and started building those things myself, the address bar first, then the Arc parts I missed. Quo is still a fork of Search under the hood, but it's turned into its own thing since.

## It's quick

Quo runs on WebKit, the engine that's already inside your Mac (it's what Safari uses). There's no second copy of Chromium to download, update and keep in memory.

- About a 9 MB download, 14 MB on disk.
- Opens instantly, with your tabs from last time ready and costing nothing until you click them.
- Tabs you're not using go to sleep on their own.
- The ad blocker works inside the engine, before a page loads, so pages come in faster instead of slower.

And on top of what Search already does, I've made it faster where it was slow for me:

- Hovering in heavy pages like Gmail is smoother. The window used to do extra work on every move of the pointer, and now it doesn't.
- The extension helper that rides along in every page is less than half the size it was (about 120 KB, down from 275 KB).
- Extensions that slow pages down get caught and offered On click, so they stop running in every page you open.

## What Search already gets right

Tabs down the side, spaces and profiles, pinned tabs, Split View, Peek, a small window for links from other apps, an ad blocker that runs before the page, passwords in your Mac's keychain and Chrome extensions on WebKit. That's all Search, and it's great.

## What I added on top

**More Arc**
- Arc's habits switched on from the start: spaces, ⌘T floating over the page, pinned rows and folders.
- Every space as a row of icons at the bottom of the sidebar, like Arc's, with a colour wheel for each one (gradients and grain included).
- ⌘T lists your open tabs and every command in the app, not just places to go.
- ⌥⌘← and ⌥⌘→ to move between spaces.
- An empty tab is your space's home: your most visited sites and what you closed last.
- The little window for links rebuilt to feel like Little Arc, flying into its place when you keep it.
- Pins keep their site. Links elsewhere open in a new tab beside the pin instead of taking it over.
- Downloads show up as cards in the sidebar.
- An onboarding like Arc's and Dia's, with a proper opening the first time you launch it.

**The address bar** (the reason this fork exists)
- Above the page with the tabs down the side: the whole address, back, forward, reload and your extensions, right where you'd expect them.

**Looks and feel**
- Roomy or Compact, with Roomy as the default.
- The sidebar lines up with the page, and the address field takes your space's colour.
- Smooth scrolling for mouse wheels.

**Bringing your stuff over**
- Every profile from Chrome, Dia, Arc, Brave, Edge and the rest, each with its own bookmarks and history.
- Their extensions come too, with a card that tells you which one is installing and what it's waiting on.

**Blocking**
- Real filter lists (EasyList, EasyPrivacy, Fanboy's Annoyances, cookie notices) a click away, on top of Search's own blocker.

**Extensions**
- Agent extensions like Claude and ChatGPT's agent can actually click, type and scroll in a page.
- Tools like SEO and font inspectors start On click when you install them, instead of running in every page.
- Lighter on every page, with notifications, popups and error reporting working like they do in Chrome.

**Under the hood**
- Sync through your own iCloud, end-to-end encrypted, no account.
- Its own updates, signed and notarized.
- Chrome's reload keys (⇧⌘R reloads from the server).
- Right-click an address you've selected to go straight to it.

Everything that's changed since the fork is in [IMPROVEMENTS.md](IMPROVEMENTS.md), and how it all looks and moves is in [DESIGN.md](DESIGN.md).

---

## What Quo sends

I wanted to know how many people actually use Quo, so it tells [TelemetryDeck](https://telemetrydeck.com) once a day that it was opened. That's it.

- **Once a day:** "App.opened", with Quo's version and build, your Mac's or iPhone's model (like `Mac15,3`) and its OS version.
- **Once per install:** a "new install" event, with the same.
- **Never:** a page, an address, a search, a tab or anything else about what you do in it.

You show up as a random number made on your device and hashed before it leaves, so one Mac can be told from another without anyone knowing whose. TelemetryDeck hashes it again and doesn't look at your IP for these. Turn it off in Settings › Privacy on the Mac or in Settings on the iPhone, and the number is forgotten.

It's all in [`Telemetry.swift`](Sources/Search/Telemetry.swift) (and [the iPhone's](iOS/Quo/App/Telemetry.swift)), one short file each, no SDK. A build without an app ID, like Search itself or your own fork, sends nothing at all.

---

## Building it

You'll need macOS 14 or later and Xcode 16 (or a Swift 6 toolchain). No dependencies beyond what ships with macOS.

```bash
./quo.sh            # build/Quo.app
./quo.sh install    # the same, then into /Applications
```

It signs with the first Developer ID in your keychain, or ad hoc if there isn't one (then right-click › Open the first time).

The code, files and module still say "Search", so changes from upstream merge cleanly; the app takes its name when it runs.

```bash
git fetch upstream && git merge upstream/main
```

## License

MIT, same as Search: see [LICENSE](LICENSE). The original code is Office Commun's and its contributors', with Quo's changes on top. "Search" and its icon are theirs. `Sources/Search/FilterList.swift` is a port of [adblock-rust](https://github.com/brave/adblock-rust) under the Mozilla Public License 2.0.
