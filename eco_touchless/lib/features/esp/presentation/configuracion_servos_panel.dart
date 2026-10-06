import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../classification/data/modelo_catalogo_service.dart';
import '../data/esp_actuadores_service.dart';
import '../domain/configuracion_servos.dart';
import 'simulador_servo.dart';

class ConfiguracionServosPanel extends StatefulWidget {
  const ConfiguracionServosPanel(
      {super.key, required this.visible, this.service});
  final bool visible;
  final EspActuadoresService? service;
  @override
  State<ConfiguracionServosPanel> createState() =>
      _ConfiguracionServosPanelState();
}

class _EdicionServo {
  _EdicionServo(this.original)
      : label = original.label,
        enabled = original.habilitado,
        cerrado = TextEditingController(text: '${original.anguloCerrado}'),
        abierto = TextEditingController(text: '${original.anguloAbierto}'),
        segundos = TextEditingController(text: '${original.cierreMs / 1000}');
  final ConfiguracionServo original;
  String label;
  bool enabled;
  final TextEditingController cerrado, abierto, segundos;
  ConfiguracionServo obtener() => ConfiguracionServo(
      id: original.id,
      gpio: original.gpio,
      label: label,
      habilitado: enabled,
      anguloCerrado: int.parse(cerrado.text),
      anguloAbierto: int.parse(abierto.text),
      cierreMs:
          (double.parse(segundos.text.replaceAll(',', '.')) * 1000).round());
  void dispose() {
    cerrado.dispose();
    abierto.dispose();
    segundos.dispose();
  }
}

class _ConfiguracionServosPanelState extends State<ConfiguracionServosPanel> {
  late final _service = widget.service ?? EspActuadoresService.instancia;
  final _form = GlobalKey<FormState>();
  final List<_EdicionServo> _ediciones = [];
  ConfiguracionServos? _base;
  final Set<String> _labels = {};
  Timer? _timer;
  bool _dirty = false, _leyendo = false, _guardando = false;
  String? _mensaje;
  @override
  void initState() {
    super.initState();
    _service.addListener(_actualizar);
    if (_service.actual != null) _adoptar(_service.actual!);
    _cargarEtiquetas();
    _programar();
  }

  @override
  void didUpdateWidget(covariant ConfiguracionServosPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _programar();
  }

  void _programar() {
    _timer?.cancel();
    if (!widget.visible) return;
    unawaited(_leer());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_guardando) _leer();
    });
  }

  Future<void> _cargarEtiquetas() async {
    final labels = <String>{};
    try {
      final modelos = await ModeloCatalogoService.instancia.obtenerModelos();
      for (final path in modelos.map((m) => m.labelsAssetPath).toSet()) {
        labels.addAll((await rootBundle.loadString(path))
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && l != 'Fondo'));
      }
      if (mounted) setState(() => _labels.addAll(labels));
    } catch (_) {
      if (mounted) {
        setState(() => _mensaje =
            'No se pudieron leer todas las etiquetas de modelos. Se mantienen las de la placa.');
      }
    }
  }

  void _actualizar() {
    if (!mounted) return;
    final remote = _service.actual;
    setState(() {
      if (remote != null &&
          !_dirty &&
          !_guardando &&
          (_base?.bootId != remote.bootId ||
              _base?.revision != remote.revision ||
              _base?.deviceId != remote.deviceId)) {
        _adoptar(remote);
      }
    });
  }

  void _adoptar(ConfiguracionServos remote) {
    for (final e in _ediciones) {
      e.dispose();
    }
    _ediciones.clear();
    _ediciones.addAll(remote.servos.map(_EdicionServo.new));
    _base = remote;
    _dirty = false;
  }

  Future<void> _leer({bool forzar = false}) async {
    if (_leyendo || _guardando) return;
    _leyendo = true;
    try {
      await _service.sincronizar(forzar: forzar);
    } catch (e) {
      if (mounted) setState(() => _mensaje = '$e');
    } finally {
      _leyendo = false;
    }
  }

  Future<void> _recargar() async {
    if (_dirty) {
      final ok = await _confirmar('Descartar cambios locales',
          'Se reemplazarán tus cambios sin guardar por los ajustes de la ESP32.');
      if (!ok || !mounted) return;
    }
    setState(() {
      _dirty = false;
      _base = null;
      _mensaje = null;
    });
    await _leer(forzar: true);
  }

  Future<bool> _confirmar(String title, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: Text(text)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar')),
                ],
              )) ??
      false;
  Future<void> _guardar() async {
    if (_base == null || !_form.currentState!.validate()) return;
    final propuesta = ConfiguracionServos(
        deviceId: _base!.deviceId,
        bootId: _base!.bootId,
        revision: _base!.revision,
        servos: _ediciones.map((e) => e.obtener()).toList());
    final error = propuesta.validar();
    if (error != null) {
      setState(() => _mensaje = error);
      return;
    }
    if (!await _confirmar('Guardar y aplicar posiciones cerradas',
        'La ESP32 guardará los ajustes y moverá los tres servos, uno a uno, a sus nuevas posiciones de CIERRE. Despejá las compuertas y mantené las manos fuera del mecanismo.\n\nProbá primero sin las varillas conectadas; un ángulo incorrecto puede forzar el servo.')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    try {
      await _service.guardar(propuesta);
      if (mounted) {
        setState(() {
          _adoptar(_service.actual!);
          _mensaje =
              'Ajustes confirmados y guardados en la ESP32. Esperá unos 3 segundos mientras se posicionan los servos.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mensaje =
            'No se confirmó el guardado: $e. Volvé a leer; no se reenvió automáticamente.');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.removeListener(_actualizar);
    for (final e in _ediciones) {
      e.dispose();
    }
    super.dispose();
  }

  static String _nombreEtiqueta(String label) => label.isEmpty
      ? 'Sin asignar'
      : label == etiquetaPlasticoMetalVidrio
          ? 'Plástico + Metal + Vidrio (una sola tapa)'
          : label;

  String? _angulo(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 0 || n > 180 ? 'Entero de 0 a 180' : null;
  }

  String? _tiempo(String? value) {
    final n = double.tryParse((value ?? '').replaceAll(',', '.'));
    return n == null || !n.isFinite || n < 0.5 || n > 60
        ? 'De 0,5 a 60 segundos'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final conectado = _service.actual != null;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Servos de la ESP32',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                  '1. Conectá la tablet.  2. Elegí etiqueta, posiciones y tiempo.  3. Guardá en la ESP32.'),
              TextButton.icon(
                  onPressed: _guardando ? null : _recargar,
                  icon: const Icon(Icons.sync),
                  label: const Text('Leer ajustes de la ESP32')),
              if (_service.legado)
                const Text(
                    'Firmware anterior: los ajustes remotos no están disponibles. Cargá eco_touchless_esp32.ino desde Arduino IDE.'),
              if (!conectado && !_service.legado)
                Text(_service.error ??
                    'Esperando conexión con el nuevo firmware…'),
              if (_mensaje != null) Text(_mensaje!),
              if (conectado && _base != null)
                Form(
                    key: _form,
                    child: Column(children: [
                      const Text(
                          'Ángulos absolutos, no cantidad de vueltas. Para invertir: cerrado 180°, abierto 90°. No usar servos de rotación continua como si fueran posicionales.'),
                      if (_dirty)
                        const Text('Cambios locales sin guardar',
                            style: TextStyle(color: Colors.orangeAccent)),
                      for (final e in _ediciones)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(children: [
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                          'Servo ${e.original.id + 1} · GPIO ${e.original.gpio}'),
                                      value: e.enabled,
                                      onChanged: _guardando
                                          ? null
                                          : (v) => setState(() {
                                                e.enabled = v;
                                                _dirty = true;
                                              })),
                                  DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          '${_base!.bootId}:${_base!.revision}:${e.original.id}'),
                                      initialValue: e.label,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              'Etiqueta que abre esta tapa',
                                          helperText: e.label ==
                                                  etiquetaPlasticoMetalVidrio
                                              ? 'Plástico, Metal y Vidrio siguen siendo clases distintas, pero abren este mismo servo.'
                                              : null,
                                          helperMaxLines: 2),
                                      items: [
                                        etiquetaPlasticoMetalVidrio,
                                        ...({..._labels, e.label}
                                            .where((l) =>
                                                l !=
                                                etiquetaPlasticoMetalVidrio)
                                            .toList()
                                          ..sort())
                                      ]
                                          .map((label) => DropdownMenuItem(
                                              value: label,
                                              child: Text(
                                                  _nombreEtiqueta(label),
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: _guardando
                                          ? null
                                          : (v) {
                                              if (v != null) {
                                                setState(() {
                                                  e.label = v;
                                                  _dirty = true;
                                                });
                                              }
                                            }),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: e.cerrado,
                                            enabled: !_guardando,
                                            keyboardType: TextInputType.number,
                                            validator: _angulo,
                                            onChanged: (_) =>
                                                setState(() => _dirty = true),
                                            decoration: const InputDecoration(
                                                labelText: 'Cerrado (°)'))),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: TextFormField(
                                            controller: e.abierto,
                                            enabled: !_guardando,
                                            keyboardType: TextInputType.number,
                                            validator: _angulo,
                                            onChanged: (_) =>
                                                setState(() => _dirty = true),
                                            decoration: const InputDecoration(
                                                labelText: 'Abierto (°)'))),
                                  ]),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                      controller: e.segundos,
                                      enabled: !_guardando,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      validator: _tiempo,
                                      onChanged: (_) =>
                                          setState(() => _dirty = true),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Cerrar después de (segundos)',
                                          helperText:
                                              'Desde la orden de apertura · 0,5 a 60 s')),
                                  Text(
                                      'Guardado en la placa: ${e.original.cierreMs / 1000} segundos'),
                                  SimuladorServo(
                                      key: ValueKey(
                                          'simulador-${e.original.gpio}'),
                                      gpio: e.original.gpio,
                                      cerrado: int.tryParse(e.cerrado.text),
                                      abierto: int.tryParse(e.abierto.text),
                                      segundos: double.tryParse(e.segundos.text
                                          .replaceAll(',', '.'))),
                                ]))),
                      FilledButton.icon(
                          onPressed: _guardando || !_dirty ? null : _guardar,
                          icon: const Icon(Icons.save),
                          label: Text(_guardando
                              ? 'Guardando…'
                              : 'Guardar en la ESP32')),
                    ])),
            ])));
  }
}
