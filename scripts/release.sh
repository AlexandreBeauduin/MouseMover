#!/bin/zsh
# Build and package a release zip: build/MouseMover-<version>.zip
# (MouseMover.app + READMEs + LICENSE). The version comes from MARKETING_VERSION in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' project.yml | head -1)"
if [[ -z "$VERSION" ]]; then
  echo "MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi
if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" != "v${VERSION}" ]]; then
  echo "Tag ${GITHUB_REF_NAME} does not match project.yml version ${VERSION}" >&2
  exit 1
fi

scripts/build-app.sh

BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/MouseMover.app/Contents/Info.plist)"
if [[ "$BUILT" != "$VERSION" ]]; then
  echo "Built app version ${BUILT} does not match ${VERSION}" >&2
  exit 1
fi

STAGE=build/release/MouseMover-${VERSION}
rm -rf build/release && mkdir -p "$STAGE"
cp -R build/MouseMover.app README.md README.fr.md README.nl.md README.de.md LICENSE "$STAGE/"
ZIP=build/MouseMover-${VERSION}.zip
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$STAGE" "$ZIP"
(cd "$(dirname "$ZIP")" && shasum -a 256 "$(basename "$ZIP")") | tee "$ZIP.sha256"
echo "OK: $ZIP"
