# MouseMover

[![CI](https://github.com/AlexandreBeauduin/MouseMover/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexandreBeauduin/MouseMover/actions/workflows/ci.yml)

[English](README.md) · **Français** · [Nederlands](README.nl.md) · [Deutsch](README.de.md)

Petite app de barre des menus macOS qui déplace la souris à intervalle régulier, selon des
motifs que tu peux dessiner ou enregistrer toi-même, pour garder la session éveillée et ton
statut « actif ».

> **Vibe codé.** Ce projet a été réalisé en conversant avec un assistant de code IA
> (Claude Code) : l'humain a décrit ce qu'il voulait, testé sur son matériel et orienté ;
> l'IA a écrit le code et la doc. Ça marche sur la machine de l'auteur ; lis le code avant
> de t'y fier sur la tienne.

## Fonctionnalités

- **Démarrer / Arrêter**, **Exécuter maintenant**, compte à rebours jusqu'au prochain cycle
  dans la barre des menus.
- Intervalle : 1, 3, 5, 10, 15 minutes ou personnalisé.
- **Motifs** : quatre intégrés (*Classique*, *Discret*, *Cercle*, *Zigzag*) et les tiens :
  - dessinés point par point dans l'éditeur (clic, pause, trajet imposé ou « humain », ordre) ;
  - ou **capture d'un geste** : MouseMover enregistre tes vrais mouvements et clics ;
  - sur l'écran ou autour du curseur, dans l'ordre ou mélangés ;
  - toujours le même, un au hasard, ou chacun son tour.
- Choix de l'écran (suit l'écran principal par défaut), multi-écrans.
- **Failsafe** : souris dans le coin en haut à gauche de l'écran principal et le cycle s'arrête.
- Lancement au démarrage de session.
- Actions **Raccourcis** : démarrer, arrêter, exécuter maintenant, régler l'intervalle,
  choisir l'écran ou le motif.
- Interface en **anglais, français, néerlandais et allemand** : suit la langue de macOS, ou
  se choisit dans le menu (*Langue*).

## Installation

**Téléchargement :** récupère `MouseMover-x.y.z.zip` sur la page
[Releases](https://github.com/AlexandreBeauduin/MouseMover/releases), décompresse, déplace
`MouseMover.app` dans `/Applications`. Binaire universel (Apple Silicon + Intel), macOS 14+.

**Depuis les sources** (Xcode 16 ou plus récent, [XcodeGen](https://github.com/yonaskolb/XcodeGen)) :

```bash
brew install xcodegen
scripts/build-app.sh --install   # compile et copie MouseMover.app dans /Applications
```

Une copie téléchargée n'est pas signée avec un Developer ID : macOS la bloque au premier
lancement → Réglages Système › Confidentialité et sécurité › **Ouvrir quand même**.

### Autorisation Accessibilité

Déplacer la souris demande **Réglages Système › Confidentialité et sécurité › Accessibilité**.
MouseMover la demande au premier lancement ; le menu affiche *⚠︎ Autoriser l'Accessibilité…*
tant qu'elle manque.

macOS lie cette autorisation à la signature de l'app. Les versions publiées sont signées
ad hoc : après **chaque mise à jour**, retire MouseMover de la liste (−) et autorise-le à nouveau.

## Fonctionnement (en bref)

- À chaque intervalle, MouseMover joue un motif sur l'écran choisi avec `CGEvent`
  (déplacements avec courbes d'accélération, pauses aléatoires, clics éventuels).
- Un motif est une liste de points en fractions de l'écran (ou de la zone autour du
  curseur) ; un point sans durée imposée reçoit un trajet aléatoire, comme une main.
- Réglages et motifs : `~/Library/Application Support/MouseMover/config.json`.

Détails : [Fonctionnement](docs/fr/FONCTIONNEMENT.md) · [Architecture](docs/fr/ARCHITECTURE.md)

## Développement

```bash
scripts/test.sh            # tests unitaires — aucune vraie souris déplacée, aucun vrai élément de connexion
scripts/build-app.sh       # build Release universel dans build/MouseMover.app + vérifications
scripts/release.sh         # build + build/MouseMover-<version>.zip (+ .sha256)
```

Le projet Xcode est généré depuis `project.yml` par XcodeGen (non versionné). Les builds sont
signés ad hoc ; pour garder l'autorisation Accessibilité d'une compilation à l'autre, signe
avec ton certificat dans `Config/Local.xcconfig` (voir `Config/Signing.xcconfig`).

Publier une version : augmente `MARKETING_VERSION` dans `project.yml`, ajoute une section à
[CHANGELOG.md](CHANGELOG.md), puis pousse le tag correspondant
(`git tag v2.1.0 && git push origin v2.1.0`) : GitHub Actions teste, compile et publie la release.

## Limites

- Les clics sont de vrais clics : un motif qui clique peut agir sur ce qui se trouve sous le
  curseur. Le motif intégré *Classique* clique une fois au milieu de l'écran.
- Certaines apps ou politiques peuvent détecter l'inactivité autrement ; MouseMover ne fait
  que simuler la souris.

## Licence et avertissement

MIT — voir [LICENSE](LICENSE). Fourni **tel quel, sans aucune garantie**. Ce projet n'est ni
affilié à Apple ni approuvé par Apple. Vérifie les règles de ton employeur avant de l'utiliser
au travail.
