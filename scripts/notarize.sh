#!/usr/bin/env bash
#
# Codesign with hardened runtime, submit to Apple notary, and staple.
# Requires APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID, DEVELOPER_ID_APPLICATION.
#
# Usage: scripts/notarize.sh [path/to/Meter.app]
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${1:-./dist/Meter.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found. Run scripts/build.sh first." >&2
  exit 1
fi

REQUIRED=(APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID DEVELOPER_ID_APPLICATION)
for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var must be set (see .env.example)" >&2
    exit 1
  fi
done

ZIP_PATH="${APP_PATH%.app}-notarize.zip"

echo "==> Codesigning $APP_PATH"
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --deep "$APP_PATH"

codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> Zipping for notarytool submission"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to Apple notary service"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

echo "==> Stapling notarization"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -f "$ZIP_PATH"
echo "==> Notarized & stapled: $APP_PATH"
