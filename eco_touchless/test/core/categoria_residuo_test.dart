import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/core/domain/categoria_residuo.dart';

void main() {
  group('CategoriaResiduo', () {
    test('convierte labels técnicos en nombres visibles', () {
      expect(CategoriaResiduo.nombreVisible('Papel_carton'), 'Papel/Cartón');
      expect(CategoriaResiduo.nombreVisible('Plastico'), 'Plástico');
      expect(CategoriaResiduo.nombreVisible('NoAceptar'), 'No aceptado');
    });

    test('conserva labels desconocidos para no ocultar clases nuevas', () {
      expect(CategoriaResiduo.nombreVisible('Electronico'), 'Electronico');
    });
  });
}
