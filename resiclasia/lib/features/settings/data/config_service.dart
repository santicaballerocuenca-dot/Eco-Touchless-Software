import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../domain/modo_interfaz.dart';
import '../../classification/domain/perfil_modelo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maneja todos los ajustes configurables de la app, persistidos en el
/// dispositivo con SharedPreferences para que sobrevivan a un reinicio.
class ConfigService extends ChangeNotifier {
  ConfigService._interno();
  static final ConfigService instancia = ConfigService._interno();

  static const _kUmbralConfianza = 'umbral_confianza';
  static const _kDeteccionMovimiento = 'deteccion_movimiento';
  static const _kSensibilidadMovimiento = 'sensibilidad_movimiento';
  static const _kGuardarHistorialAuto = 'guardar_historial_auto';
  static const _kUsarGPU = 'usar_gpu';
  static const _kBienvenidaCompletada = 'bienvenida_completada';
  static const _kRetencionImagenesDias = 'retencion_imagenes_dias';
  static const _kOnboardingEspCompletado = 'onboarding_esp_completado';
  static const _kConfirmacionManual = 'confirmacion_manual';
  static const _kTimeoutConfirmacionSegundos = 'timeout_confirmacion_segundos';
  static const _kCapturarTrasCeseMovimiento = 'capturar_tras_cese_movimiento';
  static const _kModoContinuo = 'modo_continuo';
  static const _kUmbralModoContinuo = 'umbral_modo_continuo';
  static const _kGuiaModoContinuoVista = 'guia_modo_continuo_vista';
  static const _kModeloSeleccionado = 'modelo_seleccionado';

  // --- Vinculación con la ESP32 del clasificador físico ---
  static const _kEspHabilitado = 'esp_habilitado';
  static const _kEspSsid = 'esp_ssid';
  static const _kEspPassword = 'esp_password';
  static const _kEspIp = 'esp_ip';
  static const _kEspPuerto = 'esp_puerto';
  static const _kEspTimeoutMs = 'esp_timeout_ms';

  // Valores por defecto: coinciden con los que trae el firmware de fábrica
  // (ver comentario de cabecera en resiclas_esp32.ino).
  static const String kEspSsidDefault = 'RESICLASIA';
  static const String kEspPasswordDefault = 'resiclas2026';
  static const String kEspIpDefault = '192.168.4.1';
  static const int kEspPuertoDefault = 80;
  static const int kEspTimeoutMsDefault = 3000;
  Future<String> getEspApiKey() async =>
      (await _prefsInstancia).getString('esp_api_key') ??
      'resiclas2026-control';
  Future<void> setEspApiKey(String value) async {
    await (await _prefsInstancia).setString('esp_api_key', value.trim());
    notifyListeners();
  }

  SharedPreferences? _prefs;
  Future<ModoInterfaz> getModoInterfaz() async =>
      ModoInterfaz.desde((await _prefsInstancia).getString('modo_interfaz'));
  Future<void> setModoInterfaz(ModoInterfaz modo) async {
    await (await _prefsInstancia).setString('modo_interfaz', modo.name);
    notifyListeners();
  }

  Future<PerfilModelo> getPerfilModelo(String model) async {
    if (PerfilModelo.esInsignia(model)) return PerfilModelo.insignia;
    final raw = (await _prefsInstancia).getString('perfil:$model');
    if (raw == null) return const PerfilModelo();
    try {
      return PerfilModelo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PerfilModelo();
    }
  }

  Future<void> setPerfilModelo(String model, PerfilModelo perfil) async {
    if (PerfilModelo.esInsignia(model)) return;
    PerfilModelo.fromJson(perfil.toJson());
    await (await _prefsInstancia)
        .setString('perfil:$model', jsonEncode(perfil.toJson()));
    notifyListeners();
  }

  Future<bool> getBenchHabilitado() async =>
      (await _prefsInstancia).getBool('bench_habilitado') ?? false;
  Future<void> setBenchHabilitado(bool value) async {
    await (await _prefsInstancia).setBool('bench_habilitado', value);
    notifyListeners();
  }

  Future<bool> getMantenerEsp() async =>
      (await _prefsInstancia).getBool('mantener_esp') ?? false;
  Future<void> setMantenerEsp(bool value) async {
    await (await _prefsInstancia).setBool('mantener_esp', value);
    notifyListeners();
  }

  Future<List<String>?> getModelosComparacion() async =>
      (await _prefsInstancia).getStringList('modelos_comparacion');
  Future<void> setModelosComparacion(List<String> value) async {
    await (await _prefsInstancia).setStringList('modelos_comparacion', value);
    notifyListeners();
  }

  Future<SharedPreferences> get _prefsInstancia async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // --- Umbral mínimo de confianza para aceptar una predicción como válida ---
  // Ajuste "para sacarle mayor provecho al ML": si la confianza del modelo
  // queda por debajo de este umbral, la UI avisa que el resultado es dudoso.
  Future<double> getUmbralConfianza() async {
    final prefs = await _prefsInstancia;
    return prefs.getDouble(_kUmbralConfianza) ?? 60.0;
  }

  Future<void> setUmbralConfianza(double valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setDouble(_kUmbralConfianza, valor);
    notifyListeners();
  }

  // --- Detección de movimiento (on/off) ---
  Future<bool> getDeteccionMovimiento() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kDeteccionMovimiento) ?? false;
  }

  Future<void> setDeteccionMovimiento(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kDeteccionMovimiento, valor);
    notifyListeners();
  }

  // --- Sensibilidad de detección de movimiento (0.0 = poco sensible, 1.0 = muy sensible) ---
  // Un valor más alto hace que el detector reaccione ante cambios más chicos
  // entre frames (ver fórmula del umbral en PantallaClasificacion).
  Future<double> getSensibilidadMovimiento() async {
    final prefs = await _prefsInstancia;
    return prefs.getDouble(_kSensibilidadMovimiento) ?? 0.5;
  }

  Future<void> setSensibilidadMovimiento(double valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setDouble(_kSensibilidadMovimiento, valor);
    notifyListeners();
  }

  // --- Guardar automáticamente cada clasificación en el historial ---
  Future<bool> getGuardarHistorialAuto() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kGuardarHistorialAuto) ?? true;
  }

  Future<void> setGuardarHistorialAuto(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kGuardarHistorialAuto, valor);
    notifyListeners();
  }

  // --- Usar GPU delegate para acelerar la inferencia (si el dispositivo lo soporta) ---
  Future<bool> getUsarGPU() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kUsarGPU) ?? false;
  }

  Future<void> setUsarGPU(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kUsarGPU, valor);
    notifyListeners();
  }

  Future<bool> getBienvenidaCompletada() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kBienvenidaCompletada) ?? false;
  }

  Future<void> setBienvenidaCompletada(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kBienvenidaCompletada, valor);
    notifyListeners();
  }

  /// 0 conserva las imágenes hasta que el usuario borre el historial.
  Future<int> getRetencionImagenesDias() async {
    final prefs = await _prefsInstancia;
    return prefs.getInt(_kRetencionImagenesDias) ?? 30;
  }

  Future<void> setRetencionImagenesDias(int valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setInt(_kRetencionImagenesDias, valor);
    notifyListeners();
  }

  Future<bool> getOnboardingEspCompletado() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kOnboardingEspCompletado) ?? false;
  }

  Future<void> setOnboardingEspCompletado(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kOnboardingEspCompletado, valor);
    notifyListeners();
  }

  Future<bool> getConfirmacionManual() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kConfirmacionManual) ?? true;
  }

  Future<void> setConfirmacionManual(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kConfirmacionManual, valor);
    notifyListeners();
  }

  Future<int> getTimeoutConfirmacionSegundos() async {
    final prefs = await _prefsInstancia;
    return prefs.getInt(_kTimeoutConfirmacionSegundos) ?? 5;
  }

  Future<void> setTimeoutConfirmacionSegundos(int valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setInt(_kTimeoutConfirmacionSegundos, valor.clamp(1, 30));
    notifyListeners();
  }

  Future<bool> getCapturarTrasCeseMovimiento() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kCapturarTrasCeseMovimiento) ?? false;
  }

  Future<void> setCapturarTrasCeseMovimiento(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kCapturarTrasCeseMovimiento, valor);
    notifyListeners();
  }

  Future<bool> getModoContinuo() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kModoContinuo) ?? false;
  }

  Future<void> setModoContinuo(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kModoContinuo, valor);
    notifyListeners();
  }

  Future<double> getUmbralModoContinuo() async {
    final prefs = await _prefsInstancia;
    return prefs.getDouble(_kUmbralModoContinuo) ?? 80.0;
  }

  Future<void> setUmbralModoContinuo(double valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setDouble(
      _kUmbralModoContinuo,
      valor.clamp(50.0, 99.0).toDouble(),
    );
    notifyListeners();
  }

  Future<bool> getGuiaModoContinuoVista() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kGuiaModoContinuoVista) ?? false;
  }

  Future<void> setGuiaModoContinuoVista(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kGuiaModoContinuoVista, valor);
    notifyListeners();
  }

  Future<String> getModeloSeleccionado() async {
    final prefs = await _prefsInstancia;
    return prefs.getString(_kModeloSeleccionado) ??
        'assets/modelos/EfficientNet B0.tflite';
  }

  Future<void> setModeloSeleccionado(String assetPath) async {
    final prefs = await _prefsInstancia;
    await prefs.setString(_kModeloSeleccionado, assetPath);
    notifyListeners();
  }

  // --- Vinculación ESP32: activar/desactivar el envío automático ---
  Future<bool> getEspHabilitado() async {
    final prefs = await _prefsInstancia;
    return prefs.getBool(_kEspHabilitado) ?? false;
  }

  Future<void> setEspHabilitado(bool valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setBool(_kEspHabilitado, valor);
    notifyListeners();
  }

  // --- SSID de la red que crea la ESP32 (Access Point) ---
  Future<String> getEspSsid() async {
    final prefs = await _prefsInstancia;
    return prefs.getString(_kEspSsid) ?? kEspSsidDefault;
  }

  Future<void> setEspSsid(String valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setString(_kEspSsid, valor);
    notifyListeners();
  }

  // --- Contraseña de esa red ---
  Future<String> getEspPassword() async {
    final prefs = await _prefsInstancia;
    return prefs.getString(_kEspPassword) ?? kEspPasswordDefault;
  }

  Future<void> setEspPassword(String valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setString(_kEspPassword, valor);
    notifyListeners();
  }

  // --- IP del webserver de la ESP32 dentro de esa red ---
  Future<String> getEspIp() async {
    final prefs = await _prefsInstancia;
    return prefs.getString(_kEspIp) ?? kEspIpDefault;
  }

  Future<void> setEspIp(String valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setString(_kEspIp, valor);
    notifyListeners();
  }

  // --- Puerto del webserver (80 por defecto, configurable por si algún día
  // cambia en el firmware) ---
  Future<int> getEspPuerto() async {
    final prefs = await _prefsInstancia;
    return prefs.getInt(_kEspPuerto) ?? kEspPuertoDefault;
  }

  Future<void> setEspPuerto(int valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setInt(_kEspPuerto, valor);
    notifyListeners();
  }

  // --- Timeout de cada request HTTP a la ESP32, en milisegundos ---
  Future<int> getEspTimeoutMs() async {
    final prefs = await _prefsInstancia;
    return prefs.getInt(_kEspTimeoutMs) ?? kEspTimeoutMsDefault;
  }

  Future<void> setEspTimeoutMs(int valor) async {
    final prefs = await _prefsInstancia;
    await prefs.setInt(_kEspTimeoutMs, valor);
    notifyListeners();
  }
}
