#!/usr/bin/env python3
"""Generates the movement drawings and muscle map layers in Assets.xcassets.

Both asset groups are generated wholesale: edit this script, not the asset folders.

    git clone --depth 1 https://github.com/everkinetic/data /tmp/everkinetic
    git clone --depth 1 https://github.com/HichamELBSI/react-native-body-highlighter /tmp/body-highlighter
    python3 scripts/generate_movement_art.py /tmp/everkinetic /tmp/body-highlighter

Needs rsvg-convert (brew install librsvg) and Pillow, used to measure drawing bounds.

Movement drawings come from Everkinetic (CC BY-SA 4.0). Each has a relaxed and a tensed
frame. The white fill is dropped and the line work kept as a template image, so the app
tints it from the palette. The recoloured drawings stay under CC BY-SA 4.0.

The muscle map comes from react-native-body-highlighter (MIT). Each side is split into one
template layer per MuscleGroup plus a base layer with everything else, so the app can tint
the primary and secondary muscles of a movement.

Both licences are credited in the app (CreditsView).
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "Cadence/Resources/Assets.xcassets"
LIBRARY = REPO / "Packages/TrainingEngine/Sources/TrainingEngine/Exercises/ExerciseLibrary.swift"

# Library movement id -> Everkinetic drawing id. Only drawings that show the movement as
# programmed: no drawing beats one with the wrong bench angle or a different exercise.
# A different implement is allowed where the motion is the same (a dumbbell for the
# kettlebell sumo squat, a barbell for the ab wheel).
DRAWINGS = {
    "bb-bench": "0042",
    "db-incline-press": "0080",
    "cable-fly": "0048",
    "cg-bench": "0049",
    "machine-chest-press": "0066",
    "hs-chest-press": "0066",
    "smith-bench": "0078",
    "smith-incline-bench": "0081",
    "machine-dip": "0171",
    "bb-row": "0026",
    "db-row": "0024",
    "seated-cable-row": "0025",
    "t-bar-row": "0029",
    "bb-ohp": "0004",
    "lateral-raise": "0018",
    "front-raise": "0033",
    "pull-up": "0087",
    "lat-pulldown": "0096",
    "neutral-pull-up": "0090",
    "straight-arm-pulldown": "0092",
    "rear-delt-fly": "0032",
    "bb-curl": "0211",
    "incline-db-curl": "0214",
    "hammer-curl": "0227",
    "skull-crusher": "0183",
    "cable-pushdown": "0205",
    "cable-curl": "0212",
    "db-curl": "0224",
    "machine-preacher-curl": "0236",
    "bb-back-squat": "0122",
    "bb-front-squat": "0138",
    "leg-press": "0127",
    "leg-extension": "0142",
    "kb-sumo-squat": "0152",
    "bb-deadlift": "0099",
    "rdl": "0118",
    "db-rdl": "0107",
    "good-morning": "0101",
    "leg-curl": "0119",
    "lying-leg-curl": "0117",
    "smith-rdl": "0100",
    "back-extension": "0103",
    "cable-kickback": "0112",
    "hip-abduction": "0156",
    "hip-adduction": "0157",
    "walking-lunge": "0121",
    "reverse-lunge": "0129",
    "step-up": "0137",
    "standing-calf-raise": "0282",
    "seated-calf-raise": "0279",
    "smith-calf-raise": "0280",
    "cable-crunch": "0288",
    "ab-wheel": "0286",
}
FRAMES = ("relaxation", "tension")

# Body highlighter slug -> MuscleGroup raw value, per side. Unlisted slugs go to the base
# layer. The front trapezius and the lower back stay neutral: lighting them for every row
# or every core movement would overstate what those movements train.
BODY_LAYERS = {
    "front": {
        "chest": "chest", "deltoids": "shoulders", "biceps": "biceps", "triceps": "triceps",
        "forearm": "forearms", "quadriceps": "quads", "calves": "calves",
        "abs": "core", "obliques": "core",
    },
    "back": {
        "upper-back": "back", "trapezius": "back", "deltoids": "shoulders", "triceps": "triceps",
        "forearm": "forearms", "hamstring": "hamstrings", "gluteal": "glutes", "calves": "calves",
    },
}
# Source file and x offset: the source draws the back view to the right of the front.
BODY_SOURCES = {"front": ("bodyFront", 0), "back": ("bodyBack", 724)}
BODY_HEIGHT = 1448
PADDING = 4

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)


def main(everkinetic: Path, body_highlighter: Path) -> None:
    check_ids()
    with tempfile.TemporaryDirectory() as tmp:
        write_movements(everkinetic / "dist/svg", Path(tmp))
        write_body_map(body_highlighter / "assets", Path(tmp))


def check_ids() -> None:
    known = set(re.findall(r'Exercise\(id: "([^"]+)"', LIBRARY.read_text()))
    unknown = sorted(set(DRAWINGS) - known)
    if unknown:
        sys.exit(f"Not in ExerciseLibrary: {', '.join(unknown)}")


# MARK: Movement drawings

def write_movements(svg_dir: Path, tmp: Path) -> None:
    folder = reset_group("Movement")
    for exercise_id, drawing_id in sorted(DRAWINGS.items()):
        frames = [line_work(svg_dir / f"{drawing_id}-{frame}.svg") for frame in FRAMES]
        # One viewBox for both frames, so the figure keeps its scale between them.
        box = union(*(bounds(frame, tmp) for frame in frames))
        for frame_name, root in zip(FRAMES, frames):
            set_view_box(root, pad(box))
            write_imageset(folder, f"{exercise_id}-{frame_name}", ET.tostring(root, encoding="unicode"))
    print(f"{len(DRAWINGS)} movements, {len(set(DRAWINGS.values()))} drawings")


def line_work(path: Path) -> ET.Element:
    """The drawing with its light fills removed and the lines in black."""
    root = ET.parse(path).getroot()
    for parent in list(root.iter()):
        for child in list(parent):
            fill = child.get("fill")
            if fill is None:
                continue
            if is_light(fill):
                parent.remove(child)
            else:
                child.set("fill", "#000")
    return root


def is_light(color: str) -> bool:
    hex_digits = color.lstrip("#")
    if len(hex_digits) == 3:
        hex_digits = "".join(c * 2 for c in hex_digits)
    r, g, b = (int(hex_digits[i:i + 2], 16) for i in (0, 2, 4))
    return (0.299 * r + 0.587 * g + 0.114 * b) > 128


# MARK: Muscle map

def write_body_map(asset_dir: Path, tmp: Path) -> None:
    folder = reset_group("BodyMap")
    sides = {side: read_body_parts(asset_dir / f"{source}.ts") for side, (source, _) in BODY_SOURCES.items()}

    layers: dict[str, dict[str, list[str]]] = {}
    for side, parts in sides.items():
        mapping = BODY_LAYERS[side]
        side_layers: dict[str, list[str]] = {}
        for slug, paths in parts.items():
            side_layers.setdefault(mapping.get(slug, "base"), []).extend(paths)
        layers[side] = side_layers

    # Both sides share a width and height so the two figures sit at the same scale.
    boxes = {}
    for side, side_layers in layers.items():
        x_offset = BODY_SOURCES[side][1]
        everything = [p for paths in side_layers.values() for p in paths]
        boxes[side] = bounds(body_svg(everything, (x_offset, 0, x_offset + 724, BODY_HEIGHT)), tmp)
    width = max(b[2] - b[0] for b in boxes.values())
    top = min(b[1] for b in boxes.values())
    bottom = max(b[3] for b in boxes.values())

    for side, side_layers in layers.items():
        x0, _, x1, _ = boxes[side]
        centre = (x0 + x1) / 2
        box = pad((centre - width / 2, top, centre + width / 2, bottom))
        for group, paths in sorted(side_layers.items()):
            root = body_svg(paths, box)
            write_imageset(folder, f"{side}-{group}", ET.tostring(root, encoding="unicode"))
    print("Body map layers:", {side: sorted(l) for side, l in layers.items()})


def read_body_parts(path: Path) -> dict[str, list[str]]:
    text = path.read_text()
    parts: dict[str, list[str]] = {}
    for block in re.split(r"\n\s*\{\s*\n\s*slug:", text)[1:]:
        slug = re.match(r'\s*"([^"]+)"', block).group(1)
        parts[slug] = re.findall(r'"(M[^"]+)"', block)
    return parts


def body_svg(paths: list[str], box) -> ET.Element:
    root = ET.Element(f"{{{SVG_NS}}}svg")
    for d in paths:
        ET.SubElement(root, f"{{{SVG_NS}}}path", {"d": d, "fill": "#000"})
    set_view_box(root, box)
    return root


# MARK: Shared

def bounds(root: ET.Element, tmp: Path) -> tuple[float, float, float, float]:
    """Bounding box of the drawn pixels, in viewBox units."""
    vx, vy, vw, vh = (float(v) for v in root.get("viewBox").split())
    scale = 2
    svg = tmp / "measure.svg"
    png = tmp / "measure.png"
    measured = ET.fromstring(ET.tostring(root))
    measured.set("width", str(vw * scale))
    measured.set("height", str(vh * scale))
    svg.write_text(ET.tostring(measured, encoding="unicode"))
    subprocess.run(["rsvg-convert", str(svg), "-o", str(png)], check=True)
    left, top, right, bottom = Image.open(png).getchannel("A").getbbox()
    return (vx + left / scale, vy + top / scale, vx + right / scale, vy + bottom / scale)


def union(*boxes):
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def pad(box):
    return (box[0] - PADDING, box[1] - PADDING, box[2] + PADDING, box[3] + PADDING)


def set_view_box(root: ET.Element, box) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    root.set("viewBox", f"{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}")
    root.set("width", f"{w:.2f}")
    root.set("height", f"{h:.2f}")


def reset_group(name: str) -> Path:
    folder = ASSETS / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir()
    write_json(folder / "Contents.json", {"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}})
    return folder


def write_imageset(folder: Path, name: str, svg: str) -> None:
    imageset = folder / f"{name}.imageset"
    imageset.mkdir()
    (imageset / f"{name}.svg").write_text(svg + "\n")
    write_json(imageset / "Contents.json", {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    })


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
