import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/classification/data/modelo_catalogo_service.dart';
import 'package:resiclasia/features/classification/domain/modelo_ia.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('convierte el nombre del archivo en el nombre visible', () {
    expect(
      ModeloIa.nombreDesdeRuta('assets/modelos/MobileNet_V2-prueba.tflite'),
      'MobileNet V2 prueba',
    );
  });

  test('descubre EfficientNet B0 en el catálogo de assets', () async {
    final modelos = await ModeloCatalogoService.instancia.obtenerModelos();

    expect(modelos, isNotEmpty);
    expect(modelos.map((m) => m.nombre),
        containsAll(['MobileNetv2 Version 1', 'MobileNetv2 Version 2']));
    expect(
      modelos.any(
        (modelo) =>
            modelo.assetPath == 'assets/modelos/EfficientNet B0.tflite' &&
            modelo.nombre == 'EfficientNet B0' &&
            modelo.labelsAssetPath == 'assets/labels.txt',
      ),
      isTrue,
    );
  });

  test('usa el predeterminado si la selección ya no existe', () {
    const modelos = [
      ModeloIa(
        assetPath: 'assets/modelos/Otro.tflite',
        nombre: 'Otro',
        labelsAssetPath: 'assets/labels.txt',
      ),
      ModeloIa(
        assetPath: 'assets/modelos/EfficientNet B0.tflite',
        nombre: 'EfficientNet B0',
        labelsAssetPath: 'assets/labels.txt',
      ),
    ];

    final resultado = ModeloCatalogoService.resolver(
      modelos,
      'assets/modelos/Eliminado.tflite',
    );

    expect(resultado?.nombre, 'EfficientNet B0');
  });
}
