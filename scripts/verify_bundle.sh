#!/bin/zsh
# Check a built MouseMover.app: valid signature, universal binary, bundle ID and App Intents metadata
# (needed for the Shortcuts app actions).
set -euo pipefail
APP="${1:?usage: verify_bundle.sh /path/to/MouseMover.app}"

codesign --verify --deep --strict "$APP"
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$ID" == "io.github.alexandrebeauduin.MouseMover" ]] || { echo "Unexpected bundle ID: $ID" >&2; exit 1; }
for arch in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/MouseMover" -verify_arch "$arch" || { echo "Missing $arch slice" >&2; exit 1; }
done
codesign -dv "$APP" 2>&1 | grep -E "^Identifier=|^Signature=|^TeamIdentifier="

DATA="$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
[[ -f "$DATA" ]] || { echo "Metadata.appintents missing: Shortcuts will not see the actions" >&2; exit 1; }

python3 - "$DATA" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
actions = sorted(d["actions"])
expected = {"StartMouseMoverIntent", "StopMouseMoverIntent", "RunNowIntent",
            "SetIntervalIntent", "SetDisplayIntent", "SetPatternIntent"}
missing = expected - set(actions)
assert not missing, f"missing intents: {missing}"
assert {"DisplayEntity", "PatternEntity"} <= set(d["entities"]), "missing entities"
phrases = [p["key"] for s in d["autoShortcuts"] for p in s["phraseTemplates"]]
assert phrases, "no App Shortcuts phrases"
print("Intents:", ", ".join(actions))
print(f"App Shortcuts phrases: {len(phrases)}")
PY

for lang in fr nl de; do
  for table in Localizable AppShortcuts; do
    [[ -f "$APP/Contents/Resources/$lang.lproj/$table.strings" ]] || { echo "Missing $lang.lproj/$table.strings" >&2; exit 1; }
  done
done
