import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/features/classification/domain/clasificacion.dart';
import 'package:eco_touchless/features/statistics/data/historial_export_service.dart';

void main() {
  test('genera CSV auditable y escapa comas y comillas', () {
    final csv = HistorialExportService.generarCsv([
      Clasificacion(
        id: 3,
        label: 'Papel_carton',
        labelOriginal: '"Papel, dudoso"',
        confirmada: true,
        esEnVivo: true,
        confianza: 91.25,
        rutaImagen: '/fotos/uno,2.jpg',
        fecha: DateTime.utc(2026, 8, 23),
      ),
    ]);

    expect(csv, contains('categoria_original,modo,confirmada,corregida'));
    expect(csv, contains(',en_vivo,si,si,91.25,'));
    expect(csv, contains('"""Papel, dudoso"""'));
    expect(csv, contains('"/fotos/uno,2.jpg"'));
  });
}
