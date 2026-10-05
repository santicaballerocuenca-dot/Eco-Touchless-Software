import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/features/classification/domain/control_manos_libres.dart';

const _celdas = 256;
const _config = ConfiguracionManosLibres(
  retardoQuietud: Duration(milliseconds: 600),
  enfriamientoMinimo: Duration(milliseconds: 400),
);

List<double> _escena({double fondo = 90, bool objeto = false}) {
  final celdas = List<double>.filled(_celdas, fondo);
  if (objeto) {
    // Un residuo de 6×6 celdas en el centro del visor.
    for (var y = 5; y < 11; y++) {
      for (var x = 5; x < 11; x++) {
        celdas[y * 16 + x] = fondo + 70;
      }
    }
  }
  return celdas;
}

/// Una mano que cruza el visor: un bloque que se desplaza frame a frame.
List<double> _mano(int paso, {double fondo = 90}) {
  final celdas = List<double>.filled(_celdas, fondo);
  final x0 = (paso * 3) % 12;
  for (var y = 4; y < 12; y++) {
    for (var x = x0; x < x0 + 4; x++) {
      celdas[y * 16 + x] = fondo - 60;
    }
  }
  return celdas;
}

class _Reloj {
  DateTime ahora = DateTime(2026, 1, 1);
  DateTime tic() => ahora = ahora.add(const Duration(milliseconds: 200));
}

void main() {
  group('ControlManosLibres', () {
    late ControlManosLibres control;
    late _Reloj reloj;

    EstadoManosLibres frame(List<double> escena, {bool iluminando = false}) =>
        control.procesar(
          escena,
          ahora: reloj.tic(),
          config: _config,
          iluminando: iluminando,
        );

    /// Procesa [escena] hasta [maximo] frames y devuelve cuántos tardó en
    /// disparar, o null si no disparó.
    int? hastaCapturar(List<double> escena, {int maximo = 15}) {
      for (var i = 1; i <= maximo; i++) {
        if (frame(escena).capturar) return i;
      }
      return null;
    }

    setUp(() {
      control = ControlManosLibres();
      reloj = _Reloj();
      for (var i = 0; i < 5; i++) {
        frame(_escena());
      }
    });

    test('una escena vacía y quieta no dispara', () {
      expect(hastaCapturar(_escena(), maximo: 30), isNull);
      expect(control.fase, FaseManosLibres.esperando);
    });

    test('captura cuando un residuo queda quieto delante de la cámara', () {
      for (var i = 0; i < 4; i++) {
        frame(_mano(i));
      }
      final frames = hastaCapturar(_escena(objeto: true));
      expect(frames, isNotNull);
      expect(control.fase, FaseManosLibres.enfriamiento);
    });

    test('una mano que pasa sin dejar nada no dispara', () {
      for (var i = 0; i < 4; i++) {
        frame(_mano(i));
      }
      expect(hastaCapturar(_escena(), maximo: 20), isNull);
    });

    test('no repite la foto del mismo residuo y se rearma al retirarlo', () {
      for (var i = 0; i < 4; i++) {
        frame(_mano(i));
      }
      expect(hastaCapturar(_escena(objeto: true)), isNotNull);
      // El residuo sigue ahí: no vuelve a disparar.
      expect(hastaCapturar(_escena(objeto: true), maximo: 20), isNull);

      // Se retira: vuelve a esperar y puede capturar el siguiente.
      for (var i = 0; i < 4; i++) {
        frame(_escena());
      }
      expect(control.fase, FaseManosLibres.esperando);
      for (var i = 0; i < 4; i++) {
        frame(_mano(i));
      }
      expect(hastaCapturar(_escena(objeto: true)), isNotNull);
    });

    test('rearmar permite reintentar sin retirar el residuo', () {
      for (var i = 0; i < 4; i++) {
        frame(_mano(i));
      }
      expect(hastaCapturar(_escena(objeto: true)), isNotNull);
      control.rearmar();
      expect(hastaCapturar(_escena(objeto: true)), isNotNull);
    });

    test('ignora un cambio global de exposición', () {
      expect(hastaCapturar(_escena(fondo: 130), maximo: 20), isNull);
    });

    test('captura aunque siga moviéndose tras la espera máxima', () {
      const corta = ConfiguracionManosLibres(
        retardoQuietud: Duration(milliseconds: 600),
        esperaMaximaMovimiento: Duration(seconds: 2),
      );
      var disparo = false;
      for (var i = 0; i < 20 && !disparo; i++) {
        // El residuo tiembla en la mano: alterna brillo en su zona.
        final escena = _escena(objeto: true);
        if (i.isOdd) {
          for (var y = 5; y < 11; y++) {
            for (var x = 5; x < 11; x++) {
              escena[y * 16 + x] -= 35;
            }
          }
        }
        disparo = control
            .procesar(escena, ahora: reloj.tic(), config: corta)
            .capturar;
      }
      expect(disparo, isTrue);
    });

    test('sin exigir presencia, dispara cuando termina el movimiento', () {
      const sinPresencia = ConfiguracionManosLibres(
        retardoQuietud: Duration(milliseconds: 600),
        requierePresencia: false,
      );
      for (var i = 0; i < 4; i++) {
        control.procesar(_mano(i), ahora: reloj.tic(), config: sinPresencia);
      }
      var disparo = false;
      for (var i = 0; i < 15 && !disparo; i++) {
        disparo = control
            .procesar(_escena(), ahora: reloj.tic(), config: sinPresencia)
            .capturar;
      }
      expect(disparo, isTrue);
    });

    test('la zona central ignora movimiento en los bordes', () {
      var activo = false;
      for (var i = 0; i < 6; i++) {
        final escena = _escena();
        // Alguien pasa por el borde izquierdo del visor.
        for (var y = 0; y < 16; y++) {
          escena[y * 16 + (i.isEven ? 0 : 1)] = 10;
        }
        activo = frame(escena).movimiento || activo;
      }
      expect(activo, isFalse);
    });
  });

  group('DetectorPocaLuz', () {
    test('entra en modo oscuro tras varios frames y no parpadea', () {
      final luz = DetectorPocaLuz();
      expect(luz.actualizar(30, iluminando: false), isFalse);
      for (var i = 0; i < 3; i++) {
        luz.actualizar(30, iluminando: false);
      }
      expect(luz.oscuro, isFalse);
      expect(luz.actualizar(30, iluminando: false), isTrue);
      expect(luz.oscuro, isTrue);

      // La pantalla ilumina la escena: el brillo sube, pero no lo suficiente
      // como para pensar que volvió la luz ambiente.
      for (var i = 0; i < 20; i++) {
        luz.actualizar(i == 0 ? 70 : 95, iluminando: true);
      }
      expect(luz.oscuro, isTrue);
    });

    test('sale del modo oscuro cuando vuelve la luz ambiente', () {
      final luz = DetectorPocaLuz();
      for (var i = 0; i < 5; i++) {
        luz.actualizar(25, iluminando: false);
      }
      expect(luz.oscuro, isTrue);
      luz.actualizar(70, iluminando: true);
      var cambio = false;
      for (var i = 0; i < 10; i++) {
        cambio = luz.actualizar(160, iluminando: true) || cambio;
      }
      expect(cambio, isTrue);
      expect(luz.oscuro, isFalse);
    });

    test('el motor informa el cambio de oscuridad', () {
      final control = ControlManosLibres();
      var ahora = DateTime(2026);
      EstadoManosLibres? ultimo;
      var cambios = 0;
      for (var i = 0; i < 8; i++) {
        ahora = ahora.add(const Duration(milliseconds: 200));
        ultimo =
            control.procesar(List<double>.filled(_celdas, 20), ahora: ahora);
        if (ultimo.cambioOscuridad) cambios++;
      }
      expect(ultimo!.oscuro, isTrue);
      expect(cambios, 1);
    });
  });

  test('pesos de zona central priorizan el centro', () {
    final pesos = ControlManosLibres.pesosZona(_celdas, 16, zonaCentral: true);
    expect(pesos[8 * 16 + 8], 1);
    expect(pesos[0], lessThan(0.2));
    expect(
      ControlManosLibres.pesosZona(_celdas, 16, zonaCentral: false),
      everyElement(1),
    );
  });
}
