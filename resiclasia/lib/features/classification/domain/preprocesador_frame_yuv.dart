import 'dart:typed_data';

class PlanoFrameYuv {
  const PlanoFrameYuv({
    required this.bytes,
    required this.bytesPorFila,
    required this.bytesPorPixel,
  });

  final Uint8List bytes;
  final int bytesPorFila;
  final int bytesPorPixel;
}

/// Convierte YUV420 directamente al tensor RGB normalizado sin crear JPEG,
/// PNG ni objetos Image intermedios. El muestreo también recorta y redimensiona.
Float32List preprocesarFrameYuv420({
  required int ancho,
  required int alto,
  required List<PlanoFrameYuv> planos,
  required int rotacionGrados,
  required int tamanoDestino,
  required List<double> mean,
  required List<double> std,
  Float32List? bufferSalida,
  int anchoMuestreo = 0,
  int altoMuestreo = 0,
  bool letterbox = false,
  bool bgr = false,
}) {
  if (planos.length < 2 || ancho <= 0 || alto <= 0) {
    throw ArgumentError('El frame no contiene planos YUV420 válidos.');
  }

  final rotacion = ((rotacionGrados % 360) + 360) % 360;
  final intercambiaEjes = rotacion == 90 || rotacion == 270;
  final anchoRotado = intercambiaEjes ? alto : ancho;
  final altoRotado = intercambiaEjes ? ancho : alto;
  final ratio = anchoMuestreo > 0 && altoMuestreo > 0
      ? anchoMuestreo / altoMuestreo
      : 1.0;
  final sourceRatio = anchoRotado / altoRotado;
  final cropAncho = (letterbox ? sourceRatio < ratio : sourceRatio > ratio)
      ? altoRotado * ratio
      : anchoRotado.toDouble();
  final cropAlto = cropAncho / ratio;
  final origenX = (anchoRotado - cropAncho) / 2;
  final origenY = (altoRotado - cropAlto) / 2;
  final longitudEsperada = tamanoDestino * tamanoDestino * 3;
  if (bufferSalida != null && bufferSalida.length != longitudEsperada) {
    throw ArgumentError(
      'El buffer de salida debe contener $longitudEsperada valores.',
    );
  }
  final salida = bufferSalida ?? Float32List(longitudEsperada);

  var indiceSalida = 0;
  double posicion(int index, int tamanoMuestreo) {
    final fraction = (index + 0.5) / tamanoDestino;
    return tamanoMuestreo > 0
        ? ((fraction * tamanoMuestreo).floor() + 0.5) / tamanoMuestreo
        : fraction;
  }

  for (var dy = 0; dy < tamanoDestino; dy++) {
    final rawY = (origenY + posicion(dy, altoMuestreo) * cropAlto).floor();
    final ry = rawY.clamp(0, altoRotado - 1);
    for (var dx = 0; dx < tamanoDestino; dx++) {
      final rawX = (origenX + posicion(dx, anchoMuestreo) * cropAncho).floor();
      final rx = rawX.clamp(0, anchoRotado - 1);
      if (letterbox &&
          (rawX < 0 || rawX >= anchoRotado || rawY < 0 || rawY >= altoRotado)) {
        for (var c = 0; c < 3; c++) {
          salida[indiceSalida++] = -mean[c] / std[c];
        }
        continue;
      }

      late int sx;
      late int sy;
      switch (rotacion) {
        case 90:
          sx = ry;
          sy = alto - 1 - rx;
          break;
        case 180:
          sx = ancho - 1 - rx;
          sy = alto - 1 - ry;
          break;
        case 270:
          sx = ancho - 1 - ry;
          sy = rx;
          break;
        default:
          sx = rx;
          sy = ry;
      }

      final yPlano = planos[0];
      final uPlano = planos[1];
      final vPlano = planos.length >= 3 ? planos[2] : uPlano;
      final yIndice = sy * yPlano.bytesPorFila + sx * yPlano.bytesPorPixel;
      final uvX = sx ~/ 2;
      final uvY = sy ~/ 2;
      final uIndice = uvY * uPlano.bytesPorFila + uvX * uPlano.bytesPorPixel;
      final vIndice = planos.length >= 3
          ? uvY * vPlano.bytesPorFila + uvX * vPlano.bytesPorPixel
          : uIndice + 1;

      final luminancia = yPlano.bytes[yIndice].toDouble();
      final u = uPlano.bytes[uIndice] - 128.0;
      final v = vPlano.bytes[vIndice] - 128.0;
      final r = (luminancia + 1.402 * v).clamp(0.0, 255.0) / 255.0;
      final g =
          (luminancia - 0.344136 * u - 0.714136 * v).clamp(0.0, 255.0) / 255.0;
      final b = (luminancia + 1.772 * u).clamp(0.0, 255.0) / 255.0;

      salida[indiceSalida++] = ((bgr ? b : r) - mean[0]) / std[0];
      salida[indiceSalida++] = (g - mean[1]) / std[1];
      salida[indiceSalida++] = ((bgr ? r : b) - mean[2]) / std[2];
    }
  }
  return salida;
}
