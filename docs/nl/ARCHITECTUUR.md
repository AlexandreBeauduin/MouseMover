# Architectuur

[English](../en/ARCHITECTURE.md) · [Français](../fr/ARCHITECTURE.md) · **Nederlands** · [Deutsch](../de/ARCHITEKTUR.md)

```
project.yml                  XcodeGen-spec (macOS 14+, Swift 5-taalmodus, versie)
Config/Signing.xcconfig      standaard ad-hocondertekening; optioneel Config/Local.xcconfig (genegeerd)
Sources/
  MouseMoverCore/            framework: alle logica, testbaar zonder echte muis
    MouseMoverController     status in het menu, timer, acties, patronen, opslag
    ActivityCycle            speelt een patroon op een scherm (posities, menselijke bewegingen, fail-safe)
    MousePattern             patroonmodel, tolerante decodering, ingebouwde patronen
    GestureRecorder          opgenomen monsters → vereenvoudigd patroon
    MouseDriver              protocol MouseDriver + CGEvent-implementatie
    Easing                   versnellingscurves (gelijk aan pytweening)
    Display                  actieve schermen, grenzen, labels, doelscherm
    Config                   model en opslag van config.json
    LoginItem                SMAppService-wrapper + migratie van de Python-LaunchAgent
    AccessibilityPermission  AXIsProcessTrusted / prompt
    Localization             enum Language + L10n: alle zichtbare teksten (en, fr, nl, de)
    SelfTest                 echte cyclus + rapport (--self-test)
  MouseMover/                app (SwiftUI MenuBarExtra, LSUIElement)
    MouseMoverApp            startpunt, titel in de menubalk
    MenuContent              menu, meldingen
    PatternEditor            venster "Muispatronen" (AppKit-venster met SwiftUI)
    GestureCapture           gebaaropname + zwevende banner
    Intents                  App Intents: acties, entiteiten, App Shortcuts
    {fr,nl,de}.lproj         vertalingen van de App Intents-metadata
Tests/MouseMoverCoreTests/   XCTest-unittests met nepmuis, nepschermen, nepwillekeur
scripts/                     test.sh, build-app.sh [--install], verify_bundle.sh, release.sh, forget-build-copies.sh
.github/workflows/           ci.yml (tests + build bij elke push), release.yml (publicatie bij tag v*)
```

Bundle ID: `io.github.alexandrebeauduin.MouseMover`.

## Opslag

`~/Library/Application Support/MouseMover/config.json`

```json
{ "interval_seconds": 300, "launch_at_login": true, "display_id": null,
  "pattern_mode": "single", "selected_pattern_ids": ["builtin.classic"],
  "patterns": [{ "id": "…", "name": "Mijn patroon", "anchor": "screen", "shuffle": false,
                 "points": [{ "x": 0.5, "y": 0.5, "click": true, "pause_min": 0.1, "pause_max": 0.3 }] }] }
```

Alleen de patronen van de gebruiker worden opgeslagen; de ingebouwde staan in de code. Het
decoderen is tolerant: een ontbrekend veld krijgt zijn standaardwaarde, een ongeldig punt of
patroon wordt overgeslagen in plaats van het hele bestand te verliezen. De keuze van *Taal*
staat in `UserDefaults` (sleutel `language`).

## Stabiliteit van het menu

Een open SwiftUI-menu wordt opnieuw opgebouwd telkens de geobserveerde status verandert, wat
submenu's sluit. De aftelling zit daarom in een apart object dat alleen door de titel in de
menubalk wordt geobserveerd: de timer publiceert niets op de controller zolang de status niet
verandert.

## Lokalisatie

Alle zichtbare teksten staan in `Sources/MouseMoverCore/Localization.swift`, één aanroep
`t(en:fr:nl:de:)` per tekst: een ontbrekende vertaling is een compileerfout. De taal is de eerste
ondersteunde in `Locale.preferredLanguages` (standaard Engels), overschreven door het menu
*Taal* of door `MOUSEMOVER_LANG=en|fr|nl|de`.

App Intents-metadata (titels, parameters, App Shortcuts-zinnen) wordt bij het bouwen
geëxtraheerd en wordt daarom vertaald in `Sources/MouseMover/{fr,nl,de}.lproj/Localizable.strings`
en `AppShortcuts.strings`, met de Engelse teksten als sleutels.

Een taal toevoegen: een case in `Language`, een kolom in elke `t(...)`, en een map `.lproj`.

## Tests

`MouseMoverController` en `ActivityCycle` praten met macOS via protocollen (`MouseDriver`,
`DisplayProvider`, `LoginItemControlling`, `RandomSource`…). Tests injecteren nepversies, dus
`scripts/test.sh` controleert timing, patronen, opslag, vereenvoudiging van gebaren en
lokalisatie zonder de echte muis te bewegen. De echte muis wordt getest met `--self-test` en
met de hand.

## Ondertekening

Standaard ad hoc zodat iedereen kan bouwen. macOS koppelt de toestemming Toegankelijkheid aan
de handtekening: met ad hoc moet je ze na elke nieuwe build opnieuw geven. Een persoonlijk
certificaat in `Config/Local.xcconfig` voorkomt dat tijdens de ontwikkeling.

## Release

1. Verhoog `MARKETING_VERSION` in `project.yml`.
2. Voeg een sectie `## [x.y.z] - datum` toe aan `CHANGELOG.md` (gebruikt als release notes).
3. `git tag vx.y.z && git push origin vx.y.z` → `release.yml` test, bouwt de universele zip en
   maakt de GitHub-release. De tag moet overeenkomen met de versie.
