import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../settings/data/config_service.dart';
import '../domain/configuracion_servos.dart';
import 'esp_service.dart';

/// Configuration is authoritative on the board, never guessed from local prefs.
class EspActuadoresService extends ChangeNotifier {
  EspActuadoresService(
      {http.Client? cliente,
      Future<Uri> Function()? destino,
      Future<String> Function()? clave})
      : _cliente = cliente ?? http.Client(),
        _destino = destino ?? _destinoConfigurado,
        _clave = clave ?? ConfigService.instancia.getEspApiKey;
  static final instancia = EspActuadoresService();
  final http.Client _cliente;
  final Future<Uri> Function() _destino;
  final Future<String> Function() _clave;
  ConfiguracionServos? actual;
  bool legado = false, guardando = false;
  String? error;
  String? _identidad;
  DateTime? _ultimaLectura;
  Future<ConfiguracionServos?>? _lectura;
  static Future<Uri> _destinoConfigurado() async {
    final config = ConfigService.instancia;
    final host = await config.getEspIp();
    final port = await config.getEspPuerto();
    if (!EspService.esHostLocalValido(host) || port < 1 || port > 65535) {
      throw const FormatException('IP/puerto local no válido.');
    }
    return Uri.http('$host:$port', '/config');
  }

  Future<ConfiguracionServos?> sincronizar({bool forzar = false}) async {
    if (guardando) return actual;
    final uri = await _destino();
    final token = await _clave();
    final key = '$uri|$token';
    if (key != _identidad) {
      _identidad = key;
      actual = null;
      legado = false;
      _ultimaLectura = null;
      _lectura = null;
    }
    if (!forzar &&
        _ultimaLectura != null &&
        DateTime.now().difference(_ultimaLectura!) <
            const Duration(seconds: 5)) {
      return actual;
    }
    if (_lectura != null) return _lectura;
    final future = _leer(uri, token, key);
    _lectura = future;
    try {
      return await future;
    } finally {
      if (identical(_lectura, future)) _lectura = null;
    }
  }

  Future<ConfiguracionServos?> _leer(Uri uri, String token, String key) async {
    try {
      final response = await _cliente.get(uri,
          headers: {'X-Api-Key': token}).timeout(const Duration(seconds: 3));
      if (_identidad != key) return null;
      _ultimaLectura = DateTime.now();
      if (response.statusCode == 404 || response.statusCode == 405) {
        actual = null;
        legado = true;
        error = null;
        return null;
      }
      if (response.statusCode != 200) throw StateError(_mensaje(response));
      final data = ConfiguracionServos.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
      actual = data;
      legado = false;
      error = null;
      return data;
    } catch (e) {
      if (_identidad == key) {
        actual = null;
        legado = false;
        error = '$e';
        _ultimaLectura = DateTime.now();
      }
      return null;
    } finally {
      notifyListeners();
    }
  }

  Future<void> guardar(ConfiguracionServos config) async {
    if (guardando) throw StateError('Ya se está guardando.');
    final validation = config.validar();
    if (validation != null) throw FormatException(validation);
    guardando = true;
    notifyListeners();
    try {
      // Drain older GETs before writing so their replies cannot overwrite the ACK.
      if (_lectura != null) await _lectura;
      final uri = await _destino();
      final token = await _clave();
      final key = '$uri|$token';
      if (key != _identidad ||
          actual?.deviceId != config.deviceId ||
          actual?.bootId != config.bootId ||
          actual?.revision != config.revision) {
        throw StateError(
            'Cambió la placa o su configuración. Volvé a leer antes de guardar.');
      }
      final response = await _cliente
          .put(uri,
              headers: {'X-Api-Key': token, 'Content-Type': 'application/json'},
              body: jsonEncode(config.toJson()))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw StateError(_mensaje(response));
      // A save timeout is ambiguous: require the board's full acknowledged config.
      final saved = ConfiguracionServos.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
      if (key != _identidad ||
          saved.deviceId != config.deviceId ||
          saved.bootId != config.bootId ||
          saved.revision != config.revision + 1 ||
          jsonEncode(saved.servos.map((s) => s.toJson()).toList()) !=
              jsonEncode(config.servos.map((s) => s.toJson()).toList())) {
        throw StateError(
            'La placa no confirmó los ajustes enviados. Volvé a leerlos.');
      }
      actual = saved;
      error = null;
      _ultimaLectura = DateTime.now();
    } catch (e) {
      invalidar();
      rethrow;
    } finally {
      guardando = false;
      notifyListeners();
    }
  }

  void invalidar() {
    actual = null;
    legado = false;
    _ultimaLectura = null;
  }

  static String _mensaje(http.Response r) {
    if (r.statusCode == 401) {
      return 'Clave de control incorrecta. Revisá la clave de la app y del .ino.';
    }
    if (r.statusCode == 409) {
      return 'Placa ocupada o ajustes cambiados. Esperá el cierre y volvé a leer.';
    }
    try {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'HTTP ${r.statusCode}';
    } catch (_) {
      return 'HTTP ${r.statusCode}';
    }
  }

  @override
  void dispose() {
    _cliente.close();
    super.dispose();
  }
}
