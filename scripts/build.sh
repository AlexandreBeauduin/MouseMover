#!/bin/zsh
# Compile l'app en Release, signee avec l'identite "Apple Development" du projet.
# Resultat : build/Build/Products/Release/MouseMover.app
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project MouseMover.xcodeproj -scheme MouseMover -configuration Release \
  -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
"$(dirname "$0")/verify_bundle.sh" build/Build/Products/Release/MouseMover.app
