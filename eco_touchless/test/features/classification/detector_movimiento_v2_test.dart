import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/features/classification/domain/detector_movimiento_v2.dart';

void main() {
  group('DetectorMovimientoV2', () {
    test('ignora un cambio global de exposición', () {
      final detector = DetectorMovimientoV2();
      final anterior = List<double>.filled(256, 80);
      final actual = List<double>.filled(256, 110);

      final resultado = detector.procesar(
        anterior: anterior,
        actual: actual,
        sensibilidad: 0.5,
      );

      expect(resultado.activo, isFalse);
      expect(resultado.puntuacion, 0);
    });

    test('detecta un cambio localizado fuerte', () {
      final detector = DetectorMovimientoV2();
      final anterior = List<double>.filled(256, 80);
      final actual = List<double>.from(anterior);
      for (var i = 0; i < 48; i++) {
        actual[i] = 160;
      }

      final resultado = detector.procesar(
        anterior: anterior,
        actual: actual,
        sensibilidad: 0.5,
      );

      expect(resultado.activo, isTrue);
      expect(resultado.cambio, isTrue);
    });

    test('usa histéresis antes de declarar que terminó', () {
      final detector = DetectorMovimientoV2();
      final base = List<double>.filled(256, 80);
      final movimiento = List<double>.from(base);
      for (var i = 0; i < 48; i++) {
        movimiento[i] = 160;
      }
      detector.procesar(
        anterior: base,
        actual: movimiento,
        sensibilidad: 0.5,
      );

      for (var i = 0; i < 2; i++) {
        final resultado = detector.procesar(
          anterior: base,
          actual: base,
          sensibilidad: 0.5,
        );
        expect(resultado.activo, isTrue);
      }
      final resultadoFinal = detector.procesar(
        anterior: base,
        actual: base,
        sensibilidad: 0.5,
      );
      expect(resultadoFinal.activo, isFalse);
      expect(resultadoFinal.cambio, isTrue);
    });
  });
}
