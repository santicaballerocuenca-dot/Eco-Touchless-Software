class MuestraBench {
  const MuestraBench({required this.asset, required this.label});
  final String asset, label;
}

class PrediccionBench {
  const PrediccionBench(
      {required this.esperada,
      this.predicha,
      this.confianza = 0,
      this.ms = 0,
      this.error});
  final String esperada;
  final String? predicha, error;
  final double confianza, ms;
  bool get correcta => error == null && esperada == predicha;
}

class ResultadoBench {
  ResultadoBench(this.modelo, this.total, this.normalizacion);
  final String modelo, normalizacion;
  final int total;
  final List<PrediccionBench> predicciones = [];
  String? error;
  int get aciertos => predicciones.where((p) => p.correcta).length;
  int get fallos => predicciones.where((p) => p.error != null).length;
  bool get completo => error == null && predicciones.length == total;
  double get accuracy => total == 0 ? 0 : aciertos / total * 100;
  double get msPromedio {
    final validas = predicciones.where((p) => p.error == null).toList();
    return validas.isEmpty
        ? 0
        : validas.fold<double>(0, (a, b) => a + b.ms) / validas.length;
  }
}
