import 'dart:math';

class ResultadoDetectorMovimiento {
  const ResultadoDetectorMovimiento({
    required this.activo,
    required this.cambio,
    required this.puntuacion,
    required this.umbral,
    this.grupoMayor = 0,
    this.lumaMedia = 0,
  });

  final bool activo;
  final bool cambio;
  final double puntuacion;
  final double umbral;

  /// Celdas del mayor grupo conexo de cambio (vecindad de 4). Un objeto real
  /// mueve celdas contiguas; el ruido del sensor aparece disperso.
  final int grupoMayor;

  /// Brillo medio (0–255) del frame actual.
  final double lumaMedia;
}

/// Detector temporal resistente a cambios globales de exposición.
///
/// Compensa la variación media de brillo, aprende el ruido de la cámara y
/// exige varios frames consecutivos para activar o desactivar el estado.
/// Además puede ponderar zonas del visor ([pesos]), descarta cambios
/// dispersos que no forman un grupo contiguo y relaja el umbral con poca luz,
/// donde el contraste de un objeto real es menor.
class DetectorMovimientoV2 {
  bool _activo = false;
  int _framesActivos = 0;
  int _framesQuietos = 0;
  double _ruidoBase = 1.5;

  bool get activo => _activo;
  double get ruidoBase => _ruidoBase;

  ResultadoDetectorMovimiento procesar({
    required List<double> anterior,
    required List<double> actual,
    required double sensibilidad,
    List<double>? pesos,
    int? columnas,
    int grupoMinimo = 3,
  }) {
    if (anterior.length != actual.length ||
        actual.isEmpty ||
        (pesos != null && pesos.length != actual.length)) {
      reset();
      return const ResultadoDetectorMovimiento(
        activo: false,
        cambio: false,
        puntuacion: 0,
        umbral: 0,
      );
    }

    final sensibilidadSegura = sensibilidad.clamp(0.0, 1.0);
    final lumaMedia = media(actual);
    final cambioGlobal = mediana([
      for (var i = 0; i < actual.length; i++) actual[i] - anterior[i],
    ]);

    final residuos = List<double>.filled(actual.length, 0);
    var sumaResiduos = 0.0;
    var sumaPesos = 0.0;
    for (var i = 0; i < actual.length; i++) {
      final residuo =
          ((actual[i] - anterior[i]) - cambioGlobal).abs().toDouble();
      final peso = pesos?[i] ?? 1.0;
      residuos[i] = residuo;
      sumaResiduos += residuo * peso;
      sumaPesos += peso;
    }
    final promedioResidual = sumaPesos <= 0 ? 0.0 : sumaResiduos / sumaPesos;

    final umbralSensibilidad =
        (3.0 + (1.0 - sensibilidadSegura) * 14.0) * factorPocaLuz(lumaMedia);
    final umbral = max(umbralSensibilidad, _ruidoBase * 2.4);
    final activas = [for (final r in residuos) r > umbral];
    final proporcionActiva = proporcionPonderada(activas, pesos);
    final grupo = grupoMayor(activas, columnas: columnas, pesos: pesos);
    final proporcionMinima = 0.08 + (1.0 - sensibilidadSegura) * 0.12;
    final hayGrupo = grupo < 0 || grupo >= grupoMinimo;
    final candidato = proporcionActiva >= proporcionMinima &&
        promedioResidual >= umbral * 0.42 &&
        hayGrupo;
    final residuoMaximo = residuos.reduce(max);
    final candidatoFuerte = candidato && residuoMaximo >= umbral * 3;

    if (!candidato) {
      // Solo aprende ruido en frames tranquilos para no absorber un objeto
      // en movimiento dentro del fondo adaptativo.
      _ruidoBase = (_ruidoBase * 0.9 + promedioResidual * 0.1).clamp(0.8, 12.0);
      _framesQuietos++;
      _framesActivos = 0;
    } else {
      _framesActivos++;
      _framesQuietos = 0;
    }

    final estadoAnterior = _activo;
    if (!_activo && (candidatoFuerte || _framesActivos >= 2)) {
      _activo = true;
    } else if (_activo && _framesQuietos >= 3) {
      _activo = false;
    }

    return ResultadoDetectorMovimiento(
      activo: _activo,
      cambio: estadoAnterior != _activo,
      puntuacion: proporcionActiva,
      umbral: umbral,
      grupoMayor: max(grupo, 0),
      lumaMedia: lumaMedia,
    );
  }

  void reset() {
    _activo = false;
    _framesActivos = 0;
    _framesQuietos = 0;
    _ruidoBase = 1.5;
  }

  /// Con poca luz la cámara sube la ganancia y el contraste entre un objeto
  /// y el fondo cae: se baja el umbral hasta la mitad, nunca por debajo del
  /// ruido aprendido (que sigue acotando el mínimo en [procesar]).
  static double factorPocaLuz(double lumaMedia) =>
      (lumaMedia / 90.0).clamp(0.5, 1.0).toDouble();

  static double media(List<double> valores) {
    if (valores.isEmpty) return 0;
    var suma = 0.0;
    for (final v in valores) {
      suma += v;
    }
    return suma / valores.length;
  }

  static double mediana(List<double> valores) {
    if (valores.isEmpty) return 0;
    final ordenados = List<double>.of(valores)..sort();
    final centro = ordenados.length ~/ 2;
    return ordenados.length.isOdd
        ? ordenados[centro]
        : (ordenados[centro - 1] + ordenados[centro]) / 2;
  }

  static double proporcionPonderada(List<bool> activas, List<double>? pesos) {
    if (activas.isEmpty) return 0;
    if (pesos == null) {
      return activas.where((a) => a).length / activas.length;
    }
    var total = 0.0;
    var activo = 0.0;
    for (var i = 0; i < activas.length; i++) {
      total += pesos[i];
      if (activas[i]) activo += pesos[i];
    }
    return total <= 0 ? 0 : activo / total;
  }

  /// Tamaño del mayor grupo conexo de celdas activas. Devuelve -1 si la
  /// grilla no es rectangular conocida (no se puede evaluar la vecindad).
  /// Las celdas con peso menor a 0,3 no cuentan para formar grupos.
  static int grupoMayor(
    List<bool> activas, {
    int? columnas,
    List<double>? pesos,
  }) {
    final n = activas.length;
    final ancho = columnas ?? _ladoCuadrado(n);
    if (ancho == null || ancho <= 0 || n % ancho != 0) return -1;
    bool cuenta(int i) => activas[i] && (pesos == null || pesos[i] >= 0.3);
    final visitada = List<bool>.filled(n, false);
    final pila = <int>[];
    var mayor = 0;
    for (var inicio = 0; inicio < n; inicio++) {
      if (visitada[inicio] || !cuenta(inicio)) continue;
      var tamano = 0;
      visitada[inicio] = true;
      pila.add(inicio);
      while (pila.isNotEmpty) {
        final i = pila.removeLast();
        tamano++;
        final x = i % ancho;
        final vecinos = [
          if (x > 0) i - 1,
          if (x < ancho - 1) i + 1,
          if (i - ancho >= 0) i - ancho,
          if (i + ancho < n) i + ancho,
        ];
        for (final v in vecinos) {
          if (!visitada[v] && cuenta(v)) {
            visitada[v] = true;
            pila.add(v);
          }
        }
      }
      mayor = max(mayor, tamano);
    }
    return mayor;
  }

  static int? _ladoCuadrado(int n) {
    final lado = sqrt(n).round();
    return lado * lado == n ? lado : null;
  }
}
