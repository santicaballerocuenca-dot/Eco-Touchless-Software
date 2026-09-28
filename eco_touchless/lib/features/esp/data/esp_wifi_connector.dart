import 'dart:io';
import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:plugin_wifi_connect/plugin_wifi_connect.dart';

/// Resultado de un intento de conexión automática al Wi-Fi del ESP32.
enum EspWifiResultado { conectado, permisoDenegado, fallo }

/// Intenta unir el celular a la red Wi-Fi que crea la ESP32 (su Access
/// Point) de forma programática. Android exige permiso de ubicación para
/// esto (aunque no se use la ubicación en sí: es un requisito de la API de
/// Wi-Fi del sistema), así que primero se pide ese permiso.
///
/// Si la conexión automática falla (por ejemplo, en versiones de Android
/// muy nuevas que restringen aún más este flujo, o si el usuario niega el
/// permiso), lo correcto es no insistir con reintentos silenciosos: se
/// informa el fallo para que la UI pueda guiar al usuario a conectarse a
/// mano desde Ajustes de Android, que siempre funciona.
class EspWifiConnector {
  EspWifiConnector._interno();
  static final EspWifiConnector instancia = EspWifiConnector._interno();
  static const _channel = MethodChannel('eco_touchless/wifi');
  Future<EspWifiResultado>? _pendiente;

  Future<EspWifiResultado> conectarAutomaticamente({
    required String ssid,
    required String password,
    bool automatico = false,
  }) {
    return _pendiente ??=
        _conectar(ssid: ssid, password: password, automatico: automatico)
            .whenComplete(() => _pendiente = null);
  }

  Future<EspWifiResultado> _conectar({
    required String ssid,
    required String password,
    required bool automatico,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return EspWifiResultado.fallo;
    if (Platform.isAndroid) {
      // Android <= 12 usa ubicación para operaciones Wi-Fi; Android 13+
      // usa NEARBY_WIFI_DEVICES. Pedir ambos mantiene un único flujo y se
      // acepta el que exista en la versión actual del sistema.
      final permisos = [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices
      ];
      final estados = automatico
          ? await Future.wait(permisos.map((p) => p.status))
          : (await permisos.request()).values.toList();
      final autorizado = estados.any((estado) => estado.isGranted);
      if (!autorizado) return EspWifiResultado.permisoDenegado;
    }

    try {
      if (Platform.isAndroid) {
        final solicitado = await _channel.invokeMethod<bool>('conectar', {
          'ssid': ssid,
          'password': password,
          'automatico': automatico,
        });
        if (solicitado != null) {
          // Accepted association request, not proof that HTTP is reachable.
          return solicitado
              ? EspWifiResultado.conectado
              : EspWifiResultado.fallo;
        }
      }
      if (automatico) return EspWifiResultado.fallo;
      // La red de la ESP32 tiene contraseña (WPA2-PSK), así que hace falta
      // connectToSecureNetwork y no connect() (que solo sirve para redes
      // abiertas, sin password).
      final ok = await PluginWifiConnect.connectToSecureNetwork(
        ssid,
        password,
        saveNetwork: true,
      );
      return ok == true ? EspWifiResultado.conectado : EspWifiResultado.fallo;
    } catch (_) {
      return EspWifiResultado.fallo;
    }
  }

  /// Abre la pantalla de Ajustes de Wi-Fi de Android para que el usuario
  /// elija la red manualmente. Es el camino de respaldo cuando la conexión
  /// automática no funciona en su dispositivo.
  Future<void> abrirAjustesWifi() async {
    await AppSettings.openAppSettings(type: AppSettingsType.wifi);
  }
}
