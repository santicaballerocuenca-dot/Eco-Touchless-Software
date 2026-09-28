abstract final class CategoriaResiduo {
  static const Map<String, String> _nombres = {
    'Fondo': 'Sin residuo',
    'Metal': 'Metal',
    'NoAceptar': 'No aceptado',
    'Organico': 'Orgánico',
    'Papel_carton': 'Papel/Cartón',
    'Plastico': 'Plástico',
    'Vidrio': 'Vidrio',
  };

  static String nombreVisible(String label) => _nombres[label] ?? label;
}
