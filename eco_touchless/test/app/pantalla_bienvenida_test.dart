import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/app/pantalla_bienvenida.dart';

void main() {
  testWidgets('bienvenida permite desplazarse en horizontal con fuente grande',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: PantallaBienvenida(onComenzar: () async {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Continuar'), findsOneWidget);
  });
  testWidgets('explica privacidad y completa las tres páginas', (tester) async {
    var completada = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaBienvenida(
          onComenzar: () async => completada = true,
        ),
      ),
    );

    expect(find.text('Clasificá residuos con IA'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Procesamiento privado'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Vos controlás los permisos'), findsOneWidget);

    await tester.tap(find.text('Comenzar'));
    await tester.pumpAndSettle();
    expect(completada, isTrue);
  });
}
