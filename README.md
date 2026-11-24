# Quo

A tiny Mac browser that feels and works like Arc. Safari's speed, Chrome's extensions, fully agentic, completely free and open source.

**[Download Quo →](https://github.com/razegrowth/Quo/releases/latest)** · macOS 14 or later · Apple silicon · free · [quobrowser.com](https://quobrowser.com)

---

## Why it exists

I loved Arc. Then they killed it, and everything that tried to replace it was another heavy Chromium browser with an AI sidebar bolted on.

Then I found [Search](https://github.com/driceroland/Search), a tiny WebKit browser by Office Commun, and honestly loved it. The one thing I really wanted, an address bar above the page with the tabs down the side, wasn't something they wanted in Search. Totally fair, it's their browser.

So I forked it. Quo started with that address bar, then all the Arc parts I missed, and it's turned into its own thing since.

## The basics

It runs on WebKit, the engine already inside your Mac, so there's no Chromium to carry around.

- **About a 9 MB download**, 14 MB on disk. Arc is 892 MB, Dia 1.2 GB, Chrome 1.4 GB.
- **Tabs sleep.** The ones you're not using let go on their own and come back where you left them.
- **Ads and trackers blocked** before the page loads, inside the engine, so pages come in faster.
- **Netflix plays**, signed in, through Apple's FairPlay, the same as in Safari.
- **Synced through your own iCloud.** History and open tabs between your Macs and iPhone, end-to-end encrypted.
- **Passwords and cards.** Strong passwords made for you, cards filled in at checkout, all in your keychain.
- **Handoff** for the page you're on.
- **Apple Intelligence, if you want it.** Shorter tab names, groups that name themselves, Writing Tools in text boxes, history you can search by meaning. Each one has its own switch.
- **No account.** Download it and go.

## Your Chrome extensions

No Chromium needed (macOS 15.4 or later).

- Straight from the Chrome Web Store. Hit Add to Chrome like you always have.
- They work like they do in Chrome, popups, buttons and notifications included.
- Import from Chrome, Dia or Arc and their extensions install too.
- One that drags your pages down gets offered On click, so it stops running everywhere.

## Everything you miss from Arc

On from the start, and your Arc spaces, pins, profiles and extensions come over in a click.

- Spaces you swipe between, or ⌥⌘← and →.
- Pins that keep their site. Links elsewhere open beside the pin, not over it.
- Pinned Calendar and Gmail with your next meeting and new mail right on the pin.
- ⌘T with your open tabs, plus every command in the app.
- Little windows for links from Slack, Mail and the rest.
- Split view and Peek.
- Tab groups, Tidy Tabs, the Library, and downloads as cards in the column.
- The whole address above the page, with vertical tabs down the side.

## Agentic, if you want it

Off until you turn it on, in Settings › AI & Agents.

- **Quo is its own MCP server.** Nothing to install. Hit Add to Claude Code, or:

  ```bash
  claude mcp add quo -- /Applications/Quo.app/Contents/MacOS/Quo --mcp
  ```

- **Agents can do what you do.** With full control on, Claude Code, Codex or any MCP agent can work your tabs, spaces, windows, bookmarks, history, settings and every menu command, and use pages with your sign-ins.
- **You stay in charge.** Each agent asks you in the window first, and Stop ends it. It never sees saved passwords, cards, one-time codes or private tabs.
- **Claude and ChatGPT's extensions work.** Their agents can actually click, type and scroll in pages here.

## Quo for iPhone

There's an iPhone app too, in TestFlight for now. It keeps up with the Mac: your spaces, pins, bookmarks, history and open tabs come through your own iCloud, and you can send a page between them. The code's in [`iOS/`](iOS).

## What's new

Quo updates itself. Every release and its notes are on the [releases page](https://github.com/razegrowth/Quo/releases) and the [changelog](https://quobrowser.com/changelog), and everything that's changed since the fork is in [IMPROVEMENTS.md](IMPROVEMENTS.md). How it all looks and moves is in [DESIGN.md](DESIGN.md).

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
