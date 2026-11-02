#!/usr/bin/env python3
"""Writes the Burrow icons as SVG (render.sh turns them into assets/*.png): a rat peeking out of its burrow.

Each command's icon puts its glyph up front on its own colour, with a smaller rat peeking in below.
"""
from pathlib import Path

OUT = Path(__file__).parent

DEFS = """
  <defs>
    <linearGradient id="soil" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#A9744A"/>
      <stop offset="1" stop-color="#5A3820"/>
    </linearGradient>
    <radialGradient id="fur" cx="0.5" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#B7BCC2"/>
      <stop offset="1" stop-color="#7E858D"/>
    </radialGradient>
    <clipPath id="above"><rect x="0" y="0" width="512" height="384"/></clipPath>
  </defs>
"""

SOIL = """
  <rect width="512" height="512" fill="url(#soil)"/>
  <g fill="#000" opacity="0.12">
    <circle cx="80" cy="104" r="10"/><circle cx="440" cy="80" r="8"/><circle cx="104" cy="300" r="7"/>
    <circle cx="452" cy="270" r="11"/><circle cx="64" cy="440" r="9"/><circle cx="300" cy="60" r="6"/>
  </g>
"""

RAT = """
  <path d="M128 396 C 80 392, 66 334, 102 304 S 138 244, 108 212" stroke="#E79AAC" stroke-width="13"
        stroke-linecap="round" fill="none"/>
  <ellipse cx="256" cy="384" rx="168" ry="56" fill="#24150B"/>
  <ellipse cx="256" cy="392" rx="140" ry="40" fill="#120A05"/>
  <g clip-path="url(#above)">
    <circle cx="160" cy="190" r="62" fill="url(#fur)"/>
    <circle cx="352" cy="190" r="62" fill="url(#fur)"/>
    <circle cx="164" cy="194" r="38" fill="#F2A3B5"/>
    <circle cx="348" cy="194" r="38" fill="#F2A3B5"/>
    <ellipse cx="256" cy="300" rx="118" ry="108" fill="url(#fur)"/>
    <ellipse cx="256" cy="352" rx="66" ry="48" fill="#C9CDD2"/>
    <circle cx="210" cy="282" r="17" fill="#15110F"/>
    <circle cx="302" cy="282" r="17" fill="#15110F"/>
    <circle cx="215" cy="276" r="5.5" fill="#FFF"/>
    <circle cx="307" cy="276" r="5.5" fill="#FFF"/>
    <ellipse cx="256" cy="330" rx="19" ry="13" fill="#EE7894"/>
  </g>
  <g stroke="#F4F1EC" stroke-width="5" stroke-linecap="round" fill="none" opacity="0.9">
    <path d="M222 342 Q170 326 118 318"/><path d="M222 352 Q168 352 116 360"/>
    <path d="M290 342 Q342 326 394 318"/><path d="M290 352 Q344 352 396 360"/>
  </g>
  <rect x="245" y="352" width="10" height="18" rx="3" fill="#FFF8E7"/>
  <rect x="257" y="352" width="10" height="18" rx="3" fill="#FFF8E7"/>
  <ellipse cx="182" cy="382" rx="30" ry="18" fill="#F2A3B5"/>
  <ellipse cx="330" cy="382" rx="30" ry="18" fill="#F2A3B5"/>
  <g stroke="#C77A8E" stroke-width="4" stroke-linecap="round">
    <path d="M170 376 v12"/><path d="M182 374 v14"/><path d="M194 376 v12"/>
    <path d="M318 376 v12"/><path d="M330 374 v14"/><path d="M342 376 v12"/>
  </g>
"""

def w(width: int = 12) -> str:
    return f'stroke="#FFF" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" fill="none"'

GLYPHS = {
    "switch-to": ("#3B82F6", f'<g {w()}><path d="M362 372 h64 l-18 -18"/><path d="M422 412 h-64 l18 18"/></g>'),
    "needs-me": ("#F97316", f'<g {w()}><path d="M370 436 v-88"/><path d="M370 352 h50 l-12 20 l12 20 h-50" fill="#FFF"/></g>'),
    "new-worktree": ("#22C55E", f'<g {w(14)}><path d="M392 360 v64"/><path d="M360 392 h64"/></g>'),
    "repos": ("#8B5CF6", f'<g {w(10)}><path d="M356 372 h22 l8 10 h34 v42 h-64 z"/></g>'),
    "prs": ("#14B8A6", f'<g {w(10)}><circle cx="370" cy="360" r="9"/><circle cx="370" cy="426" r="9"/>'
            f'<circle cx="416" cy="426" r="9"/><path d="M370 370 v46"/><path d="M370 372 q0 30 46 44"/></g>'),
    "menu-bar": ("#EAB308", '<g fill="#FFF"><circle cx="364" cy="392" r="10"/><circle cx="392" cy="392" r="10"/>'
                 '<circle cx="420" cy="392" r="10"/></g>'),
}


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{DEFS}{body}</svg>\n'


def shade(color: str, k: float) -> str:
    r, g, b = (int(color[i : i + 2], 16) for i in (1, 3, 5))
    return "#" + "".join(f"{max(0, min(255, round(c * k))):02X}" for c in (r, g, b))


# the art was drawn inside a 448px tile; stretch it to the edges so Raycast doesn't shrink it
BLEED = '<g transform="translate(256 256) scale(1.143) translate(-256 -256)">{}</g>'




def focus(glyph: str, color: str) -> str:
    bg = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{shade(color, 1.15)}"/>'
          f'<stop offset="1" stop-color="{shade(color, 0.7)}"/></linearGradient><rect width="512" height="512" fill="url(#bg)"/>')
    big = f'<g transform="translate(256 172) scale(2.0) translate(-392 -392)">{glyph}</g>'
    peek = f'<g transform="translate(256 470) scale(0.66) translate(-256 -384)">{RAT}</g>'
    return svg(bg + big + peek)


(OUT / "icon.svg").write_text(svg(SOIL + BLEED.format(RAT)))
for name, (color, glyph) in GLYPHS.items():
    (OUT / f"{name}.svg").write_text(focus(glyph, color))
