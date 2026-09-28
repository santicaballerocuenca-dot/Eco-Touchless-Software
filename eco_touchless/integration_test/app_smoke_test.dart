import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eco_touchless/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la aplicación inicia mostrando el onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('ResiClas-IA'), findsOneWidget);
    expect(find.text('Clasificá residuos con IA'), findsOneWidget);
  });
}
