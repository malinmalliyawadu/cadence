"""Generates the app icon, an Icon Composer document shared by the iPhone and watch apps.

The document is generated wholesale: edit this script, not Cadence/Resources/AppIcon.icon.

    python3 scripts/generate_app_icon.py
    python3 scripts/generate_app_icon.py --preview /tmp/icon-previews

The mark is an open C, the training cycle, with a dot in its gap for today: violet on deep
indigo, the dot mint. Solid fills only. The depth and the specular edge are iOS's Liquid Glass,
which renders the layers on the device, so the same document gives the default, dark, tinted
and clear appearances on iPhone and the round icon on the watch.

--preview renders every appearance with ictool, which ships inside Icon Composer in Xcode.
"""

import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ICON = REPO / "Cadence/Resources/AppIcon.icon"
ICTOOL = Path("/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")

INDIGO = "#12082E"
VIOLET = "#B47CFF"
MINT = "#5CF2D6"

# Geometry on Icon Composer's 1024 point canvas. The gap faces up and to the right, centred
# on GAP_CENTRE degrees clockwise from twelve o'clock, and the dot sits on the ring's centre line.
CENTRE = 512
RADIUS = 262
STROKE = 136
GAP = 84
GAP_CENTRE = 45
DOT_RADIUS = STROKE * 0.36


def srgb(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def point(degrees, radius=RADIUS):
    angle = math.radians(degrees - 90)
    return CENTRE + radius * math.cos(angle), CENTRE + radius * math.sin(angle)


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{body}</svg>\n'


def ring():
    # A filled outline, not a stroked arc: Liquid Glass lights the chord that closes an open
    # stroked path, which draws a hairline across the gap.
    start, end = GAP_CENTRE + GAP / 2, GAP_CENTRE + 360 - GAP / 2
    outer, inner, cap = RADIUS + STROKE / 2, RADIUS - STROKE / 2, STROKE / 2
    (ax, ay), (bx, by) = point(start, outer), point(end, outer)
    (cx, cy), (dx, dy) = point(end, inner), point(start, inner)
    path = (f"M{ax:.2f},{ay:.2f} A{outer},{outer} 0 1 1 {bx:.2f},{by:.2f} "
            f"A{cap},{cap} 0 0 1 {cx:.2f},{cy:.2f} "
            f"A{inner},{inner} 0 1 0 {dx:.2f},{dy:.2f} "
            f"A{cap},{cap} 0 0 1 {ax:.2f},{ay:.2f} Z")
    return svg(f'<path d="{path}" fill="{VIOLET}"/>')


def dot():
    x, y = point(GAP_CENTRE)
    return svg(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{DOT_RADIUS:.2f}" fill="{MINT}"/>')


def group(layer):
    return {
        "layers": [{"glass": True, "image-name": f"{layer}.svg", "name": layer}],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "specular": True,
        "translucency": {"enabled": True, "value": 0.4},
    }


def write():
    if ICON.exists():
        shutil.rmtree(ICON)
    assets = ICON / "Assets"
    assets.mkdir(parents=True)
    (assets / "ring.svg").write_text(ring())
    (assets / "dot.svg").write_text(dot())
    document = {
        "fill": {"solid": srgb(INDIGO)},
        # Front-most group first.
        "groups": [group("dot"), group("ring")],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")


def preview(directory):
    directory.mkdir(parents=True, exist_ok=True)
    renders = [("iOS", r) for r in ("Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark")]
    renders.append(("watchOS", "Default"))
    for platform, rendition in renders:
        out = directory / f"{platform}-{rendition}.png"
        subprocess.run([str(ICTOOL), str(ICON), "--export-image", "--output-file", str(out),
                        "--platform", platform, "--rendition", rendition,
                        "--width", "512", "--height", "512", "--scale", "2"],
                       check=True, stdout=subprocess.DEVNULL)
        print(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and (len(args) != 2 or args[0] != "--preview"):
        sys.exit(__doc__)
    write()
    if args:
        preview(Path(args[1]))
