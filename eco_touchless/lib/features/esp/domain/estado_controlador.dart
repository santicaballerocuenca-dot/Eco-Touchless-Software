import 'dart:convert';

/// Optional telemetry: old firmware can still answer /status with plain text.
class EstadoControlador {
  const EstadoControlador(
      {required this.deviceId,
      required this.bootId,
      required this.revision,
      required this.resetReason,
      required this.ready,
      required this.servo,
      required this.closing,
      required this.remainingMs,
      required this.holdMs});
  final String deviceId, bootId;
  final int revision, resetReason, servo, remainingMs, holdMs;
  final bool ready, closing;

  static EstadoControlador? leer(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic> ||
          data['device'] != 'eco_touchless-esp32' ||
          data['apiVersion'] != 1) {
        return null;
      }
      return EstadoControlador(
          deviceId: data['deviceId'] as String,
          bootId: data['bootId'] as String,
          revision: data['revision'] as int,
          resetReason: data['resetReason'] as int,
          ready: data['ready'] == true,
          servo: data['activeServo'] as int,
          closing: data['closing'] == true,
          remainingMs: (data['remainingMs'] as int?) ?? 0,
          holdMs: (data['activeHoldMs'] as int?) ?? 0);
    } catch (_) {
      return null;
    }
  }

  bool reinicioRespectoA(EstadoControlador? previo) =>
      previo != null && deviceId == previo.deviceId && bootId != previo.bootId;

  String get motivoReinicio => resetReason == 9
      ? 'Caída de tensión detectada (brownout). Revisá la alimentación de los servos.'
      : 'Motivo de reinicio: $resetReason. Revisá alimentación y registro serie.';
}
