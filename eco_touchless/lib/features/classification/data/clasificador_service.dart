import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/modelo_ia.dart';
import '../domain/preprocesador_frame_yuv.dart';
import '../domain/preparacion_imagen.dart';
import '../domain/perfil_modelo.dart';

/// Resultado de una clasificación: label predicho + confianza (0-100).
class ResultadoClasificacion {
  final String label;
  final double confianza;
  final double inferenciaMs;
  ResultadoClasificacion(this.label, this.confianza, {this.inferenciaMs = 0});
}

/// Envuelve el modelo TFLite seleccionado para que todas las modalidades de
/// captura compartan exactamente la misma instancia y preprocesamiento.
class ClasificadorService {
  ClasificadorService._interno();

  /// Instancia aislada para experimentar sin reemplazar el modelo principal.
  ClasificadorService.experimento();
  static final ClasificadorService instancia = ClasificadorService._interno();

  Interpreter? _interpreter;
  GpuDelegateV2? _delegateAndroid;
  GpuDelegate? _delegateIos;
  List<String> _labels = [];
  ModeloIa? _modeloActivo;
  Float32List? _bufferSalida;
  Float32List? _bufferFrameContinuo;
  bool _cargando = false;
  bool _gpuSolicitada = false;
  bool _gpuActiva = false;

  static const List<double> kMean = [0.485, 0.456, 0.406];
  static const List<double> kStd = [0.229, 0.224, 0.225];
  int _inputSize = 224;
  PerfilModelo perfil = PerfilModelo.insignia;
  String get normalizacion => perfil.normalizacion;
  List<double> get _mean => normalizacion == 'ceroUno'
      ? const [0, 0, 0]
      : normalizacion == 'menosUnoUno'
          ? const [0.5, 0.5, 0.5]
          : kMean;
  List<double> get _std => normalizacion == 'ceroUno'
      ? const [1, 1, 1]
      : normalizacion == 'menosUnoUno'
          ? const [0.5, 0.5, 0.5]
          : kStd;

  bool get listo =>
      _interpreter != null &&
      _labels.isNotEmpty &&
      _bufferSalida != null &&
      _bufferFrameContinuo != null;
  List<String> get labels => _labels;
  ModeloIa? get modeloActivo => _modeloActivo;
  int get inputSize => _inputSize;
  bool get gpuActiva => _gpuActiva;
  bool get gpuSolicitada => _gpuSolicitada;

  /// Carga el modelo una sola vez. Llamadas subsiguientes son no-op si ya
  /// está cargado, así que es seguro llamarlo desde cualquier pantalla.
  Future<String?> cargar({
    required ModeloIa modelo,
    bool usarGPU = false,
    bool forzarRecarga = false,
  }) async {
    if (_cargando) return null;
    if (listo &&
        !forzarRecarga &&
        _gpuSolicitada == usarGPU &&
        _modeloActivo?.assetPath == modelo.assetPath) {
      return null;
    }
    _cargando = true;
    _gpuSolicitada = usarGPU;
    try {
      liberar();
      _gpuSolicitada = usarGPU;
      final rawLabels = await rootBundle.loadString(modelo.labelsAssetPath);
      _labels = rawLabels
          .trim()
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (usarGPU && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final options = InterpreterOptions();
          if (Platform.isAndroid) {
            _delegateAndroid = GpuDelegateV2();
            options.addDelegate(_delegateAndroid!);
          } else {
            _delegateIos = GpuDelegate();
            options.addDelegate(_delegateIos!);
          }
          _interpreter = await Interpreter.fromAsset(
            modelo.assetPath,
            options: options,
          );
          _gpuActiva = true;
        } catch (e) {
          debugPrint('GPU no disponible; se usará CPU: $e');
          _liberarDelegates();
          _interpreter = await Interpreter.fromAsset(modelo.assetPath);
          _gpuActiva = false;
        }
      } else {
        _interpreter = await Interpreter.fromAsset(modelo.assetPath);
        _gpuActiva = false;
      }

      if (_interpreter!.getInputTensors().length != 1 ||
          _interpreter!.getOutputTensors().length != 1) {
        throw StateError(
            'Se requiere un clasificador con una entrada y una salida.');
      }
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final inputType = _interpreter!.getInputTensor(0).type;
      if (inputType != TensorType.float32) {
        throw StateError(
          'El modelo usa entrada $inputType. Actualmente se admiten modelos '
          'TFLite con entrada float32.',
        );
      }
      if (inputShape.length != 4 ||
          inputShape[0] != 1 ||
          inputShape[1] != inputShape[2] ||
          inputShape[3] != 3 ||
          inputShape[1] < 32 ||
          inputShape[1] > 1024) {
        throw StateError(
          'El modelo espera una entrada $inputShape. Se requiere el formato '
          '[1, alto, ancho, 3], cuadrado y RGB.',
        );
      }
      _inputSize = inputShape[1];
      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      if (outputTensor.type != TensorType.float32) {
        throw StateError(
          'El modelo usa salida ${outputTensor.type}. Actualmente se admiten '
          'modelos TFLite con salida float32.',
        );
      }
      if (outputShape.isEmpty ||
          outputShape.last != _labels.length ||
          outputShape.fold<int>(1, (a, b) => a * b) != _labels.length) {
        throw StateError(
          'El modelo produce ${outputShape.isEmpty ? 0 : outputShape.last} clases, '
          'pero ${modelo.labelsAssetPath} contiene ${_labels.length}.',
        );
      }
      _bufferSalida = Float32List(_labels.length);
      _bufferFrameContinuo = Float32List(_inputSize * _inputSize * 3);
      _modeloActivo = modelo;
      return null;
    } catch (e) {
      liberar();
      return e.toString();
    } finally {
      _cargando = false;
    }
  }

  Float32List _preprocesar(img.Image image) {
    image = img.bakeOrientation(image);
    if (perfil.redimensionar) {
      image = prepararImagen(image, perfil);
    }
    final shortest = min(image.width, image.height);
    final sx = (image.width - shortest) ~/ 2;
    final sy = (image.height - shortest) ~/ 2;
    final cropped =
        img.copyCrop(image, x: sx, y: sy, width: shortest, height: shortest);
    final resized = img.copyResize(
      perfil.redimensionar ? image : cropped,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final salida = Float32List(_inputSize * _inputSize * 3);
    var indice = 0;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        salida[indice++] =
            ((perfil.bgr ? pixel.b : pixel.r).toDouble() / 255.0 - _mean[0]) /
                _std[0];
        salida[indice++] = (pixel.g.toDouble() / 255.0 - _mean[1]) / _std[1];
        salida[indice++] =
            ((perfil.bgr ? pixel.r : pixel.b).toDouble() / 255.0 - _mean[2]) /
                _std[2];
      }
    }
    return salida;
  }

  /// Corre inferencia sobre bytes de una imagen completa (JPEG/PNG).
  ResultadoClasificacion? clasificarBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return clasificarImagen(image);
  }

  /// Only for isolated CPU experiment instances. Caller must await before
  /// closing the interpreter; the worker borrows, never frees, its address.
  Future<ResultadoClasificacion?> clasificarBytesEnSegundoPlano(
      Uint8List bytes) {
    if (!listo || _gpuActiva) {
      throw StateError('El experimento requiere CPU disponible');
    }
    return compute(_clasificarExperimento, <String, Object>{
      'address': _interpreter!.address,
      'labels': _labels,
      'size': _inputSize,
      'perfil': perfil.toJson(),
      'bytes': bytes,
    });
  }

  static ResultadoClasificacion? _clasificarExperimento(
      Map<String, Object> data) {
    final runner = ClasificadorService.experimento()
      .._interpreter =
          Interpreter.fromAddress(data['address'] as int, allocated: true)
      .._labels = data['labels'] as List<String>
      .._inputSize = data['size'] as int
      ..perfil = PerfilModelo.fromJson(data['perfil'] as Map<String, dynamic>);
    runner._bufferSalida = Float32List(runner._labels.length);
    runner._bufferFrameContinuo =
        Float32List(runner._inputSize * runner._inputSize * 3);
    return runner.clasificarBytes(data['bytes'] as Uint8List);
  }

  /// Corre inferencia sobre una imagen ya decodificada (útil si en el futuro
  /// se necesita clasificar un recorte en vez de la foto completa).
  ResultadoClasificacion? clasificarImagen(img.Image image) {
    if (!listo) return null;

    try {
      final input = _preprocesar(image);
      return _ejecutarTensor(input);
    } catch (e) {
      return null;
    }
  }

  /// Clasifica un frame de cámara sin escribirlo en disco ni codificar JPEG.
  ResultadoClasificacion? clasificarFrame(
    CameraImage frame, {
    required int rotacionGrados,
  }) {
    if (!listo || frame.planes.length < 2) return null;
    try {
      final input = preprocesarFrameYuv420(
        ancho: frame.width,
        alto: frame.height,
        planos: [
          for (final plano in frame.planes)
            PlanoFrameYuv(
              bytes: plano.bytes,
              bytesPorFila: plano.bytesPerRow,
              bytesPorPixel: plano.bytesPerPixel ?? 1,
            ),
        ],
        rotacionGrados: rotacionGrados,
        tamanoDestino: _inputSize,
        mean: _mean,
        std: _std,
        anchoMuestreo: perfil.redimensionar ? perfil.ancho : 0,
        altoMuestreo: perfil.redimensionar ? perfil.alto : 0,
        letterbox: perfil.letterbox,
        bgr: perfil.bgr,
        bufferSalida: _bufferFrameContinuo,
      );
      return _ejecutarTensor(input);
    } catch (e) {
      debugPrint('No se pudo clasificar un frame en RAM: $e');
      return null;
    }
  }

  ResultadoClasificacion _ejecutarTensor(Float32List input) {
    final output = _bufferSalida!;
    // ByteBuffer evita reconstruir 150 mil objetos double por inferencia.
    final reloj = Stopwatch()..start();
    _interpreter!.run(input.buffer, output.buffer);
    reloj.stop();

    final scores = probabilidades(output);
    var indice = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[indice]) indice = i;
    }
    return ResultadoClasificacion(
      _labels[indice],
      scores[indice] * 100,
      inferenciaMs: reloj.elapsedMicroseconds / 1000,
    );
  }

  void liberar() {
    _interpreter?.close();
    _interpreter = null;
    _liberarDelegates();
    _labels = [];
    _bufferSalida = null;
    _bufferFrameContinuo = null;
    _modeloActivo = null;
    _gpuActiva = false;
  }

  void _liberarDelegates() {
    _delegateAndroid?.delete();
    _delegateAndroid = null;
    _delegateIos?.delete();
    _delegateIos = null;
  }
}
