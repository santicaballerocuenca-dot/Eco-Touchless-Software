import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eco_touchless/features/classification/domain/modelo_ia.dart';
import 'package:eco_touchless/features/settings/presentation/ajustes_perfil_modelo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const experimental = ModeloIa(
      assetPath: 'assets/modelos/test.tflite',
      nombre: 'MobileNet experimental',
      labelsAssetPath: 'assets/labels.txt');
  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    testWidgets('perfil adaptable en ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: AjustesPerfilModelo(modelo: experimental)))));
      await tester.pumpAndSettle();
      expect(find.text('Input X · ancho'), findsOneWidget);
      expect(find.text('Input Y · alto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('96×96'));
      await tester.pump();
      expect(find.text('96'), findsNWidgets(2));
    });
  }
  testWidgets('insignia no permite modificar la preparación', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AjustesPerfilModelo(
                modelo: ModeloIa(
                    assetPath: 'assets/modelos/EfficientNet B0.tflite',
                    nombre: 'EfficientNet B0',
                    labelsAssetPath: 'assets/labels.txt')))));
    await tester.pumpAndSettle();
    expect(
        find.text('Modelo insignia · preparación protegida'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
