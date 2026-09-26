import AppIntents
import UIKit
import gdanav_app

// «Ehi Siri, naviga con gdanav»: i comandi vocali, come «Ok Google, naviga
// verso…» su Android Auto. Siri li sente anche in CarPlay; l'app li esegue
// senza aprirsi sul telefono (il motore Flutter si accende da sé all'avvio),
// e la guida parte sulla mappa di CarPlay come su quella del telefono.

@available(iOS 16.0, *)
struct NavigaVerso: AppIntent {
    static let title: LocalizedStringResource = "Naviga verso"
    static let description = IntentDescription("Cerca un posto o un indirizzo e parte la guida.")
    static let openAppWhenRun = false

    @Parameter(title: "Destinazione", requestValueDialog: "Dove vuoi andare?")
    var destinazione: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await ComandiVocali.aspetta { GdanavCarPlay.naviga(destinazione, fatto: $0) }
        return .result(dialog: "Cerco \(destinazione).")
    }
}

@available(iOS 16.0, *)
struct AggiungiTappa: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi una tappa"
    static let description = IntentDescription("Aggiunge un posto al viaggio in corso.")
    static let openAppWhenRun = false

    @Parameter(title: "Tappa", requestValueDialog: "Da dove vuoi passare?")
    var tappa: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await ComandiVocali.aspetta { GdanavCarPlay.naviga(tappa, tappa: true, fatto: $0) }
        return .result(dialog: "Cerco \(tappa) e ci passo.")
    }
}

@available(iOS 16.0, *)
struct PortamiACasa: AppIntent {
    static let title: LocalizedStringResource = "Portami a casa"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await ComandiVocali.aspetta { GdanavCarPlay.vaiA("casa", fatto: $0) }
        let testo = ok ? "Si torna a casa." : "Casa non è ancora impostata: si imposta dal Menu."
        return .result(dialog: IntentDialog(stringLiteral: testo))
    }
}

@available(iOS 16.0, *)
struct PortamiAlLavoro: AppIntent {
    static let title: LocalizedStringResource = "Portami al lavoro"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await ComandiVocali.aspetta { GdanavCarPlay.vaiA("lavoro", fatto: $0) }
        let testo = ok ? "Si va al lavoro." : "Lavoro non è ancora impostato: si imposta dal Menu."
        return .result(dialog: IntentDialog(stringLiteral: testo))
    }
}

@available(iOS 16.0, *)
struct ComandiGdanav: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NavigaVerso(),
            phrases: ["Naviga con \(.applicationName)", "Portami con \(.applicationName)"]
        )
        AppShortcut(
            intent: PortamiACasa(),
            phrases: ["Portami a casa con \(.applicationName)"]
        )
        AppShortcut(
            intent: PortamiAlLavoro(),
            phrases: ["Portami al lavoro con \(.applicationName)"]
        )
        AppShortcut(
            intent: AggiungiTappa(),
            phrases: ["Aggiungi una tappa con \(.applicationName)"]
        )
    }
}

enum ComandiVocali {
    /// Aspetta che l'app risponda (il motore può essere ancora spento), con
    /// l'app tenuta sveglia: Siri la apre in background.
    @MainActor
    @discardableResult
    static func aspetta(_ comando: (@escaping (Bool) -> Void) -> Void) async -> Bool {
        let compito = UIApplication.shared.beginBackgroundTask(withName: "gdanav.siri")
        defer { UIApplication.shared.endBackgroundTask(compito) }
        return await withCheckedContinuation { c in
            comando { c.resume(returning: $0) }
        }
    }
}
