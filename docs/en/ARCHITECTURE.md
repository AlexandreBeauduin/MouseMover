# Architecture

**English** · [Français](../fr/ARCHITECTURE.md) · [Nederlands](../nl/ARCHITECTUUR.md) · [Deutsch](../de/ARCHITEKTUR.md)

```
project.yml                  XcodeGen spec (macOS 14+, Swift 5 language mode, version)
Config/Signing.xcconfig      ad-hoc signing by default; optional Config/Local.xcconfig (ignored)
Sources/
  MouseMoverCore/            framework: all logic, testable without a real mouse
    MouseMoverController     state shown in the menu, timer, actions, patterns, persistence
    ActivityCycle            plays a pattern on a display (positions, human-like moves, fail-safe)
    MousePattern             pattern model, tolerant decoding, built-in patterns
    GestureRecorder          recorded samples → simplified pattern
    MouseDriver              MouseDriver protocol + CGEvent implementation
    Easing                   easing curves (same as pytweening)
    Display                  active displays, bounds, labels, target display
    Config                   config.json model and store
    LoginItem                SMAppService wrapper + Python LaunchAgent migration
    AccessibilityPermission  AXIsProcessTrusted / prompt
    Localization             Language enum + L10n: every user-facing string (en, fr, nl, de)
    SelfTest                 real cycle + report (--self-test)
  MouseMover/                app (SwiftUI MenuBarExtra, LSUIElement)
    MouseMoverApp            entry point, menu bar title
    MenuContent              menu, alerts
    PatternEditor            "Mouse patterns" window (AppKit window hosting SwiftUI)
    GestureCapture           gesture recording + floating banner
    Intents                  App Intents: actions, entities, App Shortcuts
    {fr,nl,de}.lproj         translations of the App Intents metadata
Tests/MouseMoverCoreTests/   XCTest unit tests with a fake mouse, fake displays, fake randomness
scripts/                     test.sh, build-app.sh [--install], verify_bundle.sh, release.sh
.github/workflows/           ci.yml (test + build on push), release.yml (publish on tag v*)
```

Bundle ID: `io.github.alexandrebeauduin.MouseMover`.

## Persistence

`~/Library/Application Support/MouseMover/config.json`

```json
{ "interval_seconds": 300, "launch_at_login": true, "display_id": null,
  "pattern_mode": "single", "selected_pattern_ids": ["builtin.classic"],
  "patterns": [{ "id": "…", "name": "My pattern", "anchor": "screen", "shuffle": false,
                 "points": [{ "x": 0.5, "y": 0.5, "click": true, "pause_min": 0.1, "pause_max": 0.3 }] }] }
```

Only user patterns are saved; built-in ones live in the code. Decoding is tolerant: a
missing field gets its default, an invalid point or pattern is skipped instead of losing the
whole file. The *Language* choice is in `UserDefaults` (key `language`).

## Menu stability

An open SwiftUI menu is rebuilt each time the observed state changes, which closes submenus.
The countdown therefore lives in a separate object observed only by the menu bar title: the
timer publishes nothing on the controller while the state does not change.

## Localization

All user-facing strings live in `Sources/MouseMoverCore/Localization.swift`, one
`t(en:fr:nl:de:)` call per string, so a missing translation is a compile error. The language
is the first supported one in `Locale.preferredLanguages` (fallback English), overridden by
the *Language* menu or by `MOUSEMOVER_LANG=en|fr|nl|de`.

App Intents metadata (titles, parameters, App Shortcuts phrases) is extracted at build time,
so it is translated in `Sources/MouseMover/{fr,nl,de}.lproj/Localizable.strings` and
`AppShortcuts.strings` instead, keyed by the English source strings.

To add a language: add a `Language` case, a column to every `t(...)`, and a `.lproj` folder.

## Tests

`MouseMoverController` and `ActivityCycle` talk to macOS through protocols (`MouseDriver`,
`DisplayProvider`, `LoginItemControlling`, `RandomSource`…). Tests inject fakes, so
`scripts/test.sh` checks timing, patterns, persistence, gesture simplification and
localization without moving the real mouse. The real mouse is tested with `--self-test` and
by hand.

## Signing

Ad hoc by default so that anyone can build. macOS ties the Accessibility permission to the
signature: with ad-hoc signing it must be granted again after each rebuild. A personal
certificate in `Config/Local.xcconfig` avoids that during development.

## Release

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Add a `## [x.y.z] - date` section to `CHANGELOG.md` (used as release notes).
3. `git tag vx.y.z && git push origin vx.y.z` → `release.yml` tests, builds the universal
   zip and creates the GitHub release. The tag must match the version.
