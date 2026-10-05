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

    test('descarta cambios dispersos que no forman un grupo', () {
      final detector = DetectorMovimientoV2();
      final anterior = List<double>.filled(256, 80);
      final actual = List<double>.from(anterior);
      // Tablero de ajedrez: muchas celdas cambian, ninguna contigua.
      for (var i = 0; i < 256; i++) {
        final x = i % 16;
        final y = i ~/ 16;
        if ((x + y).isEven && i % 3 == 0) actual[i] = 160;
      }

      final resultado = detector.procesar(
        anterior: anterior,
        actual: actual,
        sensibilidad: 0.9,
      );

      expect(resultado.grupoMayor, lessThan(3));
      expect(resultado.activo, isFalse);
    });

    test('con poca luz detecta cambios de menor contraste', () {
      final anterior = List<double>.filled(256, 30);
      final actual = List<double>.from(anterior);
      for (var i = 0; i < 64; i++) {
        actual[i] = 42;
      }
      final detector = DetectorMovimientoV2();
      // Sin cambio fuerte hacen falta dos frames consecutivos.
      detector.procesar(
        anterior: anterior,
        actual: actual,
        sensibilidad: 0.5,
      );
      final oscuro = detector.procesar(
        anterior: anterior,
        actual: actual,
        sensibilidad: 0.5,
      );
      expect(oscuro.activo, isTrue);
      expect(oscuro.umbral, lessThan(10));
    });
  });
}
