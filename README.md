# MouseMover (Swift)

Application de barre de menus macOS qui déplace la souris à intervalle régulier, avec commandes Siri / Raccourcis (App Intents).
Réécriture native de la version Python (`../mouse_mover_app`), qui reste inchangée.

## Fonctions

- Démarrer / Arrêter, **Exécuter maintenant**
- Intervalle : 1, 3, 5, 10, 15 min ou personnalisé
- Choix de l'écran (auto = écran principal, multi-écrans, origines négatives gérées)
- Lancement à l'ouverture de session (`SMAppService`), migration de l'ancien LaunchAgent Python
- Failsafe réimplémenté : souris en (0, 0) ⇒ le cycle est abandonné sans arrêter l'app
- Siri / Raccourcis : *Démarre MouseMover*, *Arrête MouseMover*, *Exécute MouseMover maintenant*,
  *Utilise … pour MouseMover*, et l'action « Régler l'intervalle » dans Raccourcis

## Développement

```bash
brew install xcodegen
scripts/test.sh     # tests unitaires
scripts/build.sh    # build Release signé + vérification des métadonnées App Intents
```

Le projet Xcode est généré par `xcodegen` depuis `project.yml` (non versionné).
La signature utilise le certificat « Apple Development » local : l'autorisation Accessibilité
(Réglages Système ▸ Confidentialité) reste valable d'une compilation à l'autre.

Auto-test avec la vraie souris (Accessibilité requise) :

```bash
build/Build/Products/Release/MouseMover.app/Contents/MacOS/MouseMover --self-test /tmp/rapport.json
```
