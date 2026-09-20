/// Consecutive failures and bounded backoff; independent of UI and Wi-Fi APIs.
class ReintentosConexion {
  int fallos = 0, intentos = 0;
  DateTime? proximo;
  void exito() {
    fallos = 0;
    intentos = 0;
    proximo = null;
  }

  void fallo() => fallos++;
  bool puedeIntentar(DateTime ahora) =>
      fallos >= 2 && (proximo == null || !ahora.isBefore(proximo!));
  void registrarIntento(DateTime ahora) {
    const segundos = [5, 10, 20, 40, 60];
    proximo = ahora.add(Duration(seconds: segundos[intentos.clamp(0, 4)]));
    intentos++;
  }
}
