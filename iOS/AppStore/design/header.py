"""Quo for iPhone's App Store header, the wide banner over the product page.

Two sizes Apple takes: 5244 x 2950 (16:9) and 3840 x 1646 (21:9). Everything
that matters sits in the middle, since Apple crops it differently by device
and orientation: two short lines in the middle third, three phones rising from the
bottom edge. No Q tile: the app icon sits right under the header anyway. Drawn at half size and rendered at 2x by headless Chrome.

    python3 header.py      # writes ../header/*.png
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE.parent / "raw"
OUT = HERE.parent / "header"
BUILD = HERE / "build"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
Q = (HERE.parent.parent.parent / "Icon/Quo.icon/Assets/quo-q-vector.svg").read_text().replace('fill="white"', 'fill="#171717"')

SIZES = {"header-5244x2950": (2622, 1475), "header-3840x1646": (1920, 823)}

PAGE = """<!doctype html><meta charset="utf-8">
<style>
  * {{ margin: 0; box-sizing: border-box; }}
  html, body {{ width: {w}px; height: {h}px; overflow: hidden; }}
  body {{ background: radial-gradient(120% 90% at 50% 0%, #232323 0%, #131313 55%, #0E0E0E 100%);
         font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
         color: #EDEDED; -webkit-font-smoothing: antialiased; position: relative; }}
  .top {{ position: absolute; left: 0; right: 0; top: {top}px; display: flex; flex-direction: column; align-items: center; }}
  .brand {{ display: flex; align-items: center; gap: {gap}px; }}
  .tile {{ width: {tile}px; height: {tile}px; border-radius: {tr}px; background: #FAFAFA; display: grid; place-items: center;
          box-shadow: 0 {s1}px {s2}px rgba(0,0,0,0.5); }}
  .tile svg {{ width: 60%; height: 60%; }}
  .word {{ font-size: {word}px; font-weight: 600; letter-spacing: -0.01em; }}
  h1 {{ margin-top: 0; font-size: {h1}px; line-height: 1; font-weight: 600; letter-spacing: -0.035em; text-align: center; }}
  p {{ margin-top: {pm}px; font-size: {p}px; color: #949494; letter-spacing: -0.005em; text-align: center; }}
  .phones {{ position: absolute; left: 50%; bottom: {pb}px; width: 0; height: 0; }}
  .phone {{ position: absolute; bottom: 0; width: {pw}px; padding: {pp}px; border-radius: {pr}px; background: #0A0A0A;
           box-shadow: 0 0 0 {rim}px #2E2E2E, 0 {s1}px {s3}px rgba(0,0,0,0.6); transform-origin: 50% 100%; }}
  .phone img {{ display: block; width: 100%; border-radius: {ir}px; }}
  .l {{ left: {lx}px; transform: rotate(-9deg); }}
  .c {{ left: {cx}px; z-index: 2; }}
  .r {{ left: {rx}px; transform: rotate(9deg); }}
</style>
<body>
  <div class="top">
    <h1>The browser<br>without the junk.</h1>
    <p>No ads, no trackers, no cookie banners. Free.</p>
  </div>
  <div class="phones">
    <div class="phone l"><img src="{tabs}"></div>
    <div class="phone c"><img src="{page}"></div>
    <div class="phone r"><img src="{block}"></div>
  </div>
</body>"""


def html(w, h):
    k = h / 1475  # everything scales with height; the wide one is just shorter
    pw = round(470 * k)
    return PAGE.format(
        w=w, h=h, q=Q,
        top=round(250 * k), gap=round(22 * k), tile=round(104 * k), tr=round(24 * k), word=round(58 * k),
        h1m=round(46 * k), h1=round(118 * k), pm=round(28 * k), p=round(38 * k),
        pb=round(-330 * k), pw=pw, pp=round(11 * k), pr=round(70 * k), ir=round(60 * k), rim=max(1, round(1.5 * k)),
        s1=round(30 * k), s2=round(70 * k), s3=round(120 * k),
        lx=-pw // 2 - round(440 * k), cx=-pw // 2, rx=-pw // 2 + round(440 * k),
        tabs=(RAW / "tabs.png").as_uri(), page=(RAW / "page.png").as_uri(), block=(RAW / "blocking.png").as_uri(),
    )


def main():
    BUILD.mkdir(exist_ok=True)
    OUT.mkdir(exist_ok=True)
    for name, (w, h) in SIZES.items():
        src = BUILD / f"{name}.html"
        src.write_text(html(w, h))
        png = OUT / f"{name}.png"
        subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=2",
                        f"--window-size={w},{h}", f"--screenshot={png}", "--virtual-time-budget=3000", src.as_uri()],
                       check=True, capture_output=True)
        print(png.name)


if __name__ == "__main__":
    main()
