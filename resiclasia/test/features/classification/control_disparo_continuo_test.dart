import 'package:flutter_test/flutter_test.dart';
import 'package:resiclasia/features/classification/domain/control_disparo_continuo.dart';

void main() {
  test('dispara al superar el umbral y no repite si el objeto sigue', () {
    final control = ControlDisparoContinuo();
    final ahora = DateTime(2026);

    expect(
      control.evaluar(
        label: 'Plastico',
        confianza: 85,
        umbral: 80,
        accionable: true,
        ahora: ahora,
      ),
      isTrue,
    );
    expect(
      control.evaluar(
        label: 'Plastico',
        confianza: 90,
        umbral: 80,
        accionable: true,
        ahora: ahora.add(const Duration(seconds: 4)),
      ),
      isFalse,
    );
    expect(
      control.evaluar(
        label: 'Organico',
        confianza: 96,
        umbral: 80,
        accionable: true,
        ahora: ahora.add(const Duration(seconds: 5)),
      ),
      isFalse,
    );
  });

  test('se rearma después de tres lecturas bajas', () {
    final control = ControlDisparoContinuo();
    final ahora = DateTime(2026);
    expect(
      control.evaluar(
        label: 'Organico',
        confianza: 90,
        umbral: 80,
        accionable: true,
        ahora: ahora,
      ),
      isTrue,
    );
    for (var i = 0; i < 3; i++) {
      control.evaluar(
        label: 'Fondo',
        confianza: 20,
        umbral: 80,
        accionable: false,
        ahora: ahora.add(Duration(seconds: 4, milliseconds: i * 200)),
      );
    }

    final primera = control.evaluar(
      label: 'Organico',
      confianza: 90,
      umbral: 80,
      accionable: true,
      ahora: ahora.add(const Duration(seconds: 5)),
    );
    expect(primera, isTrue);
  });

  test('no dispara bajo el umbral ni para categorías sin tapa', () {
    final control = ControlDisparoContinuo();
    final ahora = DateTime(2026);

    expect(
      control.evaluar(
        label: 'Plastico',
        confianza: 79.9,
        umbral: 80,
        accionable: true,
        ahora: ahora,
      ),
      isFalse,
    );
    expect(
      control.evaluar(
        label: 'Metal',
        confianza: 99,
        umbral: 80,
        accionable: false,
        ahora: ahora.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      control.evaluar(
        label: 'Plastico',
        confianza: double.nan,
        umbral: 80,
        accionable: true,
        ahora: ahora.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
  });
}
