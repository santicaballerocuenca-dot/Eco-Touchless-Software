import 'package:flutter/services.dart';

import '../domain/modelo_ia.dart';

/// Descubre los modelos que Flutter incluyó dentro de `assets/modelos/`.
/// Agregar o quitar un archivo requiere recompilar la aplicación, ya que los
/// assets forman parte del APK y no son archivos externos modificables.
class ModeloCatalogoService {
  ModeloCatalogoService._interno();
  static final ModeloCatalogoService instancia =
      ModeloCatalogoService._interno();

  static const directorioModelos = 'assets/modelos/';
  static const modeloPredeterminado = 'assets/modelos/EfficientNet B0.tflite';
  static const labelsPredeterminados = 'assets/labels.txt';

  List<ModeloIa>? _cache;

  Future<List<ModeloIa>> obtenerModelos() async {
    final cache = _cache;
    if (cache != null) return cache;

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();
    final rutas = assets
        .where(
          (ruta) =>
              ruta.startsWith(directorioModelos) &&
              ruta.toLowerCase().endsWith('.tflite'),
        )
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final modelos = <ModeloIa>[
      for (final ruta in rutas)
        ModeloIa(
          assetPath: ruta,
          nombre: ModeloIa.nombreDesdeRuta(ruta),
          labelsAssetPath: _labelsPara(ruta, assets),
        ),
    ];
    _cache = List.unmodifiable(modelos);
    return _cache!;
  }

  String _labelsPara(String rutaModelo, Set<String> assets) {
    final punto = rutaModelo.lastIndexOf('.');
    final labelsPropios = '${rutaModelo.substring(0, punto)}.txt';
    return assets.contains(labelsPropios)
        ? labelsPropios
        : labelsPredeterminados;
  }

  static ModeloIa? resolver(
    List<ModeloIa> modelos,
    String assetSeleccionado,
  ) {
    if (modelos.isEmpty) return null;
    for (final modelo in modelos) {
      if (modelo.assetPath == assetSeleccionado) return modelo;
    }
    for (final modelo in modelos) {
      if (modelo.assetPath == modeloPredeterminado) return modelo;
    }
    return modelos.first;
  }
}
