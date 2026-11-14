# Hoe het werkt

[English](../en/HOW-IT-WORKS.md) · [Français](../fr/FONCTIONNEMENT.md) · **Nederlands** · [Deutsch](../de/FUNKTIONSWEISE.md)

## De cyclus

Zolang MouseMover loopt, telt een timer van één seconde het interval af (zichtbaar in de
menubalk). Bij nul speelt MouseMover **één patroon** af op het doelscherm en begint dan opnieuw
te tellen. *Nu uitvoeren* speelt meteen een cyclus zonder de aftelling te resetten.

Doelscherm: het scherm gekozen in *Scherm*, anders het hoofdscherm (*Hoofdscherm volgen*,
standaard; ook gebruikt als het gekozen scherm is losgekoppeld).

Muisgebeurtenissen worden verstuurd met `CGEvent` (`mouseMoved`, `leftMouseDown` /
`leftMouseUp`), wat de toestemming **Toegankelijkheid** vereist.

## Patronen

Een patroon is een geordende lijst punten. Elk punt is een stap:

1. **ga** naar het punt;
2. eventueel **wachten** (een willekeurige pauze tussen *Minstens* en *Hoogstens*);
3. eventueel **klikken**.

| Instelling | Betekenis |
|---|---|
| Positie | `x`, `y` van 0 tot 1, als fractie van het scherm; (0, 0) is linksboven |
| Referentie | *Op het scherm*: het hele scherm. *Rond de cursor*: (0,5; 0,5) is de cursorpositie bij het begin van de cyclus, de schaal blijft die van het scherm |
| Traject | *Vaste duur*: rechte lijn met constante snelheid. Anders willekeurig, zoals een hand: 1–4 px afwijking, 0,18–0,35 s, een willekeurige versnellingscurve |
| Willekeurige volgorde | schudt de punten bij elke cyclus, behalve de punten die hun *Plaats behouden* |

Elk doel blijft 80 px van de schermranden, en alle waarden worden bij het laden van een patroon
binnen veilige grenzen gehouden (maximaal 200 punten, bewegingen van 0,05–3 s, pauzes tot 5 s):
een slecht geschreven patroon kan de muis niet blokkeren.

### Ingebouwde patronen

| Patroon | Bewegingen |
|---|---|
| Klassiek | midden + klik, de vier hoeken in willekeurige volgorde, terug naar het midden |
| Discreet | een paar pixels rond de cursor, geen klik, terug naar de exacte positie |
| Cirkel | één cirkel rond het midden van het scherm, geen klik |
| Zigzag | een veeg van links naar rechts, geen klik |

Ingebouwde patronen zijn niet te bewerken: *Dupliceren om te bewerken* maakt een bewerkbare kopie.

### Welk patroon wordt afgespeeld

In *Patronen beheren…* (of het submenu *Patroon*): *Altijd hetzelfde*,
*Willekeurig uit aangevinkte* of *Om de beurt*.

## Patroneditor

- Klik in het kader om een punt toe te voegen, sleep om het te verplaatsen; de inspector
  bewerkt het geselecteerde punt.
- Overlappende punten: klikken op het geselecteerde punt van een stapel selecteert het
  volgende, en de pijlen van de inspector gaan van punt naar punt.
- *Testen* speelt het patroon meteen af.

### Een gebaar opnemen

*Gebaar opnemen* (5, 10 of 15 s): na een aftelling van 3 seconden bemonstert MouseMover de
cursor op 60 Hz en neemt linkerklikken op, tot de tijd om is of **Esc** wordt ingedrukt.
Klikken worden tijdens de opname echt uitgevoerd.

De monsters worden een patroon:

- de cursor geldt als stil onder 0,15 % van het scherm; een stop van 0,2 s of langer wordt een
  pauze; wachten vóór de eerste beweging en na de laatste wordt weggelaten;
- het traject wordt vereenvoudigd (Douglas-Peucker, tolerantie 0,4 %), met behoud van begin,
  einde, klikken en pauzes;
- elk punt behoudt zijn echte duur, zodat het afspelen hetzelfde ritme heeft.

## Fail-safe

Zoals in de vroegere Python-versie (pyautogui): als de cursor op **(0, 0)** staat — de
linkerbovenhoek van het hoofdscherm — vóór een beweging of klik, stopt de cyclus. MouseMover
blijft draaien en probeert het opnieuw bij het volgende interval.

## Opdrachten

MouseMover levert acties aan de app Opdrachten (App Intents): starten, stoppen, nu uitvoeren,
interval instellen, scherm kiezen en patroon kiezen. Hun titels volgen de macOS-taal; hun
antwoorden volgen de taal die in de app is gekozen.

## Openen bij inloggen

`SMAppService.mainApp` — alleen betrouwbaar als de app in `/Applications` staat. Als de
LaunchAgent van de vroegere Python-versie (`~/Library/LaunchAgents/com.pudeldoodle.mousemover.plist`)
bestaat, vervangt de geïnstalleerde app hem bij de eerste start door een native inlogonderdeel.

## Zelftest

Met de toestemming Toegankelijkheid kan de app een echte cyclus afspelen en een rapport schrijven:

```bash
/Applications/MouseMover.app/Contents/MacOS/MouseMover --self-test /tmp/report.json
```

Hij controleert dat de cursor echt in de buurt van de vier hoeken kwam en terug naar het midden ging.
