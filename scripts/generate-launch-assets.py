#!/usr/bin/env python3
"""Generates the launch screen assets for every app from its Figma launch screen.

Source of truth: `design/launch-screen/<App>-Light.svg` and `<App>-Dark.svg`, full
launch screen frames exported from Figma (1290 x 2805 px, i.e. a 430 pt wide
screen at @3x). The script cuts every element out of the frame and writes it into
`Catalog/Features/<App>/Branding/Assets.xcassets`:

- `LaunchBackground`     – color set, light and dark
- `LaunchWordmark`       – "Foliora", vector
- `LaunchSubtitle`       – the product name, vector
- `LaunchMedallion`      – medallion with its glyph and glows, @2x/@3x
- `SplashMedallionBase`  – the medallion circle alone, same canvas
- `SplashMedallionGlyph` – the glyph alone, same canvas (animated by the splash)
- `ArcLeft`, `ArcRight`  – the arcs along the bottom, @2x/@3x

Elements with Figma effects (glows, inner shadows) are rendered to PNG with
resvg, because asset catalogs do not render SVG filters. Text has no effects
and stays vector. An element that differs between the light and dark frames
gets a dark appearance variant.

The layout numbers that `LaunchScreen.storyboard` and `LaunchBranding.Layout`
rely on are printed at the end; update both when they change.

Requires resvg (`brew install resvg`). Usage, from the repository root:
    python3 scripts/generate-launch-assets.py
"""

from __future__ import annotations

import copy
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DESIGN = REPO_ROOT / "design" / "launch-screen"
FEATURES = REPO_ROOT / "Catalog" / "Features"

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

FRAME_WIDTH = 1290
FRAME_SCALE = 3  # Figma pixels per point.

# Medallion canvas: centered on the circle and large enough for its glows.
# 1044 px = 348 pt, which renders to whole pixels at both @2x and @3x.
MEDALLION_CANVAS = 1044
# Arc crops, from the top of each arc to the bottom of the frame, in whole points.
ARC_RIGHT_TOP = 2361
ARC_LEFT_TOP = 1983
FRAME_BOTTOM = 2805


def tag(name: str) -> str:
    return f"{{{SVG_NS}}}{name}"


@dataclass
class Frame:
    """The elements of one launch screen frame."""

    background: str
    defs: ET.Element
    medallion: ET.Element
    glyph: ET.Element
    wordmark: ET.Element
    subtitle: ET.Element
    arc_right: ET.Element
    arc_left: ET.Element

    @property
    def circle(self) -> ET.Element:
        circle = self.medallion.find(tag("circle"))
        assert circle is not None
        return circle


def load_frame(path: Path) -> Frame:
    root = ET.parse(path).getroot()
    if root.get("viewBox") != f"0 0 {FRAME_WIDTH} {FRAME_BOTTOM}":
        raise ValueError(f"{path}: expected a {FRAME_WIDTH} x {FRAME_BOTTOM} frame")

    defs = root.find(tag("defs"))
    content = next((g for g in root.findall(tag("g")) if g.get("clip-path")), None)
    if defs is None or content is None:
        raise ValueError(f"{path}: expected the frame's clip group and defs")

    rects = [r for r in content.findall(tag("rect")) if r.get("fill", "").lower() not in ("white", "#ffffff")]
    groups = content.findall(tag("g"))
    paths = content.findall(tag("path"))

    medallion = next((g for g in groups if g.find(tag("circle")) is not None), None)
    shapes = [g for g in groups if g.find(tag("path")) is not None]
    arcs = {("left" if g.find(tag("path")).get("d", "").startswith("M0 ") else "right"): g for g in shapes[1:]}

    if len(rects) != 1 or medallion is None or len(shapes) != 3 or len(paths) != 2 or set(arcs) != {"left", "right"}:
        raise ValueError(
            f"{path}: expected a background, a medallion, a glyph, two arcs and two text paths"
        )

    return Frame(
        background=rects[0].get("fill", ""),
        defs=defs,
        medallion=medallion,
        glyph=shapes[0],
        wordmark=paths[0],
        subtitle=paths[1],
        arc_right=arcs["right"],
        arc_left=arcs["left"],
    )


# MARK: - SVG output

def svg_document(view_box: tuple[float, float, float, float], elements: list[ET.Element], defs: ET.Element | None) -> str:
    x, y, width, height = view_box
    root = ET.Element(tag("svg"), {
        "width": fmt(width / FRAME_SCALE),
        "height": fmt(height / FRAME_SCALE),
        "viewBox": " ".join(fmt(v) for v in view_box),
        "fill": "none",
    })
    if defs is not None:
        root.append(copy.deepcopy(defs))
    for element in elements:
        root.append(copy.deepcopy(element))
    ET.indent(root)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


def fmt(value: float) -> str:
    return f"{value:.4f}".rstrip("0").rstrip(".")


def path_bounds(d: str) -> tuple[float, float, float, float]:
    """Tight bounds of a path made of absolute M, L, H, V, C and Z commands."""
    tokens = re.findall(r"[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?", d)
    xs: list[float] = []
    ys: list[float] = []
    x = y = 0.0
    command = ""
    i = 0

    def number() -> float:
        nonlocal i
        value = float(tokens[i])
        i += 1
        return value

    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
            if command == "Z":
                continue
        if command in ("M", "L"):
            x, y = number(), number()
            xs.append(x); ys.append(y)
        elif command == "H":
            x = number(); xs.append(x); ys.append(y)
        elif command == "V":
            y = number(); xs.append(x); ys.append(y)
        elif command == "C":
            x1, y1, x2, y2, x3, y3 = (number() for _ in range(6))
            for step in range(1, 33):
                t = step / 32
                u = 1 - t
                xs.append(u**3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t**3 * x3)
                ys.append(u**3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t**3 * y3)
            x, y = x3, y3
        else:
            raise ValueError(f"Unsupported path command {command!r}")
    return min(xs), min(ys), max(xs), max(ys)


def snapped_box(element: ET.Element) -> tuple[float, float, float, float]:
    """The element's bounds, widened to whole Figma pixels."""
    min_x, min_y, max_x, max_y = path_bounds(element.get("d", ""))
    left, top = math.floor(min_x), math.floor(min_y)
    return left, top, math.ceil(max_x) - left, math.ceil(max_y) - top


# MARK: - Asset catalog output

def reset(directory: Path) -> None:
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)


def write_json(path: Path, contents: dict) -> None:
    path.write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


DARK = [{"appearance": "luminosity", "value": "dark"}]


def write_vector_set(catalog: Path, name: str, light: str, dark: str) -> None:
    image_set = catalog / f"{name}.imageset"
    reset(image_set)
    images = [{"filename": f"{name}.svg", "idiom": "universal"}]
    (image_set / f"{name}.svg").write_text(light, encoding="utf-8")
    if dark != light:
        (image_set / f"{name}-Dark.svg").write_text(dark, encoding="utf-8")
        images.append({"appearances": DARK, "filename": f"{name}-Dark.svg", "idiom": "universal"})
    write_json(image_set / "Contents.json", {
        "images": images,
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"},
    })


def write_raster_set(catalog: Path, name: str, light: str, dark: str, resvg: str) -> None:
    image_set = catalog / f"{name}.imageset"
    reset(image_set)
    variants = [("", light, None)]
    if dark != light:
        variants.append(("-Dark", dark, DARK))

    images = []
    with tempfile.TemporaryDirectory() as scratch:
        for suffix, svg, appearances in variants:
            source = Path(scratch) / f"{name}{suffix}.svg"
            source.write_text(svg, encoding="utf-8")
            width_pt = float(re.search(r'width="([^"]+)"', svg).group(1))
            for scale in (2, 3):
                filename = f"{name}{suffix}@{scale}x.png"
                subprocess.run(
                    [resvg, "-w", str(round(width_pt * scale)), str(source), str(image_set / filename)],
                    check=True,
                )
                entry = {"filename": filename, "idiom": "universal", "scale": f"{scale}x"}
                if appearances:
                    entry["appearances"] = appearances
                images.append(entry)
    write_json(image_set / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def write_color_set(catalog: Path, name: str, light: str, dark: str) -> None:
    color_set = catalog / f"{name}.colorset"
    reset(color_set)

    def color(hex_value: str) -> dict:
        value = hex_value.lstrip("#")
        red, green, blue = (int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
        return {
            "color-space": "srgb",
            "components": {"alpha": "1.000", "red": f"{red:.3f}", "green": f"{green:.3f}", "blue": f"{blue:.3f}"},
        }

    write_json(color_set / "Contents.json", {
        "colors": [
            {"color": color(light), "idiom": "universal"},
            {"appearances": DARK, "color": color(dark), "idiom": "universal"},
        ],
        "info": {"author": "xcode", "version": 1},
    })


# MARK: - Generation

def generate(app: str, resvg: str) -> dict[str, float]:
    light = load_frame(DESIGN / f"{app}-Light.svg")
    dark_path = DESIGN / f"{app}-Dark.svg"
    dark = load_frame(dark_path) if dark_path.exists() else light
    catalog = FEATURES / app / "Branding" / "Assets.xcassets"
    if not catalog.is_dir():
        raise ValueError(f"No asset catalog for {app} at {catalog}")

    write_color_set(catalog, "LaunchBackground", light.background, dark.background)

    # Text stays vector, cropped to its own bounds.
    boxes = {}
    for name, attribute in (("LaunchWordmark", "wordmark"), ("LaunchSubtitle", "subtitle")):
        box = snapped_box(getattr(light, attribute))
        boxes[attribute] = box
        write_vector_set(
            catalog, name,
            svg_document(box, [getattr(light, attribute)], None),
            svg_document(box, [getattr(dark, attribute)], None),
        )

    # The medallion layers share one canvas, so stacking the base and the glyph
    # reproduces the composed medallion exactly.
    cx, cy = float(light.circle.get("cx")), float(light.circle.get("cy"))
    half = MEDALLION_CANVAS / 2
    canvas = (cx - half, cy - half, MEDALLION_CANVAS, MEDALLION_CANVAS)
    layers = {
        "LaunchMedallion": lambda frame: [frame.medallion, frame.glyph],
        "SplashMedallionBase": lambda frame: [frame.medallion],
        "SplashMedallionGlyph": lambda frame: [frame.glyph],
    }
    for name, pick in layers.items():
        write_raster_set(
            catalog, name,
            svg_document(canvas, pick(light), light.defs),
            svg_document(canvas, pick(dark), dark.defs),
            resvg,
        )

    for name, attribute, top in (("ArcRight", "arc_right", ARC_RIGHT_TOP), ("ArcLeft", "arc_left", ARC_LEFT_TOP)):
        box = (0, top, FRAME_WIDTH, FRAME_BOTTOM - top)
        write_raster_set(
            catalog, name,
            svg_document(box, [getattr(light, attribute)], light.defs),
            svg_document(box, [getattr(dark, attribute)], dark.defs),
            resvg,
        )

    wordmark, subtitle = boxes["wordmark"], boxes["subtitle"]
    print(f"Generated launch assets for {app}")
    return {
        "wordmark top (pt from the frame top)": wordmark[1] / FRAME_SCALE,
        "subtitle spacing (pt)": (subtitle[1] - wordmark[1] - wordmark[3]) / FRAME_SCALE,
        "medallion center offset from the frame center (pt)": (cy - FRAME_BOTTOM / 2) / FRAME_SCALE,
        "medallion diameter (pt)": 2 * float(light.circle.get("r")) / FRAME_SCALE,
        "medallion canvas (pt)": MEDALLION_CANVAS / FRAME_SCALE,
        "left arc height (pt)": (FRAME_BOTTOM - ARC_LEFT_TOP) / FRAME_SCALE,
        "right arc height (pt)": (FRAME_BOTTOM - ARC_RIGHT_TOP) / FRAME_SCALE,
    }


def main() -> int:
    resvg = os.environ.get("RESVG") or shutil.which("resvg")
    if resvg is None:
        print("resvg is required: brew install resvg (or set RESVG to its path)", file=sys.stderr)
        return 1

    apps = sorted(path.name.removesuffix("-Light.svg") for path in DESIGN.glob("*-Light.svg"))
    if not apps:
        print(f"No launch screen designs in {DESIGN}", file=sys.stderr)
        return 1

    layouts = {app: generate(app, resvg) for app in apps}

    print("\nLayout (shared by LaunchScreen.storyboard and LaunchBranding.Layout):")
    reference = layouts[apps[0]]
    for key, value in reference.items():
        print(f"  {key}: {fmt(value)}")
    for app, layout in layouts.items():
        mismatched = [key for key, value in layout.items() if abs(value - reference[key]) > 0.01]
        if mismatched:
            print(f"warning: {app} differs from {apps[0]} in {', '.join(mismatched)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
