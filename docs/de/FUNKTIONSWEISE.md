# Funktionsweise

[English](../en/HOW-IT-WORKS.md) · [Français](../fr/FONCTIONNEMENT.md) · [Nederlands](../nl/HOE-HET-WERKT.md) · **Deutsch**

## Der Zyklus

Solange MouseMover läuft, zählt ein Sekunden-Timer das Intervall herunter (in der Menüleiste
angezeigt). Bei null spielt MouseMover **ein Muster** auf dem Zielbildschirm ab und beginnt
dann erneut zu zählen. *Jetzt ausführen* spielt sofort einen Zyklus, ohne den Countdown
zurückzusetzen.

Zielbildschirm: der unter *Bildschirm* gewählte, sonst der Hauptbildschirm (*Hauptbildschirm
folgen*, Standard; auch verwendet, wenn der gewählte Bildschirm getrennt wurde).

Mausereignisse werden mit `CGEvent` gesendet (`mouseMoved`, `leftMouseDown` / `leftMouseUp`),
was die Berechtigung **Bedienungshilfen** erfordert.

## Muster

Ein Muster ist eine geordnete Liste von Punkten. Jeder Punkt ist ein Schritt:

1. zum Punkt **gehen**;
2. optional **warten** (eine zufällige Pause zwischen *Mindestens* und *Höchstens*);
3. optional **klicken**.

| Einstellung | Bedeutung |
|---|---|
| Position | `x`, `y` von 0 bis 1, als Bruchteil des Bildschirms; (0, 0) ist oben links |
| Bezug | *Auf dem Bildschirm*: der ganze Bildschirm. *Um den Mauszeiger*: (0,5; 0,5) ist die Zeigerposition zu Beginn des Zyklus, der Maßstab bleibt der des Bildschirms |
| Bahn | *Feste Dauer*: gerade Linie mit konstanter Geschwindigkeit. Sonst zufällig, wie eine Hand: 1–4 px Versatz, 0,18–0,35 s, eine zufällige Beschleunigungskurve |
| Zufällige Reihenfolge | mischt die Punkte in jedem Zyklus, außer denen, die ihren *Platz behalten* |

Jedes Ziel bleibt 80 px von den Bildschirmrändern entfernt, und alle Werte werden beim Laden
eines Musters in sichere Grenzen gebracht (höchstens 200 Punkte, Bewegungen von 0,05–3 s,
Pausen bis 5 s): Ein schlecht geschriebenes Muster kann die Maus nicht blockieren.

### Integrierte Muster

| Muster | Bewegungen |
|---|---|
| Klassisch | Mitte + Klick, die vier Ecken in zufälliger Reihenfolge, zurück zur Mitte |
| Dezent | ein paar Pixel um den Mauszeiger, kein Klick, zurück zur exakten Position |
| Kreis | ein Kreis um die Bildschirmmitte, kein Klick |
| Zickzack | ein Schwenk von links nach rechts, kein Klick |

Integrierte Muster sind nicht bearbeitbar: *Zum Bearbeiten duplizieren* erstellt eine
bearbeitbare Kopie.

### Welches Muster abgespielt wird

In *Muster verwalten…* (oder im Untermenü *Muster*): *Immer dasselbe*,
*Zufällig unter den markierten* oder *Der Reihe nach*.

## Mustereditor

- Klicke in den Rahmen, um einen Punkt hinzuzufügen, ziehe ihn, um ihn zu verschieben; der
  Inspektor bearbeitet den ausgewählten Punkt.
- Überlappende Punkte: Ein Klick auf den ausgewählten Punkt eines Stapels wählt den nächsten,
  und die Pfeile des Inspektors springen von Punkt zu Punkt.
- *Testen* spielt das Muster sofort ab.

### Eine Geste aufzeichnen

*Geste aufzeichnen* (5, 10 oder 15 s): Nach einem 3-Sekunden-Countdown tastet MouseMover den
Mauszeiger mit 60 Hz ab und zeichnet Linksklicks auf, bis die Zeit abgelaufen ist oder **Esc**
gedrückt wird. Klicks werden während der Aufzeichnung wirklich ausgeführt.

Die Abtastwerte werden zu einem Muster:

- der Zeiger gilt unter 0,15 % des Bildschirms als still; ein Halt von 0,2 s oder mehr wird zu
  einer Pause; Warten vor der ersten und nach der letzten Bewegung wird verworfen;
- die Bahn wird vereinfacht (Douglas-Peucker, Toleranz 0,4 %), wobei Start, Ende, Klicks und
  Pausen erhalten bleiben;
- jeder Punkt behält seine echte Dauer, damit die Wiedergabe denselben Rhythmus hat.

## Fail-safe

Wie in der früheren Python-Version (pyautogui): Steht der Mauszeiger vor einer Bewegung oder
einem Klick auf **(0, 0)** — der oberen linken Ecke des Hauptbildschirms —, stoppt der Zyklus.
MouseMover läuft weiter und versucht es beim nächsten Intervall erneut.

## Kurzbefehle

MouseMover stellt der App Kurzbefehle Aktionen bereit (App Intents): starten, stoppen, jetzt
ausführen, Intervall festlegen, Bildschirm wählen und Muster wählen. Ihre Titel folgen der
macOS-Sprache; ihre Antworten folgen der in der App gewählten Sprache.

## Start bei der Anmeldung

`SMAppService.mainApp` — nur zuverlässig, wenn die App in `/Applications` liegt. Existiert der
LaunchAgent der früheren Python-Version (`~/Library/LaunchAgents/com.pudeldoodle.mousemover.plist`),
ersetzt ihn die installierte App beim ersten Start durch ein natives Anmeldeobjekt.

## Selbsttest

Mit der Berechtigung Bedienungshilfen kann die App einen echten Zyklus abspielen und einen
Bericht schreiben:

```bash
/Applications/MouseMover.app/Contents/MacOS/MouseMover --self-test /tmp/report.json
```

Er prüft, dass der Mauszeiger wirklich in die Nähe der vier Ecken und zurück zur Mitte kam.
