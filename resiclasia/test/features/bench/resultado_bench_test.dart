import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/bench/domain/resultado_bench.dart';

void main() {
  test('accuracy cuenta errores y no confunde confianza con aciertos', () {
    final result = ResultadoBench('Modelo', 3, 'perfil');
    result.predicciones.addAll([
      const PrediccionBench(
          esperada: 'Metal', predicha: 'Metal', confianza: 51, ms: 10),
      const PrediccionBench(
          esperada: 'Fondo', predicha: 'Metal', confianza: 99, ms: 20),
      const PrediccionBench(esperada: 'Vidrio', error: 'Error de inferencia'),
    ]);
    expect(result.aciertos, 1);
    expect(result.accuracy, closeTo(100 / 3, 1e-6));
    expect(result.fallos, 1);
    expect(result.msPromedio, 15);
    expect(result.completo, isTrue);
    result.error = 'carga fallida';
    expect(result.completo, isFalse);
  });
  test('manifest incluye 5 archivos existentes por cada clase y sin duplicados',
      () {
    final manifest =
        jsonDecode(File('assets/bench/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final samples = manifest['samples'] as List;
    final labels = File('assets/labels.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    expect(samples, hasLength(35));
    expect(samples.map((s) => s['source']).toSet(), hasLength(35));
    for (final label in labels) {
      expect(samples.where((s) => s['label'] == label), hasLength(5));
    }
    for (final sample in samples) {
      expect(File(sample['asset'] as String).existsSync(), isTrue);
    }
  });
}
