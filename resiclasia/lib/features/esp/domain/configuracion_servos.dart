import 'dart:convert';

class ConfiguracionServo {
  const ConfiguracionServo(
      {required this.id,
      required this.gpio,
      required this.label,
      required this.habilitado,
      required this.anguloCerrado,
      required this.anguloAbierto,
      required this.cierreMs});
  final int id, gpio, anguloCerrado, anguloAbierto, cierreMs;
  final String label;
  final bool habilitado;

  factory ConfiguracionServo.fromJson(Map<String, dynamic> json) =>
      ConfiguracionServo(
        id: json['id'] as int,
        gpio: json['gpio'] as int,
        label: json['label'] as String,
        habilitado: json['enabled'] as bool,
        anguloCerrado: json['closedAngle'] as int,
        anguloAbierto: json['openAngle'] as int,
        cierreMs: json['holdMs'] as int,
      );
  Map<String, Object> toJson() => {
        'id': id,
        'gpio': gpio,
        'label': label,
        'enabled': habilitado,
        'closedAngle': anguloCerrado,
        'openAngle': anguloAbierto,
        'holdMs': cierreMs
      };
  String? validar() {
    if (id < 0 || id > 2 || gpio != [12, 13, 15][id]) {
      return 'Identificador o GPIO no válido.';
    }
    if (anguloCerrado < 0 ||
        anguloCerrado > 180 ||
        anguloAbierto < 0 ||
        anguloAbierto > 180) {
      return 'Los ángulos deben estar entre 0 y 180°.';
    }
    if (cierreMs < 500 || cierreMs > 60000) {
      return 'El cierre debe estar entre 0,5 y 60 segundos.';
    }
    if (utf8.encode(label).length > 64 ||
        label.runes.any((c) => c < 32 || c == 127)) {
      return 'Etiqueta no válida.';
    }
    if (habilitado && (label.trim().isEmpty || label == 'Fondo')) {
      return 'Seleccioná una etiqueta distinta de Fondo.';
    }
    if (habilitado && anguloAbierto == anguloCerrado) {
      return 'Apertura y cierre deben tener ángulos diferentes.';
    }
    return null;
  }
}

class ConfiguracionServos {
  const ConfiguracionServos(
      {required this.deviceId,
      required this.bootId,
      required this.revision,
      required this.servos});
  final String deviceId, bootId;
  final int revision;
  final List<ConfiguracionServo> servos;
  factory ConfiguracionServos.fromJson(Map<String, dynamic> json) {
    if (json['apiVersion'] != 1 || json['device'] != 'resiclasia-esp32') {
      throw const FormatException(
          'Firmware no compatible con configuración de servos v1.');
    }
    final config = ConfiguracionServos(
        deviceId: json['deviceId'] as String,
        bootId: json['bootId'] as String,
        revision: json['revision'] as int,
        servos: List.unmodifiable((json['servos'] as List).map((e) =>
            ConfiguracionServo.fromJson(Map<String, dynamic>.from(e as Map)))));
    final error = config.validar();
    if (error != null) throw FormatException(error);
    return config;
  }
  String? validar() {
    if (deviceId.isEmpty ||
        bootId.isEmpty ||
        revision < 1 ||
        servos.length != 3 ||
        servos.map((s) => s.id).toSet().length != 3) {
      return 'Configuración de placa incompleta.';
    }
    final etiquetas = <String>{};
    for (final servo in servos) {
      final error = servo.validar();
      if (error != null) return 'Servo ${servo.id + 1}: $error';
      if (servo.habilitado && !etiquetas.add(servo.label)) {
        return 'No asignes la misma etiqueta a dos servos activos.';
      }
    }
    return null;
  }

  bool puedeAccionar(String label) =>
      servos.any((s) => s.habilitado && s.label == label && label != 'Fondo');
  Map<String, Object> toJson() => {
        'device': 'resiclasia-esp32',
        'apiVersion': 1,
        'deviceId': deviceId,
        'bootId': bootId,
        'revision': revision,
        'servos': servos.map((s) => s.toJson()).toList()
      };
}
