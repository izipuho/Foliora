#!/usr/bin/env python3
"""Generates the launch medallion assets for every app from its icon sources.

The app icon (`Branding/AppIcon.icon`) is the single source of truth: its
`medallion.svg` and glyph SVG are combined into the image sets used by the
launch screen and the animated splash, so the two cannot drift apart again.

For each `Catalog/Features/<App>/Branding` folder that has an `AppIcon.icon`,
the script writes into that folder's `Assets.xcassets`:

- `LaunchMedallion`      – medallion and glyph together (launch storyboard)
- `SplashMedallionBase`  – medallion circle only (splash)
- `SplashMedallionGlyph` – glyph only (splash, animated separately)

All three share the same canvas, cropped to the medallion circle, so stacking
the base and the glyph reproduces `LaunchMedallion` exactly.

Usage: python3 scripts/generate-launch-assets.py   (from the repository root)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FEATURES = REPO_ROOT / "Catalog" / "Features"

# The icon canvas is 1024 x 1024 with the medallion circle of radius 400 at its center.
ICON_CANVAS = "0 0 1024 1024"
CROP_VIEWBOX = "112 112 800 800"
# Natural size in points; the launch storyboard and the splash both rely on it.
POINT_SIZE = 220

MEDALLION_FILE = "medallion.svg"


def svg_body(path: Path, id_prefix: str) -> str:
    """Returns the inner markup of an icon layer SVG with its ids made unique."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"<metadata>.*?</metadata>", "", text, flags=re.DOTALL)

    root = re.search(r"<svg\b[^>]*>", text)
    if root is None:
        raise ValueError(f"{path}: no <svg> root element")
    view_box = re.search(r'viewBox="([^"]+)"', root.group(0))
    if view_box is None or view_box.group(1).split() != ICON_CANVAS.split():
        raise ValueError(f"{path}: expected viewBox \"{ICON_CANVAS}\"")

    body = text[root.end():text.rindex("</svg>")].strip()
    body = re.sub(r'\bid="([^"]+)"', lambda m: f'id="{id_prefix}{m.group(1)}"', body)
    body = re.sub(r"url\(#([^)]+)\)", lambda m: f"url(#{id_prefix}{m.group(1)})", body)
    body = re.sub(r'href="#([^"]+)"', lambda m: f'href="#{id_prefix}{m.group(1)}"', body)
    return body


def wrap(*bodies: str) -> str:
    content = "\n".join(bodies)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{POINT_SIZE}" height="{POINT_SIZE}" viewBox="{CROP_VIEWBOX}">\n'
        f"{content}\n"
        "</svg>\n"
    )


def write_image_set(catalog: Path, name: str, svg: str) -> None:
    image_set = catalog / f"{name}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    for stale in image_set.iterdir():
        stale.unlink()

    (image_set / f"{name}.svg").write_text(svg, encoding="utf-8")
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "original",
        },
    }
    (image_set / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def glyph_file(icon: Path) -> str:
    """Finds the icon layer that is not the medallion."""
    manifest = json.loads((icon / "icon.json").read_text(encoding="utf-8"))
    names = [layer["image-name"] for group in manifest["groups"] for layer in group["layers"]]
    glyphs = [name for name in names if name != MEDALLION_FILE]
    if MEDALLION_FILE not in names or len(glyphs) != 1:
        raise ValueError(f"{icon}: expected {MEDALLION_FILE} and exactly one glyph layer, found {names}")
    return glyphs[0]


def generate(branding: Path) -> None:
    icon = branding / "AppIcon.icon"
    catalog = branding / "Assets.xcassets"
    layers = icon / "Assets"

    medallion = svg_body(layers / MEDALLION_FILE, "medallion-")
    glyph = svg_body(layers / glyph_file(icon), "glyph-")

    write_image_set(catalog, "LaunchMedallion", wrap(medallion, glyph))
    write_image_set(catalog, "SplashMedallionBase", wrap(medallion))
    write_image_set(catalog, "SplashMedallionGlyph", wrap(glyph))
    print(f"Generated launch assets for {branding.parent.name}")


def main() -> int:
    brandings = sorted(path.parent for path in FEATURES.glob("*/Branding/AppIcon.icon"))
    if not brandings:
        print("No Branding/AppIcon.icon folders found", file=sys.stderr)
        return 1
    for branding in brandings:
        generate(branding)
    return 0


if __name__ == "__main__":
    sys.exit(main())
