import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sube el brillo de la pantalla al máximo para usarla como luz de relleno
/// cuando la escena está oscura, y lo devuelve al valor del sistema después.
///
/// Se implementa con un canal propio (Android: `WindowManager.LayoutParams.
/// screenBrightness`; iOS: `UIScreen.brightness`) para no sumar dependencias.
/// En plataformas sin implementación las llamadas no hacen nada.
class BrilloPantalla {
  BrilloPantalla._();

  static const _canal = MethodChannel('eco_touchless/pantalla');
  static bool _maximo = false;

  static bool get alMaximo => _maximo;

  static Future<void> maximo() => _fijar(1.0);

  static Future<void> restaurar() => _fijar(-1);

  static Future<void> _fijar(double valor) async {
    final maximo = valor >= 0;
    if (maximo == _maximo) return;
    _maximo = maximo;
    try {
      await _canal.invokeMethod<void>('brillo', {'valor': valor});
    } on MissingPluginException {
      // Escritorio, web o tests: no hay control de brillo.
    } on PlatformException catch (e) {
      debugPrint('No se pudo cambiar el brillo de pantalla: ${e.message}');
    }
  }
}
