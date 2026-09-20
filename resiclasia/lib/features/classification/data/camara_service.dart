import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controla una única instancia de [CameraController] compartida por TODA la
/// app (no solo por la pantalla de Clasificación). Esto es lo que permite
/// que Configuración y Estadísticas también muestren la cámara de fondo
/// (atenuada) en vez de un color plano, sin pagar el costo de inicializar
/// la cámara más de una vez ni pelear por el recurso físico.
///
/// Es un [ChangeNotifier] para que cualquier pantalla pueda escuchar cuándo
/// la cámara pasa a estar lista, sin necesidad de pasar callbacks a mano.
class CamaraService extends ChangeNotifier {
  CamaraService._interno();
  static final CamaraService instancia = CamaraService._interno();

  CameraController? _controller;
  List<CameraDescription> _camaras = [];
  bool _inicializando = false;
  bool _disponiendo = false;
  int _generacion = 0;
  Completer<void>? _inicializacionEnCurso;
  Completer<void>? _disposicionEnCurso;
  String? _error;
  CameraLensDirection _direccion = CameraLensDirection.back;
  bool _cambiando = false;
  bool get puedeCambiar =>
      !_cambiando &&
      _camaras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _camaras.any((c) => c.lensDirection == CameraLensDirection.back);
  bool get frontal => _direccion == CameraLensDirection.front;
  int get rotacionFrame {
    final c = _controller;
    if (c == null) return 0;
    final angle = switch (c.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return (c.description.sensorOrientation +
            (frontal ? angle : -angle) +
            360) %
        360;
  }

  Future<void> cambiarCamara() async {
    if (!puedeCambiar || _inicializando) return;
    _cambiando = true;
    try {
      await pausarStream();
      await disponer();
      _direccion =
          frontal ? CameraLensDirection.back : CameraLensDirection.front;
      await inicializar();
    } finally {
      _cambiando = false;
      notifyListeners();
    }
  }

  CameraController? get controller => _controller;
  bool get lista => _controller != null && _controller!.value.isInitialized;
  String? get error => _error;
  bool get hayCamaras => _camaras.isNotEmpty;

  Future<void> inicializar() async {
    final disposicion = _disposicionEnCurso;
    if (disposicion != null) await disposicion.future;
    if (lista) return;
    if (_inicializando) {
      await _inicializacionEnCurso!.future;
      if (!lista) return inicializar();
      return;
    }
    _inicializando = true;
    _inicializacionEnCurso = Completer<void>();
    final generacionActual = _generacion;
    CameraController? nuevoController;
    try {
      _camaras = await availableCameras();
      if (_camaras.isEmpty) {
        _error = 'No se encontró ninguna cámara en el dispositivo.';
        return;
      }
      final camaraTrasera = _camaras.firstWhere(
        (camara) => camara.lensDirection == _direccion,
        orElse: () => _camaras.first,
      );
      nuevoController = CameraController(
        camaraTrasera,
        ResolutionPreset.medium,
        enableAudio: false,
        // YUV420 es el formato que sabemos interpretar en la detección de
        // movimiento (accedemos directo al plano de luminancia). Sin fijar
        // esto explícitamente, algunas plataformas entregan otro formato
        // (p.ej. BGRA8888 en iOS) y el análisis de movimiento queda
        // leyendo bytes que no son luminancia real, así que nunca detecta
        // nada por más alta que se ponga la sensibilidad.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await nuevoController.initialize();
      if (generacionActual != _generacion) {
        await nuevoController.dispose();
        nuevoController = null;
        return;
      }
      _controller = nuevoController;
      nuevoController = null;
      _error = null;
    } catch (e) {
      await nuevoController?.dispose();
      _error = e.toString();
      debugPrint('Error de cámara: $e');
    } finally {
      _inicializando = false;
      _inicializacionEnCurso?.complete();
      _inicializacionEnCurso = null;
      notifyListeners();
    }
  }

  Future<void> pausarStream() async {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> disponer() async {
    if (_disponiendo) return _disposicionEnCurso!.future;
    _disponiendo = true;
    _generacion++;
    _disposicionEnCurso = Completer<void>();
    final controller = _controller;
    _controller = null;
    notifyListeners();
    try {
      await controller?.dispose();
    } finally {
      _disponiendo = false;
      _disposicionEnCurso?.complete();
      _disposicionEnCurso = null;
    }
  }
}
