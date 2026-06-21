"""
generate_icon.py  –  MyFeelsLike app icon generator
=====================================================
Requires: pip install pillow

Run:  python3 generate_icon.py
Output: AppIcon1024.png  (1024×1024, same folder as this script)

Tweak the palette constants at the top to change colours,
or adjust the coordinate variables (cc / ch) to move the figures.
"""

from PIL import Image, ImageDraw
import math, random, os

SIZE = 1024
BG   = (28, 28, 36)
DARK = (15, 15, 20)
OW   = 5   # outline width (px)

# ── Palettes ──────────────────────────────────────────────────────────────────

# Cold person
SKIN_C  = (240, 195, 155)
COAT    = (30,  65, 148)
SCARF   = (210,  42,  42)
SCARF2  = (168,  28,  28)
HAT     = (22,  50, 120)
HAT_BND = (192, 210, 238)
POM     = (228, 228, 252)
MITTEN  = (192,  36,  36)
BOOT    = (36,   26,  16)
PANT    = (38,   38,  48)
ROSY_C  = (222, 140, 120)
BREATH  = (202, 215, 232)
SNOW    = (172, 195, 228)

# Hot person
SKIN_H  = (235, 168, 108)
SHIRT   = (255, 135,  50)
SHORTS  = (65,  152, 222)
HAIR    = (72,   46,  16)
GLASS   = (20,   20,  20)
SANDAL  = (108,  72,  28)
SWEAT   = (130, 188, 255)
SUN_COL = (255, 222,  45)

# Temperature-gradient anchors (mirrors ColorScale.swift)
ANCHORS = [
    (-20, 255, 255, 255),   # white
    (  9,  30, 120, 255),   # blue
    ( 21,  40, 200,  80),   # green
    (27.25,255, 220,  30),  # yellow
    ( 33, 255,  60,  30),   # red
    ( 39, 160,  30, 220),   # purple
    ( 45,   0,   0,   0),   # black
]

# ── Helpers ───────────────────────────────────────────────────────────────────

def lerp_col(t):
    """Map t ∈ [0,1] (cold→hot) to an RGB tuple via the gradient anchors."""
    lo, hi = ANCHORS[0][0], ANCHORS[-1][0]
    temp = lo + t * (hi - lo)
    for i in range(len(ANCHORS) - 1):
        t0, r0, g0, b0 = ANCHORS[i]
        t1, r1, g1, b1 = ANCHORS[i + 1]
        if temp <= t1:
            f = (temp - t0) / (t1 - t0)
            return (int(r0+f*(r1-r0)), int(g0+f*(g1-g0)), int(b0+f*(b1-b0)))
    return ANCHORS[-1][1:]

def ell(d, cx, cy, rx, ry, fill, ow=OW):
    """Outlined ellipse."""
    d.ellipse([cx-rx-ow, cy-ry-ow, cx+rx+ow, cy+ry+ow], fill=DARK)
    d.ellipse([cx-rx,    cy-ry,    cx+rx,    cy+ry   ], fill=fill)

def rr(d, x0, y0, x1, y1, radius, fill, ow=OW):
    """Outlined rounded rectangle."""
    d.rounded_rectangle([x0-ow, y0-ow, x1+ow, y1+ow],
                        radius=max(2, radius+ow), fill=DARK)
    d.rounded_rectangle([x0, y0, x1, y1],
                        radius=max(2, radius), fill=fill)

def seg(d, x1, y1, x2, y2, hw, fill, ow=OW):
    """Outlined thick line segment (drawn as a rotated rectangle)."""
    a  = math.atan2(y2-y1, x2-x1)
    p  = a + math.pi/2
    dx, dy = math.cos(p), math.sin(p)
    def pts(h):
        return [(x1+h*dx, y1+h*dy), (x1-h*dx, y1-h*dy),
                (x2-h*dx, y2-h*dy), (x2+h*dx, y2+h*dy)]
    d.polygon(pts(hw+ow), fill=DARK)
    d.polygon(pts(hw),    fill=fill)

# ── Canvas ────────────────────────────────────────────────────────────────────
img  = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=220, fill=BG)

# ══════════════════════════════════════════════════════════════════════════════
#  COLD PERSON  (centre x = cc)
# ══════════════════════════════════════════════════════════════════════════════
cc = 192

# Boots
rr(draw, cc-54, 790, cc-8,  845, 14, BOOT)
rr(draw, cc+8,  790, cc+54, 845, 14, BOOT)
# Legs (mostly hidden by coat)
rr(draw, cc-36, 705, cc-10, 800,  8, PANT)
rr(draw, cc+10, 705, cc+36, 800,  8, PANT)
# Coat body
rr(draw, cc-66, 388, cc+66, 720, 34, COAT)
# Zipper
draw.line([(cc, 408), (cc, 712)], fill=(128, 152, 198), width=6)
for zy in [448, 498, 548, 598, 648, 698]:
    draw.ellipse([cc-5, zy-5, cc+5, zy+5], fill=(152, 172, 212))
# Arms – crossed (right arm underneath, left on top)
seg(draw, cc+62, 420, cc-34, 515, 30, COAT)   # right → ends left
seg(draw, cc-62, 420, cc+34, 515, 30, COAT)   # left  → ends right
# Mittens
ell(draw, cc+38, 525, 27, 23, MITTEN)
ell(draw, cc-38, 525, 27, 23, MITTEN)
# Scarf
rr(draw, cc-72, 332, cc+72, 400, 26, SCARF)
draw.rounded_rectangle([cc-64, 368, cc+64, 412], radius=16, fill=SCARF2)
for fy in range(340, 398, 14):
    draw.line([(cc+72, fy), (cc+84, fy+10)], fill=SCARF2, width=3)
# Head (skin base)
ell(draw, cc, 290, 58, 54, SKIN_C)
# Hat – covers forehead
rr(draw, cc-66, 210, cc+66, 294, 30, HAT)
draw.rounded_rectangle([cc-66, 276, cc+66, 298], radius=12, fill=HAT_BND)
ell(draw, cc, 202, 26, 26, POM)
# Re-expose face strip between hat (y≈293) and scarf (y≈334)
draw.ellipse([cc-52, 284, cc+52, 342], fill=SKIN_C)
draw.rounded_rectangle([cc-66, 210, cc+66, 298], radius=30, fill=HAT)
draw.rounded_rectangle([cc-66, 276, cc+66, 296], radius=12, fill=HAT_BND)
draw.rounded_rectangle([cc-72, 330, cc+72, 360], radius=20, fill=SCARF)
# Eyes (worried look – inner brow raised)
EY = 309
draw.ellipse([cc-30, EY-12, cc-8,  EY+12], fill=DARK)
draw.ellipse([cc+8,  EY-12, cc+30, EY+12], fill=DARK)
draw.ellipse([cc-28, EY-10, cc-10, EY+10], fill=(55, 36, 18))
draw.ellipse([cc+10, EY-10, cc+28, EY+10], fill=(55, 36, 18))
draw.ellipse([cc-24, EY-7,  cc-18, EY-2 ], fill=(255, 255, 255))
draw.ellipse([cc+18, EY-7,  cc+24, EY-2 ], fill=(255, 255, 255))
# Worried brows
draw.line([(cc-32, EY-19), (cc-8,  EY-15)], fill=DARK, width=5)
draw.line([(cc+8,  EY-15), (cc+32, EY-19)], fill=DARK, width=5)
# Rosy cheeks
draw.ellipse([cc-46, EY+3, cc-26, EY+16], fill=ROSY_C)
draw.ellipse([cc+26, EY+3, cc+46, EY+16], fill=ROSY_C)
# Breath puffs
for bx, by, br in [(cc+70, 298, 9), (cc+83, 285, 12), (cc+98, 293, 8)]:
    draw.ellipse([bx-br, by-br, bx+br, by+br], fill=BREATH)
# Snowflakes
flake_positions = [(80,165,18), (50,340,14), (115,490,16), (62,640,15), (88,775,13)]
for fx, fy, fr in flake_positions:
    for a in range(0, 360, 60):
        rad = math.radians(a)
        ex, ey = fx + fr*math.cos(rad), fy + fr*math.sin(rad)
        draw.line([(fx, fy), (ex, ey)], fill=SNOW, width=3)
        for t in [0.45, 0.75]:
            mx = fx + t*fr*math.cos(rad); my = fy + t*fr*math.sin(rad)
            for da in [60, -60]:
                br2 = math.radians(a+da); bl = fr*0.28
                draw.line([(mx, my),
                           (mx+bl*math.cos(br2), my+bl*math.sin(br2))],
                          fill=SNOW, width=2)
    draw.ellipse([fx-3, fy-3, fx+3, fy+3], fill=(220, 230, 248))

# ══════════════════════════════════════════════════════════════════════════════
#  HOT PERSON  (centre x = ch)
# ══════════════════════════════════════════════════════════════════════════════
ch = 822

# Sandals
rr(draw, ch-52, 806, ch-8,  826, 10, SANDAL)
rr(draw, ch+8,  806, ch+52, 826, 10, SANDAL)
for sx in [ch-44, ch-24]: draw.line([(sx, 806), (sx, 820)], fill=DARK, width=3)
for sx in [ch+24, ch+44]: draw.line([(sx, 806), (sx, 820)], fill=DARK, width=3)
# Legs (bare skin)
rr(draw, ch-44, 688, ch-12, 820, 12, SKIN_H)
rr(draw, ch+12, 688, ch+44, 820, 12, SKIN_H)
# Shorts
rr(draw, ch-60, 600, ch+60, 702, 18, SHORTS)
# Shirt body
rr(draw, ch-55, 358, ch+55, 618, 22, SHIRT)
# Shirt sleeves
seg(draw, ch-51, 392, ch-94, 530, 27, SHIRT)
seg(draw, ch+51, 392, ch+94, 530, 27, SHIRT)
# Forearms (bare skin)
seg(draw, ch-94, 530, ch-100, 645, 23, SKIN_H)
seg(draw, ch+94, 530, ch+100, 645, 23, SKIN_H)
# Hands
ell(draw, ch-100, 655, 21, 17, SKIN_H)
ell(draw, ch+100, 655, 21, 17, SKIN_H)
# V-neck
draw.polygon([(ch-20, 360), (ch+20, 360), (ch, 400)], fill=SKIN_H)
draw.line([(ch-20, 360), (ch, 400), (ch+20, 360)], fill=DARK, width=4)
# Neck
rr(draw, ch-17, 334, ch+17, 368, 10, SKIN_H)
# Head
ell(draw, ch, 278, 58, 54, SKIN_H)
# Hair (short, spiky)
draw.ellipse([ch-55, 230, ch+55, 284], fill=HAIR)
for spx, spy in [(-28,228),(0,220),(28,228),(-44,240),(44,240)]:
    sx, sy = ch+spx, spy
    draw.polygon([(sx-7, sy+14), (sx+7, sy+14), (sx, sy-12)], fill=HAIR)
draw.ellipse([ch-64, 248, ch-44, 276], fill=HAIR)
draw.ellipse([ch+44, 248, ch+64, 276], fill=HAIR)
# Sunglasses
ell(draw, ch-20, 272, 20, 14, GLASS)
ell(draw, ch+20, 272, 20, 14, GLASS)
draw.line([(ch, 272), (ch, 272)], fill=DARK, width=6)          # bridge
draw.line([(ch-40, 268), (ch-58, 264)], fill=DARK, width=4)    # L arm
draw.line([(ch+40, 268), (ch+58, 264)], fill=DARK, width=4)    # R arm
draw.ellipse([ch-35, 264, ch-20, 271], fill=(50, 50, 50))      # L shine
draw.ellipse([ch+6,  264, ch+21, 271], fill=(50, 50, 50))      # R shine
# Smile + teeth
draw.arc([ch-24, 296, ch+24, 322], start=12,  end=168, fill=DARK,            width=5)
draw.arc([ch-20, 300, ch+20, 318], start=15,  end=165, fill=(238, 232, 220), width=3)
# Sweat drops (teardrop = ellipse + triangle)
for sx, sy, sr in [(ch+68, 290, 10), (ch+78, 322, 7), (ch-76, 308, 8)]:
    draw.ellipse([sx-sr, sy-sr, sx+sr, sy+sr], fill=SWEAT)
    draw.polygon([(sx-sr+3, sy+sr-4), (sx+sr-3, sy+sr-4), (sx, sy+2*sr-2)], fill=SWEAT)
    draw.ellipse([sx-4, sy-6, sx+4, sy-1], fill=(195, 220, 255))
# Sun (top-right corner)
sun_x, sun_y, sun_r = 908, 142, 34
draw.ellipse([sun_x-sun_r-OW, sun_y-sun_r-OW,
              sun_x+sun_r+OW, sun_y+sun_r+OW], fill=DARK)
draw.ellipse([sun_x-sun_r, sun_y-sun_r,
              sun_x+sun_r, sun_y+sun_r], fill=SUN_COL)
draw.ellipse([sun_x-sun_r+6, sun_y-sun_r+6,
              sun_x+sun_r-6, sun_y+sun_r-6], fill=(255, 245, 100))
for a in range(0, 360, 45):
    rad = math.radians(a); r1 = sun_r+9; r2 = sun_r+24
    draw.line([(sun_x+r1*math.cos(rad), sun_y+r1*math.sin(rad)),
               (sun_x+r2*math.cos(rad), sun_y+r2*math.sin(rad))],
              fill=SUN_COL, width=5)

# ══════════════════════════════════════════════════════════════════════════════
#  THERMOMETER  (centred, drawn last so it sits on top)
# ══════════════════════════════════════════════════════════════════════════════
cx    = SIZE // 2
bcy   = 760; br = 130; tw = 86; ttop = 155; tbot = bcy - br + 38
stroke = 12

# Gradient fill (pixel-by-pixel scanlines)
therm = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
td    = ImageDraw.Draw(therm)
total_h = (bcy + br) - ttop
for y in range(ttop, bcy+br+1):
    t = max(0.0, min(1.0, 1.0 - (y - ttop) / total_h))
    col = lerp_col(t)
    if y <= tbot:
        for x in range(cx-tw, cx+tw+1):
            therm.putpixel((x, y), col + (255,))
    else:
        dy2 = y - bcy
        dx2 = math.sqrt(max(0, br**2 - dy2**2))
        for x in range(int(cx-dx2), int(cx+dx2)+1):
            therm.putpixel((x, y), col + (255,))
# Rounded cap at top
for y in range(ttop-tw, ttop+1):
    dy2 = y - ttop
    dx2 = math.sqrt(max(0, tw**2 - dy2**2))
    t   = max(0.0, min(1.0, 1.0 - (y - ttop) / total_h))
    col = lerp_col(t)
    for x in range(int(cx-dx2), int(cx+dx2)+1):
        therm.putpixel((x, y), col + (255,))

# Dark rim
rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
rd  = ImageDraw.Draw(rim)
rim_c = (18, 18, 26, 255)
rd.rounded_rectangle([cx-tw-stroke, ttop-stroke, cx+tw+stroke, tbot+stroke],
                     radius=tw+stroke, fill=rim_c)
rd.ellipse([cx-br-stroke, bcy-br-stroke, cx+br+stroke, bcy+br+stroke], fill=rim_c)
rd.rounded_rectangle([cx-tw, ttop, cx+tw, tbot], radius=tw, fill=(0,0,0,0))
rd.ellipse([cx-br, bcy-br, cx+br, bcy+br], fill=(0,0,0,0))

# Highlight stripe
for y in range(ttop+8, tbot-8):
    hl_x = cx - tw + 16
    for x in range(hl_x, hl_x+10):
        a = int(175 * (1 - abs(x - (hl_x+5)) / 5.0))
        therm.putpixel((x, y), (255, 255, 255, a))

# Heart cut-out
heart_scale = 52; hcx, hcy = cx, bcy + 8
heart_mask  = Image.new("L", (SIZE, SIZE), 0)
hm          = ImageDraw.Draw(heart_mask)
heart_pts   = [
    (hcx + heart_scale * 16 * math.sin(t * 2*math.pi/200)**3 / 16,
     hcy - heart_scale * (13*math.cos(t*2*math.pi/200)
                          - 5*math.cos(2*t*2*math.pi/200)
                          - 2*math.cos(3*t*2*math.pi/200)
                          -   math.cos(4*t*2*math.pi/200)) / 16)
    for t in range(200)
]
hm.polygon(heart_pts, fill=255)
heart_fill = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
therm = Image.composite(heart_fill, therm, heart_mask)

# Tick marks
tkl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
tkd = ImageDraw.Draw(tkl)
for i in range(9):
    ty = int(ttop + i * (tbot-ttop) / 8)
    tl = 24 if i%2==0 else 14; lw = 3 if i%2==0 else 2
    tkd.line([(cx+tw-2, ty), (cx+tw+tl, ty)], fill=(195,195,195,175), width=lw)

# Glow around bulb
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gd   = ImageDraw.Draw(glow)
for radd, alp in [(65, 12), (42, 22), (22, 38)]:
    warm = lerp_col(0.38)
    gd.ellipse([cx-br-radd, bcy-br-radd, cx+br+radd, bcy+br+radd], fill=warm+(alp,))

# Composite layers
img = Image.alpha_composite(img, rim)
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, therm)
img = Image.alpha_composite(img, tkl)

# ── Save ──────────────────────────────────────────────────────────────────────
out = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
out.paste(img, mask=img.split()[3])
script_dir = os.path.dirname(os.path.abspath(__file__))
out_path   = os.path.join(script_dir, "AppIcon1024.png")
out.save(out_path, "PNG")
print(f"Saved → {out_path}")
