#!/bin/bash
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/RunPulse.app"

"$REPO/scripts/package-app.sh" 0.0.0-dev

echo "Stopping running instance..."
pkill -x RunPulse 2>/dev/null || true
sleep 0.5

echo "Installing..."
rm -rf "$APP"
cp -R "$REPO/.build/package/RunPulse.app" "$APP"

echo "Re-signing..."
codesign --remove-signature "$APP"
codesign -s - "$APP"

echo "Launching..."
open "$APP"

echo "Done."
