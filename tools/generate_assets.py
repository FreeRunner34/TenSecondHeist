"""Generate original App Icon and tiny synthesized audio cues, with no external assets."""
import math
import struct
import wave
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "TenSecondHeist/Resources/Assets.xcassets/AppIcon.appiconset"
RESOURCES = ROOT / "TenSecondHeist/Resources"
ASSETS.mkdir(parents=True, exist_ok=True)

S = 2048
base = Image.new("RGB", (S, S), (7, 19, 29))
glow = Image.new("RGBA", (S, S))
g = ImageDraw.Draw(glow)
for radius in range(850, 0, -14):
    alpha = int(0.25 * (850 - radius) / 850 * 255)
    g.ellipse((1024-radius, 820-radius, 1024+radius, 820+radius), fill=(29, 121, 124, alpha))
base = Image.alpha_composite(base.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(35)))
d = ImageDraw.Draw(base)
for y in range(130, 2048, 145):
    d.line((70, y, 1970, y), fill=(34, 68, 76, 90), width=4)
for x in range(120, 2048, 145):
    d.line((x, 70, x, 1980), fill=(34, 68, 76, 90), width=4)

# Two glowing path segments and an escape door give the mark its heist silhouette.
path = [(300, 1600), (750, 1600), (750, 1200), (1290, 1200), (1290, 640), (1660, 640)]
d.line(path, fill=(7, 82, 80, 120), width=120, joint="curve")
d.line(path, fill=(67, 224, 196, 255), width=36, joint="curve")
d.ellipse((1660-52, 640-52, 1660+52, 640+52), fill=(67, 224, 196, 255))
d.rounded_rectangle((1550, 430, 1820, 850), radius=36, outline=(67, 224, 196, 255), width=28)

# The '10' is oversized and set over the route with heavy editorial type.
fontpath = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
font = ImageFont.truetype(fontpath, 730)
d.rounded_rectangle((190, 625, 1520, 1450), radius=80, fill=(8, 24, 35, 215), outline=(205, 159, 83, 210), width=12)
d.text((245, 575), "10", font=font, fill=(255, 195, 91), stroke_width=2, stroke_fill=(255, 226, 166))
small = ImageFont.truetype(fontpath, 89)
d.text((279, 1490), "SECOND HEIST", font=small, fill=(239, 244, 225))
d.ellipse((1595, 1470, 1745, 1620), fill=(240, 88, 81))
d.line((1670, 1500, 1670, 1546, 1700, 1570), fill=(255, 252, 235), width=13, joint="curve")
base.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS).save(ASSETS / "AppIcon.png", optimize=True)

(ASSETS / "Contents.json").write_text('''{
  "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
  "info": {"author": "xcode", "version": 1}
}
''')
(RESOURCES / "Assets.xcassets/Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')

def wav(name, seconds, voice):
    rate = 22050
    with wave.open(str(RESOURCES / (name + ".wav")), "wb") as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(rate)
        samples = bytearray()
        for i in range(int(rate * seconds)):
            t = i / rate
            value = max(-1, min(1, voice(t, seconds)))
            samples += struct.pack("<h", round(value * 32767))
        out.writeframes(samples)

def pad(t, seconds):
    notes = [110.0, 164.81, 196.0, 146.83]
    block = int(t / 2) % 4
    local = t % 2
    root = notes[block]
    swell = (0.3 + 0.7 * math.sin(math.pi * local / 2) ** 2) * min(1, t * 5) * min(1, (seconds - t) * 5)
    tone = (math.sin(2 * math.pi * root * t) + 0.35 * math.sin(2 * math.pi * root * 1.5 * t)) * 0.10 * swell
    pulse = math.sin(2 * math.pi * (root * 2) * t) * max(0, 1 - ((t * 2) % 1) * 4) * 0.03
    return tone + pulse

wav("music", 8, pad)
wav("go", 0.25, lambda t, s: .23 * math.sin(2 * math.pi * (320 + 780 * t / s) * t) * (1 - t/s))
wav("success", 0.65, lambda t, s: .15 * sum(math.sin(2 * math.pi * f * t) for f in (392, 494, 587)) / 3 * (1 - t/s))
wav("caught", 0.45, lambda t, s: .22 * math.sin(2 * math.pi * (220 - 130 * t/s) * t) * (1 - t/s))
print("Original icon and synthesized audio created")
