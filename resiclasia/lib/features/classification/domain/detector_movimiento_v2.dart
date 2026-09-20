import 'dart:math';

class ResultadoDetectorMovimiento {
  const ResultadoDetectorMovimiento({
    required this.activo,
    required this.cambio,
    required this.puntuacion,
    required this.umbral,
  });

  final bool activo;
  final bool cambio;
  final double puntuacion;
  final double umbral;
}

/// Detector temporal resistente a cambios globales de exposición.
///
/// Compensa la variación media de brillo, aprende el ruido de la cámara y
/// exige varios frames consecutivos para activar o desactivar el estado.
class DetectorMovimientoV2 {
  bool _activo = false;
  int _framesActivos = 0;
  int _framesQuietos = 0;
  double _ruidoBase = 1.5;

  bool get activo => _activo;

  ResultadoDetectorMovimiento procesar({
    required List<double> anterior,
    required List<double> actual,
    required double sensibilidad,
  }) {
    if (anterior.length != actual.length || actual.isEmpty) {
      reset();
      return const ResultadoDetectorMovimiento(
        activo: false,
        cambio: false,
        puntuacion: 0,
        umbral: 0,
      );
    }

    final sensibilidadSegura = sensibilidad.clamp(0.0, 1.0);
    final cambios = List<double>.filled(actual.length, 0);
    for (var i = 0; i < actual.length; i++) {
      cambios[i] = actual[i] - anterior[i];
    }
    cambios.sort();
    final centro = cambios.length ~/ 2;
    final cambioGlobal = cambios.length.isOdd
        ? cambios[centro]
        : (cambios[centro - 1] + cambios[centro]) / 2;

    final residuos = List<double>.filled(actual.length, 0);
    var sumaResiduos = 0.0;
    for (var i = 0; i < actual.length; i++) {
      final residuo =
          ((actual[i] - anterior[i]) - cambioGlobal).abs().toDouble();
      residuos[i] = residuo;
      sumaResiduos += residuo;
    }
    final promedioResidual = sumaResiduos / residuos.length;

    final umbralSensibilidad = 3.0 + (1.0 - sensibilidadSegura) * 14.0;
    final umbral = max(umbralSensibilidad, _ruidoBase * 2.4);
    final celdasActivas = residuos.where((residuo) => residuo > umbral).length;
    final proporcionActiva = celdasActivas / residuos.length;
    final proporcionMinima = 0.08 + (1.0 - sensibilidadSegura) * 0.12;
    final candidato = proporcionActiva >= proporcionMinima &&
        promedioResidual >= umbral * 0.42;
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
    );
  }

  void reset() {
    _activo = false;
    _framesActivos = 0;
    _framesQuietos = 0;
    _ruidoBase = 1.5;
  }
}
