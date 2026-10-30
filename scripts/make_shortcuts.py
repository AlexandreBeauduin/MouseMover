#!/usr/bin/env python3
"""Genere des raccourcis Siri nommes (fichiers .shortcut signes) pour les intents MouseMover.

Siri interprete « MouseMover » comme une app a ouvrir ; un raccourci nomme est
declenche par son nom, sans ambiguite.
"""
import plistlib, subprocess, tempfile, uuid
from pathlib import Path

BUNDLE = "com.pudeldoodle.MouseMoverApp"
TEAM = "W9XG2WSXRL"
OUT = Path(__file__).parent / "shortcuts"

SHORTCUTS = [
    ("Souris active", "StartMouseMoverIntent"),
    ("Souris en pause", "StopMouseMoverIntent"),
    ("Souris maintenant", "RunNowIntent"),
]

def build(intent):
    action = {
        "WFWorkflowActionIdentifier": f"{BUNDLE}.{intent}",
        "WFWorkflowActionParameters": {
            "AppIntentDescriptor": {
                "TeamIdentifier": TEAM,
                "BundleIdentifier": BUNDLE,
                "Name": "MouseMover",
                "AppIntentIdentifier": intent,
            },
            "ShowWhenRun": False,
            "UUID": str(uuid.uuid4()).upper(),
        },
    }
    return {
        "WFWorkflowActions": [action],
        "WFWorkflowClientVersion": "1200",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionNumber": 900,
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowTypes": [],
    }

OUT.mkdir(exist_ok=True)
for name, intent in SHORTCUTS:
    signed = OUT / f"{name}.shortcut"
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "unsigned.shortcut"  # sign exige l'extension .shortcut
        raw.write_bytes(plistlib.dumps(build(intent), fmt=plistlib.FMT_BINARY))
        subprocess.run(["shortcuts", "sign", "-m", "anyone", "-i", str(raw), "-o", str(signed)], check=True)
    print("OK", signed)
