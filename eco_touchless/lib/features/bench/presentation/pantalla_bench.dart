import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../classification/data/camara_service.dart';
import '../../classification/data/clasificador_service.dart';
import '../../classification/data/modelo_catalogo_service.dart';
import '../../classification/domain/modelo_ia.dart';
import '../../classification/domain/perfil_modelo.dart';
import '../../settings/data/config_service.dart';
import '../domain/resultado_bench.dart';

/// Bench and same-photo comparison never touch history or mechanical endpoints.
class PantallaBench extends StatefulWidget {
  const PantallaBench({super.key, this.comparacion = false, this.onRunning});
  final bool comparacion;
  final ValueChanged<bool>? onRunning;
  @override
  State<PantallaBench> createState() => _PantallaBenchState();
}

class _PantallaBenchState extends State<PantallaBench>
    with WidgetsBindingObserver {
  List<ModeloIa> _modelos = [];
  final Set<String> _seleccion = {};
  final List<ResultadoBench> _resultados = [];
  bool _ejecutando = false, _cancelar = false, _cargando = true;
  String? _error;
  String _estado = 'Listo para comenzar';
  int _progreso = 0, _total = 0;
  Uint8List? _foto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final modelos = await ModeloCatalogoService.instancia.obtenerModelos();
      final saved = await ConfigService.instancia.getModelosComparacion();
      if (!mounted) return;
      setState(() {
        _modelos = modelos;
        _seleccion.addAll(saved ?? modelos.map((m) => m.assetPath));
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _cargando = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelar = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ejecutando && state == AppLifecycleState.paused) {
      setState(() {
        _cancelar = true;
        _estado = 'Pausado: cancelando tras la imagen actual…';
      });
    }
  }

  Future<void> _ejecutar() async {
    if (_ejecutando) return;
    final modelos = _modelos
        .where((m) => !widget.comparacion || _seleccion.contains(m.assetPath))
        .toList();
    if (modelos.isEmpty) return;
    widget.onRunning?.call(true);
    setState(() {
      _ejecutando = true;
      _cancelar = false;
      _error = null;
      _resultados.clear();
      _progreso = 0;
      _total = 0;
      _estado = 'Preparando…';
    });
    try {
      final config = ConfigService.instancia;
      // Snapshot options so a run remains comparable even if settings change.
      final profiles = <String, PerfilModelo>{};
      for (final m in modelos) {
        profiles[m.assetPath] = await config.getPerfilModelo(m.assetPath);
      }
      final muestras = <MuestraBench>[];
      if (widget.comparacion) {
        final camara = CamaraService.instancia;
        await camara.inicializar();
        await camara.pausarStream();
        final controller = camara.controller;
        if (controller == null || !camara.lista) {
          throw StateError('Cámara no disponible');
        }
        final file = await controller.takePicture();
        try {
          _foto = await file.readAsBytes();
        } finally {
          await File(file.path).delete();
        }
        muestras.add(const MuestraBench(asset: '', label: 'Sin etiqueta real'));
      } else {
        final manifest = jsonDecode(
                await rootBundle.loadString('assets/bench/manifest.json'))
            as Map<String, dynamic>;
        for (final sample in manifest['samples'] as List) {
          muestras.add(MuestraBench(
              asset: sample['asset'] as String,
              label: sample['label'] as String));
        }
        if (muestras.isEmpty) throw StateError('El dataset está vacío');
      }
      if (!mounted || _cancelar) return;
      setState(() => _total = modelos.length * muestras.length);
      for (final model in modelos) {
        if (_cancelar || !mounted) break;
        final result = ResultadoBench(
            model.nombre, muestras.length, profiles[model.assetPath]!.resumen);
        setState(() {
          _resultados.add(result);
          _estado = 'Cargando ${model.nombre}';
        });
        final runner = ClasificadorService.experimento()
          ..perfil = profiles[model.assetPath]!;
        try {
          final error = await runner.cargar(modelo: model);
          if (error != null) throw StateError(error);
          for (final sample in muestras) {
            if (_cancelar || !mounted) break;
            try {
              final bytes = widget.comparacion
                  ? _foto!
                  : (await rootBundle.load(sample.asset)).buffer.asUint8List();
              final pred = await runner.clasificarBytesEnSegundoPlano(bytes);
              if (pred == null) {
                throw StateError('No se pudo inferir la imagen');
              }
              result.predicciones.add(PrediccionBench(
                  esperada: sample.label,
                  predicha: pred.label,
                  confianza: pred.confianza,
                  ms: pred.inferenciaMs));
            } catch (e) {
              result.predicciones
                  .add(PrediccionBench(esperada: sample.label, error: '$e'));
            }
            if (mounted) {
              setState(() {
                _progreso++;
                _estado =
                    '${model.nombre}: ${result.predicciones.length}/${muestras.length}';
              });
            }
          }
        } catch (e) {
          result.error = '$e';
          _progreso += muestras.length;
        } finally {
          runner.liberar();
        }
      }
      if (mounted) {
        setState(() => _estado =
            _cancelar ? 'Cancelado · resultados parciales' : 'Finalizado');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _ejecutando = false);
        widget.onRunning?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = _resultados.where((r) => r.completo).toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final allDone = !_ejecutando &&
        !_cancelar &&
        complete.length == _modelos.length &&
        complete.isNotEmpty;
    final content = SafeArea(
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                        widget.comparacion
                            ? 'Una foto · varios modelos'
                            : 'BENCH · laboratorio de modelos',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(widget.comparacion
                        ? '1. Elegí los modelos.  2. Encuadrá el residuo.  3. Capturá y compará. Todos reciben exactamente la misma foto; se ejecutan por turnos en CPU para limitar memoria. No se abren compuertas.'
                        : '35 imágenes etiquetadas · 5 por categoría. Ejecutar prueba todos los modelos incluidos. No usa la cámara ni abre compuertas. Aciertos = predicciones correctas / 35; confianza no equivale a accuracy.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Antes de comparar, verificá la normalización de cada modelo en Ajustes. La latencia es solo inferencia en CPU; incluye la primera ejecución, no carga ni decodificación.'),
                    if (widget.comparacion) ...[
                      if (_foto != null && !_ejecutando)
                        TextButton.icon(
                          onPressed: () => setState(() => _foto = null),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Volver a encuadrar'),
                        ),
                      for (final model in _modelos)
                        CheckboxListTile(
                          title: Text(model.nombre),
                          value: _seleccion.contains(model.assetPath),
                          onChanged: _ejecutando
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _seleccion.add(model.assetPath);
                                    } else {
                                      _seleccion.remove(model.assetPath);
                                    }
                                  });
                                  ConfigService.instancia.setModelosComparacion(
                                      _seleccion.toList());
                                },
                        ),
                      SizedBox(
                          height: 180,
                          child: _foto != null
                              ? Image.memory(_foto!, fit: BoxFit.contain)
                              : ListenableBuilder(
                                  listenable: CamaraService.instancia,
                                  builder: (context, _) => CamaraService
                                          .instancia.lista
                                      ? CameraPreview(
                                          CamaraService.instancia.controller!)
                                      : const Center(
                                          child: Text('Cámara no disponible')),
                                )),
                    ],
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: _cargando ||
                                  _ejecutando ||
                                  _modelos.isEmpty ||
                                  (widget.comparacion && _seleccion.isEmpty)
                              ? null
                              : _ejecutar,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(widget.comparacion
                              ? 'Capturar y comparar'
                              : 'Ejecutar todos los modelos')),
                      if (_ejecutando)
                        OutlinedButton(
                            onPressed: () => setState(() {
                                  _cancelar = true;
                                  _estado = 'Cancelando tras la imagen actual…';
                                }),
                            child: const Text('Cancelar')),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                        '$_estado${_total > 0 ? ' · $_progreso/$_total' : ''}'),
                    if (_ejecutando)
                      LinearProgressIndicator(
                          value: _total == 0 ? null : _progreso / _total),
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(color: Colors.orangeAccent)),
                    if (!widget.comparacion && allDone)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Mejor en esta muestra: ${complete.first.modelo} (${complete.first.accuracy.toStringAsFixed(1)}%)\n'
                                'Promedio de los ${complete.length} modelos: ${(complete.fold<double>(0, (sum, r) => sum + r.accuracy) / complete.length).toStringAsFixed(1)}%\n'
                                'Solo 35 imágenes: es una comparación exploratoria, no una validación completa. Empates pueden compartir el primer puesto.',
                              ))),
                    for (final r in _resultados)
                      Card(
                          child: ExpansionTile(
                        title: Text(r.modelo),
                        subtitle: Text(r.error ??
                            '${widget.comparacion ? r.predicciones.isEmpty ? 'Procesando…' : '${r.predicciones.first.predicha ?? 'Error'} · ${r.predicciones.first.confianza.toStringAsFixed(1)}%' : '${r.aciertos}/${r.total} aciertos · ${r.accuracy.toStringAsFixed(1)}%${r.completo ? '' : ' · parcial'}'}\n${r.msPromedio.toStringAsFixed(1)} ms · ${r.normalizacion}'),
                        children: [
                          for (final p in r.predicciones)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                  widget.comparacion
                                      ? Icons.analytics
                                      : p.correcta
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                  color:
                                      p.correcta ? Colors.greenAccent : null),
                              title: Text(
                                  '${p.esperada} → ${p.predicha ?? 'Error'}'),
                              subtitle: Text(p.error ??
                                  '${p.confianza.toStringAsFixed(1)}% · ${p.ms.toStringAsFixed(1)} ms'),
                            ),
                        ],
                      )),
                  ],
                ))));
    return widget.comparacion
        ? Scaffold(
            appBar: AppBar(title: const Text('Comparar modelos')),
            body: content)
        : content;
  }
}
