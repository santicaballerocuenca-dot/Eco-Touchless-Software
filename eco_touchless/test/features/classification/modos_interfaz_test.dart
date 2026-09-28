import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eco_touchless/core/theme/app_theme.dart';
import 'package:eco_touchless/features/settings/data/config_service.dart';
import 'package:eco_touchless/features/settings/domain/modo_interfaz.dart';
import 'package:eco_touchless/features/classification/presentation/pantalla_clasificacion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const capturas = bool.fromEnvironment('ECO_TOUCHLESS_CAPTURAS');
  setUpAll(() async {
    if (!capturas) return;
    final fuente = FontLoader('Roboto')
      ..addFont(File(
              '.tooling/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await fuente.load();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });
  for (final modo in ModoInterfaz.values) {
    for (final size in [const Size(360, 740), const Size(740, 360)]) {
      testWidgets('${modo.name} respeta controles y adapta $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester
            .runAsync(() => ConfigService.instancia.setModoInterfaz(modo));
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.oscuro(),
            home: const RepaintBoundary(
                key: ValueKey('preview'),
                child: Scaffold(body: PantallaClasificacion(visible: false)))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.cameraswitch),
            modo == ModoInterfaz.limpio ? findsNothing : findsOneWidget);
        expect(find.text('Diagnóstico de sesión'),
            modo == ModoInterfaz.desarrollador ? findsOneWidget : findsNothing);
        if (modo == ModoInterfaz.limpio) {
          expect(find.textContaining('ECO-TOUCHLESS'), findsNothing);
        }
        expect(find.byTooltip('Tomar fotografía'), findsOneWidget);
        if (capturas && size.width == 360) {
          await expectLater(
              find.byKey(const ValueKey('preview')),
              matchesGoldenFile(
                  '../../../.tooling/qa/eco_touchless_${modo.name}.png'));
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('Limpio en vivo no muestra disparador ni selector',
      (tester) async {
    await tester.runAsync(() async {
      await ConfigService.instancia.setModoInterfaz(ModoInterfaz.limpio);
      await ConfigService.instancia.setModoContinuo(true);
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.oscuro(),
        home: const Scaffold(body: PantallaClasificacion(visible: false))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tomar fotografía'), findsNothing);
    expect(find.byIcon(Icons.cameraswitch), findsNothing);
    expect(find.text('FOTO'), findsNothing);
    expect(find.text('EN VIVO'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => ConfigService.instancia.setModoContinuo(false));
  });
}
