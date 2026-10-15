import os, math
from PIL import Image, ImageDraw, ImageFont

LANDMARK_DIR = "d:/3D Stuff/GAMEJAM 2026/SONGRANG/Landmark"
os.makedirs(LANDMARK_DIR, exist_ok=True)

print("Generating Bangkok Bank Head Office (Silom) Modular PBR Textures...")

def get_fonts():
    try:
        font_huge = ImageFont.truetype("arialbd.ttf", 96)
        font_large = ImageFont.truetype("arialbd.ttf", 64)
        font_med = ImageFont.truetype("arialbd.ttf", 44)
        font_small = ImageFont.truetype("arialbd.ttf", 28)
    except:
        font_huge = font_large = font_med = font_small = ImageFont.load_default()
    return font_huge, font_large, font_med, font_small

font_huge, font_large, font_med, font_small = get_fonts()

# ==============================================================================
# 1. TEXTURE SET 1: Mat_BBL_Tower (2048x2048)
# Pylons, Horizontal Louvers, Helipad, Top Parapet Signboard, Mechanicals
# ==============================================================================
img_tower = Image.new("RGBA", (2048, 2048), (238, 240, 244, 255)) # Clean brutalist white concrete
rough_tower = Image.new("L", (2048, 2048), 180) # Semi-rough concrete
metal_tower = Image.new("L", (2048, 2048), 0)   # Dielectric
norm_tower = Image.new("RGBA", (2048, 2048), (128, 128, 255, 255))

draw_t = ImageDraw.Draw(img_tower)
draw_tr = ImageDraw.Draw(rough_tower)
draw_tm = ImageDraw.Draw(metal_tower)

# 1A. Horizontal Louver & Ribbon Glazing Facade (X: 0..1200, Y: 0..1200)
# 24 rhythmic tiers of white sunshades and dark glass
num_louvers = 24
lh = 1200 // num_louvers
for i in range(num_louvers):
    ly = i * lh
    # Sunshade shelf (top half, white concrete)
    draw_t.rectangle([0, ly, 1200, ly + lh//2], fill=(245, 247, 250, 255), outline=(210, 215, 222, 255))
    draw_tr.rectangle([0, ly, 1200, ly + lh//2], fill=160)
    # Dark reflective ribbon glass (bottom half)
    draw_t.rectangle([0, ly + lh//2, 1200, ly + (i+1)*lh], fill=(22, 30, 42, 255), outline=(12, 18, 26, 255))
    draw_tr.rectangle([0, ly + lh//2, 1200, ly + (i+1)*lh], fill=25) # high gloss glass
    draw_tm.rectangle([0, ly + lh//2, 1200, ly + (i+1)*lh], fill=40)
    # Subtle sky reflection streak
    draw_t.rectangle([0, ly + lh//2 + 2, 1200, ly + lh//2 + 6], fill=(55, 80, 115, 255))

# 1B. Top Parapet "Bangkok Bank" Corporate Signboard (X: 40..1160, Y: 1240..1440)
draw_t.rectangle([40, 1240, 1160, 1440], fill=(0, 48, 120, 255), outline=(230, 235, 245, 255), width=6)
draw_tr.rectangle([40, 1240, 1160, 1440], fill=40)
draw_tm.rectangle([40, 1240, 1160, 1440], fill=140)

# Lotus icon left
lx, ly, lr = 140, 1340, 60
draw_t.ellipse([lx-lr, ly-lr, lx+lr, ly+lr], fill=(0, 60, 145, 255), outline=(255, 255, 255, 255), width=4)
# Stylized lotus petals
draw_t.polygon([(lx, ly-36), (lx+16, ly), (lx, ly+24), (lx-16, ly)], fill=(255, 255, 255, 255))
draw_t.polygon([(lx, ly-36), (lx+28, ly-10), (lx+18, ly+18), (lx, ly)], fill=(240, 245, 252, 255))
draw_t.polygon([(lx, ly-36), (lx-28, ly-10), (lx-18, ly+18), (lx, ly)], fill=(240, 245, 252, 255))

# "Bangkok Bank" text
tb = "Bangkok Bank"
bbox_b = font_huge.getbbox(tb)
bw = bbox_b[2] - bbox_b[0]
bh = bbox_b[3] - bbox_b[1]
draw_t.text((240, 1340 - bh//2 - bbox_b[1]), tb, fill=(255, 255, 255, 255), font=font_huge)

# 1C. Circular Helipad ("H") (X: 1240..2040, Y: 1240..2040) - Dedicated 800x800 square
hx1, hy1, hx2, hy2 = 1240, 1240, 2040, 2040
hcx, hcy = (hx1 + hx2) // 2, (hy1 + hy2) // 2
hr = 380

# Square concrete apron
draw_t.rectangle([hx1, hy1, hx2, hy2], fill=(215, 218, 224, 255))
draw_tr.rectangle([hx1, hy1, hx2, hy2], fill=220)

# Dark green circular landing surface
draw_t.ellipse([hcx - hr, hcy - hr, hcx + hr, hcy + hr], fill=(24, 92, 42, 255), outline=(255, 255, 255, 255), width=10)
draw_tr.ellipse([hcx - hr, hcy - hr, hcx + hr, hcy + hr], fill=160)

# Bright yellow outer landing boundary ring
yr = hr - 30
draw_t.ellipse([hcx - yr, hcy - yr, hcx + yr, hcy + yr], fill=None, outline=(255, 215, 0, 255), width=16)

# Inner dashed target circle
ir = hr - 140
draw_t.ellipse([hcx - ir, hcy - ir, hcx + ir, hcy + ir], fill=None, outline=(255, 255, 255, 255), width=8)

# Giant Bold Yellow "H"
hw = 180
hh = 260
bar_t = 44
# Left upright
draw_t.rectangle([hcx - hw//2, hcy - hh//2, hcx - hw//2 + bar_t, hcy + hh//2], fill=(255, 220, 10, 255))
# Right upright
draw_t.rectangle([hcx + hw//2 - bar_t, hcy - hh//2, hcx + hw//2, hcy + hh//2], fill=(255, 220, 10, 255))
# Crossbar
draw_t.rectangle([hcx - hw//2, hcy - bar_t//2, hcx + hw//2, hcy + bar_t//2], fill=(255, 220, 10, 255))

# Perimeter helipad landing perimeter lights (red & green dots)
for ang_deg in range(0, 360, 30):
    rad = math.radians(ang_deg)
    px = int(hcx + (hr - 15) * math.cos(rad))
    py = int(hcy + (hr - 15) * math.sin(rad))
    draw_t.ellipse([px-8, py-8, px+8, py+8], fill=(255, 230, 50, 255), outline=(40, 40, 40, 255), width=2)

# 1D. Rooftop Mechanical Enclosures & Chillers (X: 1240..2040, Y: 0..1200)
draw_t.rectangle([1240, 0, 2040, 1200], fill=(185, 190, 198, 255))
# Steel vent slats
for vy in range(20, 1180, 40):
    draw_t.rectangle([1260, vy, 2020, vy + 24], fill=(45, 52, 62, 255), outline=(130, 138, 148, 255), width=2)
    draw_tr.rectangle([1260, vy, 2020, vy + 24], fill=60)
    draw_tm.rectangle([1260, vy, 2020, vy + 24], fill=200)

# 1E. Clean Architectural Concrete for Roof Deck & Walls (X: 0..1200, Y: 1460..2048)
draw_t.rectangle([0, 1460, 1200, 2048], fill=(232, 235, 240, 255))
draw_tr.rectangle([0, 1460, 1200, 2048], fill=210)
for sy in range(1480, 2048, 120):
    draw_t.line([(0, sy), (1200, sy)], fill=(195, 200, 208, 255), width=2)
for sx in range(120, 1200, 240):
    draw_t.line([(sx, 1460), (sx, 2048)], fill=(195, 200, 208, 255), width=2)

# Save Tower Textures
img_tower.save(os.path.join(LANDMARK_DIR, "BBL_Tower_BaseColor.png"))
Image.merge("RGB", (metal_tower, rough_tower, Image.new("L", (2048, 2048), 255))).save(
    os.path.join(LANDMARK_DIR, "BBL_Tower_RoughnessMetallic.png")
)
norm_tower.save(os.path.join(LANDMARK_DIR, "BBL_Tower_Normal.png"))
print("  Generated Mat_BBL_Tower PBR maps.")

# ==============================================================================
# 2. TEXTURE SET 2: Mat_BBL_Podium (2048x2048)
# 15° Canted Fluted Facade, Royal Garuda Emblem, Roof Garden, Helical Ramp
# ==============================================================================
img_pod = Image.new("RGBA", (2048, 2048), (236, 238, 242, 255))
rough_pod = Image.new("L", (2048, 2048), 190)
metal_pod = Image.new("L", (2048, 2048), 0)
norm_pod = Image.new("RGBA", (2048, 2048), (128, 128, 255, 255))

draw_p = ImageDraw.Draw(img_pod)
draw_pr = ImageDraw.Draw(rough_pod)
draw_pm = ImageDraw.Draw(metal_pod)

# 2A. Clean 15° Canted Fluted Facade Background (X: 0..2048, Y: 0..512)
# Pure vertical architectural fluting (64px period = 0.5m world-space flute)
for fx in range(0, 2048, 64):
    draw_p.rectangle([fx, 0, fx + 32, 512], fill=(245, 247, 250, 255))
    draw_p.rectangle([fx + 32, 0, fx + 64, 512], fill=(225, 228, 234, 255))

# 2B. High-Res 1:1 Royal Golden Garuda Emblem (X: 576..1472, Y: 512..1534)
# Dedicated zone for Garuda (Y: 512..1330) + continuous 14 flutes extension (Y: 1330..1534)
# Strictly bounded within Y <= 1534 so it NEVER bleeds into Roof Garden (Y >= 1540)!
# Exactly 14 flutes across 896px (64px per flute, matching 0.5m/flute identically!)
for fi in range(14):
    fx = 576 + fi * 64
    draw_p.rectangle([fx, 512, fx + 32, 1534], fill=(245, 247, 250, 255))
    draw_p.rectangle([fx + 32, 512, fx + 64, 1534], fill=(225, 228, 234, 255))

gcx, gcy = 1024, 820
gr = 210

# Circular gold halo backing - TRUE 1:1 CIRCLE
draw_p.ellipse([gcx - gr, gcy - gr, gcx + gr, gcy + gr], fill=(240, 185, 30, 255), outline=(255, 235, 120, 255), width=10)
draw_pm.ellipse([gcx - gr, gcy - gr, gcx + gr, gcy + gr], fill=255)
draw_pr.ellipse([gcx - gr, gcy - gr, gcx + gr, gcy + gr], fill=40)

# Outstretched Majestic Garuda Wings
draw_p.polygon([
    (gcx, gcy - 165),
    (gcx - 75, gcy - 75),
    (gcx - 200, gcy - 145),
    (gcx - 180, gcy + 35),
    (gcx - 55, gcy + 80),
    (gcx, gcy + 55),
    (gcx + 55, gcy + 80),
    (gcx + 180, gcy + 35),
    (gcx + 200, gcy - 145),
    (gcx + 75, gcy - 75)
], fill=(220, 60, 45, 255), outline=(255, 220, 60, 255), width=6)

# Golden Crown & Torso
draw_p.polygon([(gcx, gcy - 175), (gcx + 32, gcy - 90), (gcx, gcy - 35), (gcx - 32, gcy - 90)], fill=(255, 230, 80, 255))
draw_p.polygon([(gcx - 40, gcy - 35), (gcx + 40, gcy - 35), (gcx + 28, gcy + 55), (gcx - 28, gcy + 55)], fill=(255, 210, 50, 255))
# Pedestal Ribbon
draw_p.rectangle([gcx - 130, gcy + 90, gcx + 130, gcy + 130], fill=(160, 25, 25, 255), outline=(255, 215, 0, 255), width=4)

# 3D Bold "BANGKOK BANK" Gold Corporate Signage below Garuda
t_bb_pod = "BANGKOK BANK"
bbox_pod = font_huge.getbbox(t_bb_pod)
bb_w = bbox_pod[2] - bbox_pod[0]
bb_h = bbox_pod[3] - bbox_pod[1]
sign_y = gcy + 200
# Dark backing plate
draw_p.rectangle([gcx - bb_w//2 - 45, sign_y - 18, gcx + bb_w//2 + 45, sign_y + bb_h + 18], fill=(0, 42, 105, 255), outline=(255, 215, 0, 255), width=6)
draw_pm.rectangle([gcx - bb_w//2 - 45, sign_y - 18, gcx + bb_w//2 + 45, sign_y + bb_h + 18], fill=180)
draw_pr.rectangle([gcx - bb_w//2 - 45, sign_y - 18, gcx + bb_w//2 + 45, sign_y + bb_h + 18], fill=40)
# Gold Text
draw_p.text((gcx - bb_w//2, sign_y - bbox_pod[1]), t_bb_pod, fill=(255, 225, 60, 255), font=font_huge)

# 2C. Dedicated Brutalist Parking Garage Horizontal Louvers (X: 0..512, Y: 512..1536)
# Multi-level horizontal concrete louvers with dark recessed ventilation openings
draw_p.rectangle([0, 512, 512, 1536], fill=(228, 230, 235, 255))
draw_pr.rectangle([0, 512, 512, 1536], fill=190)

# Structural vertical piers
for px in [0, 160, 320, 480]:
    draw_p.rectangle([px, 512, px + 24, 1536], fill=(210, 214, 220, 255), outline=(180, 185, 192, 255))

# 12 Rhythmic parking deck ventilation horizontal louver bays
num_garage_tiers = 12
g_th = (1536 - 512) // num_garage_tiers
for gi in range(num_garage_tiers):
    gy = 512 + gi * g_th
    # Concrete floor spandrel slab (top 35%)
    draw_p.rectangle([0, gy, 512, gy + int(g_th * 0.35)], fill=(240, 242, 246, 255), outline=(200, 204, 212, 255), width=2)
    draw_pr.rectangle([0, gy, 512, gy + int(g_th * 0.35)], fill=200)
    # Dark recessed ventilation opening (middle 45%)
    draw_p.rectangle([0, gy + int(g_th * 0.35), 512, gy + int(g_th * 0.80)], fill=(25, 28, 34, 255), outline=(15, 18, 24, 255))
    draw_pr.rectangle([0, gy + int(g_th * 0.35), 512, gy + int(g_th * 0.80)], fill=150)
    # Internal concrete ramp / parked car silhouette hint inside the shadow
    draw_p.rectangle([60, gy + int(g_th * 0.50), 140, gy + int(g_th * 0.78)], fill=(45, 52, 65, 255))
    draw_p.rectangle([220, gy + int(g_th * 0.50), 300, gy + int(g_th * 0.78)], fill=(45, 52, 65, 255))
    draw_p.rectangle([380, gy + int(g_th * 0.50), 460, gy + int(g_th * 0.78)], fill=(45, 52, 65, 255))
    # Louver guardrail / angled deflector (bottom 20%)
    draw_p.rectangle([0, gy + int(g_th * 0.80), 512, gy + g_th], fill=(215, 218, 224, 255), outline=(180, 184, 192, 255))

# 2D. Rear Service Wall, Expansion Joints & Loading Bay (X: 1536..2048, Y: 512..1536)
draw_p.rectangle([1536, 512, 2048, 1536], fill=(226, 228, 233, 255))
draw_pr.rectangle([1536, 512, 2048, 1536], fill=180)
# Modular concrete panel grid
for sy in range(512, 1536, 128):
    draw_p.line([(1536, sy), (2048, sy)], fill=(185, 190, 198, 255), width=3)
for sx in range(1536, 2048, 170):
    draw_p.line([(sx, 512), (sx, 1536)], fill=(185, 190, 198, 255), width=3)

# Service access metal double door (bottom)
door_x, door_y = 1680, 1280
draw_p.rectangle([door_x, door_y, door_x + 220, 1500], fill=(55, 62, 72, 255), outline=(120, 128, 140, 255), width=6)
draw_pm.rectangle([door_x, door_y, door_x + 220, 1500], fill=180)
draw_pr.rectangle([door_x, door_y, door_x + 220, 1500], fill=60)
draw_p.line([(door_x + 110, door_y), (door_x + 110, 1500)], fill=(35, 40, 48, 255), width=4)

# 2E. Podium Roof Garden Turf & Landscaped Planters (X: 0..1024, Y: 1536..2048)
draw_p.rectangle([0, 1536, 1024, 2048], fill=(42, 132, 60, 255)) # Vibrant tropical lawn green
draw_pr.rectangle([0, 1536, 1024, 2048], fill=240)
# Garden walking pavers & hedge borders
for gy in range(1550, 2020, 100):
    draw_p.rectangle([40, gy, 984, gy + 24], fill=(225, 228, 234, 255), outline=(180, 185, 192, 255), width=2)
    draw_p.rectangle([60, gy + 32, 964, gy + 80], fill=(25, 85, 38, 255), outline=(15, 60, 25, 255), width=2) # Lush hedge

# 2F. Clean Asphalt Parking Deck Pavement (X: 1024..1536, Y: 1536..2048)
draw_p.rectangle([1024, 1536, 1536, 2048], fill=(160, 165, 175, 255)) # Clean asphalt deck
draw_pr.rectangle([1024, 1536, 1536, 2048], fill=210)
# Parking stall demarcation lines
for py in range(1560, 2040, 80):
    draw_p.line([(1040, py), (1260, py)], fill=(255, 235, 120, 255), width=3)
    draw_p.line([(1300, py), (1520, py)], fill=(255, 235, 120, 255), width=3)

# 2G. Dedicated Circular Helical Ramp Roadway (X: 1536..2048, Y: 1536..2048) - 1:1 Square
rcx, rcy = 1792, 1792
rr = 240
draw_p.rectangle([1536, 1536, 2048, 2048], fill=(155, 160, 170, 255)) # Base asphalt
draw_p.ellipse([rcx - rr, rcy - rr, rcx + rr, rcy + rr], fill=(60, 65, 74, 255), outline=(240, 244, 250, 255), width=10)
draw_p.ellipse([rcx - 120, rcy - 120, rcx + 120, rcy + 120], fill=(215, 218, 224, 255), outline=(180, 185, 192, 255), width=8) # Core island
draw_p.arc([rcx - 180, rcy - 180, rcx + 180, rcy + 180], start=10, end=350, fill=(255, 220, 30, 255), width=8) # Driving lane yellow guide line

# Save Podium Textures
img_pod.save(os.path.join(LANDMARK_DIR, "BBL_Podium_BaseColor.png"))
Image.merge("RGB", (metal_pod, rough_pod, Image.new("L", (2048, 2048), 255))).save(
    os.path.join(LANDMARK_DIR, "BBL_Podium_RoughnessMetallic.png")
)
norm_pod.save(os.path.join(LANDMARK_DIR, "BBL_Podium_Normal.png"))
print("  Generated Mat_BBL_Podium PBR maps.")

# ==============================================================================
# 3. TEXTURE SET 3: Mat_BBL_Arcade (2048x2048)
# Parabolic Arches, Recessed Banking Hall, Entrance Doors, ATM Terminal, Plaza
# ==============================================================================
img_arc = Image.new("RGBA", (2048, 2048), (235, 238, 242, 255))
rough_arc = Image.new("L", (2048, 2048), 180)
metal_arc = Image.new("L", (2048, 2048), 0)
norm_arc = Image.new("RGBA", (2048, 2048), (128, 128, 255, 255))

draw_a = ImageDraw.Draw(img_arc)
draw_ar = ImageDraw.Draw(rough_arc)
draw_am = ImageDraw.Draw(metal_arc)

# 3A. Parabolic Arch Piers (X: 0..1024, Y: 0..1024)
# Sculptural white concrete arches with smooth shading
for ax in range(0, 1024, 170):
    draw_a.rectangle([ax, 0, ax + 70, 1024], fill=(245, 247, 250, 255), outline=(210, 215, 222, 255))
    draw_a.rectangle([ax + 70, 0, ax + 150, 1024], fill=(215, 218, 225, 255))

# 3B. Recessed Banking Hall Glass Lobby (X: 1040..2048, Y: 0..1024)
draw_a.rectangle([1040, 0, 2048, 1024], fill=(22, 28, 38, 255))
draw_ar.rectangle([1040, 0, 2048, 1024], fill=30)
# Bronze window grid
for gx in range(1060, 2040, 160):
    draw_a.rectangle([gx, 40, gx + 140, 980], fill=(32, 42, 56, 255), outline=(160, 130, 80, 255), width=4)
    # Warm interior lobby lighting reflection
    draw_a.rectangle([gx + 10, 80, gx + 130, 200], fill=(65, 80, 95, 255))

# 3C. Dedicated Double Bronze Entrance Doors (X: 0..1024, Y: 1040..2048)
# Human Scale: 3.0m monumental doors (bottom 60%) + 1.9m bronze transom glass (top 40%)
draw_a.rectangle([0, 1040, 1024, 2048], fill=(22, 28, 38, 255))
draw_ar.rectangle([0, 1040, 1024, 2048], fill=30)

# Upper Architectural Transom Glass & Bronze Mullions (Y: 1040..1440)
for tx in [160, 360, 512, 664, 864]:
    draw_a.rectangle([tx - 6, 1050, tx + 6, 1430], fill=(160, 130, 80, 255), outline=(200, 170, 110, 255))
    draw_am.rectangle([tx - 6, 1050, tx + 6, 1430], fill=220)

# Heavy Horizontal Transom Beam (Y: 1425..1455)
draw_a.rectangle([0, 1425, 1024, 1455], fill=(38, 30, 22, 255), outline=(170, 140, 90, 255), width=3)
draw_am.rectangle([0, 1425, 1024, 1455], fill=220)

# Lower Monumental Double Doors (Y: 1455..2040)
# Outer bronze portal frame
dcx, dcy = 512, 1745
dw, dh = 580, 570
draw_a.rectangle([dcx - dw//2, dcy - dh//2, dcx + dw//2, dcy + dh//2], fill=(28, 24, 20, 255), outline=(190, 160, 100, 255), width=8)
draw_am.rectangle([dcx - dw//2, dcy - dh//2, dcx + dw//2, dcy + dh//2], fill=220)
draw_ar.rectangle([dcx - dw//2, dcy - dh//2, dcx + dw//2, dcy + dh//2], fill=40)

# Left & Right Door leaves
draw_a.rectangle([dcx - dw//2 + 20, dcy - dh//2 + 20, dcx - 10, dcy + dh//2 - 15], fill=(36, 44, 56, 255), outline=(150, 130, 90, 255), width=5)
draw_a.rectangle([dcx + 10, dcy - dh//2 + 20, dcx + dw//2 - 20, dcy + dh//2 - 15], fill=(36, 44, 56, 255), outline=(150, 130, 90, 255), width=5)

# Brushed Aluminum Vertical Door Pull Handles (Human eye-level)
draw_a.rectangle([dcx - 45, dcy - 60, dcx - 30, dcy + 100], fill=(245, 248, 252, 255))
draw_a.rectangle([dcx + 30, dcy - 60, dcx + 45, dcy + 100], fill=(245, 248, 252, 255))
draw_am.rectangle([dcx - 45, dcy - 60, dcx - 30, dcy + 100], fill=255)
draw_am.rectangle([dcx + 30, dcy - 60, dcx + 45, dcy + 100], fill=255)
draw_ar.rectangle([dcx - 45, dcy - 60, dcx - 30, dcy + 100], fill=20)
draw_ar.rectangle([dcx + 30, dcy - 60, dcx + 45, dcy + 100], fill=20)

# 3D. Dedicated Modern ATM Terminal Booth (X: 1040..2048, Y: 1040..1660)
# Base dark lobby glass background across entire zone to prevent ANY light bleed!
draw_a.rectangle([1040, 1040, 2048, 1660], fill=(22, 28, 38, 255))
draw_ar.rectangle([1040, 1040, 2048, 1660], fill=30)

# Upper Transom Glass & Bronze Mullions (Y: 1040..1220)
for mx in [1240, 1544, 1848]:
    draw_a.rectangle([mx - 4, 1045, mx + 4, 1215], fill=(160, 130, 80, 255))
    draw_am.rectangle([mx - 4, 1045, mx + 4, 1215], fill=200)

# Navy Blue "ATM" Signboard (Y: 1220..1310)
draw_a.rectangle([1080, 1220, 2008, 1310], fill=(0, 55, 135, 255), outline=(255, 255, 255, 255), width=4)
draw_am.rectangle([1080, 1220, 2008, 1310], fill=140)
draw_ar.rectangle([1080, 1220, 2008, 1310], fill=40)

t_atm_h = "ATM"
bbox_atm = font_huge.getbbox(t_atm_h)
aw = bbox_atm[2] - bbox_atm[0]
draw_a.text((1544 - aw//2, 1265 - (bbox_atm[3]-bbox_atm[1])//2 - bbox_atm[1]), t_atm_h, fill=(255, 255, 255, 255), font=font_huge)

# 3 Ergonomic Human-Scale ATM Kiosks (Y: 1310..1640)
draw_a.rectangle([1040, 1310, 2048, 1640], fill=(18, 22, 28, 255))
for at_x in [1120, 1420, 1720]:
    # ATM Terminal Body
    draw_a.rectangle([at_x, 1320, at_x + 220, 1630], fill=(28, 34, 44, 255), outline=(0, 160, 255, 255), width=3)
    # Bright Illuminated Cyan Touchscreen
    draw_a.rectangle([at_x + 30, 1345, at_x + 190, 1445], fill=(0, 220, 255, 255), outline=(220, 245, 255, 255), width=3)
    # Card / Receipt slot
    draw_a.rectangle([at_x + 40, 1475, at_x + 180, 1495], fill=(50, 60, 75, 255), outline=(0, 180, 255, 255), width=2)
    # Illuminated Numeric Keypad
    draw_a.rectangle([at_x + 55, 1520, at_x + 165, 1585], fill=(80, 95, 110, 255))

# 3E. Street Plaza Granite Pavement (X: 1040..2048, Y: 1660..2048)
draw_a.rectangle([1040, 1660, 2048, 2048], fill=(210, 214, 220, 255))
draw_ar.rectangle([1040, 1660, 2048, 2048], fill=220)
# Paver joint grid
for px in range(1040, 2048, 80):
    draw_a.line([(px, 1660), (px, 2048)], fill=(165, 170, 180, 255), width=2)
for py in range(1660, 2048, 80):
    draw_a.line([(1040, py), (2048, py)], fill=(165, 170, 180, 255), width=2)

# Save Arcade Textures
img_arc.save(os.path.join(LANDMARK_DIR, "BBL_Arcade_BaseColor.png"))
Image.merge("RGB", (metal_arc, rough_arc, Image.new("L", (2048, 2048), 255))).save(
    os.path.join(LANDMARK_DIR, "BBL_Arcade_RoughnessMetallic.png")
)
norm_arc.save(os.path.join(LANDMARK_DIR, "BBL_Arcade_Normal.png"))
print("  Generated Mat_BBL_Arcade PBR maps.")
print("All 3 Modular PBR Texture Sets successfully generated!")
