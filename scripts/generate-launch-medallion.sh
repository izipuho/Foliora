#!/bin/zsh
# Generates the launch medallion assets of every app from its app icon, with the
# icon's Liquid Glass, by rendering the icon through Icon Composer's ictool.
#
# For each Catalog/Features/<App>/Branding that has an AppIcon.icon, it renders the
# medallion and the glyph separately on black and on white (to cut them out with
# their transparency), and the whole icon on the light and dark LaunchBackground
# (the reference they must add up to). scripts/launch-medallion/Process.swift then
# writes into that app's Assets.xcassets:
#
#   SplashMedallionBase   the medallion without the glyph
#   SplashMedallionGlyph  the glyph, swung by the splash
#   LaunchMedallion       both together, for LaunchScreen.storyboard
#
# each with light and dark variants, @2x/@3x, and an iPad @2x size.
#
# Finally it records a fingerprint of the sources in scripts/launch-medallion/stamps,
# which the build checks to warn when an icon changed and the assets did not.
#
# Usage, from anywhere:
#   zsh scripts/generate-launch-medallion.sh            # every app
#   zsh scripts/generate-launch-medallion.sh Bells      # one app
#
# Needs Xcode 26 (Icon Composer's ictool and swift). Set ICTOOL to override its path.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/scripts/launch-medallion"
cd "$ROOT"

ICTOOL="${ICTOOL:-}"
for candidate in \
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  "/Applications/Icon Composer.app/Contents/Executables/ictool" \
  "/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"; do
  [[ -z "$ICTOOL" && -x "$candidate" ]] && ICTOOL="$candidate"
done
[[ -n "$ICTOOL" ]] || { echo "Icon Composer's ictool not found; set ICTOOL to its path" >&2; exit 1; }

if (( $# > 0 )); then
  APPS=("$@")
else
  APPS=()
  for icon in Catalog/Features/*/Branding/AppIcon.icon(N); do
    APPS+=("${${icon#Catalog/Features/}%%/*}")
  done
fi
(( ${#APPS} > 0 )) || { echo "No Catalog/Features/*/Branding/AppIcon.icon found" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Built once with optimizations: the script interpreter would be far slower on the pixel loops.
xcrun swiftc -O -o "$WORK/process" "$TOOLS/Process.swift"

# Writes a copy of the icon with a solid background and, optionally, a hidden layer group.
# $1: destination .icon, $2: source .icon, $3: background "r,g,b" in 0...1,
# $4: which group to hide: "glyph", "medallion" or "".
prepare_icon() {
  rm -rf "$1"
  cp -R "$2" "$1"
  python3 - "$1/icon.json" "$3" "$4" <<'EOF'
import json, sys
path, color, hide = sys.argv[1], sys.argv[2], sys.argv[3]
r, g, b = (float(c) for c in color.split(","))
manifest = json.load(open(path))
manifest.pop("fill", None)
manifest["fill-specializations"] = [{"value": {"solid": f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"}}]

def is_medallion(group):
    return any(layer.get("image-name") == "medallion.svg" for layer in group.get("layers", []))

medallions = [group for group in manifest["groups"] if is_medallion(group)]
if len(medallions) != 1 or len(manifest["groups"]) != 2:
    sys.exit(f"{path}: expected a medallion group and a glyph group")
for group in manifest["groups"]:
    if (hide == "medallion" and is_medallion(group)) or (hide == "glyph" and not is_medallion(group)):
        group["hidden"] = True
json.dump(manifest, open(path, "w"), indent=2)
EOF
}

# Prints the LaunchBackground color of an appearance as "r,g,b" in 0...1.
# $1: path to LaunchBackground.colorset/Contents.json, $2: "light" or "dark"
background() {
  python3 - "$1" "$2" <<'EOF'
import json, sys
path, appearance = sys.argv[1], sys.argv[2]
colors = json.load(open(path))["colors"]

def is_dark(entry):
    return any(a.get("value") == "dark" for a in entry.get("appearances", []))

matches = [c for c in colors if is_dark(c) == (appearance == "dark")] or colors
components = matches[0]["color"]["components"]

def value(text):
    text = str(text)
    number = int(text, 16) if text.lower().startswith("0x") else float(text)
    return number / 255 if number > 1 else number

print(",".join(f"{value(components[k]):.5f}" for k in ("red", "green", "blue")))
EOF
}

render() {
  "$ICTOOL" "$1" --export-image --output-file "$2" \
    --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
}

for APP in "${APPS[@]}"; do
  BRANDING="Catalog/Features/$APP/Branding"
  ICON="$BRANDING/AppIcon.icon"
  BACKGROUND="$BRANDING/Assets.xcassets/LaunchBackground.colorset/Contents.json"
  [[ -d "$ICON" ]] || { echo "No icon at $ICON" >&2; exit 1; }
  [[ -f "$BACKGROUND" ]] || { echo "No LaunchBackground color at $BACKGROUND" >&2; exit 1; }

  LIGHT=$(background "$BACKGROUND" light)
  DARK=$(background "$BACKGROUND" dark)
  RENDERS="$WORK/$APP"
  mkdir -p "$RENDERS"

  echo "Rendering $APP…"
  # The Dark rendition ignores the background fill, so everything renders as Default;
  # the medallion looks the same in both.
  for spec in "base-black:0,0,0:glyph" "base-white:1,1,1:glyph" \
              "glyph-black:0,0,0:medallion" "glyph-white:1,1,1:medallion" \
              "all-light:$LIGHT:" "all-dark:$DARK:"; do
    name="${spec%%:*}"; rest="${spec#*:}"; color="${rest%%:*}"; hide="${rest#*:}"
    prepare_icon "$WORK/AppIcon.icon" "$ICON" "$color" "$hide"
    render "$WORK/AppIcon.icon" "$RENDERS/$name.png"
  done

  "$WORK/process" "$RENDERS" "$BRANDING/Assets.xcassets" "$LIGHT" "$DARK"

  mkdir -p "$TOOLS/stamps"
  zsh "$TOOLS/fingerprint.sh" "$APP" > "$TOOLS/stamps/$APP.sha256"
  echo "Updated $APP"
done
