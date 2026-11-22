import Flutter
import UIKit

/// La schermata del telefono: il motore di `AppDelegate`, già acceso (magari
/// da CarPlay), dentro la finestra.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate
    else { return }
    window = UIWindow(windowScene: windowScene)
    _ = registerSceneLifeCycle(with: app.motore)
    window?.rootViewController = FlutterViewController(engine: app.motore, nibName: nil, bundle: nil)
    window?.makeKeyAndVisible()
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    // Il motore resta acceso per CarPlay: si lascia solo la finestra, e PRIMA
    // di avvisare i plugin. `FlutterSceneDelegate` passa la chiusura della
    // scena ai plugin dei motori che ci stanno dentro, e quello delle WebView
    // a quel punto smonta il suo registro: la scena 3D restava viva col
    // motore, e al primo messaggio dalla pagina l'app si chiudeva (SIGABRT in
    // `swift_unownedRetainStrong`, dentro `didPostMessage` di WebKit).
    if let app = UIApplication.shared.delegate as? AppDelegate {
      _ = unregisterSceneLifeCycle(with: app.motore)
    }
    window?.rootViewController = nil
    window = nil
    super.sceneDidDisconnect(scene)
  }
}
