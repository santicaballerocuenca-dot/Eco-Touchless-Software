import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eco_touchless/features/classification/presentation/pantalla_clasificacion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  for (final size in [
    const Size(320, 568),
    const Size(640, 320),
    const Size(1024, 768)
  ]) {
    testWidgets('clasificación sin cámara no desborda en $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: PantallaClasificacion(visible: false))));
      await tester.pump();
      expect(find.byIcon(Icons.cameraswitch), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
