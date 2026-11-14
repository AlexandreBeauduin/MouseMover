# Fonctionnement

[English](../en/HOW-IT-WORKS.md) · **Français** · [Nederlands](../nl/HOE-HET-WERKT.md) · [Deutsch](../de/FUNKTIONSWEISE.md)

## Le cycle

Quand MouseMover tourne, un minuteur d'une seconde décompte l'intervalle (affiché dans la barre
des menus). À zéro, MouseMover joue **un motif** sur l'écran cible, puis recommence à compter.
*Exécuter maintenant* joue un cycle tout de suite sans remettre le compte à rebours à zéro.

Écran cible : celui choisi dans *Écran*, sinon l'écran principal (*Suivre l'écran principal*,
par défaut ; utilisé aussi si l'écran choisi a été débranché).

Les événements souris sont envoyés avec `CGEvent` (`mouseMoved`, `leftMouseDown` /
`leftMouseUp`), ce qui demande l'autorisation **Accessibilité**.

## Les motifs

Un motif est une liste ordonnée de points. Chaque point est une étape :

1. **aller** au point ;
2. éventuellement **attendre** (une pause aléatoire entre *Au moins* et *Au plus*) ;
3. éventuellement **cliquer**.

| Réglage | Signification |
|---|---|
| Position | `x`, `y` de 0 à 1, en fraction de l'écran ; (0, 0) est en haut à gauche |
| Repère | *Sur l'écran* : tout l'écran. *Autour du curseur* : (0,5 ; 0,5) est la position du curseur au début du cycle, l'échelle reste celle de l'écran |
| Trajet | *Durée imposée* : ligne droite à vitesse constante. Sinon aléatoire, comme une main : un décalage de 1 à 4 px, 0,18 à 0,35 s, une courbe d'accélération au hasard |
| Ordre aléatoire | mélange les points à chaque cycle, sauf ceux qui *Gardent leur place* |

Chaque cible reste à 80 px des bords de l'écran, et toutes les valeurs sont ramenées dans des
bornes sûres au chargement d'un motif (200 points maximum, déplacements de 0,05 à 3 s, pauses
jusqu'à 5 s) : un motif mal écrit ne peut pas bloquer la souris.

### Motifs intégrés

| Motif | Mouvements |
|---|---|
| Classique | centre + clic, les quatre coins dans un ordre aléatoire, retour au centre |
| Discret | quelques pixels autour du curseur, sans clic, retour à la position exacte |
| Cercle | un cercle autour du centre de l'écran, sans clic |
| Zigzag | un balayage de gauche à droite, sans clic |

Les motifs intégrés ne se modifient pas : *Dupliquer pour modifier* en fait une copie éditable.

### Quel motif est joué

Dans *Gérer les motifs…* (ou le sous-menu *Motif*) : *Toujours le même*,
*Au hasard parmi les cochés* ou *Chacun son tour*.

## L'éditeur de motifs

- Clique dans le cadre pour ajouter un point, fais-le glisser pour le déplacer ; l'inspecteur
  modifie le point sélectionné.
- Points superposés : cliquer sur le point sélectionné d'une pile sélectionne le suivant, et
  les flèches de l'inspecteur passent d'un point à l'autre.
- *Tester* joue le motif tout de suite.

### Capturer un geste

*Capturer un geste* (5, 10 ou 15 s) : après un compte à rebours de 3 secondes, MouseMover
échantillonne le curseur à 60 Hz et enregistre les clics gauches, jusqu'à la fin du temps ou un
appui sur **Échap**. Les clics sont réellement effectués pendant l'enregistrement.

Les échantillons deviennent un motif :

- le curseur est considéré immobile en dessous de 0,15 % de l'écran ; un arrêt de 0,2 s ou plus
  devient une pause ; l'attente avant le premier mouvement et après le dernier est ignorée ;
- le tracé est simplifié (Douglas-Peucker, tolérance 0,4 %), en gardant le départ, l'arrivée,
  les clics et les pauses ;
- chaque point garde sa durée réelle, pour que la relecture ait le même rythme.

## Failsafe

Comme dans l'ancienne version Python (pyautogui) : si le curseur est en **(0, 0)** — le coin en
haut à gauche de l'écran principal — avant un déplacement ou un clic, le cycle s'arrête.
MouseMover continue de tourner et réessaie à l'intervalle suivant.

## Raccourcis

MouseMover fournit des actions à l'app Raccourcis (App Intents) : démarrer, arrêter, exécuter
maintenant, régler l'intervalle, choisir l'écran et choisir le motif. Leurs titres suivent la
langue de macOS ; leurs réponses suivent la langue choisie dans l'app.

## Lancement au démarrage de session

`SMAppService.mainApp` — fiable seulement quand l'app est dans `/Applications`. Si le
LaunchAgent de l'ancienne version Python (`~/Library/LaunchAgents/com.pudeldoodle.mousemover.plist`)
existe, l'app installée le remplace par un élément de connexion natif au premier lancement.

## Auto-test

Avec l'autorisation Accessibilité, l'app peut jouer un vrai cycle et écrire un rapport :

```bash
/Applications/MouseMover.app/Contents/MacOS/MouseMover --self-test /tmp/report.json
```

Il vérifie que le curseur est vraiment passé près des quatre coins et revenu au centre.
