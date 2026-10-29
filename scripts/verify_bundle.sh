#!/bin/zsh
# Verifie la signature du bundle et la presence des metadonnees App Intents (Siri / Raccourcis).
set -euo pipefail
APP="${1:?usage: verify_bundle.sh /chemin/MouseMover.app}"

codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^Identifier=|^TeamIdentifier="

DATA="$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
[[ -f "$DATA" ]] || { echo "Metadata.appintents manquant : Siri ne verra pas les commandes" >&2; exit 1; }

python3 - "$DATA" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
actions = sorted(d["actions"])
expected = {"StartMouseMoverIntent", "StopMouseMoverIntent", "RunNowIntent", "SetIntervalIntent", "SetDisplayIntent"}
missing = expected - set(actions)
assert not missing, f"intents manquants : {missing}"
assert "DisplayEntity" in d["entities"], "entite Ecran manquante"
phrases = [p["key"] for s in d["autoShortcuts"] for p in s["phraseTemplates"]]
assert phrases, "aucune phrase Siri"
print("Intents :", ", ".join(actions))
print(f"Phrases Siri : {len(phrases)}")
PY
