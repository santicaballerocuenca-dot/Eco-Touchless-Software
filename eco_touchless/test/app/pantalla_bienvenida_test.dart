import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/app/pantalla_bienvenida.dart';

// El tutorial tiene ilustraciones en bucle: se avanza con pump() en lugar de
// pumpAndSettle(), que nunca terminaría de esperar.
const _transicion = Duration(milliseconds: 600);

Future<void> _continuar(WidgetTester tester) async {
  await tester.tap(find.text('Continuar'));
  await tester.pump();
  await tester.pump(_transicion);
}

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
        home: PantallaBienvenida(onComenzar: (_) async {})));
    await tester.pump(_transicion);
    expect(tester.takeException(), isNull);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('se adapta a una tablet apaisada sin desbordes', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: PantallaBienvenida(onComenzar: (_) async {})));
    for (var i = 0; i < 4; i++) {
      await tester.pump(_transicion);
      expect(tester.takeException(), isNull);
      await _continuar(tester);
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Comenzar'), findsOneWidget);
  });

  testWidgets('recorre las cinco páginas y activa manos libres por defecto',
      (tester) async {
    bool? manosLibres;
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaBienvenida(
          onComenzar: (valor) async => manosLibres = valor,
        ),
      ),
    );
    await tester.pump(_transicion);

    expect(find.text('Bienvenido a ECO-TOUCHLESS'), findsOneWidget);
    expect(find.image(const AssetImage(kLogoEcoTouchless)), findsOneWidget);

    await _continuar(tester);
    expect(find.text('Así de simple'), findsOneWidget);

    await _continuar(tester);
    expect(find.text('Sin tocar la tablet'), findsOneWidget);

    await _continuar(tester);
    expect(find.text('Para mejores resultados'), findsOneWidget);

    await _continuar(tester);
    expect(find.text('Privado y bajo tu control'), findsOneWidget);
    expect(find.text('Saltar'), findsNothing);

    await tester.tap(find.text('Comenzar'));
    await tester.pump();
    expect(manosLibres, isTrue);
  });

  testWidgets('permite desactivar manos libres y saltar al final',
      (tester) async {
    bool? manosLibres;
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaBienvenida(
          onComenzar: (valor) async => manosLibres = valor,
        ),
      ),
    );
    await tester.pump(_transicion);
    await _continuar(tester);
    await _continuar(tester);

    final interruptor = find.text('Activar modo manos libres');
    await tester.ensureVisible(interruptor);
    await tester.pump();
    await tester.tap(interruptor);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);

    await tester.tap(find.text('Saltar'));
    await tester.pump();
    await tester.pump(_transicion);
    expect(find.text('Privado y bajo tu control'), findsOneWidget);

    await tester.tap(find.byTooltip('Anterior'));
    await tester.pump();
    await tester.pump(_transicion);
    expect(find.text('Para mejores resultados'), findsOneWidget);

    await _continuar(tester);
    await tester.tap(find.text('Comenzar'));
    await tester.pump();
    expect(manosLibres, isFalse);
  });

  testWidgets('en modo repaso termina con Listo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaBienvenida(
          repaso: true,
          onComenzar: (_) async {},
        ),
      ),
    );
    await tester.pump(_transicion);
    expect(find.text('Repasemos lo básico'), findsOneWidget);
    await tester.tap(find.text('Saltar'));
    await tester.pump();
    await tester.pump(_transicion);
    expect(find.text('Listo'), findsOneWidget);
  });
}
