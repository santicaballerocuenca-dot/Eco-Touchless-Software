import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../settings/data/config_service.dart';
import 'esp_service.dart';
import 'esp_wifi_connector.dart';
import 'esp_actuadores_service.dart';
import '../domain/estado_controlador.dart';
import '../domain/reintentos_conexion.dart';

/// Foreground-only heartbeat. Never retries a mechanical command.
class EspConexionMonitor extends ChangeNotifier with WidgetsBindingObserver {
  EspConexionMonitor._();
  static final instancia = EspConexionMonitor._();
  static const _channel = MethodChannel('eco_touchless/wifi');
  Timer? _timer;
  bool _iniciado = false, _consultando = false, _foreground = true;
  bool activo = false;
  bool? conectado;
  bool reconectando = false;
  String? errorRetencion;
  int _generation = 0;
  int _lectura = 0;
  bool _mantener = false;
  String? _configuracion;
  String _ssid = '', _password = '';
  final _reintentos = ReintentosConexion();
  EstadoControlador? controlador;
  String? avisoReinicio;

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    WidgetsBinding.instance.addObserver(this);
    ConfigService.instancia.addListener(_configurar);
    _configurar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    _configurar();
  }

  Future<void> _configurar() async {
    final lectura = ++_lectura;
    final config = ConfigService.instancia;
    final enabled = await config.getEspHabilitado();
    final mantener = await config.getMantenerEsp();
    final ssid = await config.getEspSsid();
    final password = await config.getEspPassword();
    final destino = '${await config.getEspIp()}:${await config.getEspPuerto()}';
    if (lectura != _lectura) return;
    final signature =
        '$enabled|$mantener|$ssid|$password|$destino|$_foreground';
    if (signature == _configuracion) return;
    _configuracion = signature;
    final generation = ++_generation;
    _mantener = mantener;
    _ssid = ssid;
    _password = password;
    controlador = null;
    avisoReinicio = null;
    _reintentos.exito();
    activo = enabled;
    _timer?.cancel();
    conectado = null;
    errorRetencion = null;
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('retener',
            {'enabled': enabled && mantener && _foreground, 'ssid': ssid});
      }
    } on PlatformException catch (e) {
      errorRetencion = 'No se pudo mantener Wi-Fi: ${e.message}';
    } on MissingPluginException {
      errorRetencion = 'Retención Wi-Fi no disponible en esta plataforma.';
    }
    if (generation != _generation) return;
    notifyListeners();
    if (enabled && _foreground) {
      unawaited(comprobar());
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => comprobar());
    }
  }

  Future<void> comprobar() async {
    if (!activo ||
        !_foreground ||
        _consultando ||
        EspService.instancia.enviando) {
      return;
    }
    _consultando = true;
    final generation = _generation;
    try {
      final result = await EspService.instancia.diagnosticar();
      if (generation != _generation) return;
      if (result.correcto) {
        conectado = true;
        _reintentos.exito();
        errorRetencion = null;
        final nuevo = result.controlador;
        if (nuevo != null) {
          if (nuevo.reinicioRespectoA(controlador) || nuevo.resetReason == 9) {
            avisoReinicio = 'La ESP32 se reinició. ${nuevo.motivoReinicio} '
                'Un reinicio interrumpe el tiempo de apertura.';
          }
          final actual = EspActuadoresService.instancia.actual;
          if (actual?.bootId != nuevo.bootId ||
              actual?.revision != nuevo.revision) {
            EspActuadoresService.instancia.invalidar();
          }
        }
        controlador = nuevo;
        if (EspActuadoresService.instancia.actual == null) {
          await EspActuadoresService.instancia.sincronizar();
        }
      } else {
        _reintentos.fallo();
        if (_reintentos.fallos >= 2) conectado = false;
        EspActuadoresService.instancia.invalidar();
        EspService.instancia.renovarConexion();
        if (_mantener && _reintentos.puedeIntentar(DateTime.now())) {
          await _recuperar(automatico: true);
        }
      }
      if (generation == _generation) notifyListeners();
    } finally {
      _consultando = false;
    }
  }

  Future<void> _recuperar({required bool automatico}) async {
    if (reconectando || !_foreground || !activo) return;
    reconectando = true;
    final generation = _generation;
    _reintentos.registrarIntento(DateTime.now());
    notifyListeners();
    try {
      final resultado = await EspWifiConnector.instancia
          .conectarAutomaticamente(
              ssid: _ssid, password: _password, automatico: automatico);
      if (generation != _generation) return;
      errorRetencion = resultado == EspWifiResultado.conectado
          ? 'Recuperando enlace; esperando respuesta de la ESP32…'
          : 'Para autorizar Wi-Fi, tocá Reconectar y aceptá el aviso de Android.';
      EspService.instancia.renovarConexion();
    } finally {
      reconectando = false;
      notifyListeners();
    }
  }

  Future<void> reconectar() async {
    await _recuperar(automatico: false);
    await comprobar();
  }
}
