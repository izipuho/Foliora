#!/bin/zsh
# Prints a fingerprint of everything the launch medallion assets of an app are made
# from: its app icon, its LaunchBackground color and the generator itself.
#
# Usage: zsh scripts/launch-medallion/fingerprint.sh <App>
#
# scripts/generate-launch-medallion.sh stores it in stamps/<App>.sha256;
# check.sh compares it at build time.

set -euo pipefail

APP="$1"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TOOLS/../.." && pwd)"
BRANDING="Catalog/Features/$APP/Branding"

cd "$ROOT"
{
  for file in \
    $BRANDING/AppIcon.icon/**/*(.N) \
    $BRANDING/Assets.xcassets/LaunchBackground.colorset/Contents.json \
    scripts/generate-launch-medallion.sh \
    scripts/launch-medallion/Process.swift; do
    # Skip Finder metadata such as .DS_Store.
    [[ "${file:t}" == .* ]] && continue
    print -r -- "$(shasum -a 256 < "$file" | cut -d' ' -f1)  $file"
  done
} | LC_ALL=C sort -k2 | shasum -a 256 | cut -d' ' -f1
