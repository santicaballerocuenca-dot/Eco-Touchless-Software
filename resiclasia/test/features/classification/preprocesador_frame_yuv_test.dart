import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/classification/domain/preprocesador_frame_yuv.dart';

void main() {
  test('convierte YUV420 de tres planos directamente a Float32', () {
    final buffer = Float32List(12);
    final salida = preprocesarFrameYuv420(
      ancho: 4,
      alto: 4,
      planos: [
        PlanoFrameYuv(
          bytes: Uint8List.fromList(List.filled(16, 128)),
          bytesPorFila: 4,
          bytesPorPixel: 1,
        ),
        PlanoFrameYuv(
          bytes: Uint8List.fromList(List.filled(4, 128)),
          bytesPorFila: 2,
          bytesPorPixel: 1,
        ),
        PlanoFrameYuv(
          bytes: Uint8List.fromList(List.filled(4, 128)),
          bytesPorFila: 2,
          bytesPorPixel: 1,
        ),
      ],
      rotacionGrados: 90,
      tamanoDestino: 2,
      mean: const [0, 0, 0],
      std: const [1, 1, 1],
      bufferSalida: buffer,
    );

    expect(identical(salida, buffer), isTrue);
    expect(salida, hasLength(12));
    for (final canal in salida) {
      expect(canal, closeTo(128 / 255, 0.001));
    }
  });

  test('admite UV intercalado de dos planos', () {
    final salida = preprocesarFrameYuv420(
      ancho: 2,
      alto: 2,
      planos: [
        PlanoFrameYuv(
          bytes: Uint8List.fromList(List.filled(4, 100)),
          bytesPorFila: 2,
          bytesPorPixel: 1,
        ),
        PlanoFrameYuv(
          bytes: Uint8List.fromList([128, 128]),
          bytesPorFila: 2,
          bytesPorPixel: 2,
        ),
      ],
      rotacionGrados: 0,
      tamanoDestino: 1,
      mean: const [0, 0, 0],
      std: const [1, 1, 1],
    );

    expect(salida, hasLength(3));
    expect(salida[0], closeTo(100 / 255, 0.001));
  });
}
