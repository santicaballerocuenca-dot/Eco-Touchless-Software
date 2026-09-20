class PerfilModelo {
  const PerfilModelo(
      {this.ancho = 160,
      this.alto = 160,
      this.normalizacion = 'ceroUno',
      this.letterbox = false,
      this.bgr = true,
      this.redimensionar = true});
  static const insignia = PerfilModelo(
      ancho: 224,
      alto: 224,
      normalizacion: 'imagenet',
      bgr: false,
      redimensionar: false);
  final int ancho, alto;
  final String normalizacion;
  final bool letterbox, bgr, redimensionar;
  static bool esInsignia(String path) =>
      path == 'assets/modelos/EfficientNet B0.tflite';
  String get resumen =>
      '$ancho×$alto · $normalizacion · ${letterbox ? 'letterbox' : 'center-crop'} · ${bgr ? 'BGR' : 'RGB'}';
  Map<String, Object> toJson() => {
        'ancho': ancho,
        'alto': alto,
        'normalizacion': normalizacion,
        'letterbox': letterbox,
        'bgr': bgr,
        'redimensionar': redimensionar
      };
  factory PerfilModelo.fromJson(Map<String, dynamic> data) {
    final width = data['ancho'] as int? ?? 160;
    final height = data['alto'] as int? ?? 160;
    final norm = data['normalizacion'] as String? ?? 'ceroUno';
    if (width < 16 ||
        width > 1024 ||
        height < 16 ||
        height > 1024 ||
        !['ceroUno', 'menosUnoUno', 'imagenet'].contains(norm)) {
      throw const FormatException('Dimensiones o normalización no válidas');
    }
    return PerfilModelo(
        ancho: width,
        alto: height,
        normalizacion: norm,
        letterbox: data['letterbox'] as bool? ?? false,
        bgr: data['bgr'] as bool? ?? true,
        redimensionar: data['redimensionar'] as bool? ?? true);
  }
}
