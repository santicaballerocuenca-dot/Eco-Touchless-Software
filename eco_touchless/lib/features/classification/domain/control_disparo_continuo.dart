class ControlDisparoContinuo {
  ControlDisparoContinuo({
    this.lecturasRequeridas = 1,
    this.lecturasParaRearmar = 3,
    this.enfriamiento = const Duration(seconds: 3),
  });

  final int lecturasRequeridas;
  final int lecturasParaRearmar;
  final Duration enfriamiento;

  String? _candidato;
  int _lecturasCandidato = 0;
  int _lecturasBajas = 0;
  bool _enclavado = false;
  DateTime? _ultimoDisparo;

  bool evaluar({
    required String label,
    required double confianza,
    required double umbral,
    required bool accionable,
    required DateTime ahora,
  }) {
    if (!confianza.isFinite) return false;
    if (label == 'Fondo') {
      _candidato = null;
      _lecturasCandidato = 0;
      _lecturasBajas++;
      if (_lecturasBajas >= lecturasParaRearmar) {
        _enclavado = false;
      }
      return false;
    }

    // Una lectura dudosa o una categoría sin tapa sigue representando un
    // objeto presente. No dispara, pero tampoco rearma una tapa ya abierta.
    if (confianza < umbral || !accionable) {
      _candidato = null;
      _lecturasCandidato = 0;
      _lecturasBajas = 0;
      return false;
    }

    _lecturasBajas = 0;
    if (_candidato == label) {
      _lecturasCandidato++;
    } else {
      _candidato = label;
      _lecturasCandidato = 1;
    }

    final fueraDeEnfriamiento = _ultimoDisparo == null ||
        ahora.difference(_ultimoDisparo!) >= enfriamiento;
    final debeDisparar = _lecturasCandidato >= lecturasRequeridas &&
        fueraDeEnfriamiento &&
        !_enclavado;
    if (debeDisparar) {
      _enclavado = true;
      _ultimoDisparo = ahora;
    }
    return debeDisparar;
  }

  void reset() {
    _candidato = null;
    _lecturasCandidato = 0;
    _lecturasBajas = 0;
    _enclavado = false;
    _ultimoDisparo = null;
  }
}
