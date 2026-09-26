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
    super.sceneDidDisconnect(scene)
    if let app = UIApplication.shared.delegate as? AppDelegate {
      _ = unregisterSceneLifeCycle(with: app.motore)
    }
    // Il motore resta acceso per CarPlay: si lascia solo la finestra.
    window?.rootViewController = nil
    window = nil
  }
}
