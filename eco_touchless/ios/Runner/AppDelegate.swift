import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var brilloOriginal: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Brillo de pantalla: la app usa la pantalla en blanco como luz de relleno
    // cuando la cámara detecta poca luz. Un valor negativo restaura el original.
    if let controller = window?.rootViewController as? FlutterViewController {
      let canal = FlutterMethodChannel(
        name: "eco_touchless/pantalla", binaryMessenger: controller.binaryMessenger)
      canal.setMethodCallHandler { [weak self] call, result in
        guard call.method == "brillo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let argumentos = call.arguments as? [String: Any]
        let valor = argumentos?["valor"] as? Double ?? -1
        if valor < 0 {
          if let original = self?.brilloOriginal { UIScreen.main.brightness = original }
          self?.brilloOriginal = nil
        } else {
          if self?.brilloOriginal == nil { self?.brilloOriginal = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(min(max(valor, 0.01), 1))
        }
        result(nil)
      }
    }
    UIApplication.shared.isIdleTimerDisabled = true
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
