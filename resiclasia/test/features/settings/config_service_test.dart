import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/settings/data/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resiclasia/features/classification/domain/perfil_modelo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('usa 5 segundos y confirmación manual como valores iniciales', () async {
    SharedPreferences.setMockInitialValues({});
    final config = ConfigService.instancia;

    expect(await config.getConfirmacionManual(), isTrue);
    expect(await config.getTimeoutConfirmacionSegundos(), 5);
    expect(await config.getCapturarTrasCeseMovimiento(), isFalse);
    expect(await config.getModoContinuo(), isFalse);
    expect(await config.getUmbralModoContinuo(), 80);
    expect(await config.getBenchHabilitado(), isFalse);
    expect(await config.getMantenerEsp(), isFalse);
    expect(
      await config.getModeloSeleccionado(),
      'assets/modelos/EfficientNet B0.tflite',
    );
  });

  test('perfiles independientes y modelo insignia protegido', () async {
    final config = ConfigService.instancia;
    await config.setPerfilModelo(
        'experimental',
        const PerfilModelo(
            ancho: 96,
            alto: 128,
            letterbox: true,
            bgr: false,
            normalizacion: 'menosUnoUno'));
    final perfil = await config.getPerfilModelo('experimental');
    expect(perfil.ancho, 96);
    expect(perfil.alto, 128);
    expect(perfil.letterbox, isTrue);
    expect((await config.getPerfilModelo('otro')).ancho, 160);
    const flagship = 'assets/modelos/EfficientNet B0.tflite';
    await config.setPerfilModelo(flagship, const PerfilModelo());
    expect((await config.getPerfilModelo(flagship)).normalizacion, 'imagenet');
    expect((await config.getPerfilModelo(flagship)).bgr, isFalse);
    await config.setBenchHabilitado(true);
    await config.setMantenerEsp(true);
    expect(await config.getBenchHabilitado(), isTrue);
    expect(await config.getMantenerEsp(), isTrue);
  });

  test('persiste las nuevas preferencias', () async {
    final config = ConfigService.instancia;

    await config.setConfirmacionManual(false);
    await config.setTimeoutConfirmacionSegundos(10);
    await config.setCapturarTrasCeseMovimiento(true);
    await config.setModoContinuo(true);
    await config.setUmbralModoContinuo(84);
    await config.setModeloSeleccionado('assets/modelos/MobileNet V2.tflite');

    expect(await config.getConfirmacionManual(), isFalse);
    expect(await config.getTimeoutConfirmacionSegundos(), 10);
    expect(await config.getCapturarTrasCeseMovimiento(), isTrue);
    expect(await config.getModoContinuo(), isTrue);
    expect(await config.getUmbralModoContinuo(), 84);
    expect(
      await config.getModeloSeleccionado(),
      'assets/modelos/MobileNet V2.tflite',
    );
  });
}
