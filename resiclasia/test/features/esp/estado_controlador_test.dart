import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/esp/domain/estado_controlador.dart';
import 'package:resiclasia/features/esp/domain/reintentos_conexion.dart';

void main() {
  EstadoControlador estado(String boot,
          {String device = 'a', int tiempo = 5000}) =>
      EstadoControlador.leer(jsonEncode({
        'device': 'resiclasia-esp32',
        'apiVersion': 1,
        'deviceId': device,
        'bootId': boot,
        'revision': 2,
        'resetReason': 9,
        'ready': true,
        'activeServo': 1,
        'closing': false,
        'remainingMs': tiempo,
        'activeHoldMs': tiempo,
      }))!;
  test('telemetría mantiene 5 y 50 segundos sin truncarlos', () {
    for (final ms in [5000, 50000]) {
      expect(estado('1', tiempo: ms).holdMs, ms);
      expect(estado('1', tiempo: ms).remainingMs, ms);
    }
  });
  test('reinicio requiere misma placa y boot diferente', () {
    expect(estado('2').reinicioRespectoA(estado('1')), isTrue);
    expect(estado('1').reinicioRespectoA(estado('1')), isFalse);
    expect(estado('2', device: 'b').reinicioRespectoA(estado('1')), isFalse);
    expect(estado('1').reinicioRespectoA(null), isFalse);
    expect(estado('1').motivoReinicio, contains('brownout'));
  });
  test('firmware antiguo o JSON ajeno no inventa telemetría', () {
    for (final body in ['OK', '{}', '[]', '{"device":"other"}']) {
      expect(EstadoControlador.leer(body), isNull);
    }
  });
  test(
      'reintentos toleran un fallo, espacian intentos y se reinician al recuperar',
      () {
    final retry = ReintentosConexion();
    var now = DateTime(2026);
    retry.fallo();
    expect(retry.puedeIntentar(now), isFalse);
    retry.fallo();
    for (final wait in [5, 10, 20, 40, 60, 60]) {
      expect(retry.puedeIntentar(now), isTrue);
      retry.registrarIntento(now);
      expect(
          retry.puedeIntentar(now.add(Duration(seconds: wait - 1))), isFalse);
      now = now.add(Duration(seconds: wait));
    }
    retry.exito();
    expect(retry.fallos, 0);
    expect(retry.intentos, 0);
    expect(retry.puedeIntentar(now), isFalse);
  });
}
