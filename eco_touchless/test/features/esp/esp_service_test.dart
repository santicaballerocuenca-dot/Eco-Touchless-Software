import 'package:flutter_test/flutter_test.dart';
import 'package:eco_touchless/features/esp/data/esp_service.dart';

void main() {
  group('EspService.esHostLocalValido', () {
    test('acepta redes privadas y mDNS local', () {
      expect(EspService.esHostLocalValido('192.168.4.1'), isTrue);
      expect(EspService.esHostLocalValido('10.0.0.15'), isTrue);
      expect(EspService.esHostLocalValido('172.16.1.2'), isTrue);
      expect(EspService.esHostLocalValido('eco-touchless.local'), isTrue);
    });

    test('rechaza Internet, loopback y hosts mal formados', () {
      expect(EspService.esHostLocalValido('8.8.8.8'), isFalse);
      expect(EspService.esHostLocalValido('127.0.0.1'), isFalse);
      expect(EspService.esHostLocalValido('https://192.168.4.1'), isFalse);
      expect(EspService.esHostLocalValido('equipo.example.com'), isFalse);
    });
  });

  test('solo las categorías con tapa física son accionables', () {
    expect(EspService.puedeAccionarLegado('Plastico'), isTrue);
    expect(EspService.puedeAccionarLegado('Papel_carton'), isTrue);
    expect(EspService.puedeAccionarLegado('Organico'), isTrue);
    expect(EspService.puedeAccionarLegado('Metal'), isFalse);
    expect(EspService.puedeAccionarLegado('Vidrio'), isFalse);
    expect(EspService.puedeAccionarLegado('Fondo'), isFalse);
    expect(EspService.puedeAccionarLegado('NoAceptar'), isFalse);
    expect(EspService.puedeAccionar('Plastico'), isFalse,
        reason: 'Sin mapa confirmado no se arma En vivo');
  });
}
