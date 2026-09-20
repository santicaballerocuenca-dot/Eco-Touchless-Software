import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/esp/presentation/simulador_servo.dart';

void main() {
  for (final seconds in [5.0, 50.0]) {
    testWidgets('simulación invertida respeta $seconds segundos',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SimuladorServo(
                  gpio: 12, cerrado: 180, abierto: 90, segundos: seconds))));
      expect(find.text('Simulación cerrada · 180°'), findsOneWidget);
      await tester.tap(find.text('Probar ciclo virtual'));
      await tester.pump();
      expect(find.text('Simulación abierta · 90°'), findsOneWidget);
      await tester.pump(Duration(milliseconds: (seconds * 1000).round() - 1));
      expect(find.text('Simulación abierta · 90°'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Simulación cerrada · 180°'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('valores inválidos desactivan la prueba y dispose cancela timers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SimuladorServo(
                gpio: 15, cerrado: 360, abierto: 90, segundos: 5))));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SimuladorServo(
                gpio: 15, cerrado: 0, abierto: 90, segundos: 50))));
    await tester.tap(find.text('Probar ciclo virtual'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(tester.takeException(), isNull);
  });
}
