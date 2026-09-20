import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_theme.dart';
import '../../../core/domain/categoria_residuo.dart';
import '../../../core/widgets/fondo_camara.dart';
import '../../esp/data/esp_service.dart';
import '../../settings/data/config_service.dart';
import '../../statistics/data/database_service.dart';
import '../data/camara_service.dart';
import '../data/clasificador_service.dart';
import '../data/modelo_catalogo_service.dart';
import '../domain/clasificacion.dart';
import '../domain/control_disparo_continuo.dart';
import '../domain/detector_movimiento_v2.dart';
import '../domain/modelo_ia.dart';
import '../domain/preparacion_imagen.dart';
import '../../esp/presentation/estado_esp.dart';
import '../../esp/data/esp_conexion_monitor.dart';
import '../../settings/domain/modo_interfaz.dart';

class PantallaClasificacion extends StatefulWidget {
  const PantallaClasificacion({super.key, this.visible = true});

  final bool visible;

  @override
  State<PantallaClasificacion> createState() => _PantallaClasificacionState();
}

class _PantallaClasificacionState extends State<PantallaClasificacion>
    with WidgetsBindingObserver {
  final _camara = CamaraService.instancia;
  final _clasificador = ClasificadorService.instancia;
  final _catalogoModelos = ModeloCatalogoService.instancia;
  final _config = ConfigService.instancia;
  final _database = DatabaseService.instancia;

  bool _isProcessing = false;
  ModoInterfaz _modoInterfaz = ModoInterfaz.facil;
  List<ModeloIa> _modelos = const [];
  final List<String> _recientes = [];
  String? _errorInferencia;
  bool _confirmacionFueManual = false;
  bool get _detallado => _modoInterfaz.muestraDetalles;
  bool get _desarrollador => _modoInterfaz == ModoInterfaz.desarrollador;
  bool get _limpio => _modoInterfaz == ModoInterfaz.limpio;
  bool? get _espVinculadaAlClasificar => EspConexionMonitor.instancia.activo
      ? EspConexionMonitor.instancia.conectado
      : false;
  String _label = 'Apuntá y dispará';
  String _confidence = "0.0";
  bool _resultadoDudoso = false;
  String? _loadError;
  String? _ultimaFotoPath;

  double _umbralConfianza = 60.0;
  bool _deteccionMovimientoActiva = false;
  double _sensibilidadMovimiento = 0.5;
  bool _guardarHistorialAuto = true;
  bool _confirmacionManual = true;
  int _timeoutConfirmacionSegundos = 5;
  bool _capturarTrasCeseMovimiento = false;
  bool _ultimaFotoEsTemporal = false;
  bool _cargandoConfiguracion = false;
  bool _recargarConfiguracionPendiente = false;
  bool _modoContinuo = false;
  double _umbralModoContinuo = 80.0;
  bool _procesandoFrameContinuo = false;
  DateTime _ultimoFrameContinuo = DateTime.fromMillisecondsSinceEpoch(0);
  final _controlDisparoContinuo = ControlDisparoContinuo();
  int _latenciaInferenciaMs = 0;
  int _disparosContinuos = 0;
  ModeloIa? _modeloSeleccionado;

  bool _streamActivo = false;
  bool _movimientoDetectado = false;
  DateTime _ultimoChequeoMovimiento = DateTime.now();
  List<double>? _frameAnteriorLuma;
  final _detectorMovimiento = DetectorMovimientoV2();
  DateTime? _ultimoDisparoAutomatico;

  // --- Disparo automático tras detectar movimiento ---
  // El detector v2 filtra exposición y ruido antes de iniciar esta cuenta.
  // Según la preferencia del usuario, la cuenta se cancela al volver a la
  // quietud o permanece armada para capturar el objeto una vez detenido.
  static const Duration _retardoDisparoAutomatico = Duration(seconds: 2);
  static const Duration _enfriamientoDisparoAutomatico = Duration(seconds: 5);
  Timer? _timerDisparoAutomatico;
  int _cuentaRegresivaSegundos = 0;

  // --- Envío a la ESP32 ---
  String? _espMensaje;
  bool _espMensajeEsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camara.addListener(_onCamaraActualizada);
    _config.addListener(_onConfiguracionActualizada);
    _database.addListener(_onHistorialActualizado);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _cargarConfiguracion();
      _actualizarStreamMovimiento();
    });
  }

  void _onConfiguracionActualizada() {
    unawaited(_cargarConfiguracion());
  }

  void _onHistorialActualizado() {
    final ruta = _ultimaFotoPath;
    if (ruta != null && !File(ruta).existsSync() && mounted) {
      setState(() {
        _ultimaFotoPath = null;
        _ultimaFotoEsTemporal = false;
      });
    }
  }

  void _onCamaraActualizada() {
    if (!mounted) return;
    setState(() {});
    _actualizarStreamMovimiento();
  }

  Future<void> _cargarConfiguracion() async {
    if (_cargandoConfiguracion) {
      _recargarConfiguracionPendiente = true;
      return;
    }
    _cargandoConfiguracion = true;
    try {
      do {
        _recargarConfiguracionPendiente = false;
        await _aplicarConfiguracion();
      } while (_recargarConfiguracionPendiente && mounted);
    } finally {
      _cargandoConfiguracion = false;
    }
  }

  Future<void> _aplicarConfiguracion() async {
    final modoContinuoAnterior = _modoContinuo;
    final umbral = await _config.getUmbralConfianza();
    final movimiento = await _config.getDeteccionMovimiento();
    final sensibilidad = await _config.getSensibilidadMovimiento();
    final guardarAuto = await _config.getGuardarHistorialAuto();
    final confirmacionManual = await _config.getConfirmacionManual();
    final timeoutConfirmacion = await _config.getTimeoutConfirmacionSegundos();
    final capturarTrasCese = await _config.getCapturarTrasCeseMovimiento();
    final modoContinuo = await _config.getModoContinuo();
    final modoInterfaz = await _config.getModoInterfaz();
    final umbralContinuo = await _config.getUmbralModoContinuo();
    final usarGPU = await _config.getUsarGPU();
    final modeloAsset = await _config.getModeloSeleccionado();
    final modelos = await _catalogoModelos.obtenerModelos();
    final modelo = ModeloCatalogoService.resolver(modelos, modeloAsset);
    final perfil =
        modelo == null ? null : await _config.getPerfilModelo(modelo.assetPath);

    if (!mounted) return;
    setState(() {
      _modoInterfaz = modoInterfaz;
      _modelos = modelos;
    });
    if (modelo == null) {
      _clasificador.liberar();
      setState(() {
        _modeloSeleccionado = null;
        _loadError = 'No hay modelos .tflite dentro de assets/modelos/.';
      });
      _actualizarStreamMovimiento();
      return;
    }
    setState(() {
      _umbralConfianza = umbral;
      _deteccionMovimientoActiva = movimiento;
      _sensibilidadMovimiento = sensibilidad;
      _guardarHistorialAuto = guardarAuto;
      _confirmacionManual = confirmacionManual;
      _timeoutConfirmacionSegundos = timeoutConfirmacion;
      _capturarTrasCeseMovimiento = capturarTrasCese;
      _modoContinuo = modoContinuo;
      _umbralModoContinuo = umbralContinuo;
      _modeloSeleccionado = modelo;
      if (modoContinuoAnterior != modoContinuo) {
        _label = modoContinuo ? 'Fondo' : 'Apuntá y dispará';
        _confidence = '0.0';
        _latenciaInferenciaMs = 0;
        _disparosContinuos = 0;
      }
    });

    if (!capturarTrasCese && !_movimientoDetectado) {
      _cancelarCuentaRegresivaDisparo();
    }
    if (modoContinuoAnterior != modoContinuo) {
      _reiniciarEstadoContinuo();
      if (modoContinuo) {
        unawaited(EspService.instancia.precalentarConexion());
      }
    }

    _clasificador.perfil = perfil!;
    final error = await _clasificador.cargar(
      modelo: modelo,
      usarGPU: usarGPU,
    );
    if (!mounted) return;
    setState(() => _loadError = error);

    if (usarGPU && !_clasificador.gpuActiva) {
      await _config.setUsarGPU(false);
      if (!mounted) return;
      if (_detallado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'La GPU no es compatible con este modelo o dispositivo. Se usa CPU.'),
          ),
        );
      }
    }

    _actualizarStreamMovimiento();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_pausarCamara());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_reanudarCamara());
    }
  }

  @override
  void didUpdateWidget(covariant PantallaClasificacion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _actualizarStreamMovimiento();
      });
    }
  }

  Future<void> _pausarCamara() async {
    await _detenerStreamMovimiento();
    await _camara.disponer();
  }

  Future<void> _reanudarCamara() async {
    await _camara.inicializar();
    if (mounted) _actualizarStreamMovimiento();
  }

  void _actualizarStreamMovimiento() {
    final controller = _camara.controller;
    if (!_camara.lista || controller == null) return;
    final requiereStream =
        widget.visible && (_deteccionMovimientoActiva || _modoContinuo);
    if (requiereStream && !_streamActivo) {
      _streamActivo = true;
      unawaited(controller
          .startImageStream(_procesarFrameCamara)
          .catchError((Object e) {
        _streamActivo = false;
        debugPrint('No se pudo iniciar el stream de movimiento: $e');
      }));
    } else if (!requiereStream && _streamActivo) {
      unawaited(_detenerStreamMovimiento());
    }
  }

  void _procesarFrameCamara(CameraImage frame) {
    if (_modoContinuo) {
      _procesarFrameContinuo(frame);
    } else if (_deteccionMovimientoActiva) {
      _procesarFrameMovimiento(frame);
    }
  }

  void _procesarFrameContinuo(CameraImage frame) {
    final ahora = DateTime.now();
    if (!widget.visible ||
        _procesandoFrameContinuo ||
        _isProcessing ||
        !_clasificador.listo ||
        ahora.difference(_ultimoFrameContinuo).inMilliseconds < 80) {
      return;
    }
    _ultimoFrameContinuo = ahora;
    _procesandoFrameContinuo = true;
    final reloj = Stopwatch()..start();
    try {
      final resultado = _clasificador.clasificarFrame(
        frame,
        rotacionGrados: _camara.rotacionFrame,
      );
      reloj.stop();
      if (resultado == null || !mounted || !_modoContinuo) return;

      final superaUmbral = resultado.confianza >= _umbralModoContinuo;
      final accionable = EspService.puedeAccionar(resultado.label);
      setState(() {
        _label = resultado.label;
        _confidence = resultado.confianza.toStringAsFixed(1);
        _resultadoDudoso = !superaUmbral;
        _latenciaInferenciaMs = reloj.elapsedMilliseconds;
        _errorInferencia = null;
        _registrarReciente(resultado.label, resultado.confianza);
      });

      final debeDisparar = _controlDisparoContinuo.evaluar(
        label: resultado.label,
        confianza: resultado.confianza,
        umbral: _umbralModoContinuo,
        accionable: accionable,
        ahora: ahora,
      );
      if (debeDisparar) {
        unawaited(_accionarDeteccionContinua(resultado));
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _errorInferencia = 'No se pudo analizar el fotograma: $e');
      }
    } finally {
      _procesandoFrameContinuo = false;
    }
  }

  Future<void> _accionarDeteccionContinua(
    ResultadoClasificacion resultado,
  ) async {
    if (mounted) {
      setState(() {
        _espMensaje = '⚡ Umbral superado. Enviando a la ESP32...';
        _espMensajeEsError = false;
      });
    }

    final envio = _notificarEsp32(
      resultado.label,
      contarDisparoContinuo: true,
    );
    if (_guardarHistorialAuto) {
      unawaited(
        _database
            .insertar(
          Clasificacion(
            label: resultado.label,
            labelOriginal: resultado.label,
            confirmada: false,
            esEnVivo: true,
            aceptacion: 'automatica',
            espVinculada: _espVinculadaAlClasificar,
            confianza: resultado.confianza,
            rutaImagen: '',
            fecha: DateTime.now(),
          ),
        )
            .catchError((Object error) {
          debugPrint('No se pudo guardar la detección continua: $error');
          return -1;
        }),
      );
    }
    await envio;
  }

  Future<void> _detenerStreamMovimiento() async {
    final controller = _camara.controller;
    final estabaActivo = _streamActivo;
    _streamActivo = false;
    _cancelarCuentaRegresivaDisparo();
    if (_movimientoDetectado && mounted) {
      setState(() => _movimientoDetectado = false);
    }
    if (estabaActivo &&
        controller != null &&
        controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('No se pudo detener el stream de movimiento: $e');
      }
    }
    _frameAnteriorLuma = null;
    _detectorMovimiento.reset();
  }

  void _reiniciarEstadoContinuo() {
    _procesandoFrameContinuo = false;
    _controlDisparoContinuo.reset();
  }

  Future<void> _cambiarModoContinuo(bool activo) async {
    if (_isProcessing || activo == _modoContinuo) return;
    setState(() {
      _modoContinuo = activo;
      _label = activo ? 'Fondo' : 'Apuntá y dispará';
      _confidence = '0.0';
      _latenciaInferenciaMs = 0;
      _disparosContinuos = 0;
      _espMensaje = activo
          ? 'En vivo listo: apuntá y mantené el residuo en el marco.'
          : null;
      _resultadoDudoso = false;
    });
    _reiniciarEstadoContinuo();
    await _config.setModoContinuo(activo);
    if (activo) {
      // El calentamiento es oportunista: no demora la apertura de la guía ni
      // la activación del stream si la ESP32 está apagada o fuera de alcance.
      unawaited(EspService.instancia.precalentarConexion());
      if (!mounted) return;
      final guiaVista = await _config.getGuiaModoContinuoVista();
      if (!guiaVista && mounted) {
        await _mostrarGuiaModoContinuo();
        await _config.setGuiaModoContinuoVista(true);
      }
    }
    if (mounted) _actualizarStreamMovimiento();
  }

  Future<void> _mostrarGuiaModoContinuo() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Modo En vivo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonCian,
                    ),
              ),
              const SizedBox(height: 18),
              const _PasoModoContinuo(
                numero: '1',
                icono: Icons.center_focus_strong,
                titulo: 'Apuntá',
                descripcion: 'Poné un solo residuo dentro del marco.',
              ),
              const _PasoModoContinuo(
                numero: '2',
                icono: Icons.pan_tool_alt_outlined,
                titulo: 'Mantenelo quieto',
                descripcion:
                    'La app reconoce el residuo fotograma a fotograma.',
              ),
              const _PasoModoContinuo(
                numero: '3',
                icono: Icons.bolt,
                titulo: 'Listo, sin tocar nada',
                descripcion:
                    'Si esa categoría tiene tapa automática, la app la acciona.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.videocam),
                label: const Text('Empezar en vivo'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Extrae una cuadrícula del plano Y de YUV420 y la entrega al detector v2,
  /// que compensa exposición global, aprende ruido y aplica histéresis.
  void _procesarFrameMovimiento(CameraImage frame) {
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoChequeoMovimiento).inMilliseconds < 250) return;
    _ultimoChequeoMovimiento = ahora;
    if (_isProcessing) return;

    try {
      final plano = frame.planes[0];
      final bytes = plano.bytes;
      final ancho = frame.width;
      final alto = frame.height;
      // bytesPerRow puede ser mayor que el ancho real por padding de fila:
      // hay que usarlo para indexar, no `ancho`, o el muestreo se desalinea
      // progresivamente fila a fila en varios dispositivos Android.
      final stride = plano.bytesPerRow;

      const grilla = 16;
      final bloqueAncho = ancho ~/ grilla;
      final bloqueAlto = alto ~/ grilla;
      if (bloqueAncho == 0 || bloqueAlto == 0) return;

      final actual = List<double>.filled(grilla * grilla, 0);

      for (int by = 0; by < grilla; by++) {
        for (int bx = 0; bx < grilla; bx++) {
          int suma = 0;
          int cuenta = 0;
          final startY = by * bloqueAlto;
          final startX = bx * bloqueAncho;
          for (int y = startY; y < startY + bloqueAlto && y < alto; y += 4) {
            final filaBase = y * stride;
            for (int x = startX;
                x < startX + bloqueAncho && x < ancho;
                x += 4) {
              suma += bytes[filaBase + x];
              cuenta++;
            }
          }
          actual[by * grilla + bx] = cuenta > 0 ? suma / cuenta : 0;
        }
      }

      if (_frameAnteriorLuma != null) {
        final resultado = _detectorMovimiento.procesar(
          anterior: _frameAnteriorLuma!,
          actual: actual,
          sensibilidad: _sensibilidadMovimiento,
        );

        if (resultado.cambio && mounted) {
          setState(() => _movimientoDetectado = resultado.activo);
          if (resultado.activo) {
            _iniciarCuentaRegresivaDisparo();
          } else if (!_capturarTrasCeseMovimiento) {
            _cancelarCuentaRegresivaDisparo();
          }
        }
      }
      _frameAnteriorLuma = actual;
    } catch (e) {
      debugPrint('Error en detección de movimiento: $e');
    }
  }

  /// Arranca (o reinicia) la cuenta regresiva de 2 segundos que, al llegar
  /// a cero, dispara la foto automáticamente. Se muestra en pantalla para
  /// que el usuario sepa que está por sacarse la foto y pueda, por ejemplo,
  /// terminar de acomodar el residuo frente a la cámara.
  void _iniciarCuentaRegresivaDisparo() {
    final ultimoDisparo = _ultimoDisparoAutomatico;
    if (ultimoDisparo != null &&
        DateTime.now().difference(ultimoDisparo) <
            _enfriamientoDisparoAutomatico) {
      return;
    }
    _timerDisparoAutomatico?.cancel();
    if (_isProcessing) return;

    setState(
        () => _cuentaRegresivaSegundos = _retardoDisparoAutomatico.inSeconds);

    _timerDisparoAutomatico =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || (!_movimientoDetectado && !_capturarTrasCeseMovimiento)) {
        timer.cancel();
        return;
      }
      final restante = _cuentaRegresivaSegundos - 1;
      if (restante <= 0) {
        timer.cancel();
        setState(() => _cuentaRegresivaSegundos = 0);
        _ultimoDisparoAutomatico = DateTime.now();
        _takePictureAndProcess();
      } else {
        setState(() => _cuentaRegresivaSegundos = restante);
      }
    });
  }

  /// Cancela el disparo automático si el movimiento cesó antes de tiempo
  /// (por ejemplo, alguien acercó la mano y la sacó sin dejar nada).
  void _cancelarCuentaRegresivaDisparo() {
    _timerDisparoAutomatico?.cancel();
    _timerDisparoAutomatico = null;
    if (_cuentaRegresivaSegundos != 0 && mounted) {
      setState(() => _cuentaRegresivaSegundos = 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camara.removeListener(_onCamaraActualizada);
    _config.removeListener(_onConfiguracionActualizada);
    _database.removeListener(_onHistorialActualizado);
    _timerDisparoAutomatico?.cancel();
    unawaited(_detenerStreamMovimiento());
    if (_ultimaFotoEsTemporal && _ultimaFotoPath != null) {
      unawaited(_borrarArchivoSiExiste(_ultimaFotoPath!));
    }
    super.dispose();
  }

  Future<void> _borrarArchivoSiExiste(String ruta) async {
    try {
      final archivo = File(ruta);
      if (await archivo.exists()) {
        await archivo.delete();
      }
    } catch (e) {
      debugPrint('No se pudo borrar la foto temporal: $e');
    }
  }

  Future<String> _guardarCopiaPermanente(String pathTemporal) async {
    final dir = await getApplicationDocumentsDirectory();
    final carpetaFotos = Directory(p.join(dir.path, 'fotos_clasificadas'));
    if (!await carpetaFotos.exists()) {
      await carpetaFotos.create(recursive: true);
    }
    final nombreArchivo = 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destino = p.join(carpetaFotos.path, nombreArchivo);
    await File(pathTemporal).copy(destino);
    return destino;
  }

  Future<void> _takePictureAndProcess() async {
    final controller = _camara.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessing) {
      return;
    }
    if (!_clasificador.listo) {
      if (_detallado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  '⏳ El modelo todavía está cargando, esperá un segundo.')),
        );
      }
      return;
    }

    // Cancelamos cualquier cuenta regresiva pendiente: la foto ya se está
    // tomando ahora (sea porque el usuario tocó el botón o porque el
    // temporizador de movimiento llegó a cero), así que no debe quedar un
    // segundo disparo programado sobre esta misma escena.
    _cancelarCuentaRegresivaDisparo();

    // Si había un stream de detección de movimiento activo, se detiene
    // temporalmente: no se puede tomar una foto con takePicture() mientras
    // hay un stream de imágenes corriendo sobre el mismo controller.
    final streamEstabaActivo = _streamActivo;
    if (streamEstabaActivo) {
      await _detenerStreamMovimiento();
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _errorInferencia = null;
      _espMensaje = null;
    });

    String? capturaTemporal;
    String? copiaPermanenteSinRegistrar;
    final fechaCaptura = DateTime.now();
    final espAlCapturar = _espVinculadaAlClasificar;
    try {
      final xFile = await controller.takePicture();
      capturaTemporal = xFile.path;
      final bytes = await File(xFile.path).readAsBytes();
      final reloj = Stopwatch()..start();
      final result = _clasificador.clasificarBytes(bytes);
      reloj.stop();
      if (_clasificador.perfil.redimensionar) {
        await File(xFile.path)
            .writeAsBytes(prepararCapturaPerfil(bytes, _clasificador.perfil));
      }

      if (result != null) {
        final dudoso = result.confianza < _umbralConfianza;
        if (!mounted) {
          await _borrarArchivoSiExiste(xFile.path);
          return;
        }
        final fotoAnterior = _ultimaFotoPath;
        final fotoAnteriorEraTemporal = _ultimaFotoEsTemporal;

        setState(() {
          _label = result.label;
          _confidence = result.confianza.toStringAsFixed(1);
          _resultadoDudoso = dudoso;
          _latenciaInferenciaMs = reloj.elapsedMilliseconds;
          _registrarReciente(result.label, result.confianza);
          _ultimaFotoPath = xFile.path;
          _ultimaFotoEsTemporal = true;
        });

        if (fotoAnteriorEraTemporal &&
            fotoAnterior != null &&
            fotoAnterior != xFile.path) {
          unawaited(_borrarArchivoSiExiste(fotoAnterior));
        }

        final labelConfirmada = await _solicitarConfirmacion(result);
        if (!mounted) return;
        if (labelConfirmada == null) {
          setState(() {
            _espMensaje = 'Resultado sin confirmar: no se guardó ni se envió.';
            _espMensajeEsError = false;
            _isProcessing = false;
          });
          return;
        }

        String rutaVista = xFile.path;
        var fotoTemporal = true;
        if (_guardarHistorialAuto) {
          final rutaPermanente = await _guardarCopiaPermanente(xFile.path);
          copiaPermanenteSinRegistrar = rutaPermanente;
          await _database.insertar(Clasificacion(
            label: labelConfirmada,
            labelOriginal: result.label,
            confirmada: _confirmacionFueManual,
            aceptacion: _confirmacionFueManual ? 'manual' : 'automatica',
            espVinculada: espAlCapturar,
            confianza: result.confianza,
            rutaImagen: rutaPermanente,
            fecha: fechaCaptura,
          ));
          copiaPermanenteSinRegistrar = null;
          rutaVista = rutaPermanente;
          fotoTemporal = false;
          await _borrarArchivoSiExiste(xFile.path);
          capturaTemporal = null;
        }

        if (!mounted) {
          if (fotoTemporal) await _borrarArchivoSiExiste(rutaVista);
          return;
        }
        setState(() {
          _label = labelConfirmada;
          _resultadoDudoso = false;
          _ultimaFotoPath = rutaVista;
          _ultimaFotoEsTemporal = fotoTemporal;
          _isProcessing = false;
        });
        unawaited(_notificarEsp32(labelConfirmada));
      } else {
        await _borrarArchivoSiExiste(xFile.path);
        capturaTemporal = null;
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _errorInferencia = 'La IA no pudo procesar la imagen.';
          });
          if (_detallado) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('❌ La IA no pudo procesar la imagen.')),
            );
          }
        }
      }
    } catch (e) {
      if (capturaTemporal != null) {
        await _borrarArchivoSiExiste(capturaTemporal);
      }
      if (copiaPermanenteSinRegistrar != null) {
        await _borrarArchivoSiExiste(copiaPermanenteSinRegistrar);
      }
      debugPrint('Error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorInferencia = 'No se pudo guardar o procesar la fotografía: $e';
          if (capturaTemporal == _ultimaFotoPath) {
            _ultimaFotoPath = null;
            _ultimaFotoEsTemporal = false;
          }
        });
        if (_detallado) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('❌ No se pudo guardar o procesar la fotografía.')),
          );
        }
      }
    } finally {
      if (mounted && streamEstabaActivo) {
        _actualizarStreamMovimiento();
      }
    }
  }

  Future<String?> _solicitarConfirmacion(
    ResultadoClasificacion resultado,
  ) async {
    _confirmacionFueManual = _confirmacionManual;
    if (!_confirmacionManual) {
      for (var restante = _timeoutConfirmacionSegundos;
          restante > 0;
          restante--) {
        if (!mounted) return null;
        setState(() {
          _espMensaje = 'Aceptación automática en $restante s...';
          _espMensajeEsError = false;
        });
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return mounted ? resultado.label : null;
    }

    final alternativas = _clasificador.labels
        .where((label) => label != 'Fondo')
        .toList(growable: false);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirmá el resultado',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'La IA detectó ${CategoriaResiduo.nombreVisible(resultado.label)} '
                'con ${resultado.confianza.toStringAsFixed(1)}% de confianza.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, resultado.label),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar resultado'),
              ),
              const SizedBox(height: 16),
              const Text(
                'O corregí la categoría:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in alternativas)
                    ActionChip(
                      label: Text(CategoriaResiduo.nombreVisible(label)),
                      onPressed: () => Navigator.pop(context, label),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar y no guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Envía el label reconocido a la ESP32 para que abra el servo
  /// correspondiente (ver EspService para el mapeo label -> endpoint y las
  /// reglas de qué residuos no disparan ningún servo). No bloquea el resto
  /// de la UI: se muestra un mensaje breve con el resultado del envío.
  Future<void> _notificarEsp32(
    String label, {
    bool contarDisparoContinuo = false,
  }) async {
    final resultado = await EspService.instancia.enviarClasificacion(label);
    if (!mounted) return;

    // "noAplica" (etiqueta sin servo asignado) y "deshabilitado" son normales,
    // no errores: no hace falta alarmar al usuario con color de error.
    final esError = resultado.estado == EspEnvioEstado.error;
    setState(() {
      if (contarDisparoContinuo && resultado.estado == EspEnvioEstado.enviado) {
        _disparosContinuos++;
      }
      _espMensaje = resultado.mensaje;
      _espMensajeEsError = esError;
    });
  }

  Color get _colorEstado {
    if (_loadError != null) return AppColors.coral;
    if (_modoContinuo) {
      final confianza = double.tryParse(_confidence) ?? 0;
      if (confianza < _umbralModoContinuo) return AppColors.neonMagenta;
      return EspService.puedeAccionar(_label)
          ? AppColors.neonCian
          : AppColors.ambar;
    }
    if (_deteccionMovimientoActiva && _movimientoDetectado) {
      return AppColors.ambar;
    }
    if (_cuentaRegresivaSegundos > 0) return AppColors.ambar;
    if (_resultadoDudoso) return AppColors.ambar;
    return AppColors.limaVivo;
  }

  Future<void> _cambiarCamaraPrincipal() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await _detenerStreamMovimiento();
    try {
      await _camara.cambiarCamara();
      _reiniciarEstadoContinuo();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        _actualizarStreamMovimiento();
      }
    }
  }

  void _registrarReciente(String label, double confianza) {
    final texto =
        '${CategoriaResiduo.nombreVisible(label)} · ${confianza.toStringAsFixed(1)}%';
    if (_recientes.isNotEmpty &&
        _recientes.first.split(' · ').first == texto.split(' · ').first) {
      _recientes[0] = texto;
    } else {
      _recientes.insert(0, texto);
      if (_recientes.length > 4) _recientes.removeLast();
    }
  }

  Widget _panelControles() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded,
              color: AppColors.neonCian, size: 22),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('VisionIA',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800))),
          Tooltip(
              message: _modoInterfaz.titulo,
              child:
                  Icon(_desarrollador ? Icons.code : Icons.insights_outlined)),
        ]),
        const SizedBox(height: 12),
        if (_desarrollador) ...[
          _SelectorModoCaptura(
              modoContinuo: _modoContinuo,
              habilitado: !_isProcessing,
              onChanged: _cambiarModoContinuo),
          const SizedBox(height: 12),
          if (_modelos.isNotEmpty && _modeloSeleccionado != null)
            DropdownButtonFormField<String>(
                key: ValueKey(_modeloSeleccionado!.assetPath),
                initialValue: _modeloSeleccionado!.assetPath,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cambiar modelo'),
                items: _modelos
                    .map((m) => DropdownMenuItem(
                        value: m.assetPath,
                        child: Text(m.nombre, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _isProcessing
                    ? null
                    : (path) {
                        if (path != null) _config.setModeloSeleccionado(path);
                      }),
          const SizedBox(height: 12),
        ],
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _modoContinuo
                              ? 'INFERENCIA EN VIVO'
                              : 'CAPTURA DE IMAGEN',
                          style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.6,
                              color: Colors.white60)),
                      const SizedBox(height: 10),
                      Text(
                          _isProcessing
                              ? 'Analizando…'
                              : CategoriaResiduo.nombreVisible(_label),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: _colorEstado)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                          value: ((double.tryParse(_confidence) ?? 0) / 100)
                              .clamp(0, 1),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(8),
                          color: _colorEstado),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _dato(
                            Icons.verified_outlined, 'Confianza $_confidence%'),
                        _dato(Icons.timer_outlined,
                            'Inferencia $_latenciaInferenciaMs ms'),
                        if (_modoContinuo)
                          _dato(Icons.bolt_outlined,
                              'Umbral ${_umbralModoContinuo.toStringAsFixed(0)}%'),
                      ]),
                      if (_resultadoDudoso)
                        const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                                'Probá con mejor luz y centrá el objeto.')),
                      if (_cuentaRegresivaSegundos > 0)
                        Text('Capturando en $_cuentaRegresivaSegundos s…'),
                      if (_movimientoDetectado && !_modoContinuo)
                        const Text('Movimiento detectado'),
                    ]))),
        const SizedBox(height: 12),
        const EstadoEsp(),
        if (_espMensaje != null) _aviso(_espMensaje!, _espMensajeEsError),
        if (_loadError != null ||
            _camara.error != null ||
            _errorInferencia != null)
          _aviso(_loadError ?? _camara.error ?? _errorInferencia!, true),
        if (_desarrollador) ...[
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Diagnóstico de sesión',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                            'Motor: ${_clasificador.gpuActiva ? 'GPU' : 'CPU'} · ${_clasificador.listo ? 'Listo' : 'Cargando'}'),
                        Text(
                            'Tensor: ${_clasificador.inputSize} × ${_clasificador.inputSize}'),
                        Text(
                            'Preparación: ${_clasificador.perfil.letterbox ? 'Letterbox' : 'Center-crop'}'),
                        Text(
                            'Cámara: ${_camara.frontal ? 'Frontal' : 'Trasera'} · Stream: ${_streamActivo ? 'activo' : 'pausado'}'),
                        Text('Aperturas aceptadas: $_disparosContinuos'),
                        const Divider(height: 24),
                        const Text('Últimas inferencias · sesión',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        if (_recientes.isEmpty)
                          const Text('Todavía no hay resultados.'),
                        for (final result in _recientes)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(result)),
                      ]))),
        ],
      ]),
    );
  }

  Widget _dato(IconData icon, String texto) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.limaBrillante),
        const SizedBox(width: 6),
        Flexible(child: Text(texto, style: const TextStyle(fontSize: 12))),
      ]));

  Widget _aviso(String texto, bool error) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(texto,
          style: TextStyle(
              color: error ? AppColors.ambar : AppColors.limaBrillante)));

  Widget _resultadoFacil() => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_modoContinuo ? 'VisionIA · En vivo' : 'VisionIA · Cámara',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
            _isProcessing
                ? 'Un momento, estoy analizando…'
                : (double.tryParse(_confidence) ?? 0) > 0
                    ? CategoriaResiduo.nombreVisible(_label)
                    : 'Centrá el objeto en el recuadro',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
      ]));

  Widget _areaCaptura() {
    final perfil = _clasificador.perfil;
    return Column(children: [
      Expanded(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(builder: (context, box) {
                final ratio =
                    perfil.redimensionar ? perfil.ancho / perfil.alto : 1.0;
                final width = (box.maxHeight * ratio).clamp(0.0, box.maxWidth);
                final height = width / ratio;
                return Center(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                            width: width,
                            height: height,
                            child: Stack(fit: StackFit.expand, children: [
                              FondoCamara(
                                  controller: _camara.controller,
                                  ajuste: perfil.letterbox
                                      ? BoxFit.contain
                                      : BoxFit.cover),
                              IgnorePointer(
                                  child: DecoratedBox(
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(28),
                                          border: Border.all(
                                              color: _modoContinuo
                                                  ? AppColors.neonCian
                                                      .withValues(alpha: 0.65)
                                                  : Colors.white
                                                      .withValues(alpha: 0.3),
                                              width: 2)))),
                              if (!_limpio)
                                Positioned(
                                    top: 8,
                                    right: 8,
                                    child: IconButton.filledTonal(
                                        tooltip: _camara.frontal
                                            ? 'Cambiar a cámara trasera'
                                            : 'Cambiar a cámara frontal',
                                        onPressed: !_isProcessing &&
                                                _camara.puedeCambiar
                                            ? _cambiarCamaraPrincipal
                                            : null,
                                        icon: const Icon(Icons.cameraswitch))),
                              if (_modoContinuo && _detallado)
                                const Positioned(
                                    left: 16,
                                    top: 18,
                                    child: Text('● EN VIVO',
                                        style: TextStyle(
                                            color: AppColors.neonCian,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700))),
                            ]))));
              }))),
      if (!_modoContinuo)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BotonDisparo(
                diametro: _limpio ? 96 : 80,
                activo: !_isProcessing && _camara.lista && _clasificador.listo,
                procesando: _isProcessing,
                onPressed: _takePictureAndProcess)),
      if (_modoContinuo && _desarrollador)
        Padding(
            padding: const EdgeInsets.all(8),
            child: _AyudaCompactaEnVivo(onAyuda: _mostrarGuiaModoContinuo)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: LayoutBuilder(builder: (context, box) {
      if (_limpio) return _areaCaptura();
      if (!_detallado) {
        return Column(children: [
          ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * 0.28),
              child: SingleChildScrollView(child: _resultadoFacil())),
          Expanded(child: _areaCaptura()),
        ]);
      }
      if (box.maxWidth > box.maxHeight && box.maxWidth >= 600) {
        return Row(children: [
          Expanded(child: _areaCaptura()),
          SizedBox(
              width: (box.maxWidth * 0.4).clamp(240.0, 400.0),
              child: _panelControles()),
        ]);
      }
      return Column(children: [
        SizedBox(height: box.maxHeight * 0.40, child: _panelControles()),
        Expanded(child: _areaCaptura()),
      ]);
    }));
  }
}

class _SelectorModoCaptura extends StatelessWidget {
  const _SelectorModoCaptura({
    required this.modoContinuo,
    required this.habilitado,
    required this.onChanged,
  });

  final bool modoContinuo;
  final bool habilitado;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Selector de modo de clasificación',
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: modoContinuo ? AppColors.neonCian : Colors.white24,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _BotonModo(
                icono: Icons.photo_camera_outlined,
                texto: 'FOTO',
                seleccionado: !modoContinuo,
                habilitado: habilitado,
                onTap: () => onChanged(false),
              ),
            ),
            Expanded(
              child: _BotonModo(
                icono: Icons.videocam_outlined,
                texto: 'EN VIVO',
                seleccionado: modoContinuo,
                habilitado: habilitado,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonModo extends StatelessWidget {
  const _BotonModo({
    required this.icono,
    required this.texto,
    required this.seleccionado,
    required this.habilitado,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final bool seleccionado;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = seleccionado
        ? (texto == 'EN VIVO' ? AppColors.neonCian : AppColors.limaBrillante)
        : Colors.white54;
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: seleccionado ? color.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: color, size: 19),
            const SizedBox(width: 7),
            Flexible(
                child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _AyudaCompactaEnVivo extends StatelessWidget {
  const _AyudaCompactaEnVivo({required this.onAyuda});

  final VoidCallback onAyuda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.neonMagenta),
      ),
      child: Row(
        children: [
          const Icon(Icons.center_focus_strong,
              color: AppColors.neonCian, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'APUNTÁ  →  MANTENÉ  →  LISTO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ver instrucciones',
            onPressed: onAyuda,
            icon: const Icon(Icons.help_outline, color: AppColors.neonCian),
          ),
        ],
      ),
    );
  }
}

class _PasoModoContinuo extends StatelessWidget {
  const _PasoModoContinuo({
    required this.numero,
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  final String numero;
  final IconData icono;
  final String titulo;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.neonCian.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.neonCian),
                ),
                child: Icon(icono, color: AppColors.neonCian),
              ),
              Positioned(
                top: -6,
                left: -6,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.neonMagenta,
                  child: Text(
                    numero,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 2),
                Text(descripcion,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonDisparo extends StatelessWidget {
  final double diametro;
  final bool activo;
  final bool procesando;
  final VoidCallback onPressed;
  const _BotonDisparo(
      {this.diametro = 80,
      required this.activo,
      required this.procesando,
      required this.onPressed});

  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      enabled: activo,
      label: 'Tomar fotografía',
      child: Tooltip(
          message: 'Tomar fotografía',
          child: SizedBox.square(
              dimension: diametro,
              child: FilledButton(
                onPressed: activo ? onPressed : null,
                style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.bosqueProfundo,
                    disabledBackgroundColor: const Color(0xFF405161),
                    disabledForegroundColor: Colors.white60,
                    shape: const CircleBorder(
                        side: BorderSide(color: Colors.white60, width: 3))),
                child: procesando
                    ? const SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 3))
                    : const Icon(Icons.camera_alt_rounded, size: 30),
              ))));
}
