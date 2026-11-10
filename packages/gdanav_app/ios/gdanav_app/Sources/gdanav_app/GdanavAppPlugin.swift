import Flutter
import Network
import UIKit

/// Il lato iPhone di `gdanav_app`: quello che su Android fa `GdanavAppPlugin.kt`
/// (i permessi Bluetooth) e `PonteAuto.kt` (lo schermo dell'auto, qui CarPlay).
public class GdanavAppPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let permessi = FlutterMethodChannel(name: "gdanav/permessi", binaryMessenger: registrar.messenger())
        permessi.setMethodCallHandler { call, risultato in
            switch call.method {
            // Su iPhone il permesso del Bluetooth lo chiede il sistema da sé,
            // la prima volta che si cercano i dongle: qui non c'è niente da fare.
            case "bluetooth":
                risultato(true)
            default:
                risultato(FlutterMethodNotImplemented)
            }
        }
        // Lo schermo acceso finché si guida (`lib/sorgenti/schermo_acceso.dart`).
        let schermo = FlutterMethodChannel(name: "gdanav/schermo", binaryMessenger: registrar.messenger())
        schermo.setMethodCallHandler { call, risultato in
            guard call.method == "acceso" else { return risultato(FlutterMethodNotImplemented) }
            SchermoAcceso.tieni(call.arguments as? Bool == true)
            risultato(nil)
        }
        // Se la rete si paga a consumo: gli edifici della scena 3D si scaricano
        // solo su una rete che non costa (`stato/gestore_edifici.dart`).
        ReteAConsumo.accendi()
        let rete = FlutterMethodChannel(name: "gdanav/rete", binaryMessenger: registrar.messenger())
        rete.setMethodCallHandler { call, risultato in
            guard call.method == "aConsumo" else { return risultato(FlutterMethodNotImplemented) }
            risultato(ReteAConsumo.adesso)
        }
        PonteAuto.shared.collega(registrar: registrar)
        // La guida per l'Apple Watch dell'app ospite (`GdanavOrologio`).
        GdanavOrologio.accendi()
        // La scena di CarPlay la crea iOS dal nome scritto nell'Info.plist:
        // senza un riferimento qui il linker potrebbe lasciarla fuori.
        _ = GdanavCarPlay.self
    }
}

/// Il blocco automatico dell'iPhone, fermo finché si guida. Se l'app ospite
/// lo aveva già fermato per conto suo (il pannello a muro di GdAHome), alla
/// fine della guida resta fermo: si rimette com'era, non «acceso».
enum SchermoAcceso {
    private static var primaDellaGuida: Bool?

    static func tieni(_ acceso: Bool) {
        DispatchQueue.main.async {
            let app = UIApplication.shared
            if acceso {
                if primaDellaGuida == nil { primaDellaGuida = app.isIdleTimerDisabled }
                app.isIdleTimerDisabled = true
            } else if let prima = primaDellaGuida {
                app.isIdleTimerDisabled = prima
                primaDellaGuida = nil
            }
        }
    }
}

/// Se la rete di adesso si paga a consumo (i dati del telefono, un hotspot, il
/// risparmio dati acceso). Nel dubbio sì.
enum ReteAConsumo {
    private static let monitor = NWPathMonitor()
    private static var acceso = false

    static func accendi() {
        guard !acceso else { return }
        acceso = true
        monitor.start(queue: DispatchQueue(label: "gdanav.rete"))
    }

    static var adesso: Bool {
        let p = monitor.currentPath
        return p.status != .satisfied || p.isExpensive || p.isConstrained
    }
}
