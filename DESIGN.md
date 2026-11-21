# Quo design

How Quo looks, reads and moves, for everything made under its name: the Mac app, the iOS app, the website, and whatever else carries the Q. The values here are the Mac app's own (`Sources/Search/Design.swift`, `Welcome.swift`, `SpaceSwipe.swift`), so a thing built from this page sits beside the app without looking borrowed.

## The idea

Quo is a quiet browser. The page is the point, and everything Quo draws gets out of its way.

- **Monochrome.** Greys from near-white to near-black. Quo has no brand colour: the only colour is the one a person gives their space, and the sites' own.
- **Small, calm type.** Nothing shouts. Hierarchy comes from weight and grey, rarely from size.
- **Few things, well placed.** One action that matters on a screen, filled; the rest outlined or plain.
- **Motion with weight, never long.** Things settle like objects, not slide like slides. Most moves finish in under a third of a second.
- **Plain words.** Short sentences, sentence case, no exclamation marks.

## Logo

**The app icon** is a white rounded tile with a dark, heavy Q. **The mark** is the Q alone (`Icon/Quo.icon/Assets/quo-q-vector.svg`), a ring with a short rounded tail at four o'clock.

| Use | What |
|---|---|
| App icon, favicon, social image | The tile: white `#FAFAFA` ground, Q in ink `#171717` |
| Beside a wordmark, in a header | The Q alone, in ink on light, in `#EDEDED` on dark |
| Smallest | 16 px for the tile, 12 px for the Q |
| Clear space | A quarter of the Q's height on every side |

The wordmark is "Quo" set in the system face at weight 600 (semibold), tracking −0.01 em, in ink. The Q sits before it at the wordmark's cap height plus a third, with a gap of half the Q's width.

Don't recolour the Q, outline it, add a gradient or a glow to it, rotate it, or set it on a busy photograph. On a space's colour it stays ink or white, whichever reads.

## Colour

Every colour is a pair: one for light, one for dark. They're greys, written as their white level.

| Token | Light | Dark | For |
|---|---|---|---|
| `ground` | `#FFFFFF` | `#1C1C1C` | The surface things sit on: a page, a card, a sheet |
| `frame` | `#F4F4F4` | `#131313` | The window behind a card: the column, gaps around it |
| `ink` | `#171717` | `#EDEDED` | Text and icons that matter; filled buttons |
| `muted` | `#8C8C8C` | `#949494` | Secondary text, resting icons, labels |
| `faint` | `#D4D4D4` | `#525252` | Placeholder, the faintest ink, disabled |
| `hairline` | `#E8E8E8` | `#333333` | 1 px borders and dividers |
| `wash` | `#EFEFEF` | `#2D2D2D` | The selected row, a control's track |
| `hover` | `#F6F6F6` | `#262626` | Under the pointer |

**Colour comes from the person, not the brand.** A space's colour is one of six, or a gradient of up to three, with optional film grain. It washes the chrome behind the content, never the content itself.

| Space colour | Hex |
|---|---|
| None | `#737885` |
| Blue | `#4285F5` |
| Green | `#33A873` |
| Orange | `#F59E33` |
| Red | `#E65466` |
| Violet | `#9E66E6` |

Two colours carry meaning and appear nowhere else: **safe** `#14803D` / `#4ADE80` (a private connection) and **caution** `#B5540A` / `#FABF24` (one that isn't). Never use red or green for decoration.

**Grain**, where a surface has a space's colour, is a fixed noise tile at 4–6 % opacity: felt, not seen. Never on text or on content.

## Type

**The face is the system's**: SF Pro on Apple platforms (SF Pro Text below 20 pt, Display above, which the system picks), and on the web the same through the system stack. Numbers that change or line up are tabular.

```css
font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
```

Two weights do nearly everything: **regular (400)** and **medium (500)**. **Semibold (600)** is for titles only. Bold is reserved for a countdown or a number that has to be read at a glance.

### Scale

Sizes stay small. The Mac app reads at 13; iOS and the web read a step larger because they're held further away or read longer, but the steps between sizes stay the same.

| Role | Mac | iOS | Web | Weight | Line height | Tracking |
|---|---|---|---|---|---|---|
| Caption: counts, times, fine print | 11 | 12 | 12 px | 400 | 1.35 | 0 |
| Footnote: secondary lines, labels | 12 | 13 | 13 px | 400 | 1.4 | 0 |
| Body: rows, buttons, paragraphs | 13 | 15 | 15 px | 400 | 1.45 | 0 |
| Body emphasis: row titles, active items | 13 | 15 | 15 px | 500 | 1.45 | 0 |
| Callout: a card's title | 15 | 17 | 17 px | 600 | 1.3 | −0.005 em |
| Title: a screen's title | 20 | 22 | 22 px | 600 | 1.2 | −0.01 em |
| Display: one per page, at most | 28 | 28 | 32 px (40 px on a wide hero) | 600 | 1.1 | −0.02 em |

Roomy, the app's larger density, moves each role up by 1.5 pt (13 → 14.5). Nothing on any screen goes above Display, and most screens never use it.

**Rules**

- Sentence case everywhere: titles, buttons, menus. Never all caps, never Title Case For Everything.
- Grey before size: a secondary line is `muted` at the same or one step smaller, not a much smaller size.
- Tighten tracking only from Title up. Small text keeps the face's own spacing.
- One line where it can be: a row's title truncates at its end, an address in its middle.

## Space

A 4-point grid. The values that come up again and again:

| Token | pt | Typical use |
|---|---|---|
| `space-1` | 2 | Between rows in a list, inside tight controls |
| `space-2` | 4 | Icon to its label in a chip |
| `space-3` | 8 | Between buttons, a card's gap from the window |
| `space-4` | 10 | A row's inner padding, the column's margin |
| `space-5` | 12 | Between label and control |
| `space-6` | 16 | A card's padding |
| `space-7` | 20 | A large card's padding, between groups |
| `space-8` | 24 | Between sections |
| `space-9` | 32 | Around a screen's content |

Rows are 28 pt (Compact) or 40 pt (Roomy) on the Mac, 44 pt on iOS. Every tap target on iOS is at least 44 × 44.

## Shape

| Token | Radius | Use |
|---|---|---|
| `radius-xs` | 5 | A segment inside a control |
| `radius-sm` | 8 | Rows, buttons in a toolbar, small tiles |
| `radius-md` | 10 | The page's card, inputs |
| `radius-lg` | 14 | Cards, popovers, sheets' inner panels |
| `radius-xl` | 20 | Large hero cards (the onboarding's) |
| `capsule` | full | Buttons with words, chips, toggles, badges |

All corners are continuous (squircle), not circular arcs: `RoundedRectangle(style: .continuous)` in SwiftUI; on the web, a plain `border-radius` is close enough.

## Surfaces and depth

Depth is quiet: a hairline and a soft shadow, never a heavy one.

| Level | Border | Shadow | For |
|---|---|---|---|
| Flat | none | none | Rows, the column |
| Raised | 1 px `hairline` | 0 1 2 rgba(0,0,0,0.08) | A selected segment, a tile |
| Floating | 1 px `hairline` | 0 8 20 rgba(0,0,0,0.14) | Cards over content, popovers |
| Overlay | 1 px `hairline` | 0 14 30 rgba(0,0,0,0.30) | Dark glass over a stage |

**Dark glass** (the onboarding's cards, and anything over a coloured stage): `rgba(0,0,0,0.42)` under `rgba(255,255,255,0.045)`, a 1 px border from `rgba(255,255,255,0.14)` at the top to `0.04` at the bottom, radius 20. It takes the colour behind it a little; it never picks up the desktop's tint.

## Components

**Buttons.** Words in a capsule. *Primary* is filled with `ink`, its text `ground`: one per screen. *Secondary* is `ground` with a 1 px `hairline` border and `ink` text. *Plain* is text alone in `muted`, for the quiet way out ("Don't ask again"). Height 28 (small) or 36 (regular) on the Mac, 44 on iOS; horizontal padding 10–18.

**Segmented controls.** A `wash` track with radius 9, segments with radius 7; the chosen segment is `ground` with the Raised shadow, and slides to the next one (`settle`). Its word goes from `muted` regular to `ink` medium.

**Toggles.** A capsule track. On the stage: white with a black knob when on, `rgba(255,255,255,0.16)` with a white knob when off. In the app, the system's.

**Rows.** An icon (16 pt) or a site's mark, 10–12 pt to its title, the title in Body (medium when live), a muted note after it. The selected row is `wash`; the one under the pointer `hover`. One highlight travels from row to row rather than each row lighting on its own.

**Cards.** `ground`, radius 14, padding 16, Floating. A title in Callout, a line in Footnote `muted`, then the thing to do.

**Icons.** SF Symbols, weight medium, sized to the type beside them (about the text size minus one). Resting `muted`, active `ink`. On the web, a matching outline set at 1.5 px stroke.

**Counts and countdowns.** Small type under or beside the thing they belong to, `muted`, tabular; never a red bubble.

## Motion

Things move like light objects with a little weight: quick to start, unhurried to stop, and never past their place. Nothing moves for its own sake, and nothing takes long. Following Apple's *Designing Fluid Interfaces* and Emil Kowalski's design-engineering rules: springs are critically damped unless a hand threw the thing, nothing eases in, nothing grows from nothing, and what the keyboard does is never animated.

### Curves

| Token | SwiftUI | CSS | Feels like | For |
|---|---|---|---|---|
| `quick` | `.easeOut(duration: 0.14)` | `140ms cubic-bezier(0.2, 0.8, 0.2, 1)` | A tap | Hover in and out, colour changes, small fades |
| `out` | `.timingCurve(0.23, 1, 0.32, 1, duration:)` | `cubic-bezier(0.23, 1, 0.32, 1)` | Answering at once | Anything on a set length: entrances, exits (shorter than the way in), Core Animation and window fades |
| `settle` | `.spring(response: 0.30, dampingFraction: 1)` | `320ms cubic-bezier(0.25, 1, 0.35, 1)` | Landing in place | Selection moving, a toggle, a segment, a card appearing |
| `glide` | `.spring(response: 0.34, dampingFraction: 1)` | `360ms cubic-bezier(0.25, 1, 0.35, 1)` | Travel, straight into place | A highlight travelling between rows, layout changing size |
| `smooth` | `.smooth(duration: 0.42)` | `420ms cubic-bezier(0.25, 0.8, 0.25, 1)` | A page turned by hand | Swapping one view for another, the new-space card |
| `rise` | `.spring(response: 0.6, dampingFraction: 0.85)` | `600ms cubic-bezier(0.16, 1, 0.3, 1)` | Arriving | Things coming onto a screen for the first time |
| `fold` | out `.spring(response: 0.14, dampingFraction: 1)`, in `.spring(response: 0.13, dampingFraction: 1)` | out `140ms`, in `130ms`, both on `out` | Snappy | A sidebar folding away and back |
| `press` | `PressStyle`: 0.97 in 0.1 s, back in 0.16 s, both on `out` | `transform: scale(0.97)` | Giving under a finger | Every button: no button without it, and never a bounce |

Hover glows fade in on `smooth` at 0.45 s and out at 0.55 s, never with a bounce: a spring that overshoots an opacity flashes on the way out.

### Choreography

- **Rise.** Things arriving come up 10–14 pt from below, from 0 to 1 opacity, from a 4–6 pt blur to sharp, one after another 50–70 ms apart. A heading first, then what it introduces, then the action.
- **Swap.** One view giving way to another: the old one fades and shrinks to 0.96–0.97 on a quick 0.24 s; the new one rises in 0.1 s later on `smooth`. Never slide a whole screen sideways for a change of content; slide only for a change of place (one space to the next).
- **Travel.** A highlight or selection is one shape that moves to its new place on `glide` (matched geometry), never two that fade.
- **Hover.** On `quick`, or `smooth` for anything larger than a row. The leaving item lets go 60 ms after the next one takes the highlight, so it travels instead of blinking.
- **Popovers and floating cards.** Scale from 0.94 at the edge they come from, with a 6 pt rise and a fade, on `settle`; out faster, on a plain fade and 0.97.
- **Opening moment.** Once, on first launch only: dark, the mark blooming from 0.5 scale and a 20 pt blur in a soft glow with one fine ring spreading away, then the stage and the words. About two seconds in all. Nowhere else gets this.

### Rules

- **Damping 1 by default.** Overshoot only where the hand carried momentum into it (the swipe between spaces, a thrown window). A menu, a highlight or a card the app moved lands without passing its place.
- **Nothing eases in.** Entrances and exits alike go on `out`, the exit a little shorter. An ease-in holds still for the first frames, the very ones being watched.
- **Nothing grows from nothing.** A transition starts at 0.9 scale or more, with a fade. Below that it looks like it came from nowhere.
- **The keyboard is never animated.** ⌘T and ⌘L open and close at once; the arrow keys light their row at once. Only the pointer's own hover travels.
- **Every press answers.** Buttons use `PressStyle`; tabs and pins give on `Give`.
- **Under 300 ms** for anything in the interface. Cards, sheets and the new-space card may take up to 0.45 s; the first-run opening is the one long moment.

**Reduce Motion:** every move becomes an instant change or a 0.15–0.2 s fade. Nothing floats, spins or rises.

## Voice

- Say what it does, plainly: "Bring your things." "Nothing leaves your Mac."
- Short sentences. Sentence case. No exclamation marks, no "awesome", no emoji.
- British spelling: colour, favourite, organise.
- Name things by what they are to the person ("your spaces", "the page"), not by how they're built.
- Buttons are verbs: "Bring Them In", "Run on Click", "Show My Meetings". The quiet way out is "Not Now" or "Cancel", never "No thanks!".

## For iOS

- Use the system face and Dynamic Type, mapping the scale above to text styles: Caption → `.caption`, Footnote → `.footnote`, Body → `.subheadline` (15), Callout → `.headline`, Title → `.title3`, Display → `.title` at most. Keep `.largeTitle` out of the app.
- Light and dark from the system. Same greys; `ground` is the system background, `wash` the grouped secondary.
- 44 pt rows and targets, 16 pt side margins, sheets with radius 14 at the top.
- Motion tokens as above; tab and navigation transitions are the system's.

## For the web

Tokens to start from:

```css
:root {
  --ground: #FFFFFF; --frame: #F4F4F4; --ink: #171717; --muted: #8C8C8C;
  --faint: #D4D4D4; --hairline: #E8E8E8; --wash: #EFEFEF; --hover: #F6F6F6;
  --safe: #14803D; --caution: #B5540A;

  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
  --text-caption: 12px; --text-footnote: 13px; --text-body: 15px;
  --text-callout: 17px; --text-title: 22px; --text-display: 32px;

  --radius-sm: 8px; --radius-md: 10px; --radius-lg: 14px; --radius-xl: 20px;
  --shadow-raised: 0 1px 2px rgba(0,0,0,.08);
  --shadow-floating: 0 8px 20px rgba(0,0,0,.14);

  --ease-quick: cubic-bezier(0.2, 0.8, 0.2, 1);    /* 140ms */
  --ease-settle: cubic-bezier(0.25, 1, 0.35, 1);    /* 320ms */
  --ease-glide: cubic-bezier(0.25, 1, 0.35, 1);     /* 360ms, no overshoot */
  --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
  --ease-smooth: cubic-bezier(0.25, 0.8, 0.25, 1);  /* 420ms */
  --ease-rise: cubic-bezier(0.16, 1, 0.3, 1);       /* 600ms */
}

@media (prefers-color-scheme: dark) {
  :root {
    --ground: #1C1C1C; --frame: #131313; --ink: #EDEDED; --muted: #949494;
    --faint: #525252; --hairline: #333333; --wash: #2D2D2D; --hover: #262626;
    --safe: #4ADE80; --caution: #FABF24;
  }
}

@media (prefers-reduced-motion: reduce) {
  * { transition-duration: 150ms !important; animation: none !important; }
}
```

A page is mostly `ground` and `ink`: a header with the Q and "Quo", one line of what it is, one filled button to download, a quiet secondary link, and real screenshots of the app on `frame`. Body text at 15 px, measure 60–70 characters. If something needs colour, take it from a screenshot of a space, not from a brand palette.
