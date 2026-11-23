# Quo for iPhone, overnight (23 Nov 2026)

Branch `claude/iphone-overnight`, in `.claude/worktrees/iphone-overnight`, 10 commits on top of main (3f1aa3b). Nothing pushed, released or uploaded. A signed Release device build succeeds, the new widget extension included.

## Done, and how it was tested

| # | What | Tested in the simulator |
|---|------|------------------------|
| 1 | Shorter tab names in the tab switcher, Settings toggle, on by default with Apple Intelligence | Names appear on the cards. Real model checked on the Mac with the same prompt: "Re: Q3 budget review", "Generating content with Foundation Models" |
| 2 | Summary under a held link's preview (no cookies; site's own cookies only on 401/403/404/sign-in; never across a redirect) | Shimmer and glow while reading, then the summary under the live preview |
| 3 | Hold a card in the tab switcher for what its page says, with Open and Done | Works; reads the open page's own text |
| 4 | Ask This Page in the ^ toolbar, streamed answers, follow-ups | Starters, question, streamed answer. Real model on the Mac: right answer to "Who invented packet switching?", "doesn't mention" for an off-page question |
| 5 | Smart routing: questions to Perplexity/ChatGPT (Settings › Search Engine › Questions go to), offered as the top suggestion when none is set; a site name goes to the site | 9 phrases checked through the real routing code: github/figma/youtube to the sites, questions to Perplexity, keywords stay searches |
| 6 | Listen to Page, Live Activity on the Lock Screen and in the Dynamic Island, Control Centre play/pause | Reads in the background; island shows title and progress; pause and stop from the island both work |
| 7 | App Shortcuts: Summarise This Page, Read This Aloud, Send My Tabs to My Mac, Open in Quo | All four show under Quo in Shortcuts; Summarise ran and answered |
| 8 | History search by meaning (no Apple Intelligence needed) | "cheap flights to lisbon" finds the TAP page, "that pasta recipe" the cacio e pepe one, "melting polar ice" the Arctic article |
| 9 | Clearer names for messy downloads (PDF text, Vision for scans and photos), one tap or ignore, never automatic | IMG_2834.pdf got a suggestion, the tap renamed it on disk. Real model on the Mac: "Acme Supplies Ltd invoice March 2026", "Lease agreement 14 Elm Street Skopje June 2026" |

## Worth knowing

- **The simulator's own Apple model wouldn't answer** (ModelManager error 1026 on iOS 27, a safety-model error on 26.5), although it said it was available. So the screens were tested with a stand-in model (`QUO_FAKE_MODEL=1`, test runs only), and every prompt was run against the Mac's real model separately. **Try 1 to 4 and 9 on your iPhone Air** to see the real model's answers in the app.
- **The search sheet can't open in the simulator here** (it rides the on-screen keyboard, which this simulator won't show), so routing (5) and meaning (8) were checked through their code at launch rather than by typing. Try typing "github" and "how do I boil an egg" on the phone.
- The iPhone's sentence embedding isn't on the simulator, so meaning search falls back to averaged word vectors there (and on any phone without it). The phone may use the sentence model instead; its cut-off (0.62) is untested.
- The App Shortcuts' Siri phrases, and Spotlight, are untested beyond the Shortcuts app.
- Listen's Lock Screen view is untested (I didn't lock the simulator); the Dynamic Island one is tested.
- A fix found along the way: Wikipedia's mobile pages fold their sections, which made the page reader pick a hidden one; it now skips undrawn paragraphs.
- Test hooks are in `Quo/App/TestRuns.swift` (QUO_TRACE only).
- Nothing in `IMPROVEMENTS.md` is pushed; its six new iPhone lines are on the branch.

## Left

- Real-device check of everything above.
- Merge the branch into main, then a TestFlight build (0.6.0, build 6) when you're happy.
