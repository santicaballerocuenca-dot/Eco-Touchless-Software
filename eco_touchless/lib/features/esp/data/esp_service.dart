import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/domain/categoria_residuo.dart';
import '../../settings/data/config_service.dart';
import 'esp_actuadores_service.dart';
import '../domain/estado_controlador.dart';

/// Resultado de un intento de envío a la ESP32, para que la UI pueda dar
/// feedback claro sin tener que interpretar excepciones crudas.
enum EspEnvioEstado { enviado, noAplica, deshabilitado, error }

class EspEnvioResultado {
  final EspEnvioEstado estado;
  final String mensaje;
  const EspEnvioResultado(this.estado, this.mensaje);
}

class EspDiagnostico {
  const EspDiagnostico({
    required this.correcto,
    required this.endpoint,
    required this.duracion,
    required this.mensaje,
    this.codigoHttp,
    this.respuesta,
    this.controlador,
  });

  final bool correcto;
  final String endpoint;
  final Duration duracion;
  final int? codigoHttp;
  final String mensaje;
  final String? respuesta;
  final EstadoControlador? controlador;
}

/// Encapsula la comunicación HTTP con el ESP32 que controla los servos de
/// los basureros.
///
/// Compatibilidad con firmware anterior (mapa fijo):
///   /plastico  -> tapa compartida Plástico/Metal/Vidrio
///   /papel     -> tapa Papel/Cartón
///   /organico  -> tapa Orgánico
///
/// El firmware configurable usa /classify y el mapa confirmado por /config.
/// Fondo nunca acciona; las demás categorías dependen de los servos activos.
class EspService {
  EspService._interno() {
    ConfigService.instancia.addListener(_invalidarConfiguracion);
  }
  static final EspService instancia = EspService._interno();

  /// Mapeo label del modelo -> endpoint del ESP32. Los labels que no
  /// aparecen acá (Metal, Vidrio, NoAceptar, Fondo) simplemente no generan
  /// ningún tráfico de red.
  static const Map<String, String> _endpointPorLabel = {
    'Plastico': 'plastico',
    'Papel_carton': 'papel',
    'Organico': 'organico',
  };

  /// Evita mandar dos pedidos en simultáneo si el usuario dispara fotos muy
  /// rápido (el servo del ESP32 ya ignora pedidos mientras está en
  /// movimiento, pero total esto ahorra una llamada de red innecesaria).
  bool _enviando = false;
  http.Client _cliente = http.Client();
  bool get enviando => _enviando;
  void renovarConexion() {
    if (_enviando) return;
    _cliente.close();
    _cliente = http.Client();
  }

  bool _configuracionLista = false;
  Future<void>? _preparacionEnCurso;
  int _generacionConfiguracion = 0;
  bool _habilitado = false;
  String _ip = ConfigService.kEspIpDefault;
  int _puerto = ConfigService.kEspPuertoDefault;
  int _timeoutMs = ConfigService.kEspTimeoutMsDefault;
  final Map<String, Uri> _urisOrden = {};

  static bool puedeAccionar(String label) {
    final remoto = EspActuadoresService.instancia;
    return remoto.actual?.puedeAccionar(label) ??
        (remoto.legado && puedeAccionarLegado(label));
  }

  static bool puedeAccionarLegado(String label) =>
      _endpointPorLabel.containsKey(label);

  void _invalidarConfiguracion() {
    _generacionConfiguracion++;
    _configuracionLista = false;
    _urisOrden.clear();
  }

  /// Precarga la configuración para que el primer disparo en vivo no espere
  /// lecturas de SharedPreferences.
  Future<void> preparar() {
    if (_configuracionLista) return Future.value();
    final preparacionActual = _preparacionEnCurso;
    if (preparacionActual != null) return preparacionActual;

    final nuevaPreparacion = _cargarConfiguracionVigente();
    _preparacionEnCurso = nuevaPreparacion;
    return nuevaPreparacion.whenComplete(() {
      if (identical(_preparacionEnCurso, nuevaPreparacion)) {
        _preparacionEnCurso = null;
      }
    });
  }

  Future<void> _cargarConfiguracionVigente() async {
    final config = ConfigService.instancia;
    while (!_configuracionLista) {
      final generacionAlIniciar = _generacionConfiguracion;
      final valores = await Future.wait<Object>([
        config.getEspHabilitado(),
        config.getEspIp(),
        config.getEspPuerto(),
        config.getEspTimeoutMs(),
      ]);
      if (generacionAlIniciar != _generacionConfiguracion) continue;
      _habilitado = valores[0] as bool;
      _ip = valores[1] as String;
      _puerto = valores[2] as int;
      _timeoutMs = valores[3] as int;
      _configuracionLista = true;
    }
  }

  /// Abre anticipadamente la conexión TCP mediante el endpoint seguro
  /// `/status`; el mismo [Client] puede reutilizarla para la primera orden.
  Future<void> precalentarConexion() async {
    await preparar();
    if (!_habilitado ||
        !esHostLocalValido(_ip) ||
        _puerto < 1 ||
        _puerto > 65535) {
      return;
    }
    try {
      await _cliente
          .get(Uri.http('$_ip:$_puerto', '/status'))
          .timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      // Es una optimización oportunista. El envío real informará cualquier
      // problema de red con su mensaje habitual.
    }
  }

  /// Solo permite hosts de red privada o nombres mDNS locales. Evita que una
  /// configuración manipulada convierta la app en un cliente HTTP arbitrario.
  static bool esHostLocalValido(String host) {
    final normalizado = host.trim().toLowerCase();
    if (RegExp(r'^[a-z0-9][a-z0-9-]{0,61}\.local$').hasMatch(normalizado)) {
      return true;
    }
    final partes = normalizado.split('.');
    if (partes.length != 4) return false;
    final octetos = partes.map(int.tryParse).toList();
    if (octetos.any((valor) => valor == null || valor < 0 || valor > 255)) {
      return false;
    }
    final a = octetos[0]!;
    final b = octetos[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254);
  }

  /// Envía el resultado de una clasificación a la ESP32, si corresponde.
  /// Devuelve un [EspEnvioResultado] siempre (nunca lanza), para que la UI
  /// pueda mostrar feedback sin try/catch propio.
  Future<EspEnvioResultado> enviarClasificacion(String label) async {
    await preparar();
    if (!_habilitado) {
      return const EspEnvioResultado(
        EspEnvioEstado.deshabilitado,
        'Vinculación con ESP32 desactivada.',
      );
    }

    final actuadores = EspActuadoresService.instancia;
    try {
      await actuadores.sincronizar();
    } catch (_) {
      return const EspEnvioResultado(EspEnvioEstado.error,
          'No se pudo leer la configuración de la ESP32. Revisá IP y puerto.');
    }
    await preparar();
    if (!_habilitado) {
      return const EspEnvioResultado(
          EspEnvioEstado.deshabilitado, 'Envío desactivado.');
    }
    final remoto = actuadores.actual;
    final endpoint = remoto != null
        ? 'classify'
        : actuadores.legado
            ? _endpointPorLabel[label]
            : null;
    if (actuadores.guardando || (remoto == null && !actuadores.legado)) {
      return const EspEnvioResultado(EspEnvioEstado.error,
          'No se pudo verificar la configuración de servos. Revisá conexión y clave de control.');
    }
    if (endpoint == null || (remoto != null && !remoto.puedeAccionar(label))) {
      return const EspEnvioResultado(
        EspEnvioEstado.noAplica,
        'Este residuo no abre ninguna tapa automáticamente.',
      );
    }

    if (_enviando) {
      return const EspEnvioResultado(
        EspEnvioEstado.error,
        'Ya hay un envío en curso, se ignora este.',
      );
    }

    if (!esHostLocalValido(_ip) || _puerto < 1 || _puerto > 65535) {
      return const EspEnvioResultado(
        EspEnvioEstado.error,
        'La dirección configurada para la ESP32 no es una red local válida.',
      );
    }

    _enviando = true;
    try {
      final uriBase = _urisOrden.putIfAbsent(
        endpoint,
        () => Uri.http('$_ip:$_puerto', '/$endpoint'),
      );
      final uri = remoto == null
          ? uriBase
          : uriBase.replace(queryParameters: {
              'label': label,
              'deviceId': remoto.deviceId,
              'bootId': remoto.bootId,
              'revision': '${remoto.revision}',
              'requestId':
                  '${DateTime.now().microsecondsSinceEpoch}-${_secuenciaOrden++}',
            });
      // Una orden física no se reintenta automáticamente: si la tapa se abrió
      // pero se perdió la respuesta, repetir el GET podría accionar dos veces.
      final respuesta = await _cliente.get(uri, headers: {
        'X-Api-Key': await ConfigService.instancia.getEspApiKey()
      }).timeout(
        Duration(milliseconds: _timeoutMs.clamp(500, 15000).toInt()),
      );
      if (respuesta.statusCode == 200) {
        return EspEnvioResultado(
          EspEnvioEstado.enviado,
          'Apertura de ${CategoriaResiduo.nombreVisible(label)} aceptada por la ESP32.',
        );
      }
      if (respuesta.statusCode == 409) actuadores.invalidar();
      return EspEnvioResultado(
        EspEnvioEstado.error,
        'La ESP32 rechazó la orden (HTTP ${respuesta.statusCode}).',
      );
    } on TimeoutException {
      return const EspEnvioResultado(
        EspEnvioEstado.error,
        'La ESP32 no respondió a tiempo. Revisá la conexión Wi-Fi.',
      );
    } on SocketException catch (e) {
      debugPrint('EspService: error de red: ${e.message}');
      return const EspEnvioResultado(
        EspEnvioEstado.error,
        'No se pudo contactar a la ESP32. Revisá la conexión Wi-Fi.',
      );
    } catch (e) {
      debugPrint('EspService: error enviando la orden: $e');
      return const EspEnvioResultado(
        EspEnvioEstado.error,
        'La orden no pudo enviarse por una configuración o respuesta inválida.',
      );
    } finally {
      _enviando = false;
    }
  }

  static int _secuenciaOrden = 0;

  /// Consulta /status en la ESP32, útil para el botón "Probar conexión" en
  /// Configuración.
  Future<EspEnvioResultado> probarConexion() async {
    final diagnostico = await diagnosticar();
    return EspEnvioResultado(
      diagnostico.correcto ? EspEnvioEstado.enviado : EspEnvioEstado.error,
      diagnostico.mensaje,
    );
  }

  /// Verifica configuración, latencia, código HTTP y contenido de /status.
  Future<EspDiagnostico> diagnosticar() async {
    await preparar();
    if (!esHostLocalValido(_ip) || _puerto < 1 || _puerto > 65535) {
      return const EspDiagnostico(
        correcto: false,
        endpoint: '',
        duracion: Duration.zero,
        mensaje:
            'La dirección configurada no es una IP privada o un nombre .local válido.',
      );
    }

    final uri = Uri.http('$_ip:$_puerto', '/status');
    final reloj = Stopwatch()..start();
    try {
      final respuesta = await _cliente.get(uri).timeout(
            Duration(milliseconds: _timeoutMs.clamp(500, 15000).toInt()),
          );
      reloj.stop();
      final cuerpo = respuesta.body.trim();
      final resumen = cuerpo.isEmpty
          ? null
          : cuerpo.substring(0, cuerpo.length.clamp(0, 160));
      if (respuesta.statusCode == 200) {
        return EspDiagnostico(
          correcto: true,
          endpoint: uri.toString(),
          duracion: reloj.elapsed,
          codigoHttp: respuesta.statusCode,
          respuesta: resumen,
          controlador: EstadoControlador.leer(cuerpo),
          mensaje:
              'Conectado en ${reloj.elapsedMilliseconds} ms. La ESP32 responde correctamente.',
        );
      }
      return EspDiagnostico(
        correcto: false,
        endpoint: uri.toString(),
        duracion: reloj.elapsed,
        codigoHttp: respuesta.statusCode,
        respuesta: resumen,
        mensaje: 'La ESP32 respondió con HTTP ${respuesta.statusCode}.',
      );
    } on TimeoutException {
      reloj.stop();
      return EspDiagnostico(
        correcto: false,
        endpoint: uri.toString(),
        duracion: reloj.elapsed,
        mensaje: 'Sin respuesta después de ${reloj.elapsedMilliseconds} ms. '
            'Verificá la red Wi-Fi, la IP y que la ESP32 esté encendida.',
      );
    } catch (e) {
      reloj.stop();
      debugPrint('EspService: error probando conexión: $e');
      return EspDiagnostico(
        correcto: false,
        endpoint: uri.toString(),
        duracion: reloj.elapsed,
        mensaje: 'No se pudo conectar. Revisá la IP, el puerto y la red Wi-Fi.',
      );
    }
  }
}
