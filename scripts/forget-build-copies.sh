#!/bin/zsh
# Unregister the build copies of MouseMover.app from LaunchServices. Xcode registers every
# product it builds; with several copies registered, the Shortcuts app can list the
# MouseMover actions twice. Only /Applications/MouseMover.app should stay registered.
set -uo pipefail
cd "$(dirname "$0")/.."
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in build/DerivedData/Build/Products/*/MouseMover.app(N) build/MouseMover.app build/release/*/MouseMover.app(N); do
  [[ -d "$app" ]] && "$LSREGISTER" -u "$PWD/$app" >/dev/null 2>&1
done
exit 0
