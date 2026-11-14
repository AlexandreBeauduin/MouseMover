#!/bin/zsh
# Build MouseMover.app in Release into ./build (universal binary: Apple Silicon + Intel).
# Signed ad hoc unless Config/Local.xcconfig sets your own identity.
# Usage: scripts/build-app.sh [--install]   (--install copies the app to /Applications and opens it)
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project MouseMover.xcodeproj -scheme MouseMover -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  ONLY_ACTIVE_ARCH=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP=build/MouseMover.app
rm -rf "$APP"
ditto build/DerivedData/Build/Products/Release/MouseMover.app "$APP"
scripts/verify_bundle.sh "$APP"
echo "OK: $APP ($(lipo -archs "$APP/Contents/MacOS/MouseMover"))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MouseMover 2>/dev/null || true
  rm -rf /Applications/MouseMover.app
  ditto "$APP" /Applications/MouseMover.app
  open /Applications/MouseMover.app
  echo "Installed in /Applications/MouseMover.app"
fi
