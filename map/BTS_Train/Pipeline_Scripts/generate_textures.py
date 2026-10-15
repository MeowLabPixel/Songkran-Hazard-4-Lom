import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageChops

TEX_DIR = r"d:\3D Stuff\GAMEJAM 2026\SONGRANG\BTS Train"
os.makedirs(TEX_DIR, exist_ok=True)

SIZE = 2048

# -------------------------------------------------------------------------
# AUTHENTIC BANGKOK BTS SKYTRAIN PALETTE (MATCHING USER REFERENCE IMAGES)
# -------------------------------------------------------------------------
BODY_WHITE    = (244, 246, 250, 255)  # Clean bright off-white / light silver
WHITE_SHADOW  = (220, 224, 230, 255)  # Soft panel shading
ROYAL_BLUE    = (13, 47, 129, 255)    # #0D2F81 Authentic BTS Deep Royal Blue
ROYAL_BLUE_LT = (22, 70, 175, 255)    # Highlight for blue panel edges
SKIRT_NAVY    = (9, 29, 78, 255)      # #091D4E Shadow navy for lower skirt
CRIMSON_RED   = (216, 30, 40, 255)    # #D81E28 Vibrant saturated BTS red
CRIMSON_DARK  = (175, 20, 28, 255)    # Bevel shadow for red stripe
GOLD_AMBER    = (255, 160, 16, 255)   # #FFA010 Glowing amber LED text
LED_BG        = (18, 20, 24, 255)     # Dark LED bezel/housing
DARK_FRAME    = (26, 30, 38, 255)     # Rubber window seal & dark trim
BLACK_VISOR   = (20, 23, 29, 255)     # Front gloss black nose visor
GLASS_TINT    = (30, 42, 58, 255)     # Sleek tinted glass with subtle blue tone
GLASS_SPEC    = (50, 68, 92, 255)     # Glass reflection highlight
THRESHOLD_YEL = (230, 168, 23, 255)   # #E6A817 Yellow door caution line
CREAM_BASE    = BODY_WHITE            # Bulkhead end walls

base_img = Image.new("RGBA", (SIZE, SIZE), BODY_WHITE)
orm_img = Image.new("RGBA", (SIZE, SIZE), (255, 128, 0, 255))
draw_base = ImageDraw.Draw(base_img)
draw_orm = ImageDraw.Draw(orm_img)

def paint_rect(x1, y1, x2, y2, base_col, roughness=128, metallic=0, ao=255):
    draw_base.rectangle([x1, y1, x2, y2], fill=base_col)
    draw_orm.rectangle([x1, y1, x2, y2], fill=(ao, roughness, metallic, 255))

def paint_line(x1, y1, x2, y2, base_col, width=1, roughness=128, metallic=0, ao=255):
    draw_base.line([x1, y1, x2, y2], fill=base_col, width=width)
    draw_orm.line([x1, y1, x2, y2], fill=(ao, roughness, metallic, 255), width=width)

def paint_poly(points, base_col, roughness=128, metallic=0, ao=255):
    draw_base.polygon(points, fill=base_col)
    draw_orm.polygon(points, fill=(ao, roughness, metallic, 255))

# =========================================================================
# TOP HALF: AUTHENTIC BANGKOK BTS SKYTRAIN HULL (y: 0 .. 1024)
# =========================================================================

# 1. Base White Upper Cantrail & Roof (y: 0 .. 160)
paint_rect(0, 0, SIZE, 160, BODY_WHITE, roughness=90, metallic=40)
paint_rect(0, 0, SIZE, 70, (235, 238, 244, 255), roughness=100, metallic=40, ao=240)
paint_line(0, 70, SIZE, 70, (215, 219, 226, 255), width=2, roughness=120, metallic=30, ao=210)

# 2. Continuous Top Red Stripe across the passenger side wall (y: 135 .. 165)
paint_rect(0, 135, 1200, 165, CRIMSON_RED, roughness=60, metallic=30)
paint_line(0, 135, 1200, 135, CRIMSON_DARK, width=2, roughness=70, metallic=20)
paint_line(0, 165, 1200, 165, CRIMSON_DARK, width=2, roughness=70, metallic=20)

# 3. Window Band (y: 165 .. 490) - Tinted glass & white pillars
paint_rect(0, 165, 1200, 490, BODY_WHITE, roughness=90, metallic=40)

# 4. SOLID ROYAL BLUE LOWER BODY (y: 490 .. 860) across entire passenger side!
paint_rect(0, 490, 1200, 860, ROYAL_BLUE, roughness=55, metallic=35)
# Subtle horizontal fluting / reflection lines in the deep blue gloss finish
paint_line(0, 580, 1200, 580, ROYAL_BLUE_LT, width=2, roughness=50, metallic=40)
paint_line(0, 670, 1200, 670, (8, 32, 92, 255), width=2, roughness=60, metallic=30)
paint_line(0, 760, 1200, 760, ROYAL_BLUE_LT, width=2, roughness=50, metallic=40)

# 5. Skirt (y: 860 .. 1024) - Deep shadow navy with panel seams
paint_rect(0, 860, 1200, 1024, SKIRT_NAVY, roughness=120, metallic=60, ao=200)
for hx in range(30, 1200 - 40, 150):
    paint_rect(hx, 885, hx + 90, 975, (7, 23, 62, 255), roughness=140, metallic=50, ao=180)
    draw_base.rectangle([hx, 885, hx + 90, 975], outline=(5, 16, 46, 255), width=2)


# -------------------------------------------------------------------------
# SECTION 1A: SIDE PASSENGER WALL (x: 0 .. 1200) [U: 0.00 .. 0.585]
# -------------------------------------------------------------------------
door_xs = [60, 380, 700, 1000]
door_w = 120
door_top = 165
door_bot = 840

win_ranges = [
    (door_xs[0] + door_w + 18, door_xs[1] - 18),
    (door_xs[1] + door_w + 18, door_xs[2] - 18),
    (door_xs[2] + door_w + 18, door_xs[3] - 18)
]

try:
    font_led = ImageFont.truetype("arial.ttf", 20)
    font_sub = ImageFont.truetype("arial.ttf", 16)
    font_num = ImageFont.truetype("arial.ttf", 34)
    font_head = ImageFont.truetype("arial.ttf", 26)
except Exception:
    font_led = None
    font_sub = None
    font_num = None
    font_head = None

# Windows with frames (clean, sleek tinted glass)
for wx1, wx2 in win_ranges:
    paint_rect(wx1 - 5, 175, wx2 + 5, 475, DARK_FRAME, roughness=60, metallic=30, ao=230)
    paint_rect(wx1, 180, wx2, 470, GLASS_TINT, roughness=15, metallic=20, ao=255)
    # Glass subtle specular reflection
    paint_line(wx1 + 15, 195, wx2 - 40, 195, GLASS_SPEC, width=3, roughness=10, metallic=40)
    mid_x = (wx1 + wx2) // 2
    paint_line(mid_x, 180, mid_x, 470, (20, 24, 30, 255), width=6, roughness=100, metallic=40)
    draw_base.rectangle([wx1, 180, wx2, 470], outline=(16, 20, 26, 255), width=4)

# Passenger Doors (Blue Lower Half, White Upper Half, Large Windows)
for dx in door_xs:
    paint_rect(dx - 4, door_top - 4, dx + door_w + 4, door_bot + 4, DARK_FRAME, roughness=100, metallic=30, ao=190)
    # Upper door body (White)
    paint_rect(dx, door_top, dx + door_w, 490, BODY_WHITE, roughness=70, metallic=40)
    # Lower door body (Solid Deep Royal Blue matching the body!)
    paint_rect(dx, 490, dx + door_w, door_bot, ROYAL_BLUE, roughness=55, metallic=35)
    
    # Door Windows (two panels)
    leaf_w = door_w // 2
    for lx1, lx2 in [(dx + 8, dx + leaf_w - 6), (dx + leaf_w + 6, dx + door_w - 8)]:
        paint_rect(lx1 - 3, 200, lx2 + 3, 450, DARK_FRAME, roughness=60, metallic=30)
        paint_rect(lx1, 205, lx2, 445, GLASS_TINT, roughness=15, metallic=20)
        draw_base.rectangle([lx1, 205, lx2, 445], outline=(16, 20, 26, 255), width=2)
    
    # Center door leaf rubber split
    paint_line(dx + leaf_w, door_top, dx + leaf_w, door_bot, (16, 18, 22, 255), width=4, roughness=180, metallic=10)
    # Bottom threshold yellow warning line
    paint_rect(dx, door_bot - 14, dx + door_w, door_bot, THRESHOLD_YEL, roughness=90, metallic=20)


# -------------------------------------------------------------------------
# SECTION 1B: CAB CHEEK & THE ICONIC DYNAMIC SWOOP (x: 1200 .. 1650) [U: 0.585 .. 0.805]
# Focus purely on the bold colors & stripes (no unit numbers or cluttered text)
# -------------------------------------------------------------------------
paint_rect(1200, 0, 1650, 1024, BODY_WHITE, roughness=90, metallic=40)
paint_rect(1200, 0, 1650, 70, (235, 238, 244, 255), roughness=100, metallic=40, ao=240)
paint_line(1200, 70, 1650, 70, (215, 219, 226, 255), width=2, roughness=120, metallic=30, ao=210)

# 1. Lower Body Deep Royal Blue with diagonal swoop contour
blue_pts = [(1200, 490), (1250, 490)]
for i in range(1, 31):
    t = i / 30.0
    s = t ** 1.35
    x = 1250 + 400 * t
    y_b = 490 + (770 - 490) * s
    blue_pts.append((int(x), int(y_b)))
blue_poly = blue_pts + [(1650, 860), (1200, 860)]
paint_poly(blue_poly, ROYAL_BLUE, roughness=55, metallic=35)
# Outline along actual perimeter (smooth, no straight chords across whitespace!)
for i in range(len(blue_pts) - 1):
    paint_line(blue_pts[i][0], blue_pts[i][1], blue_pts[i+1][0], blue_pts[i+1][1], ROYAL_BLUE_LT, width=2, roughness=50, metallic=40)

# Skirt below y=860
paint_rect(1200, 860, 1650, 1024, SKIRT_NAVY, roughness=120, metallic=60, ao=200)
for hx in [1260, 1420, 1560]:
    paint_rect(hx, 885, hx + 90, 975, (7, 23, 62, 255), roughness=140, metallic=50, ao=180)
    draw_base.rectangle([hx, 885, hx + 90, 975], outline=(5, 16, 46, 255), width=2)

# 2. Mathematically Smooth Dynamic Crimson Red Swoop (constant 34px thickness)
# Perfectly outlines with ZERO stray chord lines!
red_top = [(1200, 135), (1215, 135)]
red_bot = [(1200, 169), (1215, 169)]
stripe_thick = 34
for i in range(1, 31):
    t = i / 30.0
    s = t ** 1.35
    x = 1215 + 435 * t
    y_t = 135 + (695 - 135) * s
    red_top.append((int(x), int(y_t)))
    red_bot.append((int(x), int(y_t + stripe_thick)))

red_poly = red_top + list(reversed(red_bot))
paint_poly(red_poly, CRIMSON_RED, roughness=60, metallic=30)
# Perimeter dark bevels (point-by-point along curve to prevent any chord cuts)
for i in range(len(red_top) - 1):
    paint_line(red_top[i][0], red_top[i][1], red_top[i+1][0], red_top[i+1][1], CRIMSON_DARK, width=2, roughness=70, metallic=20)
for i in range(len(red_bot) - 1):
    paint_line(red_bot[i][0], red_bot[i][1], red_bot[i+1][0], red_bot[i+1][1], CRIMSON_DARK, width=2, roughness=70, metallic=20)

# 3. Cab Side Window (Drivers cab side glass, positioned forward near front nose)
# Clean, spacious trapezoid matching cab rake - zero collision with swoop!
cw_frame = [(1536, 176), (1644, 176), (1644, 439), (1511, 439)]
paint_poly(cw_frame, DARK_FRAME, roughness=60, metallic=30, ao=210)

cw_glass = [(1540, 180), (1640, 180), (1640, 435), (1515, 435)]
paint_poly(cw_glass, GLASS_TINT, roughness=15, metallic=20)
draw_base.polygon(cw_glass, outline=(16, 20, 26, 255), width=2)

# Driver window vertical pillar split
paint_line(1590, 180, 1575, 435, (20, 24, 30, 255), width=4, roughness=100, metallic=40)
# Subtle glass specular reflection line
paint_line(1550, 200, 1630, 200, GLASS_SPEC, width=3, roughness=10, metallic=40)


# -------------------------------------------------------------------------
# SECTION 1C: FRONT NOSE & FACE (x: 1650 .. 2048) [U: 0.805 .. 1.00]
# -------------------------------------------------------------------------
fn_x1, fn_x2 = 1650, 2048
fn_cx = 1849  # Exact center of front face

# 1. Background Fill
paint_rect(fn_x1, 0, fn_x2, 160, BODY_WHITE, roughness=90, metallic=40)

# Red accent cradle on lower chin (connecting seamlessly to cheek swoop at y=695..729)
paint_rect(fn_x1, 695, fn_x2, 730, CRIMSON_RED, roughness=60, metallic=30)
paint_line(fn_x1, 695, fn_x2, 695, CRIMSON_DARK, width=2)
paint_line(fn_x1, 730, fn_x2, 730, CRIMSON_DARK, width=2)

# White separator bar below red (connecting seamlessly to cheek white at y=730..770)
paint_rect(fn_x1, 730, fn_x2, 770, BODY_WHITE, roughness=80, metallic=40)
# Royal blue lower chin / cowcatcher (connecting seamlessly to cheek blue at y=770..860)
paint_rect(fn_x1, 770, fn_x2, 860, ROYAL_BLUE, roughness=55, metallic=35)
# Navy skirt at bottom
paint_rect(fn_x1, 860, fn_x2, 1024, SKIRT_NAVY, roughness=120, metallic=60, ao=200)

# 2. Central Gloss Black Visor & Emergency Exit Door
vx1 = 1678
vx2 = 2020
vy1 = 20
vy2 = 690

paint_rect(vx1 - 5, vy1 - 4, vx2 + 5, vy2 + 4, (12, 14, 18, 255), roughness=40, metallic=60)
paint_rect(vx1, vy1, vx2, vy2, (16, 18, 24, 255), roughness=25, metallic=50)

# Destination Marquee Display at top (matching photo: "008 SAMRONG" in glowing amber)
mq_w = 240
mq_x1 = fn_cx - mq_w // 2
mq_x2 = fn_cx + mq_w // 2
paint_rect(mq_x1, 65, mq_x2, 145, (8, 10, 14, 255), roughness=60, metallic=30, ao=220)
draw_base.rectangle([mq_x1, 65, mq_x2, 145], outline=(32, 38, 48, 255), width=3)
paint_rect(mq_x1 + 6, 72, mq_x2 - 6, 138, (22, 14, 4, 255), roughness=40, metallic=20)

txt_dest = "008  SAMRONG"
if font_head:
    for dx, dy in [(-2,0),(2,0),(0,-2),(0,2),(-1,-1),(1,1),(-1,1),(1,-1)]:
        draw_base.text((fn_cx - 84 + dx, 92 + dy), txt_dest, font=font_head, fill=(160, 65, 0, 255))
    for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
        draw_base.text((fn_cx - 84 + dx, 92 + dy), txt_dest, font=font_head, fill=(230, 115, 0, 255))
    draw_base.text((fn_cx - 84, 92), txt_dest, font=font_head, fill=(255, 215, 60, 255))
else:
    paint_rect(fn_cx - 80, 85, fn_cx + 80, 125, GOLD_AMBER, roughness=15, metallic=10)

# Center Column (Emergency Egress Door, authentic to BTS EMU-B3 reference)
cd_w = 64
cd_x1 = fn_cx - cd_w // 2
cd_x2 = fn_cx + cd_w // 2
paint_rect(cd_x1, 150, cd_x2, vy2, (18, 21, 28, 255), roughness=30, metallic=45)
paint_line(cd_x1, 150, cd_x1, vy2, (10, 12, 16, 255), width=3)
paint_line(cd_x2, 150, cd_x2, vy2, (10, 12, 16, 255), width=3)
paint_line(fn_cx, 155, fn_cx, vy2 - 10, (28, 34, 46, 255), width=2)
paint_rect(fn_cx - 4, 440, fn_cx + 4, 475, (45, 54, 68, 255), roughness=50, metallic=80)

# 3. Dual Opaque Windshields with Retro Stylized Glass Shine (Songkran Hazard aesthetic!)
win_top = 168
win_bot = 488
win_h = win_bot - win_top

lw_out_top = vx1 + 10  # 1688
lw_in_top  = cd_x1 - 6 # 1811
lw_out_bot = vx1 + 18  # 1696
lw_in_bot  = cd_x1 - 6 # 1811

rw_in_top  = cd_x2 + 6 # 1887
rw_out_top = vx2 - 10  # 2010
rw_in_bot  = cd_x2 + 6 # 1887
rw_out_bot = vx2 - 18  # 2002

paint_poly([(lw_out_top-4, win_top-4), (lw_in_top+4, win_top-4), (lw_in_bot+4, win_bot+4), (lw_out_bot-4, win_bot+4)], (10, 12, 16, 255), roughness=70, metallic=40)
paint_poly([(rw_in_top-4, win_top-4), (rw_out_top+4, win_top-4), (rw_out_bot+4, win_bot+4), (rw_in_bot-4, win_bot+4)], (10, 12, 16, 255), roughness=70, metallic=40)

# Paint Opaque Styled Glass with Sky Shine Band
GLASS_BASE = (26, 36, 50, 255)
GLASS_MID  = (38, 52, 72, 255)
GLASS_SHINE = (140, 175, 215, 255)

for is_left, x_ot, x_it, x_ib, x_ob in [(True, lw_out_top, lw_in_top, lw_in_bot, lw_out_bot),
                                       (False, rw_in_top, rw_out_top, rw_out_bot, rw_in_bot)]:
    for y in range(win_top, win_bot):
        ty = (y - win_top) / float(win_h)
        if is_left:
            xl = int(x_ot + (x_ob - x_ot) * ty)
            xr = int(x_it + (x_ib - x_it) * ty)
        else:
            xl = int(x_it + (x_ib - x_it) * ty)
            xr = int(x_ot + (x_ob - x_ot) * ty)
            
        base_factor = math.sin(ty * math.pi)
        r = int(GLASS_BASE[0] + (GLASS_MID[0] - GLASS_BASE[0]) * base_factor)
        g = int(GLASS_BASE[1] + (GLASS_MID[1] - GLASS_BASE[1]) * base_factor)
        b = int(GLASS_BASE[2] + (GLASS_MID[2] - GLASS_BASE[2]) * base_factor)
        
        # Horizon sky shine reflection band across upper-mid glass
        if 0.30 <= ty <= 0.52:
            st = 1.0 - abs(ty - 0.40) / 0.11
            r = int(r * (1.0 - 0.65 * st) + GLASS_SHINE[0] * (0.65 * st))
            g = int(g * (1.0 - 0.65 * st) + GLASS_SHINE[1] * (0.65 * st))
            b = int(b * (1.0 - 0.65 * st) + GLASS_SHINE[2] * (0.65 * st))
            
        # Top sun visor band
        if ty < 0.16:
            st = (0.16 - ty) / 0.16
            r = int(r * (1.0 - 0.6 * st) + 14 * (0.6 * st))
            g = int(g * (1.0 - 0.6 * st) + 16 * (0.6 * st))
            b = int(b * (1.0 - 0.6 * st) + 24 * (0.6 * st))
            
        paint_line(xl, y, xr, y, (r, g, b, 255), roughness=15, metallic=30)

# Crisp Specular Reflections (Strictly clipped to window glass mask so shine NEVER goes past window)
glass_mask = Image.new("L", (SIZE, SIZE), 0)
m_draw = ImageDraw.Draw(glass_mask)
m_draw.polygon([(lw_out_top + 2, win_top + 2), (lw_in_top - 2, win_top + 2), 
                (lw_in_bot - 2, win_bot - 2), (lw_out_bot + 2, win_bot - 2)], fill=255)
m_draw.polygon([(rw_in_top + 2, win_top + 2), (rw_out_top - 2, win_top + 2), 
                (rw_out_bot - 2, win_bot - 2), (rw_in_bot + 2, win_bot - 2)], fill=255)

spec_overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sp_draw = ImageDraw.Draw(spec_overlay)

# Left Window: Dynamic diagonal shine stripes (slanted parallel to horizon light)
sp_draw.polygon([(lw_out_top + 10, win_top - 10), (lw_out_top + 38, win_top - 10),
                 (lw_out_top + 38 + 55, win_bot + 10), (lw_out_top + 10 + 55, win_bot + 10)], fill=(255, 255, 255, 55))
sp_draw.polygon([(lw_out_top + 48, win_top - 10), (lw_out_top + 66, win_top - 10),
                 (lw_out_top + 66 + 55, win_bot + 10), (lw_out_top + 48 + 55, win_bot + 10)], fill=(255, 255, 255, 32))

# Right Window: Matching parallel diagonal shine stripes across right pane
sp_draw.polygon([(rw_in_top + 10, win_top - 10), (rw_in_top + 38, win_top - 10),
                 (rw_in_top + 38 + 55, win_bot + 10), (rw_in_top + 10 + 55, win_bot + 10)], fill=(255, 255, 255, 55))
sp_draw.polygon([(rw_in_top + 48, win_top - 10), (rw_in_top + 66, win_top - 10),
                 (rw_in_top + 66 + 55, win_bot + 10), (rw_in_top + 48 + 55, win_bot + 10)], fill=(255, 255, 255, 32))

# Sharp white horizon reflection line across each pane
y_h = int(win_top + win_h * 0.40)
sp_draw.line([(lw_out_top, y_h), (lw_in_top, y_h)], fill=(255, 255, 255, 110), width=3)
sp_draw.line([(lw_out_top, y_h + 2), (lw_in_top, y_h + 2)], fill=(220, 240, 255, 60), width=2)

sp_draw.line([(rw_in_top, y_h), (rw_out_top, y_h)], fill=(255, 255, 255, 110), width=3)
sp_draw.line([(rw_in_top, y_h + 2), (rw_out_top, y_h + 2)], fill=(220, 240, 255, 60), width=2)

# Strictly multiply alpha channel by glass_mask so NO pixels outside the glass can ever receive shine
r_ch, g_ch, b_ch, a_ch = spec_overlay.split()
final_a = ImageChops.multiply(a_ch, glass_mask)
spec_overlay.putalpha(final_a)

base_img = Image.alpha_composite(base_img, spec_overlay)
draw_base = ImageDraw.Draw(base_img)

# Frit borders
draw_base.polygon([(lw_out_top, win_top), (lw_in_top, win_top), (lw_in_bot, win_bot), (lw_out_bot, win_bot)], outline=(12, 14, 18, 255), width=4)
draw_base.polygon([(rw_in_top, win_top), (rw_out_top, win_top), (rw_out_bot, win_bot), (rw_in_bot, win_bot)], outline=(12, 14, 18, 255), width=4)

# Dual Mechanical Windshield Wipers
paint_line(cd_x1 - 2, win_bot - 8, cd_x1 - 22, win_top + 45, (10, 12, 16, 255), width=5, roughness=80, metallic=60)
paint_line(cd_x1 - 2, win_bot - 8, cd_x1 - 22, win_top + 45, (90, 100, 115, 255), width=2, roughness=50, metallic=80)
paint_line(cd_x1 - 22, win_top + 40, cd_x1 - 28, win_top + 230, (20, 24, 30, 255), width=4, roughness=90, metallic=40)
paint_rect(cd_x1 - 6, win_bot - 12, cd_x1 + 2, win_bot - 2, (32, 38, 48, 255), roughness=70, metallic=60)

paint_line(cd_x2 + 2, win_bot - 8, cd_x2 + 22, win_top + 45, (10, 12, 16, 255), width=5, roughness=80, metallic=60)
paint_line(cd_x2 + 2, win_bot - 8, cd_x2 + 22, win_top + 45, (90, 100, 115, 255), width=2, roughness=50, metallic=80)
paint_line(cd_x2 + 22, win_top + 40, cd_x2 + 28, win_top + 230, (20, 24, 30, 255), width=4, roughness=90, metallic=40)
paint_rect(cd_x2 - 2, win_bot - 12, cd_x2 + 6, win_bot - 2, (32, 38, 48, 255), roughness=70, metallic=60)

# 4. ICONIC BOOMERANG LED ACCENTS (DAYTIME RUNNING LIGHTS) FROM REFERENCE!
drl_l_outer = [(lw_out_bot - 6, win_bot + 16), (lw_out_bot + 28, win_bot + 48), (cd_x1 - 4, win_bot + 48),
               (cd_x1 - 4, win_bot + 60), (lw_out_bot + 24, win_bot + 60), (lw_out_bot - 8, win_bot + 24)]
paint_poly(drl_l_outer, (26, 30, 40, 255), roughness=60, metallic=40)
drl_l_core = [(lw_out_bot - 4, win_bot + 18), (lw_out_bot + 26, win_bot + 52), (cd_x1 - 6, win_bot + 52),
              (cd_x1 - 6, win_bot + 56), (lw_out_bot + 24, win_bot + 56), (lw_out_bot - 6, win_bot + 22)]
paint_poly(drl_l_core, (255, 255, 255, 255), roughness=10, metallic=10)
paint_line(lw_out_bot - 4, win_bot + 18, lw_out_bot + 26, win_bot + 52, (225, 245, 255, 255), width=3, roughness=10, metallic=10)
paint_line(lw_out_bot + 26, win_bot + 52, cd_x1 - 6, win_bot + 52, (225, 245, 255, 255), width=3, roughness=10, metallic=10)
paint_line(lw_out_bot - 2, win_bot + 27, lw_out_bot + 26, win_bot + 63, CRIMSON_RED, width=3, roughness=50, metallic=30)
paint_line(lw_out_bot + 26, win_bot + 63, cd_x1 - 4, win_bot + 63, CRIMSON_RED, width=3, roughness=50, metallic=30)

drl_r_outer = [(rw_out_bot + 6, win_bot + 16), (rw_out_bot - 28, win_bot + 48), (cd_x2 + 4, win_bot + 48),
               (cd_x2 + 4, win_bot + 60), (rw_out_bot - 24, win_bot + 60), (rw_out_bot + 8, win_bot + 24)]
paint_poly(drl_r_outer, (26, 30, 40, 255), roughness=60, metallic=40)
drl_r_core = [(rw_out_bot + 4, win_bot + 18), (rw_out_bot - 26, win_bot + 52), (cd_x2 + 6, win_bot + 52),
              (cd_x2 + 6, win_bot + 56), (rw_out_bot - 24, win_bot + 56), (rw_out_bot + 6, win_bot + 22)]
paint_poly(drl_r_core, (255, 255, 255, 255), roughness=10, metallic=10)
paint_line(rw_out_bot + 4, win_bot + 18, rw_out_bot - 26, win_bot + 52, (225, 245, 255, 255), width=3, roughness=10, metallic=10)
paint_line(rw_out_bot - 26, win_bot + 52, cd_x2 + 6, win_bot + 52, (225, 245, 255, 255), width=3, roughness=10, metallic=10)
paint_line(rw_out_bot + 2, win_bot + 27, rw_out_bot - 26, win_bot + 63, CRIMSON_RED, width=3, roughness=50, metallic=30)
paint_line(rw_out_bot - 26, win_bot + 63, cd_x2 + 4, win_bot + 63, CRIMSON_RED, width=3, roughness=50, metallic=30)

# 5. Modern Stylized LED Headlights (Symmetrical on both sides, 100% inside fn_x1..fn_x2)
hl_w = 64
hl_h = 42
hl_y = 693
hx_left = 1656
hx_right = fn_x2 - hl_w - 6

# Left Headlight Cluster
paint_rect(hx_left - 2, hl_y - 2, hx_left + hl_w + 2, hl_y + hl_h + 2, DARK_FRAME, roughness=70, metallic=50)
paint_rect(hx_left, hl_y, hx_left + hl_w - 22, hl_y + hl_h, (255, 248, 225, 255), roughness=10, metallic=10)
draw_orm.rectangle([hx_left, hl_y, hx_left + hl_w - 22, hl_y + hl_h], fill=(255, 10, 10, 255))
paint_rect(hx_left + hl_w - 20, hl_y, hx_left + hl_w, hl_y + hl_h, (230, 25, 35, 255), roughness=15, metallic=15)
draw_base.rectangle([hx_left, hl_y, hx_left + hl_w, hl_y + hl_h], outline=(18, 22, 28, 255), width=2)
paint_line(hx_left + hl_w - 21, hl_y, hx_left + hl_w - 21, hl_y + hl_h, (18, 22, 28, 255), width=2)

# Right Headlight Cluster (Mirrored!)
paint_rect(hx_right - 2, hl_y - 2, hx_right + hl_w + 2, hl_y + hl_h + 2, DARK_FRAME, roughness=70, metallic=50)
paint_rect(hx_right, hl_y, hx_right + 20, hl_y + hl_h, (230, 25, 35, 255), roughness=15, metallic=15)
paint_rect(hx_right + 22, hl_y, hx_right + hl_w, hl_y + hl_h, (255, 248, 225, 255), roughness=10, metallic=10)
draw_orm.rectangle([hx_right + 22, hl_y, hx_right + hl_w, hl_y + hl_h], fill=(255, 10, 10, 255))
draw_base.rectangle([hx_right, hl_y, hx_right + hl_w, hl_y + hl_h], outline=(18, 22, 28, 255), width=2)
paint_line(hx_right + 21, hl_y, hx_right + 21, hl_y + hl_h, (18, 22, 28, 255), width=2)



# =========================================================================
# BOTTOM HALF: ROOF, HVAC, BULKHEAD, UNDERSIDE, WHEELS, BOGIE (y: 1024 .. 2048)
# Distinct, non-overlapping UV regions for 100% clean rendering!
# =========================================================================

# ZONE A1: Clean Corrugated Roof (x: 0 .. 600, y: 1024 .. 2048) [U: 0.010..0.280, V: 0.010..0.495]
paint_rect(0, 1024, 600, 2048, (216, 220, 226, 255), roughness=130, metallic=120)
for rx in range(20, 590, 24):
    paint_line(rx, 1024, rx, 2048, (175, 180, 188, 255), width=3, roughness=150, metallic=100, ao=210)
    paint_line(rx + 2, 1024, rx + 2, 2048, (242, 245, 250, 255), width=2, roughness=110, metallic=140, ao=255)

# ZONE A2: HVAC TOP FACE FANS (x: 610 .. 1020, y: 1030 .. 1520) [U: 0.300..0.495, V: 0.260..0.495]
ht_x1, ht_y1, ht_x2, ht_y2 = 610, 1030, 1020, 1520
paint_rect(ht_x1, ht_y1, ht_x2, ht_y2, (185, 190, 198, 255), roughness=120, metallic=100, ao=210)
draw_base.rectangle([ht_x1, ht_y1, ht_x2, ht_y2], outline=(130, 135, 145, 255), width=5)
for gy in range(ht_y1 + 20, ht_y1 + 120, 14):
    paint_line(ht_x1 + 25, gy, ht_x2 - 25, gy, (55, 60, 68, 255), width=5, roughness=190, metallic=40, ao=160)

fan_r = 75
for fcx, fcy in [(ht_x1 + 105, ht_y1 + 280), (ht_x2 - 105, ht_y1 + 280)]:
    draw_base.ellipse([fcx - fan_r, fcy - fan_r, fcx + fan_r, fcy + fan_r], fill=(38, 42, 48, 255), outline=(100, 105, 115, 255), width=5)
    draw_orm.ellipse([fcx - fan_r, fcy - fan_r, fcx + fan_r, fcy + fan_r], fill=(180, 160, 80, 255))
    draw_base.ellipse([fcx - 20, fcy - 20, fcx + 20, fcy + 20], fill=(140, 145, 155, 255))
    for ang in range(0, 360, 45):
        rad = math.radians(ang)
        bx = fcx + int(math.cos(rad) * (fan_r - 8))
        by = fcy + int(math.sin(rad) * (fan_r - 8))
        paint_line(fcx, fcy, bx, by, (75, 80, 90, 255), width=5, roughness=140, metallic=120)

# ZONE A3: HVAC SIDE/END LOUVERS (x: 610 .. 1020, y: 1530 .. 1750) [U: 0.300..0.495, V: 0.145..0.252]
hs_x1, hs_y1, hs_x2, hs_y2 = 610, 1530, 1020, 1750
paint_rect(hs_x1, hs_y1, hs_x2, hs_y2, (180, 185, 192, 255), roughness=130, metallic=110, ao=200)
draw_base.rectangle([hs_x1, hs_y1, hs_x2, hs_y2], outline=(120, 125, 135, 255), width=3)
for ly in range(hs_y1 + 14, hs_y2 - 14, 12):
    paint_line(hs_x1 + 15, ly, hs_x2 - 15, ly, (48, 52, 58, 255), width=4, roughness=200, metallic=40, ao=160)

# ZONE A4: GANGWAY BELLOWS (x: 610 .. 1020, y: 1760 .. 2040) [U: 0.300..0.495, V: 0.005..0.138]
gw_x1, gw_y1, gw_x2, gw_y2 = 610, 1760, 1020, 2040
paint_rect(gw_x1, gw_y1, gw_x2, gw_y2, (38, 42, 46, 255), roughness=210, metallic=20, ao=220)
for py in range(gw_y1 + 8, gw_y2 - 8, 16):
    paint_line(gw_x1, py, gw_x2, py, (20, 22, 25, 255), width=5, roughness=230, metallic=10, ao=140)
    paint_line(gw_x1, py + 2, gw_x2, py + 2, (58, 63, 70, 255), width=2, roughness=190, metallic=20, ao=255)

# ZONE B: END BULKHEAD / GANGWAY WALL (x: 1030 .. 1280, y: 1030 .. 2040) [U: 0.505..0.625, V: 0.005..0.495]
bk_x1, bk_y1, bk_x2, bk_y2 = 1030, 1030, 1280, 2040
paint_rect(bk_x1, bk_y1, bk_x2, bk_y2, CREAM_BASE, roughness=90, metallic=40)
# End wall cantrail & fluting
paint_line(bk_x1, bk_y1 + 60, bk_x2, bk_y1 + 60, (210, 205, 195, 255), width=3)
# Gangway doorway opening & rubber seal trim
dw_x1, dw_x2 = bk_x1 + 35, bk_x2 - 35
dw_y1, dw_y2 = bk_y1 + 180, bk_y2 - 60
paint_rect(dw_x1 - 6, dw_y1 - 6, dw_x2 + 6, dw_y2 + 6, DARK_FRAME, roughness=150, metallic=40)
paint_rect(dw_x1, dw_y1, dw_x2, dw_y2, (32, 36, 42, 255), roughness=180, metallic=30)
# Threshold caution bar at bottom
paint_rect(dw_x1, dw_y2 - 16, dw_x2, dw_y2, GOLD_AMBER, roughness=100, metallic=20)
# Panel seams on sides
paint_line(bk_x1 + 18, bk_y1, bk_x1 + 18, bk_y2, (215, 210, 200, 255), width=2)
paint_line(bk_x2 - 18, bk_y1, bk_x2 - 18, bk_y2, (215, 210, 200, 255), width=2)

# ZONE C: UNDERSIDE FLOOR PLATE (x: 1290 .. 1600, y: 1030 .. 2040) [U: 0.630..0.780, V: 0.005..0.495]
uf_x1, uf_y1, uf_x2, uf_y2 = 1290, 1030, 1600, 2040
paint_rect(uf_x1, uf_y1, uf_x2, uf_y2, (34, 38, 44, 255), roughness=180, metallic=120, ao=220)
# Longitudinal structural steel corrugations running full length
for cx in range(uf_x1 + 20, uf_x2 - 20, 22):
    paint_line(cx, uf_y1, cx, uf_y2, (22, 25, 30, 255), width=3, roughness=210, metallic=80, ao=170)
    paint_line(cx + 2, uf_y1, cx + 2, uf_y2, (48, 53, 62, 255), width=2, roughness=160, metallic=140, ao=255)
# Edge dark shadow border
paint_rect(uf_x1, uf_y1, uf_x1 + 10, uf_y2, (20, 22, 26, 255), roughness=200, metallic=60)
paint_rect(uf_x2 - 10, uf_y1, uf_x2, uf_y2, (20, 22, 26, 255), roughness=200, metallic=60)

# ZONE D1: CIRCULAR RAILWAY WHEEL DISC (x: 1620 .. 1820, y: 1030 .. 1230)
# Center: (1720, 1130), Radius: 95px -> [U_c: 0.83984, V_c: 0.44824, R_uv: 0.04639]
wc_x, wc_y = 1720, 1130
paint_rect(1620, 1030, 1820, 1230, (30, 33, 38, 255), roughness=180, metallic=100)
# 1. Outer steel tire / flange rim
draw_base.ellipse([wc_x - 95, wc_y - 95, wc_x + 95, wc_y + 95], fill=(95, 102, 112, 255), outline=(130, 138, 150, 255), width=4)
draw_orm.ellipse([wc_x - 95, wc_y - 95, wc_x + 95, wc_y + 95], fill=(220, 50, 210, 255))
# 2. Machined steel bevel ring
draw_base.ellipse([wc_x - 85, wc_y - 85, wc_x + 85, wc_y + 85], fill=(145, 152, 165, 255), outline=(75, 80, 90, 255), width=3)
draw_orm.ellipse([wc_x - 85, wc_y - 85, wc_x + 85, wc_y + 85], fill=(240, 40, 230, 255))
# 3. Recessed dark forged wheel web
draw_base.ellipse([wc_x - 72, wc_y - 72, wc_x + 72, wc_y + 72], fill=(52, 56, 64, 255), outline=(32, 35, 40, 255), width=3)
draw_orm.ellipse([wc_x - 72, wc_y - 72, wc_x + 72, wc_y + 72], fill=(200, 90, 160, 255))
# 4. Concentric circular brake ring groove
draw_base.ellipse([wc_x - 52, wc_y - 52, wc_x + 52, wc_y + 52], outline=(30, 33, 38, 255), width=6)
# 5. Raised center axle hub
draw_base.ellipse([wc_x - 34, wc_y - 34, wc_x + 34, wc_y + 34], fill=(74, 80, 90, 255), outline=(115, 122, 134, 255), width=3)
draw_orm.ellipse([wc_x - 34, wc_y - 34, wc_x + 34, wc_y + 34], fill=(220, 60, 190, 255))
# 6. Center axle bearing cap & bolts
draw_base.ellipse([wc_x - 16, wc_y - 16, wc_x + 16, wc_y + 16], fill=(28, 30, 35, 255))
for bang in range(0, 360, 60):
    brad = math.radians(bang)
    bx = wc_x + int(math.cos(brad) * 25)
    by = wc_y + int(math.sin(brad) * 25)
    draw_base.ellipse([bx - 3, by - 3, bx + 3, by + 3], fill=(160, 165, 175, 255))

# ZONE D2: WHEEL CYLINDRICAL TREAD (x: 1830 .. 2040, y: 1030 .. 1230) [U: 0.895..0.995, V: 0.398..0.495]
paint_rect(1830, 1030, 2040, 1230, (65, 70, 80, 255), roughness=80, metallic=190)
for ty in range(1045, 1220, 15):
    paint_line(1830, ty, 2040, ty, (50, 54, 62, 255), width=2, roughness=100, metallic=170)
    paint_line(1830, ty + 2, 2040, ty + 2, (80, 86, 98, 255), width=2, roughness=70, metallic=200)

# ZONE D3: BOGIE H-FRAME CHASSIS (x: 1620 .. 2040, y: 1240 .. 1560) [U: 0.795..0.995, V: 0.240..0.390]
# Heavy dark cast industrial steel - ZERO yellow hazard tape!
paint_rect(1620, 1240, 2040, 1560, (46, 50, 58, 255), roughness=160, metallic=110)
draw_base.rectangle([1620, 1240, 2040, 1560], outline=(30, 33, 38, 255), width=4)
# Side frame chamfers and suspension spring mounts
for fy in range(1260, 1540, 28):
    paint_line(1640, fy, 2020, fy, (36, 40, 46, 255), width=4, roughness=180, metallic=90)
    paint_line(1640, fy + 2, 2020, fy + 2, (62, 68, 78, 255), width=2, roughness=130, metallic=130)
# Dark suspension coil spring graphic blocks
for sp_x in [1680, 1820, 1960]:
    paint_rect(sp_x, 1280, sp_x + 36, 1520, (26, 28, 32, 255), roughness=200, metallic=80)
    for cpy in range(1290, 1510, 18):
        paint_line(sp_x + 2, cpy, sp_x + 34, cpy, (68, 74, 84, 255), width=5, roughness=100, metallic=180)

# ZONE D4: 3RD RAIL CURRENT PICKUP SHOE (x: 1620 .. 1760, y: 1570 .. 1720) [U: 0.795..0.860, V: 0.160..0.230]
paint_rect(1620, 1570, 1760, 1720, (50, 54, 60, 255), roughness=160, metallic=70)
# Brass / amber contact shoe plate
paint_rect(1640, 1610, 1740, 1680, (205, 145, 35, 255), roughness=90, metallic=180)
draw_base.rectangle([1640, 1610, 1740, 1680], outline=(140, 95, 20, 255), width=3)

# ZONE D5: UNDERFLOOR EQUIPMENT BOXES (x: 1770 .. 2040, y: 1570 .. 2040) [U: 0.865..0.995, V: 0.005..0.230]
paint_rect(1770, 1570, 2040, 2040, (38, 42, 48, 255), roughness=170, metallic=90, ao=190)
for bx in [1785, 1915]:
    paint_rect(bx, 1590, bx + 115, 2010, (28, 31, 36, 255), roughness=190, metallic=70, ao=160)
    draw_base.rectangle([bx, 1590, bx + 115, 2010], outline=(55, 60, 70, 255), width=3)
    # cooling vents
    for vy in range(1620, 1980, 16):
        paint_line(bx + 12, vy, bx + 103, vy, (16, 18, 22, 255), width=4, roughness=220, metallic=30)

import time

def safe_save(img, filepath):
    tmp = filepath + ".tmp"
    for attempt in range(10):
        try:
            img.save(tmp, "PNG")
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                except Exception:
                    pass
            os.replace(tmp, filepath)
            print("Saved:", filepath)
            return
        except Exception as e:
            time.sleep(0.3)
    # final fallback
    img.save(filepath, "PNG")
    print("Saved directly:", filepath)

# Save BaseColor as clean 24-bit RGB (eliminates any accidental alpha-blend depth sorting in Blender/Engines)
base_rgb = base_img.convert("RGB")
base_path = os.path.join(TEX_DIR, "BTS_Train_BaseColor.png")
orm_path = os.path.join(TEX_DIR, "BTS_Train_RoughnessMetallic.png")
safe_save(base_rgb, base_path)
safe_save(orm_img, orm_path)

norm_img = Image.new("RGB", (SIZE, SIZE), (128, 128, 255))
norm_path = os.path.join(TEX_DIR, "BTS_Train_Normal.png")
safe_save(norm_img, norm_path)

