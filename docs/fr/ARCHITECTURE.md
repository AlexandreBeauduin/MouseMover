# Architecture

[English](../en/ARCHITECTURE.md) · **Français** · [Nederlands](../nl/ARCHITECTUUR.md) · [Deutsch](../de/ARCHITEKTUR.md)

```
project.yml                  spec XcodeGen (macOS 14+, mode de langage Swift 5, version)
Config/Signing.xcconfig      signature ad hoc par défaut ; Config/Local.xcconfig optionnel (ignoré)
Sources/
  MouseMoverCore/            framework : toute la logique, testable sans vraie souris
    MouseMoverController     état affiché dans le menu, minuteur, actions, motifs, persistance
    ActivityCycle            joue un motif sur un écran (positions, mouvements humains, failsafe)
    MousePattern             modèle de motif, décodage tolérant, motifs intégrés
    GestureRecorder          échantillons enregistrés → motif simplifié
    MouseDriver              protocole MouseDriver + implémentation CGEvent
    Easing                   courbes d'accélération (identiques à pytweening)
    Display                  écrans actifs, limites, libellés, écran cible
    Config                   modèle et stockage de config.json
    LoginItem                enveloppe SMAppService + migration du LaunchAgent Python
    AccessibilityPermission  AXIsProcessTrusted / invite
    Localization             enum Language + L10n : tous les textes affichés (en, fr, nl, de)
    SelfTest                 vrai cycle + rapport (--self-test)
  MouseMover/                app (SwiftUI MenuBarExtra, LSUIElement)
    MouseMoverApp            point d'entrée, titre dans la barre des menus
    MenuContent              menu, alertes
    PatternEditor            fenêtre « Motifs de souris » (fenêtre AppKit hébergeant du SwiftUI)
    GestureCapture           enregistrement de geste + bandeau flottant
    Intents                  App Intents : actions, entités, App Shortcuts
    {fr,nl,de}.lproj         traductions des métadonnées App Intents
Tests/MouseMoverCoreTests/   tests unitaires XCTest avec fausse souris, faux écrans, faux hasard
scripts/                     test.sh, build-app.sh [--install], verify_bundle.sh, release.sh, forget-build-copies.sh
.github/workflows/           ci.yml (tests + build à chaque push), release.yml (publication sur tag v*)
```

Bundle ID : `io.github.alexandrebeauduin.MouseMover`.

## Persistance

`~/Library/Application Support/MouseMover/config.json`

```json
{ "interval_seconds": 300, "launch_at_login": true, "display_id": null,
  "pattern_mode": "single", "selected_pattern_ids": ["builtin.classic"],
  "patterns": [{ "id": "…", "name": "Mon motif", "anchor": "screen", "shuffle": false,
                 "points": [{ "x": 0.5, "y": 0.5, "click": true, "pause_min": 0.1, "pause_max": 0.3 }] }] }
```

Seuls les motifs de l'utilisateur sont enregistrés ; les intégrés vivent dans le code. Le
décodage est tolérant : un champ manquant prend sa valeur par défaut, un point ou un motif
invalide est ignoré au lieu de perdre tout le fichier. Le choix de *Langue* est dans
`UserDefaults` (clé `language`).

## Stabilité du menu

Un menu SwiftUI ouvert est reconstruit à chaque changement de l'état observé, ce qui ferme les
sous-menus. Le compte à rebours vit donc dans un objet séparé, observé seulement par le titre de
la barre des menus : le minuteur ne publie rien sur le contrôleur tant que l'état ne change pas.

## Localisation

Tous les textes affichés sont dans `Sources/MouseMoverCore/Localization.swift`, un appel
`t(en:fr:nl:de:)` par texte : une traduction manquante est une erreur de compilation. La langue
est la première prise en charge dans `Locale.preferredLanguages` (anglais par défaut), remplacée
par le menu *Langue* ou par `MOUSEMOVER_LANG=en|fr|nl|de`.

Les métadonnées App Intents (titres, paramètres, phrases App Shortcuts) sont extraites à la
compilation : elles sont donc traduites dans `Sources/MouseMover/{fr,nl,de}.lproj/Localizable.strings`
et `AppShortcuts.strings`, avec les textes anglais comme clés.

Ajouter une langue : un cas à `Language`, une colonne à chaque `t(...)`, et un dossier `.lproj`.

## Tests

`MouseMoverController` et `ActivityCycle` parlent à macOS via des protocoles (`MouseDriver`,
`DisplayProvider`, `LoginItemControlling`, `RandomSource`…). Les tests injectent des faux, donc
`scripts/test.sh` vérifie le minutage, les motifs, la persistance, la simplification des gestes
et la localisation sans bouger la vraie souris. La vraie souris se teste avec `--self-test` et
à la main.

## Signature

Ad hoc par défaut pour que tout le monde puisse compiler. macOS lie l'autorisation
Accessibilité à la signature : en ad hoc, il faut la redonner après chaque recompilation. Un
certificat personnel dans `Config/Local.xcconfig` évite ça pendant le développement.

## Publication

1. Augmente `MARKETING_VERSION` dans `project.yml`.
2. Ajoute une section `## [x.y.z] - date` à `CHANGELOG.md` (utilisée comme notes de version).
3. `git tag vx.y.z && git push origin vx.y.z` → `release.yml` teste, construit le zip universel
   et crée la release GitHub. Le tag doit correspondre à la version.
