/// Representa una clasificación de basura guardada en el historial.
class Clasificacion {
  final int? id;
  final String label;
  final String labelOriginal;
  final bool confirmada;
  final bool esEnVivo;

  /// Null on historical rows where these facts were not recorded.
  final bool? espVinculada;
  final String? aceptacion; // manual | automatica | null (legacy)
  final double confianza; // 0.0 a 100.0
  final String rutaImagen; // path absoluto en el almacenamiento del celular
  final DateTime fecha;

  Clasificacion({
    this.id,
    required this.label,
    String? labelOriginal,
    this.confirmada = false,
    this.esEnVivo = false,
    this.espVinculada,
    this.aceptacion,
    required this.confianza,
    required this.rutaImagen,
    required this.fecha,
  }) : labelOriginal = labelOriginal ?? label;

  bool get corregida => labelOriginal != label;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'labelOriginal': labelOriginal,
      'confirmada': confirmada ? 1 : 0,
      'esEnVivo': esEnVivo ? 1 : 0,
      'espVinculada': espVinculada == null ? null : (espVinculada! ? 1 : 0),
      'aceptacion': aceptacion,
      'confianza': confianza,
      'rutaImagen': rutaImagen,
      // Guardamos como milisegundos desde epoch: permite ordenar y
      // filtrar por fecha fácilmente en SQL, y reconstruir DateTime exacto
      // (con hora, minuto y segundo) al leer.
      'fecha': fecha.millisecondsSinceEpoch,
    };
  }

  factory Clasificacion.fromMap(Map<String, dynamic> map) {
    return Clasificacion(
      id: map['id'] as int?,
      label: map['label'] as String,
      labelOriginal: map['labelOriginal'] as String? ?? map['label'] as String,
      confirmada: (map['confirmada'] as int? ?? 0) == 1,
      esEnVivo: (map['esEnVivo'] as int? ?? 0) == 1,
      espVinculada:
          map['espVinculada'] == null ? null : map['espVinculada'] == 1,
      aceptacion: map['aceptacion'] as String?,
      confianza: (map['confianza'] as num).toDouble(),
      rutaImagen: map['rutaImagen'] as String,
      fecha: DateTime.fromMillisecondsSinceEpoch(map['fecha'] as int),
    );
  }
}

/// Resumen agregado por tipo de basura, usado en la pantalla de Estadísticas.
class ConteoPorLabel {
  final String label;
  final int cantidad;

  ConteoPorLabel({required this.label, required this.cantidad});
}

/// Resumen agregado por día, usado para el gráfico de "fechas donde más se clasificó".
class ConteoPorDia {
  final DateTime dia; // normalizado a medianoche
  final int cantidad;

  ConteoPorDia({required this.dia, required this.cantidad});
}
