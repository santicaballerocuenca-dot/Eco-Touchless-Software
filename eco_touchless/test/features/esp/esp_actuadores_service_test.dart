import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eco_touchless/features/esp/data/esp_actuadores_service.dart';
import 'package:eco_touchless/features/esp/domain/configuracion_servos.dart';

Map<String, dynamic> fixture(
        {int revision = 1, String label = 'Metal', String boot = 'boot-123'}) =>
    {
      'apiVersion': 1,
      'device': 'eco_touchless-esp32',
      'deviceId': 'plate-1',
      'bootId': boot,
      'revision': revision,
      'servos': [
        for (var i = 0; i < 3; i++)
          {
            'id': i,
            'gpio': [12, 13, 15][i],
            'enabled': true,
            'label': [label, 'Papel_carton', 'Organico'][i],
            'closedAngle': 180,
            'openAngle': 90,
            'holdMs': 3000
          }
      ],
    };
EspActuadoresService service(
        Future<http.Response> Function(http.Request) handler,
        {Future<Uri> Function()? destino}) =>
    EspActuadoresService(
        cliente: MockClient(handler),
        destino: destino ?? () async => Uri.parse('http://192.168.4.1/config'),
        clave: () async => 'test-key');

void main() {
  test(
      'acepta servo invertido y Metal asignado, no Fondo ni etiquetas no asignadas',
      () {
    final config = ConfiguracionServos.fromJson(fixture());
    expect(config.validar(), isNull);
    expect(config.puedeAccionar('Metal'), isTrue);
    expect(config.puedeAccionar('Plastico'), isFalse);
    expect(config.puedeAccionar('Fondo'), isFalse);
  });
  group('Plastico_Metal_Vidrio', () {
    test('un servo abre para Plastico, Metal y Vidrio, y para nada más', () {
      final config = ConfiguracionServos.fromJson(
          fixture(label: etiquetaPlasticoMetalVidrio));
      expect(config.validar(), isNull);
      for (final clase in ['Plastico', 'Metal', 'Vidrio']) {
        expect(config.puedeAccionar(clase), isTrue, reason: clase);
        expect(config.servoPara(clase)!.id, 0, reason: clase);
      }
      expect(config.puedeAccionar('NoAceptar'), isFalse);
      expect(config.puedeAccionar('Fondo'), isFalse);
      expect(config.puedeAccionar('Papel_carton'), isTrue);
      expect(config.servoPara('Papel_carton')!.id, 1);
    });
    test('un servo deshabilitado no abre ninguna de las tres clases', () {
      final data = fixture(label: etiquetaPlasticoMetalVidrio);
      (data['servos'] as List)[0]['enabled'] = false;
      final config = ConfiguracionServos.fromJson(data);
      for (final clase in ['Plastico', 'Metal', 'Vidrio']) {
        expect(config.puedeAccionar(clase), isFalse, reason: clase);
      }
    });
    test('rechaza que otro servo activo repita una de las tres clases', () {
      for (final clase in ['Plastico', 'Metal', 'Vidrio']) {
        final data = fixture(label: etiquetaPlasticoMetalVidrio);
        (data['servos'] as List)[1]['label'] = clase;
        expect(() => ConfiguracionServos.fromJson(data),
            throwsA(isA<FormatException>()),
            reason: clase);
      }
    });
    test('permite repetir una de las clases si el otro servo está apagado', () {
      final data = fixture(label: etiquetaPlasticoMetalVidrio);
      (data['servos'] as List)[1]['label'] = 'Plastico';
      (data['servos'] as List)[1]['enabled'] = false;
      expect(ConfiguracionServos.fromJson(data).validar(), isNull);
    });
    test('no se pueden usar dos servos activos con el grupo', () {
      final data = fixture(label: etiquetaPlasticoMetalVidrio);
      (data['servos'] as List)[1]['label'] = etiquetaPlasticoMetalVidrio;
      expect(() => ConfiguracionServos.fromJson(data), throwsFormatException);
    });
  });
  test(
      'rechaza 360 grados, timeout inválido, GPIO cambiado y etiquetas duplicadas',
      () {
    for (final field in ['openAngle', 'holdMs', 'gpio', 'label']) {
      final data = fixture();
      (data['servos'] as List)[0][field] = {
        'openAngle': 360,
        'holdMs': 0,
        'gpio': 4,
        'label': 'Papel_carton'
      }[field];
      expect(() => ConfiguracionServos.fromJson(data), throwsFormatException);
    }
    expect(() => ConfiguracionServos.fromJson(fixture(label: 'Fondo')),
        throwsFormatException);
  });
  test('lee, cachea y confirma configuración guardada, enviando clave',
      () async {
    var gets = 0, puts = 0;
    final api = service((request) async {
      expect(request.headers['X-Api-Key'], 'test-key');
      if (request.method == 'GET') {
        gets++;
        return http.Response(jsonEncode(fixture()), 200);
      }
      puts++;
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      data['revision'] = 2;
      return http.Response(jsonEncode(data), 200);
    });
    addTearDown(api.dispose);
    final config = (await api.sincronizar())!;
    await api.sincronizar();
    expect(gets, 1);
    await api.guardar(config);
    expect(puts, 1);
    expect(api.actual!.revision, 2);
  });
  test('solo 404/405 activa compatibilidad, no 401 ni 500 ni timeout',
      () async {
    for (final status in [404, 405, 401, 500]) {
      final api = service((_) async => http.Response('{}', status));
      await api.sincronizar();
      expect(api.legado, status == 404 || status == 405);
      expect(api.actual, isNull);
      api.dispose();
    }
    final api = service((_) async => throw TimeoutException('offline'));
    await api.sincronizar();
    expect(api.legado, isFalse);
    api.dispose();
  });
  test('no reintenta guardado con timeout y descarta mapa ambiguo', () async {
    var puts = 0;
    final api = service((r) async {
      if (r.method == 'GET') return http.Response(jsonEncode(fixture()), 200);
      puts++;
      throw TimeoutException('Sin ACK');
    });
    addTearDown(api.dispose);
    final config = (await api.sincronizar())!;
    await expectLater(api.guardar(config), throwsA(isA<TimeoutException>()));
    expect(puts, 1);
    expect(api.actual, isNull);
    expect(api.guardando, isFalse);
  });
  test('rechaza ACK que cambia los ajustes, aunque devuelva HTTP 200',
      () async {
    final api = service((r) async => http.Response(
        jsonEncode(r.method == 'GET'
            ? fixture()
            : fixture(revision: 2, label: 'Vidrio')),
        200));
    addTearDown(api.dispose);
    final config = (await api.sincronizar())!;
    await expectLater(api.guardar(config), throwsStateError);
    expect(api.actual, isNull);
  });
  test('cambiar IP no reutiliza configuración de la placa anterior', () async {
    var host = '192.168.4.1';
    final api = service(
        (r) async => r.url.host == '192.168.4.1'
            ? http.Response(jsonEncode(fixture()), 200)
            : http.Response('{}', 500),
        destino: () async => Uri.http(host, '/config'));
    addTearDown(api.dispose);
    expect(await api.sincronizar(), isNotNull);
    host = '192.168.4.2';
    expect(await api.sincronizar(), isNull);
    expect(api.legado, isFalse);
  });
  test('una revisión antigua no se envía al guardar', () async {
    var gets = 0, puts = 0;
    final api = service((r) async {
      if (r.method == 'PUT') puts++;
      return http.Response(jsonEncode(fixture(revision: ++gets)), 200);
    });
    addTearDown(api.dispose);
    final old = (await api.sincronizar())!;
    await api.sincronizar(forzar: true);
    await expectLater(api.guardar(old), throwsStateError);
    expect(puts, 0);
  });
}
