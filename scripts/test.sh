#!/bin/zsh
# Run the unit tests (no real mouse, no real login item).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project MouseMover.xcodeproj -scheme MouseMover -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test 2>&1 \
  | grep -E "error:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | sort -u
scripts/forget-build-copies.sh
