import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/features/classification/domain/clasificacion.dart';

void main() {
  test('serializa confirmación y corrección manual', () {
    final fecha = DateTime(2026, 8, 23, 10, 30);
    final clasificacion = Clasificacion(
      id: 7,
      label: 'Plastico',
      labelOriginal: 'Vidrio',
      confirmada: true,
      esEnVivo: true,
      confianza: 72.5,
      rutaImagen: '/foto.jpg',
      fecha: fecha,
    );

    final restaurada = Clasificacion.fromMap(clasificacion.toMap());

    expect(restaurada.label, 'Plastico');
    expect(restaurada.labelOriginal, 'Vidrio');
    expect(restaurada.confirmada, isTrue);
    expect(restaurada.esEnVivo, isTrue);
    expect(restaurada.corregida, isTrue);
    expect(restaurada.fecha, fecha);
  });

  test('lee registros de la base anterior sin columnas nuevas', () {
    final restaurada = Clasificacion.fromMap({
      'id': 1,
      'label': 'Metal',
      'confianza': 80.0,
      'rutaImagen': '',
      'fecha': 0,
    });

    expect(restaurada.labelOriginal, 'Metal');
    expect(restaurada.confirmada, isFalse);
    expect(restaurada.esEnVivo, isFalse);
    expect(restaurada.corregida, isFalse);
  });
}
