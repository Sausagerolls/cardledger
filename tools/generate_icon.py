#!/usr/bin/env python3
"""Generate the CardLedger App Store icon (1024x1024, no alpha, sRGB).

Design: indigo->violet brand gradient, two stacked trading cards (the inventory),
and a gold coin badge (the price/ledger). Drawn at 4x and downsampled for crisp edges.
"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 1024
SS = 4               # supersample factor
W = S * SS

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# ---- background: vertical indigo -> violet gradient + soft top-left glow ----
top = (0x5B, 0x4F, 0xE8)      # indigo
bot = (0x7C, 0x3A, 0xED)      # violet
bg = Image.new("RGB", (W, W), top)
px = bg.load()
for y in range(W):
    t = y / (W - 1)
    row = lerp(top, bot, t)
    for x in range(W):
        px[x, y] = row

# radial highlight (top-left) for depth
glow = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([-W*0.35, -W*0.45, W*0.75, W*0.65], fill=90)
glow = glow.filter(ImageFilter.GaussianBlur(W*0.12))
white = Image.new("RGB", (W, W), (255, 255, 255))
bg = Image.composite(white, bg, glow.point(lambda v: int(v*0.55)))

def rounded_card(w, h, radius, fill, outline=None, ow=0):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w-1, h-1], radius=radius, fill=fill,
                        outline=outline, width=ow)
    return img

def paste_rotated(base, card, cx, cy, angle):
    # soft drop shadow
    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([0, 0, card.size[0]-1, card.size[1]-1],
                         radius=int(card.size[0]*0.12), fill=(20, 10, 40, 130))
    shadow = shadow.rotate(angle, expand=True, resample=Image.BICUBIC)
    shadow = shadow.filter(ImageFilter.GaussianBlur(W*0.012))
    base.alpha_composite(shadow, (int(cx - shadow.size[0]/2),
                                  int(cy - shadow.size[1]/2 + W*0.012)))
    rot = card.rotate(angle, expand=True, resample=Image.BICUBIC)
    base.alpha_composite(rot, (int(cx - rot.size[0]/2), int(cy - rot.size[1]/2)))

canvas = bg.convert("RGBA")

cw, ch = int(W*0.40), int(W*0.55)
radius = int(cw*0.14)

# back card (lavender-tinted white), tilted right
back = rounded_card(cw, ch, radius, (236, 232, 255, 255))
paste_rotated(canvas, back, W*0.50 + W*0.045, W*0.50, -11)

# front card (white), tilted left, with ledger rows
front = rounded_card(cw, ch, radius, (255, 255, 255, 255))
fd = ImageDraw.Draw(front)
bar_x = int(cw*0.16)
bar_w = [int(cw*0.68), int(cw*0.68), int(cw*0.46)]
bar_y = int(ch*0.30)
for i, bw in enumerate(bar_w):
    y = bar_y + i*int(ch*0.13)
    fd.rounded_rectangle([bar_x, y, bar_x+bw, y+int(ch*0.055)],
                         radius=int(ch*0.028), fill=(0x4F, 0x46, 0xE5, 255))
# top accent bar (indigo, bolder)
fd.rounded_rectangle([bar_x, int(ch*0.16), bar_x+int(cw*0.34), int(ch*0.16)+int(ch*0.075)],
                     radius=int(ch*0.03), fill=(0x7C, 0x3A, 0xED, 255))
paste_rotated(canvas, front, W*0.50 - W*0.03, W*0.50, 8)

# gold coin badge (value) overlapping bottom-right
coin_d = int(W*0.20)
coin = Image.new("RGBA", (coin_d, coin_d), (0, 0, 0, 0))
cd = ImageDraw.Draw(coin)
cd.ellipse([0, 0, coin_d-1, coin_d-1], fill=(0xF5, 0xC2, 0x42, 255),
           outline=(0xB8, 0x86, 0x0B, 255), width=int(coin_d*0.05))
cd.ellipse([int(coin_d*0.12)]*2 + [int(coin_d*0.88)]*2, outline=(0xFF, 0xE3, 0x8A, 255), width=int(coin_d*0.03))
# pound sign drawn as strokes
lw = int(coin_d*0.07)
cx0, cy0 = coin_d*0.5, coin_d*0.5
cd.arc([int(coin_d*0.34), int(coin_d*0.20), int(coin_d*0.72), int(coin_d*0.52)], 70, 300, fill=(0x6b,0x4f,0x05,255), width=lw)
cd.line([int(coin_d*0.40), int(coin_d*0.36), int(coin_d*0.40), int(coin_d*0.72)], fill=(0x6b,0x4f,0x05,255), width=lw)
cd.line([int(coin_d*0.30), int(coin_d*0.72), int(coin_d*0.70), int(coin_d*0.72)], fill=(0x6b,0x4f,0x05,255), width=lw)
cd.line([int(coin_d*0.32), int(coin_d*0.54), int(coin_d*0.58), int(coin_d*0.54)], fill=(0x6b,0x4f,0x05,255), width=lw)
sh = Image.new("RGBA", coin.size, (0,0,0,0))
ImageDraw.Draw(sh).ellipse([0,0,coin_d-1,coin_d-1], fill=(20,10,40,120))
sh = sh.filter(ImageFilter.GaussianBlur(W*0.01))
canvas.alpha_composite(sh, (int(W*0.62 - coin_d/2), int(W*0.70 - coin_d/2 + W*0.01)))
canvas.alpha_composite(coin, (int(W*0.62 - coin_d/2), int(W*0.70 - coin_d/2)))

# downsample, flatten to RGB (no alpha) for App Store
final = canvas.convert("RGB").resize((S, S), Image.LANCZOS)
out = os.path.join(os.path.dirname(__file__), "..",
                   "CardLedger/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
final.save(out, "PNG")
print("wrote", os.path.normpath(out), final.size, final.mode)
