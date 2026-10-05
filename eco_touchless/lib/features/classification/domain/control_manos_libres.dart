import 'dart:math';

import 'detector_movimiento_v2.dart';

/// Etapas del disparo automático "sin tocar la tablet".
enum FaseManosLibres {
  /// Escena tranquila: esperando que alguien acerque un residuo.
  esperando,

  /// Hay movimiento en el visor (una mano acercando algo).
  movimiento,

  /// El movimiento cesó y hay algo delante: se cuenta el tiempo de quietud.
  estabilizando,

  /// Ya se disparó una captura; espera a que retiren el residuo (o cambie la
  /// escena) antes de volver a armarse, para no repetir la misma foto.
  enfriamiento,
}

class ConfiguracionManosLibres {
  const ConfiguracionManosLibres({
    this.sensibilidad = 0.5,
    this.retardoQuietud = const Duration(milliseconds: 1200),
    this.zonaCentral = true,
    this.requierePresencia = true,
    this.esperaMaximaMovimiento = const Duration(seconds: 5),
    this.enfriamientoMinimo = const Duration(milliseconds: 1500),
    this.absorberFondoTras = const Duration(seconds: 20),
  });

  /// 0 = poco sensible, 1 = muy sensible.
  final double sensibilidad;

  /// Tiempo que el residuo debe quedar quieto antes de sacar la foto.
  final Duration retardoQuietud;

  /// Prioriza el centro del visor e ignora casi por completo los bordes, donde
  /// suele pasar gente caminando detrás del clasificador.
  final bool zonaCentral;

  /// Si es `true`, solo captura cuando queda un objeto delante (distinto del
  /// fondo aprendido). Evita fotos vacías cuando una mano pasa y se va.
  final bool requierePresencia;

  /// Si el residuo sigue moviéndose (por ejemplo, sostenido con la mano)
  /// durante este tiempo, se captura igual.
  final Duration esperaMaximaMovimiento;

  /// Pausa mínima entre dos capturas automáticas.
  final Duration enfriamientoMinimo;

  /// Un cambio estático que persiste este tiempo pasa a formar parte del
  /// fondo (por ejemplo, alguien movió la tablet o dejó algo fijo).
  final Duration absorberFondoTras;
}

class EstadoManosLibres {
  const EstadoManosLibres({
    required this.fase,
    required this.progreso,
    required this.capturar,
    required this.presencia,
    required this.movimiento,
    required this.lumaMedia,
    required this.oscuro,
    required this.cambioOscuridad,
  });

  final FaseManosLibres fase;

  /// Avance de la quietud (0–1) mientras la fase es [FaseManosLibres.estabilizando].
  final double progreso;

  /// `true` solamente en el frame en que hay que sacar la foto.
  final bool capturar;
  final bool presencia;
  final bool movimiento;
  final double lumaMedia;
  final bool oscuro;

  /// `true` en el frame en que [oscuro] cambió de valor.
  final bool cambioOscuridad;
}

/// Decide cuándo la escena está demasiado oscura para una buena foto.
///
/// Usa histéresis y frames consecutivos para no parpadear. Mientras la
/// pantalla ilumina la escena, el brillo medido sube por la propia luz de la
/// pantalla: para apagarla se exige que la escena supere claramente el brillo
/// de referencia registrado con la luz encendida (señal de que volvió la luz
/// ambiente).
class DetectorPocaLuz {
  DetectorPocaLuz({
    this.umbralEntrada = 50,
    this.umbralSalida = 85,
    this.framesEntrada = 5,
    this.framesSalida = 10,
    this.margenConLuz = 45,
  });

  final double umbralEntrada;
  final double umbralSalida;
  final int framesEntrada;
  final int framesSalida;
  final double margenConLuz;

  bool _oscuro = false;
  int _contador = 0;
  double? _referenciaConLuz;

  bool get oscuro => _oscuro;

  /// Devuelve `true` si el estado cambió en este frame.
  bool actualizar(double luma, {required bool iluminando}) {
    if (!_oscuro) {
      _contador = luma < umbralEntrada ? _contador + 1 : 0;
      if (_contador >= framesEntrada) {
        _oscuro = true;
        _contador = 0;
        _referenciaConLuz = null;
        return true;
      }
      return false;
    }

    if (iluminando) {
      // El primer frame tras estabilizarse la luz fija la referencia; luego
      // solo baja (nunca sube) para no perseguir a la escena.
      final ref = _referenciaConLuz;
      _referenciaConLuz = ref == null ? luma : min(ref, luma);
    }
    final salida = iluminando
        ? max(umbralSalida, (_referenciaConLuz ?? luma) + margenConLuz)
        : umbralSalida;
    _contador = luma > salida ? _contador + 1 : 0;
    if (_contador >= framesSalida) {
      _oscuro = false;
      _contador = 0;
      _referenciaConLuz = null;
      return true;
    }
    return false;
  }

  /// Olvida la referencia con luz (p. ej., tras encender o apagar la
  /// iluminación de pantalla o cambiar de cámara).
  void olvidarReferencia() => _referenciaConLuz = null;

  void reset() {
    _oscuro = false;
    _contador = 0;
    _referenciaConLuz = null;
  }
}

/// Motor del modo manos libres: combina movimiento entre frames, presencia de
/// un objeto respecto de un fondo aprendido y quietud para decidir el mejor
/// momento de sacar la foto, sin que nadie toque la pantalla.
///
/// Flujo típico: alguien acerca un residuo (movimiento) → lo sostiene o lo
/// apoya (quietud + presencia) → foto → se retira el residuo (rearme).
/// Una mano que entra y sale sin dejar nada no dispara, porque al quedar
/// quieta la escena vuelve a coincidir con el fondo.
class ControlManosLibres {
  ControlManosLibres({this.columnas = 16, DetectorPocaLuz? detectorLuz})
      : luz = detectorLuz ?? DetectorPocaLuz();

  final int columnas;
  final DetectorPocaLuz luz;
  final _detector = DetectorMovimientoV2();

  List<double>? _anterior;
  List<double>? _fondo;
  List<double>? _instantaneaCaptura;
  List<double>? _pesos;
  bool? _pesosZonaCentral;

  FaseManosLibres _fase = FaseManosLibres.esperando;
  bool _armado = true;
  int _framesIgnorar = 0;
  DateTime? _inicioMovimiento;
  DateTime? _inicioQuietud;
  DateTime? _inicioPresenciaQuieta;
  DateTime? _ultimaCaptura;

  FaseManosLibres get fase => _fase;
  bool get armado => _armado;

  EstadoManosLibres procesar(
    List<double> actual, {
    required DateTime ahora,
    ConfiguracionManosLibres config = const ConfiguracionManosLibres(),
    bool iluminando = false,
  }) {
    final lumaMedia = DetectorMovimientoV2.media(actual);
    final cambioOscuridad = luz.actualizar(lumaMedia, iluminando: iluminando);
    final pesos = _pesosPara(actual.length, config.zonaCentral);

    if (_framesIgnorar > 0 ||
        _fondo == null ||
        _fondo!.length != actual.length) {
      // Tras una pausa (foto, flash, cambio de luz) la cámara reajusta la
      // exposición: se descartan unos frames y se reaprende el fondo si hace
      // falta, sin perder el estado de armado.
      if (_framesIgnorar > 0) _framesIgnorar--;
      if (_fondo == null || _fondo!.length != actual.length) {
        _fondo = List<double>.of(actual);
      }
      _anterior = List<double>.of(actual);
      return _estado(
        progreso: 0,
        capturar: false,
        presencia: false,
        movimiento: false,
        lumaMedia: lumaMedia,
        cambioOscuridad: cambioOscuridad,
      );
    }

    final anterior = _anterior;
    _anterior = List<double>.of(actual);
    final movimiento = anterior == null
        ? false
        : _detector
            .procesar(
              anterior: anterior,
              actual: actual,
              sensibilidad: config.sensibilidad,
              pesos: pesos,
              columnas: columnas,
            )
            .activo;
    final presencia = _difiere(_fondo!, actual, config.sensibilidad, pesos);

    _actualizarFondo(actual, ahora, config, movimiento, presencia);

    if (!_armado) {
      final cambioEscena = _instantaneaCaptura != null &&
          _difiere(_instantaneaCaptura!, actual, config.sensibilidad, pesos);
      final ultima = _ultimaCaptura;
      final enfriado = ultima == null ||
          ahora.difference(ultima) >= config.enfriamientoMinimo;
      if (enfriado && (!presencia || cambioEscena)) {
        _armado = true;
        _fase = FaseManosLibres.esperando;
        _instantaneaCaptura = null;
        _inicioMovimiento = null;
        _inicioQuietud = null;
      } else {
        _fase = FaseManosLibres.enfriamiento;
        return _estado(
          progreso: 0,
          capturar: false,
          presencia: presencia,
          movimiento: movimiento,
          lumaMedia: lumaMedia,
          cambioOscuridad: cambioOscuridad,
        );
      }
    }

    var capturar = false;
    var progreso = 0.0;
    if (movimiento) {
      if (_fase != FaseManosLibres.movimiento) {
        _inicioMovimiento ??= ahora;
      }
      _fase = FaseManosLibres.movimiento;
      _inicioQuietud = null;
      final inicio = _inicioMovimiento ?? ahora;
      // Un residuo sostenido con la mano nunca queda perfectamente quieto:
      // tras la espera máxima se captura igual si hay algo delante.
      if ((presencia || !config.requierePresencia) &&
          ahora.difference(inicio) >= config.esperaMaximaMovimiento) {
        capturar = true;
      }
    } else if (_fase == FaseManosLibres.movimiento ||
        _fase == FaseManosLibres.estabilizando ||
        (_fase == FaseManosLibres.esperando && presencia)) {
      if (config.requierePresencia && !presencia) {
        // Pasó una mano y se fue sin dejar nada: no hay qué fotografiar.
        _volverAEsperar();
      } else {
        _fase = FaseManosLibres.estabilizando;
        final inicio = _inicioQuietud ??= ahora;
        final quieto = ahora.difference(inicio);
        final total = max(1, config.retardoQuietud.inMilliseconds);
        progreso = (quieto.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
        if (quieto >= config.retardoQuietud) capturar = true;
      }
    }

    if (capturar) {
      _armado = false;
      _ultimaCaptura = ahora;
      _instantaneaCaptura = List<double>.of(actual);
      _inicioMovimiento = null;
      _inicioQuietud = null;
      _fase = FaseManosLibres.enfriamiento;
      progreso = 1;
    }

    return _estado(
      progreso: progreso,
      capturar: capturar,
      presencia: presencia,
      movimiento: movimiento,
      lumaMedia: lumaMedia,
      cambioOscuridad: cambioOscuridad,
    );
  }

  /// La cámara se detiene un momento (foto, flash, cambio de cámara): olvida
  /// el frame anterior y descarta algunos frames mientras se reajusta la
  /// exposición. Conserva el fondo y el estado de armado.
  void pausar({int framesIgnorar = 4}) {
    _anterior = null;
    _framesIgnorar = max(_framesIgnorar, framesIgnorar);
    _detector.reset();
    _inicioQuietud = null;
  }

  /// La iluminación de la escena cambió de golpe (se encendió o apagó la luz
  /// de pantalla): hay que reaprender el fondo con la nueva luz.
  void notificarCambioIluminacion() {
    pausar(framesIgnorar: 5);
    _fondo = null;
    _instantaneaCaptura = null;
    luz.olvidarReferencia();
  }

  /// Permite volver a capturar sin retirar el residuo (p. ej., el resultado
  /// fue dudoso y conviene intentar otra vez).
  void rearmar() {
    _armado = true;
    _instantaneaCaptura = null;
    _volverAEsperar();
  }

  void reiniciar() {
    _anterior = null;
    _fondo = null;
    _instantaneaCaptura = null;
    _armado = true;
    _framesIgnorar = 0;
    _ultimaCaptura = null;
    _inicioPresenciaQuieta = null;
    _detector.reset();
    luz.reset();
    _volverAEsperar();
  }

  void _volverAEsperar() {
    _fase = FaseManosLibres.esperando;
    _inicioMovimiento = null;
    _inicioQuietud = null;
  }

  void _actualizarFondo(
    List<double> actual,
    DateTime ahora,
    ConfiguracionManosLibres config,
    bool movimiento,
    bool presencia,
  ) {
    final fondo = _fondo!;
    if (!movimiento && !presencia) {
      // Escena vacía y tranquila: el fondo sigue cambios lentos de luz.
      for (var i = 0; i < fondo.length; i++) {
        fondo[i] = fondo[i] * 0.9 + actual[i] * 0.1;
      }
      _inicioPresenciaQuieta = null;
      return;
    }
    if (movimiento || _fase == FaseManosLibres.estabilizando) {
      _inicioPresenciaQuieta = null;
      return;
    }
    final inicio = _inicioPresenciaQuieta ??= ahora;
    if (ahora.difference(inicio) >= config.absorberFondoTras) {
      _fondo = List<double>.of(actual);
      _inicioPresenciaQuieta = null;
    }
  }

  /// `true` si [actual] difiere de [referencia] en una zona contigua
  /// suficientemente grande, descontando el cambio global de exposición.
  bool _difiere(
    List<double> referencia,
    List<double> actual,
    double sensibilidad,
    List<double> pesos,
  ) {
    if (referencia.length != actual.length || actual.isEmpty) return false;
    final s = sensibilidad.clamp(0.0, 1.0);
    final diferencias = [
      for (var i = 0; i < actual.length; i++) actual[i] - referencia[i],
    ];
    final global = DetectorMovimientoV2.mediana(diferencias);
    final umbral = max(
      (7.0 + (1.0 - s) * 16.0) *
          DetectorMovimientoV2.factorPocaLuz(
              DetectorMovimientoV2.media(actual)),
      _detector.ruidoBase * 3,
    );
    final activas = [for (final d in diferencias) (d - global).abs() > umbral];
    final proporcion = DetectorMovimientoV2.proporcionPonderada(activas, pesos);
    final grupo = DetectorMovimientoV2.grupoMayor(
      activas,
      columnas: columnas,
      pesos: pesos,
    );
    final proporcionMinima = 0.035 + (1.0 - s) * 0.06;
    return proporcion >= proporcionMinima && (grupo < 0 || grupo >= 3);
  }

  List<double> _pesosPara(int celdas, bool zonaCentral) {
    final cache = _pesos;
    if (cache != null &&
        cache.length == celdas &&
        _pesosZonaCentral == zonaCentral) {
      return cache;
    }
    _pesosZonaCentral = zonaCentral;
    return _pesos = pesosZona(celdas, columnas, zonaCentral: zonaCentral);
  }

  /// Pesos por celda: con [zonaCentral] el 65 % central pesa 1, el anillo
  /// siguiente 0,4 y los bordes 0,1.
  static List<double> pesosZona(
    int celdas,
    int columnas, {
    required bool zonaCentral,
  }) {
    if (!zonaCentral || columnas <= 0 || celdas % columnas != 0) {
      return List<double>.filled(celdas, 1);
    }
    final filas = celdas ~/ columnas;
    return [
      for (var y = 0; y < filas; y++)
        for (var x = 0; x < columnas; x++)
          () {
            final nx = ((x + 0.5) / columnas) * 2 - 1;
            final ny = ((y + 0.5) / filas) * 2 - 1;
            final d = max(nx.abs(), ny.abs());
            if (d <= 0.65) return 1.0;
            if (d <= 0.85) return 0.4;
            return 0.1;
          }(),
    ];
  }

  EstadoManosLibres _estado({
    required double progreso,
    required bool capturar,
    required bool presencia,
    required bool movimiento,
    required double lumaMedia,
    required bool cambioOscuridad,
  }) =>
      EstadoManosLibres(
        fase: _fase,
        progreso: progreso,
        capturar: capturar,
        presencia: presencia,
        movimiento: movimiento,
        lumaMedia: lumaMedia,
        oscuro: luz.oscuro,
        cambioOscuridad: cambioOscuridad,
      );
}
