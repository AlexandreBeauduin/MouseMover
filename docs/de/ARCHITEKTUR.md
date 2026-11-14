# Architektur

[English](../en/ARCHITECTURE.md) · [Français](../fr/ARCHITECTURE.md) · [Nederlands](../nl/ARCHITECTUUR.md) · **Deutsch**

```
project.yml                  XcodeGen-Spezifikation (macOS 14+, Swift-5-Sprachmodus, Version)
Config/Signing.xcconfig      standardmäßig Ad-hoc-Signatur; optional Config/Local.xcconfig (ignoriert)
Sources/
  MouseMoverCore/            Framework: die ganze Logik, ohne echte Maus testbar
    MouseMoverController     Zustand im Menü, Timer, Aktionen, Muster, Speicherung
    ActivityCycle            spielt ein Muster auf einem Bildschirm (Positionen, menschliche Bewegungen, Fail-safe)
    MousePattern             Mustermodell, tolerantes Dekodieren, integrierte Muster
    GestureRecorder          aufgezeichnete Abtastwerte → vereinfachtes Muster
    MouseDriver              Protokoll MouseDriver + CGEvent-Implementierung
    Easing                   Beschleunigungskurven (wie pytweening)
    Display                  aktive Bildschirme, Grenzen, Bezeichnungen, Zielbildschirm
    Config                   Modell und Speicher von config.json
    LoginItem                SMAppService-Wrapper + Migration des Python-LaunchAgents
    AccessibilityPermission  AXIsProcessTrusted / Abfrage
    Localization             Enum Language + L10n: alle sichtbaren Texte (en, fr, nl, de)
    SelfTest                 echter Zyklus + Bericht (--self-test)
  MouseMover/                App (SwiftUI MenuBarExtra, LSUIElement)
    MouseMoverApp            Einstiegspunkt, Titel in der Menüleiste
    MenuContent              Menü, Hinweise
    PatternEditor            Fenster „Mausmuster“ (AppKit-Fenster mit SwiftUI)
    GestureCapture           Gestenaufzeichnung + schwebendes Banner
    Intents                  App Intents: Aktionen, Entitäten, App Shortcuts
    {fr,nl,de}.lproj         Übersetzungen der App-Intents-Metadaten
Tests/MouseMoverCoreTests/   XCTest-Unit-Tests mit Fake-Maus, Fake-Bildschirmen, Fake-Zufall
scripts/                     test.sh, build-app.sh [--install], verify_bundle.sh, release.sh
.github/workflows/           ci.yml (Tests + Build bei jedem Push), release.yml (Veröffentlichung bei Tag v*)
```

Bundle ID: `io.github.alexandrebeauduin.MouseMover`.

## Speicherung

`~/Library/Application Support/MouseMover/config.json`

```json
{ "interval_seconds": 300, "launch_at_login": true, "display_id": null,
  "pattern_mode": "single", "selected_pattern_ids": ["builtin.classic"],
  "patterns": [{ "id": "…", "name": "Mein Muster", "anchor": "screen", "shuffle": false,
                 "points": [{ "x": 0.5, "y": 0.5, "click": true, "pause_min": 0.1, "pause_max": 0.3 }] }] }
```

Nur die Muster des Benutzers werden gespeichert; die integrierten stehen im Code. Das
Dekodieren ist tolerant: Ein fehlendes Feld erhält seinen Standardwert, ein ungültiger Punkt
oder ein ungültiges Muster wird übersprungen, statt die ganze Datei zu verlieren. Die Wahl der
*Sprache* liegt in `UserDefaults` (Schlüssel `language`).

## Menüstabilität

Ein geöffnetes SwiftUI-Menü wird bei jeder Änderung des beobachteten Zustands neu aufgebaut,
was Untermenüs schließt. Der Countdown lebt deshalb in einem eigenen Objekt, das nur der Titel
in der Menüleiste beobachtet: Der Timer veröffentlicht nichts auf dem Controller, solange sich
der Zustand nicht ändert.

## Lokalisierung

Alle sichtbaren Texte stehen in `Sources/MouseMoverCore/Localization.swift`, ein Aufruf
`t(en:fr:nl:de:)` pro Text: Eine fehlende Übersetzung ist ein Kompilierfehler. Die Sprache ist
die erste unterstützte in `Locale.preferredLanguages` (Standard Englisch), überschrieben durch
das Menü *Sprache* oder durch `MOUSEMOVER_LANG=en|fr|nl|de`.

App-Intents-Metadaten (Titel, Parameter, App-Shortcuts-Sätze) werden beim Build extrahiert und
deshalb in `Sources/MouseMover/{fr,nl,de}.lproj/Localizable.strings` und `AppShortcuts.strings`
übersetzt, mit den englischen Texten als Schlüssel.

Eine Sprache hinzufügen: ein Case in `Language`, eine Spalte in jedem `t(...)` und ein
`.lproj`-Ordner.

## Tests

`MouseMoverController` und `ActivityCycle` sprechen über Protokolle mit macOS (`MouseDriver`,
`DisplayProvider`, `LoginItemControlling`, `RandomSource`…). Tests injizieren Fakes, sodass
`scripts/test.sh` Timing, Muster, Speicherung, Gestenvereinfachung und Lokalisierung prüft,
ohne die echte Maus zu bewegen. Die echte Maus wird mit `--self-test` und von Hand getestet.

## Signatur

Standardmäßig ad hoc, damit jeder bauen kann. macOS bindet die Berechtigung Bedienungshilfen an
die Signatur: Bei Ad-hoc-Signatur muss sie nach jedem Build erneut erteilt werden. Ein
persönliches Zertifikat in `Config/Local.xcconfig` vermeidet das während der Entwicklung.

## Release

1. Erhöhe `MARKETING_VERSION` in `project.yml`.
2. Füge einen Abschnitt `## [x.y.z] - Datum` zu `CHANGELOG.md` hinzu (als Release Notes verwendet).
3. `git tag vx.y.z && git push origin vx.y.z` → `release.yml` testet, baut das universelle Zip
   und erstellt das GitHub-Release. Das Tag muss zur Version passen.
