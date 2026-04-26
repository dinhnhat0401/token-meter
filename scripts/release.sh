#!/usr/bin/env bash
#
# Package the notarized Meter.app into a DMG, compute its SHA256,
# and emit the version + sha256 lines to paste into the cask.
#
# Usage: scripts/release.sh [version]
# (version defaults to MARKETING_VERSION baked into project.yml)
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="./dist/Meter.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found. Run scripts/build.sh && scripts/notarize.sh first." >&2
  exit 1
fi

VERSION="${1:-$(grep -E 'MARKETING_VERSION:' project.yml | head -1 | awk -F'"' '{print $2}')}"
if [[ -z "$VERSION" ]]; then
  echo "error: could not determine VERSION" >&2
  exit 1
fi

DMG_PATH="./dist/Meter-${VERSION}.dmg"
STAGE_DIR="./dist/dmg-stage"

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Meter ${VERSION}" \
    --window-pos 200 120 \
    --window-size 540 320 \
    --icon-size 96 \
    --icon "Meter.app" 140 160 \
    --hide-extension "Meter.app" \
    --app-drop-link 400 160 \
    "$DMG_PATH" \
    "$STAGE_DIR/" || true
fi

# Fallback: use hdiutil if create-dmg isn't available or failed.
if [[ ! -f "$DMG_PATH" ]]; then
  hdiutil create -volname "Meter ${VERSION}" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"
fi

rm -rf "$STAGE_DIR"

SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

cat <<EOF

==> Built: $DMG_PATH
==> SHA-256: $SHA

Paste into Casks/meter.rb:

  version "$VERSION"
  sha256 "$SHA"

EOF
