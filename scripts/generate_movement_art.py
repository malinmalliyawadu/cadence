"""Generates the movement photos and muscle map layers in Assets.xcassets.

Both asset groups are generated wholesale: edit this script, not the asset folders.

    git clone --depth 1 https://github.com/yuhonas/free-exercise-db /tmp/free-exercise-db
    git clone --depth 1 https://github.com/HichamELBSI/react-native-body-highlighter /tmp/body-highlighter
    python3 scripts/generate_movement_art.py /tmp/free-exercise-db /tmp/body-highlighter

Needs rsvg-convert (brew install librsvg) and Pillow.

Movement photos come from Free Exercise DB (public domain, Unlicense). Each exercise has two
photos, the starting position and the other end of the movement, in that order. They are
cropped to 3:2 and scaled down so every photo sits in the same frame.

The muscle map comes from react-native-body-highlighter (MIT). Each side is split into one
template layer per MuscleGroup plus a base layer with everything else, so the app can tint
the primary and secondary muscles of a movement.

Both are credited in the app (CreditsView).
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

# Library movement id -> Free Exercise DB exercise id. Only photos that show the movement as
# programmed: no photo beats one with the wrong bench angle or a different exercise. A
# different implement is allowed where the motion is the same (a dumbbell for the kettlebell
# sumo squat, a barbell for the Smith machine glute bridge and calf raise, a landmine for the
# T-bar row), and the unweighted version stands in for a weighted one.
PHOTOS = {
    "bb-bench": "Barbell_Bench_Press_-_Medium_Grip",
    "db-incline-press": "Incline_Dumbbell_Press",
    "db-flat-press": "Dumbbell_Bench_Press",
    "cable-fly": "Cable_Crossover",
    "dip": "Dips_-_Chest_Version",
    "cg-bench": "Close-Grip_Barbell_Bench_Press",
    "hs-incline-press": "Leverage_Incline_Chest_Press",
    "hs-chest-press": "Leverage_Chest_Press",
    "machine-chest-press": "Machine_Bench_Press",
    "smith-bench": "Smith_Machine_Bench_Press",
    "smith-incline-bench": "Smith_Machine_Incline_Bench_Press",
    "machine-fly": "Butterfly",
    "machine-dip": "Dip_Machine",
    "bb-row": "Bent_Over_Barbell_Row",
    "db-row": "One-Arm_Dumbbell_Row",
    "chest-supported-row": "Lying_T-Bar_Row",
    "seated-cable-row": "Seated_Cable_Rows",
    "face-pull": "Face_Pull",
    "hs-iso-row": "Leverage_Iso_Row",
    "t-bar-row": "Bent_Over_Two-Arm_Long_Bar_Row",
    "machine-rear-delt-fly": "Reverse_Machine_Flyes",
    "rack-pull": "Rack_Pulls",
    "bb-ohp": "Standing_Military_Press",
    "db-shoulder-press": "Seated_Dumbbell_Press",
    "lateral-raise": "Side_Lateral_Raise",
    "cable-lateral-raise": "Standing_Low-Pulley_Deltoid_Raise",
    "machine-shoulder-press": "Machine_Shoulder_Military_Press",
    "hs-shoulder-press": "Leverage_Shoulder_Press",
    "front-raise": "Front_Dumbbell_Raise",
    "pull-up": "Pullups",
    "chin-up": "Chin-Up",
    "lat-pulldown": "Wide-Grip_Lat_Pulldown",
    "neutral-pull-up": "V-Bar_Pullup",
    "straight-arm-pulldown": "Straight-Arm_Pulldown",
    "rear-delt-fly": "Seated_Bent-Over_Rear_Delt_Raise",
    "bb-curl": "Barbell_Curl",
    "incline-db-curl": "Incline_Dumbbell_Curl",
    "hammer-curl": "Hammer_Curls",
    "skull-crusher": "EZ-Bar_Skullcrusher",
    "cable-pushdown": "Triceps_Pushdown",
    "overhead-cable-ext": "Cable_Rope_Overhead_Triceps_Extension",
    "cable-curl": "Standing_Biceps_Cable_Curl",
    "db-curl": "Dumbbell_Bicep_Curl",
    "machine-preacher-curl": "Machine_Preacher_Curls",
    "reverse-curl": "Reverse_Barbell_Curl",
    "wrist-curl": "Seated_Palm-Up_Barbell_Wrist_Curl",
    "reverse-wrist-curl": "Seated_Palms-Down_Barbell_Wrist_Curl",
    "cable-wrist-curl": "Cable_Wrist_Curl",
    "bb-back-squat": "Barbell_Squat",
    "bb-front-squat": "Front_Barbell_Squat",
    "hack-squat": "Hack_Squat",
    "leg-press": "Leg_Press",
    "leg-extension": "Leg_Extensions",
    "kb-sumo-squat": "Plie_Dumbbell_Squat",
    "bb-deadlift": "Barbell_Deadlift",
    "rdl": "Romanian_Deadlift",
    "db-rdl": "Stiff-Legged_Dumbbell_Deadlift",
    "good-morning": "Good_Morning",
    "leg-curl": "Seated_Leg_Curl",
    "nordic-curl": "Natural_Glute_Ham_Raise",
    "lying-leg-curl": "Lying_Leg_Curls",
    "smith-rdl": "Smith_Machine_Stiff-Legged_Deadlift",
    "glute-ham-raise": "Glute_Ham_Raise",
    "back-extension": "Hyperextensions_Back_Extensions",
    "hip-thrust": "Barbell_Hip_Thrust",
    "cable-kickback": "One-Legged_Cable_Kickback",
    "hip-abduction": "Thigh_Abductor",
    "hip-adduction": "Thigh_Adductor",
    "smith-glute-bridge": "Barbell_Glute_Bridge",
    "bulgarian-split-squat": "One_Leg_Barbell_Squat",
    "walking-lunge": "Dumbbell_Lunges",
    "reverse-lunge": "Dumbbell_Rear_Lunge",
    "step-up": "Dumbbell_Step_Ups",
    "standing-calf-raise": "Standing_Calf_Raises",
    "seated-calf-raise": "Seated_Calf_Raise",
    "smith-calf-raise": "Standing_Barbell_Calf_Raise",
    "machine-crunch": "Ab_Crunch_Machine",
    "hanging-leg-raise": "Hanging_Leg_Raise",
    "cable-crunch": "Cable_Crunch",
    "ab-wheel": "Ab_Roller",
}
FRAMES = ("start", "end")
PHOTO_SIZE = (720, 480)
PHOTO_QUALITY = 80

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


def main(free_exercise_db: Path, body_highlighter: Path) -> None:
    check_ids()
    write_movements(free_exercise_db / "exercises")
    with tempfile.TemporaryDirectory() as tmp:
        write_body_map(body_highlighter / "assets", Path(tmp))


def check_ids() -> None:
    known = set(re.findall(r'Exercise\(id: "([^"]+)"', LIBRARY.read_text()))
    unknown = sorted(set(PHOTOS) - known)
    if unknown:
        sys.exit(f"Not in ExerciseLibrary: {', '.join(unknown)}")


# MARK: Movement photos

def write_movements(photo_dir: Path) -> None:
    folder = reset_group("Movement")
    for exercise_id, photo_id in sorted(PHOTOS.items()):
        for index, frame in enumerate(FRAMES):
            photo = cropped(Image.open(photo_dir / photo_id / f"{index}.jpg").convert("RGB"))
            name = f"{exercise_id}-{frame}"
            imageset = folder / f"{name}.imageset"
            imageset.mkdir()
            photo.save(imageset / f"{name}.jpg", quality=PHOTO_QUALITY, optimize=True, progressive=True)
            write_json(imageset / "Contents.json", {
                "images": [{"filename": f"{name}.jpg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            })
    print(f"{len(PHOTOS)} movements, {len(set(PHOTOS.values()))} photo pairs")


def cropped(photo: Image.Image) -> Image.Image:
    """The centre of the photo at 3:2, scaled to PHOTO_SIZE."""
    width, height = photo.size
    target = PHOTO_SIZE[0] / PHOTO_SIZE[1]
    if width / height > target:
        crop_width = round(height * target)
        left = (width - crop_width) // 2
        photo = photo.crop((left, 0, left + crop_width, height))
    else:
        crop_height = round(width / target)
        top = (height - crop_height) // 2
        photo = photo.crop((0, top, width, top + crop_height))
    return photo.resize(PHOTO_SIZE, Image.LANCZOS)


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
