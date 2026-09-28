enum ModoInterfaz {
  limpio('Limpio', 'Solo la cámara y un disparador grande.'),
  facil('Fácil', 'Resultados sencillos, sin datos técnicos.'),
  detallado('Detallado', 'Confianza, tiempos y estado de conexión.'),
  desarrollador(
      'Desarrollador', 'Diagnóstico, modelos rápidos y últimos resultados.');

  const ModoInterfaz(this.titulo, this.descripcion);
  final String titulo, descripcion;
  bool get muestraDetalles => this == detallado || this == desarrollador;
  static ModoInterfaz desde(String? nombre) =>
      values.firstWhere((m) => m.name == nombre, orElse: () => facil);
}
