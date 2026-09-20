import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resiclasia/features/esp/data/esp_actuadores_service.dart';
import 'package:resiclasia/features/esp/presentation/configuracion_servos_panel.dart';

void main() {
  for (final segundos in [5, 50]) {
    testWidgets(
        'confirma antes de mover cierres y guarda $segundos segundos completos',
        (tester) async {
      var puts = 0;
      final data = <String, dynamic>{
        'apiVersion': 1,
        'device': 'resiclasia-esp32',
        'deviceId': 'board',
        'bootId': 'boot',
        'revision': 1,
        'servos': [
          for (var i = 0; i < 3; i++)
            {
              'id': i,
              'gpio': [12, 13, 15][i],
              'enabled': true,
              'label': ['Metal', 'Papel_carton', 'Organico'][i],
              'closedAngle': 180,
              'openAngle': 90,
              'holdMs': 3000
            }
        ]
      };
      final service = EspActuadoresService(
          destino: () async => Uri.parse('http://192.168.4.1/config'),
          clave: () async => 'key',
          cliente: MockClient((r) async {
            if (r.method == 'GET') return http.Response(jsonEncode(data), 200);
            puts++;
            final saved = jsonDecode(r.body) as Map<String, dynamic>;
            saved['revision'] = 2;
            return http.Response(jsonEncode(saved), 200);
          }));
      await service.sincronizar();
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ConfiguracionServosPanel(
                      visible: false, service: service)))));
      await tester.pumpAndSettle();
      expect(find.text('Servo 1 · GPIO 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Ver abierto').first);
      await tester.tap(find.text('Ver abierto').first);
      await tester.pumpAndSettle();
      expect(find.text('Simulación abierta · 90°'), findsOneWidget);
      expect(puts, 0);
      await tester.enterText(find.byType(TextFormField).first, '170');
      await tester.enterText(find.byType(TextFormField).at(2), '$segundos');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar en la ESP32'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en la ESP32'));
      await tester.pumpAndSettle();
      expect(puts, 0);
      expect(
          find.text('Guardar y aplicar posiciones cerradas'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(puts, 0);
      await tester.ensureVisible(find.text('Guardar en la ESP32'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en la ESP32'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(puts, 1);
      expect(service.actual!.servos.first.anguloCerrado, 170);
      expect(service.actual!.servos.first.cierreMs, segundos * 1000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
