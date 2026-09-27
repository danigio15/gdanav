import Flutter
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
        PonteAuto.shared.collega(registrar: registrar)
        // La scena di CarPlay la crea iOS dal nome scritto nell'Info.plist:
        // senza un riferimento qui il linker potrebbe lasciarla fuori.
        _ = GdanavCarPlay.self
    }
}
