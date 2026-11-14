import Foundation

/// Supported UI languages. English is the fallback.
public enum Language: String, CaseIterable, Sendable {
    case en, fr, nl, de

    /// Name of the language in itself (for the language picker).
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .nl: return "Nederlands"
        case .de: return "Deutsch"
        }
    }

    /// First supported language in the given preference list (e.g. Locale.preferredLanguages).
    public static func preferred(from identifiers: [String]) -> Language {
        for identifier in identifiers {
            let code = String(identifier.prefix { $0 != "-" && $0 != "_" }).lowercased()
            if let language = Language(rawValue: code) { return language }
        }
        return .en
    }
}

/// All user-facing strings, in one place.
/// To add a language: add a case to `Language`, then a column to every `t(...)` call
/// (the compiler lists the missing ones). App Intents metadata (Shortcuts titles, Siri phrases)
/// lives in `Sources/MouseMover/*.lproj` instead, because it is extracted at build time.
public enum L10n {
    /// Override with `MOUSEMOVER_LANG=fr` or the app's Language menu.
    public static var language: Language = automaticLanguage

    /// `MOUSEMOVER_LANG`, else the first supported system language, else English.
    public static var automaticLanguage: Language {
        if let env = ProcessInfo.processInfo.environment["MOUSEMOVER_LANG"],
           let language = Language(rawValue: env.lowercased()) {
            return language
        }
        return Language.preferred(from: Locale.preferredLanguages)
    }

    /// Applies a Language menu choice: a `Language` raw value, or "" to follow the system.
    public static func apply(choice: String) {
        language = Language(rawValue: choice) ?? automaticLanguage
    }

    /// Locale matching `language`, for number and list formatting.
    public static var locale: Locale { Locale(identifier: language.rawValue) }

    static func t(en: String, fr: String, nl: String, de: String) -> String {
        switch language {
        case .en: return en
        case .fr: return fr
        case .nl: return nl
        case .de: return de
        }
    }

    // MARK: - Menu bar

    public static var paused: String { t(en: "pause", fr: "pause", nl: "pauze", de: "Pause") }
    public static var start: String { t(en: "Start", fr: "Démarrer", nl: "Starten", de: "Starten") }
    public static var stop: String { t(en: "Stop", fr: "Arrêter", nl: "Stoppen", de: "Stoppen") }
    public static var runNow: String { t(en: "Run now", fr: "Exécuter maintenant", nl: "Nu uitvoeren", de: "Jetzt ausführen") }
    public static var interval: String { t(en: "Interval", fr: "Intervalle", nl: "Interval", de: "Intervall") }
    public static var customInterval: String { t(en: "Custom…", fr: "Personnalisé…", nl: "Aangepast…", de: "Eigener Wert…") }
    public static func minutesShort(_ minutes: Int) -> String { "\(minutes) min" }
    public static var managePatterns: String {
        t(en: "Manage patterns…", fr: "Gérer les motifs…", nl: "Patronen beheren…", de: "Muster verwalten…")
    }
    public static var display: String { t(en: "Display", fr: "Écran", nl: "Scherm", de: "Bildschirm") }
    public static var followMainDisplay: String {
        t(en: "Follow main display (auto)", fr: "Suivre l'écran principal (auto)",
          nl: "Hoofdscherm volgen (auto)", de: "Hauptbildschirm folgen (auto)")
    }
    public static var refreshDisplays: String {
        t(en: "Refresh display list", fr: "Actualiser la liste des écrans",
          nl: "Schermlijst vernieuwen", de: "Bildschirmliste aktualisieren")
    }
    public static var launchAtLogin: String {
        t(en: "Launch at login", fr: "Lancer au démarrage de session",
          nl: "Openen bij inloggen", de: "Bei der Anmeldung starten")
    }
    public static var openAccessibilitySettings: String {
        t(en: "Open Accessibility Settings…", fr: "Ouvrir Réglages Accessibilité…",
          nl: "Toegankelijkheidsinstellingen openen…", de: "Bedienungshilfen-Einstellungen öffnen…")
    }
    public static var allowAccessibility: String {
        t(en: "⚠︎ Allow Accessibility…", fr: "⚠︎ Autoriser l'Accessibilité…",
          nl: "⚠︎ Toegankelijkheid toestaan…", de: "⚠︎ Bedienungshilfen erlauben…")
    }
    public static var languageMenu: String { t(en: "Language", fr: "Langue", nl: "Taal", de: "Sprache") }
    public static var systemLanguage: String { t(en: "System", fr: "Système", nl: "Systeem", de: "System") }
    public static var quit: String { t(en: "Quit", fr: "Quitter", nl: "Stoppen", de: "Beenden") }

    // MARK: - Pattern menu

    public static func patternMenuSingle(_ name: String) -> String {
        t(en: "Pattern: \(name)", fr: "Motif : \(name)", nl: "Patroon: \(name)", de: "Muster: \(name)")
    }
    public static func patternMenuRandom(_ count: Int) -> String {
        t(en: "Pattern: \(count) at random", fr: "Motif : \(count) au hasard",
          nl: "Patroon: \(count) willekeurig", de: "Muster: \(count) zufällig")
    }
    public static func patternMenuSequence(_ count: Int) -> String {
        t(en: "Pattern: \(count) in turn", fr: "Motif : \(count) chacun son tour",
          nl: "Patroon: \(count) om de beurt", de: "Muster: \(count) abwechselnd")
    }
    public static var modeSingle: String {
        t(en: "Always the same", fr: "Toujours le même", nl: "Altijd hetzelfde", de: "Immer dasselbe")
    }
    public static var modeRandom: String {
        t(en: "Random among checked", fr: "Au hasard parmi les cochés",
          nl: "Willekeurig uit aangevinkte", de: "Zufällig unter den markierten")
    }
    public static var modeSequence: String {
        t(en: "Each in turn", fr: "Chacun son tour", nl: "Om de beurt", de: "Der Reihe nach")
    }

    // MARK: - Alerts

    public static var ok: String { "OK" }
    public static var cancel: String { t(en: "Cancel", fr: "Annuler", nl: "Annuleren", de: "Abbrechen") }
    public static var customIntervalTitle: String {
        t(en: "Custom interval", fr: "Intervalle personnalisé", nl: "Aangepast interval", de: "Eigenes Intervall")
    }
    public static var customIntervalPrompt: String {
        t(en: "Minutes between two activities:", fr: "Durée en minutes entre deux activités :",
          nl: "Minuten tussen twee activiteiten:", de: "Minuten zwischen zwei Aktivitäten:")
    }
    public static var invalidValue: String {
        t(en: "Invalid value", fr: "Valeur invalide", nl: "Ongeldige waarde", de: "Ungültiger Wert")
    }
    public static var invalidMinutes: String {
        t(en: "Enter a number of minutes greater than 0.", fr: "Entre un nombre de minutes supérieur à 0.",
          nl: "Voer een aantal minuten groter dan 0 in.", de: "Gib eine Minutenzahl größer als 0 ein.")
    }
    public static var unavailable: String {
        t(en: "Unavailable", fr: "Indisponible", nl: "Niet beschikbaar", de: "Nicht verfügbar")
    }
    public static func launchAtLoginFailed(_ reason: String) -> String {
        t(en: "Could not change launch at login: \(reason)",
          fr: "Impossible de modifier le lancement au démarrage : \(reason)",
          nl: "Kan openen bij inloggen niet wijzigen: \(reason)",
          de: "Start bei der Anmeldung konnte nicht geändert werden: \(reason)")
    }

    // MARK: - Displays

    public static func displayLabel(index: Int, width: Int, height: Int, isMain: Bool) -> String {
        let base = t(en: "Display \(index)", fr: "Écran \(index)", nl: "Scherm \(index)", de: "Bildschirm \(index)")
            + " — \(width)x\(height)"
        guard isMain else { return base }
        return base + t(en: " (main)", fr: " (principal)", nl: " (hoofdscherm)", de: " (Hauptbildschirm)")
    }
    public static var mainDisplayAuto: String {
        t(en: "Main display (auto)", fr: "Écran principal (auto)", nl: "Hoofdscherm (auto)", de: "Hauptbildschirm (auto)")
    }

    // MARK: - Patterns

    public static var patternClassic: String { t(en: "Classic", fr: "Classique", nl: "Klassiek", de: "Klassisch") }
    public static var patternDiscreet: String { t(en: "Discreet", fr: "Discret", nl: "Discreet", de: "Dezent") }
    public static var patternCircle: String { t(en: "Circle", fr: "Cercle", nl: "Cirkel", de: "Kreis") }
    public static var patternZigzag: String { t(en: "Zigzag", fr: "Zigzag", nl: "Zigzag", de: "Zickzack") }
    public static var defaultPatternName: String { t(en: "Pattern", fr: "Motif", nl: "Patroon", de: "Muster") }
    public static var untitledPattern: String {
        t(en: "Untitled pattern", fr: "Motif sans nom", nl: "Naamloos patroon", de: "Unbenanntes Muster")
    }
    public static var newPattern: String { t(en: "New pattern", fr: "Nouveau motif", nl: "Nieuw patroon", de: "Neues Muster") }
    public static func copyName(_ name: String) -> String {
        t(en: "\(name) (copy)", fr: "\(name) (copie)", nl: "\(name) (kopie)", de: "\(name) (Kopie)")
    }
    public static var recordedGesture: String {
        t(en: "Recorded gesture", fr: "Geste enregistré", nl: "Opgenomen gebaar", de: "Aufgezeichnete Geste")
    }

    // MARK: - Pattern editor

    public static var editorTitle: String { t(en: "Mouse patterns", fr: "Motifs de souris", nl: "Muispatronen", de: "Mausmuster") }
    public static var choosePattern: String {
        t(en: "Choose a pattern from the list.", fr: "Choisis un motif dans la liste.",
          nl: "Kies een patroon uit de lijst.", de: "Wähle ein Muster aus der Liste.")
    }
    public static var builtInSection: String { t(en: "Built-in", fr: "Intégrés", nl: "Ingebouwd", de: "Integriert") }
    public static var myPatterns: String { t(en: "My patterns", fr: "Mes motifs", nl: "Mijn patronen", de: "Meine Muster") }
    public static var noneYet: String { t(en: "None yet", fr: "Aucun pour l'instant", nl: "Nog geen", de: "Noch keine") }
    public static var duplicatePattern: String {
        t(en: "Duplicate pattern", fr: "Dupliquer le motif", nl: "Patroon dupliceren", de: "Muster duplizieren")
    }
    public static var deletePattern: String {
        t(en: "Delete pattern", fr: "Supprimer le motif", nl: "Patroon verwijderen", de: "Muster löschen")
    }
    public static func confirmDelete(_ name: String) -> String {
        t(en: "Delete “\(name)”?", fr: "Supprimer « \(name) » ?", nl: "„\(name)” verwijderen?", de: "„\(name)“ löschen?")
    }
    public static var delete: String { t(en: "Delete", fr: "Supprimer", nl: "Verwijderen", de: "Löschen") }
    public static var deleteWarning: String {
        t(en: "The pattern will be permanently deleted.", fr: "Le motif sera définitivement supprimé.",
          nl: "Het patroon wordt definitief verwijderd.", de: "Das Muster wird endgültig gelöscht.")
    }
    public static var usedByMouseMover: String {
        t(en: "Used by MouseMover", fr: "Utilisé par MouseMover", nl: "Gebruikt door MouseMover", de: "Von MouseMover verwendet")
    }
    public static var builtInLocked: String {
        t(en: "Built-in pattern: it cannot be edited.", fr: "Motif intégré : il n'est pas modifiable.",
          nl: "Ingebouwd patroon: het kan niet worden bewerkt.", de: "Integriertes Muster: Es kann nicht bearbeitet werden.")
    }
    public static var duplicateToEdit: String {
        t(en: "Duplicate to edit", fr: "Dupliquer pour modifier", nl: "Dupliceren om te bewerken", de: "Zum Bearbeiten duplizieren")
    }
    public static var patternName: String { t(en: "Pattern name", fr: "Nom du motif", nl: "Naam van patroon", de: "Name des Musters") }
    public static var inUse: String { t(en: "In use", fr: "Utilisé", nl: "In gebruik", de: "Verwendet") }
    public static var useThisPattern: String {
        t(en: "Use this pattern", fr: "Utiliser ce motif", nl: "Dit patroon gebruiken", de: "Dieses Muster verwenden")
    }
    public static var useThisPatternHelp: String {
        t(en: "MouseMover will play only this pattern.", fr: "MouseMover jouera uniquement ce motif.",
          nl: "MouseMover speelt alleen dit patroon af.", de: "MouseMover spielt nur dieses Muster ab.")
    }
    public static var captureGesture: String {
        t(en: "Capture a gesture", fr: "Capturer un geste", nl: "Gebaar opnemen", de: "Geste aufzeichnen")
    }
    public static func captureFor(_ seconds: Int) -> String {
        t(en: "For \(seconds) seconds", fr: "Pendant \(seconds) secondes", nl: "Gedurende \(seconds) seconden",
          de: "\(seconds) Sekunden lang")
    }
    public static var captureHelp: String {
        t(en: "Record your own mouse movements and clicks into a new pattern.",
          fr: "Enregistre tes propres mouvements de souris et clics dans un nouveau motif.",
          nl: "Neem je eigen muisbewegingen en klikken op in een nieuw patroon.",
          de: "Zeichne deine eigenen Mausbewegungen und Klicks in einem neuen Muster auf.")
    }
    public static var test: String { t(en: "Test", fr: "Tester", nl: "Testen", de: "Testen") }
    public static var testHelp: String {
        t(en: "Play the pattern right now (move the mouse into a corner to interrupt it).",
          fr: "Joue le motif tout de suite (souris dans un coin pour l'interrompre).",
          nl: "Speel het patroon nu af (beweeg de muis naar een hoek om te onderbreken).",
          de: "Spielt das Muster sofort ab (Maus in eine Ecke bewegen, um abzubrechen).")
    }
    public static var anchor: String { t(en: "Reference", fr: "Repère", nl: "Referentie", de: "Bezug") }
    public static var anchorScreen: String { t(en: "On screen", fr: "Sur l'écran", nl: "Op het scherm", de: "Auf dem Bildschirm") }
    public static var anchorCursor: String {
        t(en: "Around the cursor", fr: "Autour du curseur", nl: "Rond de cursor", de: "Um den Mauszeiger")
    }
    public static var anchorHelp: String {
        t(en: "Around the cursor: the center of the frame is the cursor position at the start of the cycle.",
          fr: "Autour du curseur : le centre du cadre est la position du curseur au début du cycle.",
          nl: "Rond de cursor: het midden van het kader is de cursorpositie aan het begin van de cyclus.",
          de: "Um den Mauszeiger: Die Mitte des Rahmens ist die Zeigerposition zu Beginn des Zyklus.")
    }
    public static var shuffle: String { t(en: "Random order", fr: "Ordre aléatoire", nl: "Willekeurige volgorde", de: "Zufällige Reihenfolge") }
    public static var shuffleHelp: String {
        t(en: "Shuffle the points on every cycle (except those that keep their place).",
          fr: "Mélange l'ordre des points à chaque cycle (sauf ceux qui gardent leur place).",
          nl: "Schudt de punten bij elke cyclus (behalve de punten die hun plaats houden).",
          de: "Mischt die Punkte in jedem Zyklus (außer denen, die ihren Platz behalten).")
    }
    public static var emptyCanvasHint: String {
        t(en: "Click in the frame to add a point, or capture a gesture.",
          fr: "Clique dans le cadre pour ajouter un point, ou capture un geste.",
          nl: "Klik in het kader om een punt toe te voegen, of neem een gebaar op.",
          de: "Klicke in den Rahmen, um einen Punkt hinzuzufügen, oder zeichne eine Geste auf.")
    }
    public static func patternSummary(points: Int, seconds: String) -> String {
        switch language {
        case .en: return "\(points) point\(points == 1 ? "" : "s") · about \(seconds) s per cycle"
        case .fr: return "\(points) point\(points > 1 ? "s" : "") · environ \(seconds) s par cycle"
        case .nl: return "\(points) punt\(points == 1 ? "" : "en") · ongeveer \(seconds) s per cyclus"
        case .de: return "\(points) Punkt\(points == 1 ? "" : "e") · etwa \(seconds) s pro Zyklus"
        }
    }
    public static var canvasEditHint: String {
        t(en: " · click: add · drag: move", fr: " · clic : ajouter · glisser : déplacer",
          nl: " · klik: toevoegen · slepen: verplaatsen", de: " · Klick: hinzufügen · Ziehen: verschieben")
    }
    public static var noPointSelected: String {
        t(en: "No point selected", fr: "Aucun point sélectionné", nl: "Geen punt geselecteerd", de: "Kein Punkt ausgewählt")
    }
    public static var pointsExplanation: String {
        t(en: "Each point is a step: the mouse goes there, optionally waits, then clicks if asked. Points are played in the order of their number.",
          fr: "Chaque point est une étape : la souris s'y rend, attend éventuellement, puis clique si demandé. Les points sont joués dans l'ordre de leur numéro.",
          nl: "Elk punt is een stap: de muis gaat erheen, wacht eventueel en klikt als dat gevraagd is. De punten worden afgespeeld in de volgorde van hun nummer.",
          de: "Jeder Punkt ist ein Schritt: Die Maus fährt dorthin, wartet eventuell und klickt, falls gewünscht. Die Punkte werden in der Reihenfolge ihrer Nummer abgespielt.")
    }
    public static var noMovementRecorded: String {
        t(en: "No movement recorded", fr: "Aucun mouvement enregistré", nl: "Geen beweging opgenomen", de: "Keine Bewegung aufgezeichnet")
    }
    public static var noMovementHint: String {
        t(en: "Move the mouse after the countdown to record a gesture.",
          fr: "Bouge la souris après le compte à rebours pour enregistrer un geste.",
          nl: "Beweeg de muis na het aftellen om een gebaar op te nemen.",
          de: "Bewege die Maus nach dem Countdown, um eine Geste aufzuzeichnen.")
    }
    public static var cursorStartHelp: String {
        t(en: "Cursor position at the start of the cycle", fr: "Position du curseur au début du cycle",
          nl: "Cursorpositie aan het begin van de cyclus", de: "Zeigerposition zu Beginn des Zyklus")
    }
    public static func point(_ number: Int) -> String {
        t(en: "Point \(number)", fr: "Point \(number)", nl: "Punt \(number)", de: "Punkt \(number)")
    }
    public static func clickPoint(_ number: Int) -> String {
        t(en: "Point \(number) (click)", fr: "Point \(number) (clic)", nl: "Punt \(number) (klik)", de: "Punkt \(number) (Klick)")
    }
    public static func overlappingPoints(_ numbers: [Int]) -> String {
        let list = numbers.map(String.init).formatted(.list(type: .and).locale(locale))
        return t(en: "Points \(list) overlap · click again to switch between them",
                 fr: "Points \(list) superposés · clique encore pour passer de l'un à l'autre",
                 nl: "Punten \(list) overlappen · klik nogmaals om te wisselen",
                 de: "Punkte \(list) überlappen · erneut klicken, um zwischen ihnen zu wechseln")
    }
    public static var previousPoint: String { t(en: "Previous point", fr: "Point précédent", nl: "Vorig punt", de: "Vorheriger Punkt") }
    public static var nextPoint: String { t(en: "Next point", fr: "Point suivant", nl: "Volgend punt", de: "Nächster Punkt") }
    public static func pointOf(_ number: Int, _ count: Int) -> String {
        t(en: "Point \(number) of \(count)", fr: "Point \(number) sur \(count)",
          nl: "Punt \(number) van \(count)", de: "Punkt \(number) von \(count)")
    }
    public static var position: String { t(en: "Position", fr: "Position", nl: "Positie", de: "Position") }
    public static var horizontal: String { t(en: "Horizontal", fr: "Horizontal", nl: "Horizontaal", de: "Horizontal") }
    public static var vertical: String { t(en: "Vertical", fr: "Vertical", nl: "Verticaal", de: "Vertikal") }
    public static var clickOnArrival: String {
        t(en: "Click on arrival", fr: "Cliquer à l'arrivée", nl: "Klikken bij aankomst", de: "Bei Ankunft klicken")
    }
    public static var keepPlace: String {
        t(en: "Keep its place", fr: "Garder sa place", nl: "Plaats behouden", de: "Platz behalten")
    }
    public static var keepPlaceHelp: String {
        t(en: "This point is not shuffled with the others.", fr: "Ce point n'est pas mélangé avec les autres.",
          nl: "Dit punt wordt niet met de andere geschud.", de: "Dieser Punkt wird nicht mit den anderen gemischt.")
    }
    public static var pauseOnArrival: String {
        t(en: "Pause on arrival", fr: "Pause à l'arrivée", nl: "Pauze bij aankomst", de: "Pause bei Ankunft")
    }
    public static var wait: String { t(en: "Wait", fr: "Attendre", nl: "Wachten", de: "Warten") }
    public static var atLeast: String { t(en: "At least", fr: "Au moins", nl: "Minstens", de: "Mindestens") }
    public static var atMost: String { t(en: "At most", fr: "Au plus", nl: "Hoogstens", de: "Höchstens") }
    public static var pathToPoint: String {
        t(en: "Path to the point", fr: "Trajet jusqu'au point", nl: "Traject naar het punt", de: "Weg zum Punkt")
    }
    public static var fixedDuration: String {
        t(en: "Fixed duration", fr: "Durée imposée", nl: "Vaste duur", de: "Feste Dauer")
    }
    public static var straightPath: String {
        t(en: "Straight line, at constant speed.", fr: "Trajet en ligne droite, à vitesse constante.",
          nl: "Rechte lijn, met constante snelheid.", de: "Gerade Linie mit konstanter Geschwindigkeit.")
    }
    public static var humanPath: String {
        t(en: "Random duration and curve, like a hand.", fr: "Durée et courbe au hasard, comme une main.",
          nl: "Willekeurige duur en curve, als een hand.", de: "Zufällige Dauer und Kurve, wie eine Hand.")
    }
    public static var playEarlier: String {
        t(en: "Play this point earlier", fr: "Jouer ce point plus tôt", nl: "Dit punt eerder afspelen", de: "Diesen Punkt früher abspielen")
    }
    public static var playLater: String {
        t(en: "Play this point later", fr: "Jouer ce point plus tard", nl: "Dit punt later afspelen", de: "Diesen Punkt später abspielen")
    }

    // MARK: - Gesture capture

    public static func captureCountdown(_ seconds: Int) -> String {
        t(en: "Get your mouse ready… \(seconds)", fr: "Prépare ta souris… \(seconds)",
          nl: "Maak je muis klaar… \(seconds)", de: "Mach deine Maus bereit… \(seconds)")
    }
    public static var escToCancel: String {
        t(en: "Esc to cancel", fr: "Échap pour annuler", nl: "Esc om te annuleren", de: "Esc zum Abbrechen")
    }
    public static func recording(_ seconds: Int) -> String {
        t(en: "Recording… \(seconds) s", fr: "Enregistrement… \(seconds) s",
          nl: "Opnemen… \(seconds) s", de: "Aufnahme… \(seconds) s")
    }
    public static var recordingDetail: String {
        t(en: "Clicks are really performed · Esc to finish",
          fr: "Les clics sont réellement effectués · Échap pour terminer",
          nl: "Klikken worden echt uitgevoerd · Esc om te stoppen",
          de: "Klicks werden wirklich ausgeführt · Esc zum Beenden")
    }

    // MARK: - Shortcuts (runtime dialogs)

    public static var startedDialog: String {
        t(en: "MouseMover is running.", fr: "MouseMover est démarré.", nl: "MouseMover is gestart.", de: "MouseMover läuft.")
    }
    public static var stoppedDialog: String {
        t(en: "MouseMover is paused.", fr: "MouseMover est en pause.", nl: "MouseMover is gepauzeerd.", de: "MouseMover ist pausiert.")
    }
    public static var cycleStarted: String {
        t(en: "Cycle started.", fr: "Cycle lancé.", nl: "Cyclus gestart.", de: "Zyklus gestartet.")
    }
    public static var cycleAlreadyRunning: String {
        t(en: "A cycle is already running.", fr: "Un cycle est déjà en cours.",
          nl: "Er loopt al een cyclus.", de: "Ein Zyklus läuft bereits.")
    }
    public static func intervalSet(_ minutes: String) -> String {
        t(en: "Interval set to \(minutes) minutes.", fr: "Intervalle réglé sur \(minutes) minutes.",
          nl: "Interval ingesteld op \(minutes) minuten.", de: "Intervall auf \(minutes) Minuten gesetzt.")
    }
    public static func displaySet(_ name: String) -> String {
        t(en: "MouseMover now uses “\(name)”.", fr: "MouseMover utilise maintenant « \(name) ».",
          nl: "MouseMover gebruikt nu „\(name)”.", de: "MouseMover verwendet jetzt „\(name)“.")
    }
    public static func patternSet(_ name: String) -> String {
        t(en: "MouseMover now plays the “\(name)” pattern.", fr: "MouseMover joue maintenant le motif « \(name) ».",
          nl: "MouseMover speelt nu het patroon „\(name)”.", de: "MouseMover spielt jetzt das Muster „\(name)“.")
    }
    public static var unknownPattern: String {
        t(en: "This pattern no longer exists.", fr: "Ce motif n'existe plus.",
          nl: "Dit patroon bestaat niet meer.", de: "Dieses Muster existiert nicht mehr.")
    }
}
