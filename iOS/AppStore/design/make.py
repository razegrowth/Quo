"""Quo for iPhone's App Store screens, 1320 x 2868 (6.9" iPhone).

Each is an HTML page (a headline, a line under it, the app's own screen in a
phone) rendered by headless Chrome. Quo's DESIGN.md: monochrome greys, the
system face, semibold only for titles, plain words.

    python3 make.py        # writes ../screenshots/*.png
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE.parent / "raw"
OUT = HERE.parent / "screenshots"
BUILD = HERE / "build"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ICON = HERE.parent.parent / "Quo/AppIcon.icon"
ICTOOL = "/Applications/Icon Composer.app/Contents/Executables/ictool"

LIGHT = dict(ground="#F4F4F4", ink="#171717", muted="#737373")
DARK = dict(ground="#131313", ink="#EDEDED", muted="#949494")

SCREENS = [
    dict(name="1-quo", hero=True, raw="page.png", theme=DARK,
         title="The quiet browser<br>for iPhone.",
         line="Fast, free, and nothing to sign up for. Your pages, without the junk around them.",
         points=["Ads, trackers and cookie banners blocked", "Tabs that tidy themselves",
                 "Ask any page a question, on your iPhone", "Picks up where your Mac left off"]),
    dict(name="2-page", raw="page.png", theme=LIGHT,
         title="The web, and nothing<br>in the way.",
         line="One bar at the bottom. Everything else waits under a single tap."),
    dict(name="3-tabs", raw="tabs.png", theme=DARK,
         title="Tabs that tidy<br>themselves.",
         line="The ones you haven't touched in a week move to the Archive on their own."),
    dict(name="4-blocking", raw="blocking.png", theme=LIGHT,
         title="Ads, trackers and<br>cookie banners, gone.",
         line="Blocked on every site from the start. One tap lets a site through."),
    dict(name="5-toolbar", raw="toolbar.png", theme=LIGHT,
         title="Ask the page<br>you're on.",
         line="Find, pin, share, or ask a question about what you're reading. On your iPhone, nothing sent."),
    dict(name="6-quiet", raw=None, theme=DARK,
         title="No account.<br>No servers.<br>Just a browser.",
         line="Nothing you browse is ever sent to us. Sync goes through your own iCloud, end-to-end encrypted."),
]

HERO = """<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: 1320px; height: 2868px; overflow: hidden; background: {ground}; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
         color: {ink}; -webkit-font-smoothing: antialiased; position: relative; }}
  .brand {{ position: absolute; left: 120px; top: 190px; display: flex; align-items: center; gap: 32px; }}
  .tile {{ width: 168px; height: 168px; }}
  .tile img {{ display: block; width: 100%; height: 100%; }}
  .word {{ font-size: 84px; font-weight: 600; letter-spacing: -0.01em; }}
  .free {{ margin-left: 8px; font-size: 34px; font-weight: 500; color: {muted}; border: 2px solid #333;
          border-radius: 999px; padding: 10px 26px; }}
  h1 {{ position: absolute; left: 120px; right: 100px; top: 470px; font-size: 140px; line-height: 1.0;
       font-weight: 600; letter-spacing: -0.035em; }}
  p {{ position: absolute; left: 120px; top: 790px; max-width: 1000px; font-size: 48px; line-height: 1.3;
      color: {muted}; letter-spacing: -0.005em; }}
  ul {{ position: absolute; left: 120px; top: 1000px; list-style: none; padding: 0; }}
  li {{ display: flex; align-items: center; gap: 28px; font-size: 44px; line-height: 1.25; font-weight: 500;
       letter-spacing: -0.005em; margin-top: 26px; }}
  li svg {{ flex: none; width: 52px; height: 52px; }}
  .phone {{ position: absolute; left: 50%; top: 1500px; width: 1000px; transform: translateX(-50%);
           padding: 24px; border-radius: 162px; background: #0A0A0A;
           box-shadow: 0 0 0 3px #2E2E2E, 0 -30px 160px rgba(255,255,255,0.06); }}
  .phone img {{ display: block; width: 100%; border-radius: 138px; }}
  .fade {{ position: absolute; left: 0; right: 0; bottom: 0; height: 260px;
          background: linear-gradient(to bottom, rgba(19,19,19,0), {ground}); }}
</style>
<body>
  <div class="brand"><div class="tile">{q}</div><div class="word">Quo</div><div class="free">Free</div></div>
  <h1>{title}</h1>
  <p>{line}</p>
  <ul>{points}</ul>
  <div class="phone"><img src="{img}"></div>
  <div class="fade"></div>
</body>"""

CHECK = ('<svg viewBox="0 0 52 52"><circle cx="26" cy="26" r="25" fill="#EDEDED"/>'
         '<path d="M15 26.5l7.5 7.5L37 19" fill="none" stroke="#131313" stroke-width="4.5" '
         'stroke-linecap="round" stroke-linejoin="round"/></svg>')

BASE = """<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: 1320px; height: 2868px; overflow: hidden; background: {ground}; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
         color: {ink}; -webkit-font-smoothing: antialiased; position: relative; }}
  .copy {{ position: absolute; left: 120px; right: 120px; top: 200px; }}
  h1 {{ font-size: 112px; line-height: 1.04; font-weight: 600; letter-spacing: -0.03em; }}
  p {{ margin-top: 44px; font-size: 46px; line-height: 1.32; color: {muted}; max-width: 960px; letter-spacing: -0.005em; }}
  .phone {{ position: absolute; left: 50%; bottom: 120px; width: 930px; transform: translateX(-50%);
           padding: 22px; border-radius: 150px; background: #0A0A0A;
           box-shadow: 0 0 0 3px {rim}, 0 60px 140px rgba(0,0,0,{shadow}); }}
  .phone img {{ display: block; width: 100%; border-radius: 128px; }}
  .mark {{ position: absolute; left: 120px; bottom: 260px; display: flex; align-items: center; gap: 36px; }}
  .tile {{ width: 200px; height: 200px; }}
  .tile img {{ display: block; width: 100%; height: 100%; }}
  .word {{ font-size: 88px; font-weight: 600; letter-spacing: -0.01em; }}
  .closer .copy {{ top: 760px; }}
  .closer h1 {{ font-size: 136px; }}
  .closer p {{ margin-top: 64px; }}
</style>
<body class="{cls}">
  <div class="copy"><h1>{title}</h1><p>{line}</p></div>
  {body}
</body>"""


def page(s):
    t = s["theme"]
    dark = t is DARK
    q = f'<img src="file://{BUILD / "icon.png"}">'
    if s.get("hero"):
        points = "".join(f"<li>{CHECK}{x}</li>" for x in s["points"])
        return HERO.format(title=s["title"], line=s["line"], points=points, q=q,
                           img=f'file://{RAW / s["raw"]}', **t)
    if s["raw"]:
        body = f'<div class="phone"><img src="file://{RAW / s["raw"]}"></div>'
        cls = ""
    else:
        body = f'<div class="mark"><div class="tile">{q}</div><div class="word">Quo</div></div>'
        cls = "closer"
    return BASE.format(cls=cls, title=s["title"], line=s["line"], body=body,
                       rim="#2E2E2E" if dark else "#D9D9D9", shadow="0.5" if dark else "0.16", **t)


def main():
    BUILD.mkdir(exist_ok=True)
    OUT.mkdir(exist_ok=True)
    # The app icon as iOS draws it, from the Icon Composer file the app ships.
    subprocess.run([ICTOOL, str(ICON), "--export-image", "--output-file", str(BUILD / "icon.png"), "--platform", "iOS",
                    "--rendition", "Default", "--width", "512", "--height", "512", "--scale", "1"],
                   check=True, capture_output=True)
    for s in SCREENS:
        html = BUILD / f'{s["name"]}.html'
        html.write_text(page(s))
        png = OUT / f'{s["name"]}.png'
        subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
                        "--window-size=1320,2868", f"--screenshot={png}", "--virtual-time-budget=3000",
                        html.as_uri()], check=True, capture_output=True)
        print(png.name)


if __name__ == "__main__":
    main()
