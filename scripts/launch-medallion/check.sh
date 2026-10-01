#!/bin/zsh
# Build-time check that an app's launch medallion assets match its app icon.
#
# Run by the "Check Launch Medallion" build phase:
#   zsh "$SRCROOT/scripts/launch-medallion/check.sh" <App>
#
# It only compares fingerprints; it never renders. When the icon, the launch
# background or the generator changed since the assets were generated, it warns.

set -euo pipefail

APP="$1"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
STAMP="$TOOLS/stamps/$APP.sha256"

current="$(zsh "$TOOLS/fingerprint.sh" "$APP")"
recorded="$(cat "$STAMP" 2>/dev/null || true)"

# The build phase declares this file as its output. It is written only while the
# assets are up to date, so Xcode skips the check until an input changes, but keeps
# running it, and warning, on every build while they are stale.
OUTPUT="${DERIVED_FILE_DIR:-}/launch-medallion-$APP.checked"

if [[ "$current" != "$recorded" ]]; then
  echo "warning: The launch medallion of $APP is out of date with its app icon. Run scripts/generate-launch-medallion.sh $APP and commit the result."
  if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then rm -f "$OUTPUT"; fi
elif [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
  mkdir -p "$DERIVED_FILE_DIR"
  print -r -- "$current" > "$OUTPUT"
fi
