/// Cuándo usar la pantalla en blanco como luz de relleno para la foto.
enum ModoIluminacion {
  apagada('Apagada'),
  automatica('Automática'),
  siempre('Siempre');

  const ModoIluminacion(this.titulo);

  final String titulo;

  static ModoIluminacion desde(String? valor) =>
      ModoIluminacion.values.firstWhere((modo) => modo.name == valor,
          orElse: () => ModoIluminacion.automatica);
}
