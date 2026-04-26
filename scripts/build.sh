#!/usr/bin/env bash
#
# Build a Release Meter.app universal binary into ./dist/.
# Usage: scripts/build.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Meter.xcodeproj"
SCHEME="Meter"
CONFIG="Release"
ARCHIVE_PATH="./dist/Meter.xcarchive"
EXPORT_PATH="./dist"
EXPORT_OPTIONS="./dist/ExportOptions.plist"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

mkdir -p ./dist
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH/Meter.app"
xcodegen generate

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-"-"}" \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID:-}" \
  archive

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"
else
  echo "==> No Developer ID configured — copying ad-hoc-signed app from archive."
  cp -R "$ARCHIVE_PATH/Products/Applications/Meter.app" "$EXPORT_PATH/Meter.app"
fi

echo "Built: $EXPORT_PATH/Meter.app"
