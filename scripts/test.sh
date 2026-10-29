#!/bin/zsh
# Lance les tests unitaires (aucune souris reelle, aucun element de connexion reel).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project MouseMover.xcodeproj -scheme MouseMover -configuration Debug \
  -derivedDataPath build test 2>&1 | grep -E "error:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | sort -u
