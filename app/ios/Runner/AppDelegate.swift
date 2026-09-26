import Flutter
import UIKit

/// Un motore Flutter solo, acceso all'avvio: lo usano la schermata del
/// telefono e CarPlay, che può aprire l'app senza il telefono in mano (come
/// `MotoreFlutter.kt` per Android Auto).
@main
@objc class AppDelegate: FlutterAppDelegate {
  lazy var motore = FlutterEngine(name: "gdanav")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    motore.run()
    GeneratedPluginRegistrant.register(with: motore)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
