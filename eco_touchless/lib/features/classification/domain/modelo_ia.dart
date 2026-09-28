class ModeloIa {
  const ModeloIa({
    required this.assetPath,
    required this.nombre,
    required this.labelsAssetPath,
  });

  final String assetPath;
  final String nombre;
  final String labelsAssetPath;

  static String nombreDesdeRuta(String assetPath) {
    final archivo = assetPath.split('/').last;
    final punto = archivo.lastIndexOf('.');
    final sinExtension = punto > 0 ? archivo.substring(0, punto) : archivo;
    return sinExtension
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
