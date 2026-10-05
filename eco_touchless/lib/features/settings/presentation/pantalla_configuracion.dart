import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fondo_camara.dart';
import '../../classification/data/camara_service.dart';
import '../../classification/data/modelo_catalogo_service.dart';
import '../../classification/domain/modelo_ia.dart';
import '../../esp/data/esp_service.dart';
import '../../esp/data/esp_wifi_connector.dart';
import '../../statistics/data/database_service.dart';
import '../data/config_service.dart';
import '../domain/modo_iluminacion.dart';
import '../domain/modo_interfaz.dart';
import '../../../app/pantalla_bienvenida.dart';
import 'ajustes_perfil_modelo.dart';
import '../../bench/presentation/pantalla_bench.dart';
import '../../esp/presentation/estado_esp.dart';
import '../../esp/presentation/configuracion_servos_panel.dart';

class PantallaConfiguracion extends StatefulWidget {
  const PantallaConfiguracion({super.key, this.visible = true});
  final bool visible;

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  final _config = ConfigService.instancia;
  final _camara = CamaraService.instancia;
  final _catalogoModelos = ModeloCatalogoService.instancia;

  bool _cargando = true;
  ModoInterfaz _modoInterfaz = ModoInterfaz.facil;
  bool _benchHabilitado = false;
  bool _mantenerEsp = false;
  int _ultimaCargaAjustes = 0;

  double _umbralConfianza = 60.0;
  bool _deteccionMovimiento = false;
  double _sensibilidadMovimiento = 0.5;
  bool _capturarTrasCeseMovimiento = false;
  int _retardoCapturaMs = 1200;
  bool _zonaCentral = true;
  ModoIluminacion _modoIluminacion = ModoIluminacion.automatica;
  bool _autoaceptarManosLibres = true;
  bool _confirmacionManual = true;
  int _timeoutConfirmacionSegundos = 5;
  bool _modoContinuo = false;
  double _umbralModoContinuo = 80.0;
  bool _guardarHistorialAuto = true;
  int _retencionImagenesDias = 30;
  bool _usarGPU = false;
  List<ModeloIa> _modelos = const [];
  ModeloIa? _modeloSeleccionado;
  String? _modelosError;

  // --- Vinculación ESP32 ---
  bool _espHabilitado = false;
  late final TextEditingController _espSsidCtrl;
  late final TextEditingController _espPasswordCtrl;
  late final TextEditingController _espIpCtrl;
  late final TextEditingController _espPuertoCtrl;
  late final TextEditingController _espApiKeyCtrl;
  bool _espConectando = false;
  bool _espProbando = false;
  String? _espMensajeEstado;
  bool _espMensajeEsError = false;
  EspDiagnostico? _ultimoDiagnostico;

  @override
  void initState() {
    super.initState();
    _espSsidCtrl = TextEditingController();
    _espPasswordCtrl = TextEditingController();
    _espIpCtrl = TextEditingController();
    _espPuertoCtrl = TextEditingController();
    _espApiKeyCtrl = TextEditingController();
    _config.addListener(_onConfiguracionExterna);
    _cargarAjustes();
  }

  void _onConfiguracionExterna() {
    _cargarAjustes();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfiguracionExterna);
    _espSsidCtrl.dispose();
    _espPasswordCtrl.dispose();
    _espIpCtrl.dispose();
    _espPuertoCtrl.dispose();
    _espApiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarAjustes() async {
    final solicitud = ++_ultimaCargaAjustes;
    final umbral = await _config.getUmbralConfianza();
    final movimiento = await _config.getDeteccionMovimiento();
    final sensibilidad = await _config.getSensibilidadMovimiento();
    final capturarTrasCese = await _config.getCapturarTrasCeseMovimiento();
    final retardoCaptura = await _config.getRetardoCapturaMs();
    final zonaCentral = await _config.getZonaCentralMovimiento();
    final modoIluminacion = await _config.getModoIluminacion();
    final autoaceptar = await _config.getAutoaceptarManosLibres();
    final confirmacionManual = await _config.getConfirmacionManual();
    final timeoutConfirmacion = await _config.getTimeoutConfirmacionSegundos();
    final modoContinuo = await _config.getModoContinuo();
    final modoInterfaz = await _config.getModoInterfaz();
    final umbralModoContinuo = await _config.getUmbralModoContinuo();
    final guardarAuto = await _config.getGuardarHistorialAuto();
    final retencionImagenes = await _config.getRetencionImagenesDias();
    final gpu = await _config.getUsarGPU();
    final bench = await _config.getBenchHabilitado();
    final mantenerEsp = await _config.getMantenerEsp();
    final modeloAsset = await _config.getModeloSeleccionado();
    List<ModeloIa> modelos = const [];
    String? modelosError;
    try {
      modelos = await _catalogoModelos.obtenerModelos();
    } catch (error) {
      modelosError = 'No se pudo leer el catálogo de modelos: $error';
    }
    final modeloSeleccionado =
        ModeloCatalogoService.resolver(modelos, modeloAsset);

    final espHabilitado = await _config.getEspHabilitado();
    final espSsid = await _config.getEspSsid();
    final espPassword = await _config.getEspPassword();
    final espIp = await _config.getEspIp();
    final espPuerto = await _config.getEspPuerto();
    final espApiKey = await _config.getEspApiKey();

    if (!mounted || solicitud != _ultimaCargaAjustes) return;
    setState(() {
      _umbralConfianza = umbral;
      _deteccionMovimiento = movimiento;
      _sensibilidadMovimiento = sensibilidad;
      _capturarTrasCeseMovimiento = capturarTrasCese;
      _retardoCapturaMs = retardoCaptura;
      _zonaCentral = zonaCentral;
      _modoIluminacion = modoIluminacion;
      _autoaceptarManosLibres = autoaceptar;
      _confirmacionManual = confirmacionManual;
      _timeoutConfirmacionSegundos = timeoutConfirmacion;
      _modoContinuo = modoContinuo;
      _modoInterfaz = modoInterfaz;
      _umbralModoContinuo = umbralModoContinuo;
      _guardarHistorialAuto = guardarAuto;
      _retencionImagenesDias = retencionImagenes;
      _usarGPU = gpu;
      _benchHabilitado = bench;
      _mantenerEsp = mantenerEsp;
      _modelos = modelos;
      _modeloSeleccionado = modeloSeleccionado;
      _modelosError = modelosError ??
          (modelos.isEmpty
              ? 'No se encontraron archivos .tflite en assets/modelos/.'
              : null);

      _espHabilitado = espHabilitado;
      _espSsidCtrl.text = espSsid;
      _espPasswordCtrl.text = espPassword;
      _espIpCtrl.text = espIp;
      _espPuertoCtrl.text = espPuerto.toString();
      _espApiKeyCtrl.text = espApiKey;

      _cargando = false;
    });
  }

  Future<void> _conectarAWifiEsp() async {
    final ssid = _espSsidCtrl.text.trim();
    final password = _espPasswordCtrl.text;
    if (ssid.isEmpty ||
        ssid.length > 32 ||
        password.length < 8 ||
        password.length > 63) {
      setState(() {
        _espMensajeEsError = true;
        _espMensajeEstado =
            'Ingresá un SSID válido y una contraseña WPA2 de 8 a 63 caracteres.';
      });
      return;
    }
    await _config.setEspSsid(ssid);
    await _config.setEspPassword(password);
    if (!mounted) return;
    setState(() {
      _espConectando = true;
      _espMensajeEstado = null;
    });

    final resultado = await EspWifiConnector.instancia.conectarAutomaticamente(
      ssid: _espSsidCtrl.text.trim(),
      password: _espPasswordCtrl.text,
    );

    if (!mounted) return;

    switch (resultado) {
      case EspWifiResultado.conectado:
        setState(() {
          _espConectando = false;
          _espMensajeEsError = false;
          _espMensajeEstado =
              'Solicitud enviada a "${_espSsidCtrl.text.trim()}". Aceptá el aviso de Android y esperá a que el estado indique ESP32 conectada.';
        });
        break;
      case EspWifiResultado.permisoDenegado:
      case EspWifiResultado.fallo:
        setState(() {
          _espConectando = false;
          _espMensajeEsError = true;
          _espMensajeEstado = 'No se pudo conectar automáticamente. '
              'Abrí el Wi-Fi del sistema y elegí la red a mano.';
        });
        // El camino automático no siempre funciona (depende de la versión
        // de Android y del fabricante), así que ofrecemos el camino manual
        // como respaldo confiable en el mismo momento del fallo.
        await EspWifiConnector.instancia.abrirAjustesWifi();
        break;
    }
  }

  Future<void> _probarConexionEsp() async {
    // Guardamos primero lo que haya en los campos para que la prueba use
    // los valores actuales, aunque el usuario no haya salido del campo.
    if (!await _guardarCamposEspSiValidos()) return;
    if (!mounted) return;
    setState(() {
      _espProbando = true;
      _espMensajeEstado = null;
      _ultimoDiagnostico = null;
    });
    final diagnostico = await EspService.instancia.diagnosticar();
    if (!mounted) return;
    setState(() {
      _espProbando = false;
      _espMensajeEsError = !diagnostico.correcto;
      _espMensajeEstado = diagnostico.mensaje;
      _ultimoDiagnostico = diagnostico;
    });
  }

  Future<void> _cambiarEspHabilitado(bool habilitado) async {
    setState(() => _espHabilitado = habilitado);
    await _config.setEspHabilitado(habilitado);
    if (!habilitado || !mounted) return;
    final yaVisto = await _config.getOnboardingEspCompletado();
    if (!mounted || yaVisto) return;
    await _mostrarGuiaEsp();
    await _config.setOnboardingEspCompletado(true);
  }

  Future<void> _mostrarGuiaEsp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar el clasificador físico'),
        content: const Text(
          '1. Encendé la ESP32 y esperá a que cree su red.\n\n'
          '2. Ingresá el SSID y la contraseña.\n\n'
          '3. Tocá “Conectar el celular a esta red”. Android puede pedir '
          'permiso de dispositivos cercanos o ubicación.\n\n'
          '4. Ejecutá el diagnóstico. Debe responder HTTP 200 antes de '
          'clasificar residuos.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<bool> _guardarCamposEspSiValidos() async {
    final ip = _espIpCtrl.text.trim();
    final puerto = int.tryParse(_espPuertoCtrl.text.trim());
    if (!EspService.esHostLocalValido(ip) ||
        puerto == null ||
        puerto < 1 ||
        puerto > 65535) {
      if (mounted) {
        setState(() {
          _espMensajeEsError = true;
          _espMensajeEstado =
              'Usá una IP privada válida y un puerto entre 1 y 65535.';
        });
      }
      return false;
    }
    await _config.setEspIp(ip);

    final ssid = _espSsidCtrl.text.trim();
    if (ssid.isEmpty || ssid.length > 32) {
      if (mounted) {
        setState(() {
          _espMensajeEsError = true;
          _espMensajeEstado = 'El SSID debe contener entre 1 y 32 caracteres.';
        });
      }
      return false;
    }
    await _config.setEspSsid(ssid);

    final password = _espPasswordCtrl.text;
    if (password.length < 8 || password.length > 63) {
      if (mounted) {
        setState(() {
          _espMensajeEsError = true;
          _espMensajeEstado =
              'La contraseña WPA2 debe contener entre 8 y 63 caracteres.';
        });
      }
      return false;
    }
    await _config.setEspPassword(password);
    await _config.setEspPuerto(puerto);
    return true;
  }

  Future<void> _confirmarBorrarHistorial() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar todo el historial?'),
        content: const Text(
          'Esto va a eliminar todas las clasificaciones, fotografías guardadas '
          'y estadísticas asociadas. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      await DatabaseService.instancia.borrarTodo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Historial borrado.')),
        );
      }
    }
  }

  Future<void> _cambiarModelo(String assetPath) async {
    ModeloIa? seleccionado;
    for (final modelo in _modelos) {
      if (modelo.assetPath == assetPath) {
        seleccionado = modelo;
        break;
      }
    }
    if (seleccionado == null ||
        seleccionado.assetPath == _modeloSeleccionado?.assetPath) {
      return;
    }
    setState(() => _modeloSeleccionado = seleccionado);
    await _config.setModeloSeleccionado(seleccionado.assetPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${seleccionado.nombre} seleccionado. Se usará en Foto y En vivo.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder para que, si la cámara todavía se está inicializando
    // cuando se entra a esta pantalla, el fondo pase de degradé de marca a
    // imagen real en cuanto esté lista (sin necesitar volver a entrar).
    return ListenableBuilder(
      listenable: _camara,
      builder: (context, _) => FondoCamara(
        controller: null,
        // Fondo de ambiente: muy desenfocado y oscurecido para que sirva de
        // atmósfera sin competir con las tarjetas de ajustes.
        intensidadBlur: 22,
        oscurecido: 0.55,
        child: SafeArea(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.limaVivo))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    110,
                  ),
                  children: [
                    _seccion('Tu espacio ECO-TOUCHLESS'),
                    _tarjeta(children: [
                      Text('¿Cuánta información querés ver?',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ModoInterfaz>(
                          key: ValueKey(_modoInterfaz),
                          initialValue: _modoInterfaz,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Modo de interfaz'),
                          items: ModoInterfaz.values
                              .map((modo) => DropdownMenuItem(
                                  value: modo, child: Text(modo.titulo)))
                              .toList(),
                          onChanged: (modo) {
                            if (modo != null) _config.setModoInterfaz(modo);
                          }),
                      const SizedBox(height: 8),
                      Text(_modoInterfaz.descripcion),
                      const Text(
                          'Limpio y Fácil ocultan diagnósticos en la pantalla principal. '
                          'La confirmación de resultados sigue tu ajuste habitual.'),
                    ]),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: const Text('Ver el tutorial de nuevo'),
                      subtitle: const Text(
                          'Repasá cómo clasificar sin tocar la tablet y los consejos para mejores fotos.'),
                      onTap: _abrirTutorial,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.compare),
                      title: const Text('Comparar modelos'),
                      subtitle: const Text(
                          'Elegí varios modelos y probalos con la misma foto. No acciona la ESP32.'),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  const PantallaBench(comparacion: true))),
                    ),
                    if (_modeloSeleccionado != null)
                      AjustesPerfilModelo(
                          key: ValueKey(_modeloSeleccionado!.assetPath),
                          modelo: _modeloSeleccionado!),
                    _seccion('Modelo de clasificación'),
                    _tarjeta(
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.model_training,
                              color: AppColors.limaBrillante,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Modelo activo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_modelosError != null)
                          Text(
                            _modelosError!,
                            style: const TextStyle(color: AppColors.coral),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _modeloSeleccionado?.assetPath,
                                isExpanded: true,
                                icon: const Icon(Icons.expand_more),
                                items: [
                                  for (final modelo in _modelos)
                                    DropdownMenuItem(
                                      value: modelo.assetPath,
                                      child: Text(
                                        modelo.nombre,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (assetPath) {
                                  if (assetPath != null) {
                                    _cambiarModelo(assetPath);
                                  }
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${_modelos.length} modelo${_modelos.length == 1 ? '' : 's'} disponible${_modelos.length == 1 ? '' : 's'}. '
                          'El nombre se toma del archivo .tflite.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Para agregar otro: copialo a assets/modelos/ y recompilá la app.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.neonCian,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Divider(height: 28, color: Colors.white12),
                        Text(
                          'Umbral mínimo de confianza: ${_umbralConfianza.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const Text(
                          'Si la IA está menos segura que esto, el resultado se '
                          'marca como dudoso en vez de aceptarse directamente.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        Slider(
                          value: _umbralConfianza,
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '${_umbralConfianza.toStringAsFixed(0)}%',
                          onChanged: (v) =>
                              setState(() => _umbralConfianza = v),
                          onChangeEnd: (v) => _config.setUmbralConfianza(v),
                        ),
                        _switch(
                          titulo: 'Pedir confirmación del resultado',
                          subtitulo:
                              'Permite confirmar o corregir la categoría antes de guardarla. '
                              'Si se desactiva, se acepta automáticamente tras la espera.',
                          valor: _confirmacionManual,
                          onChanged: (v) {
                            setState(() => _confirmacionManual = v);
                            _config.setConfirmacionManual(v);
                          },
                        ),
                        if (!_confirmacionManual)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.timer_outlined),
                            title: const Text(
                              'Espera para aceptar',
                              style: TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text(
                              'Durante este tiempo se muestra el resultado sin pedir confirmación.',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12),
                            ),
                            trailing: DropdownButton<int>(
                              value: _timeoutConfirmacionSegundos,
                              items: const [
                                DropdownMenuItem(value: 3, child: Text('3 s')),
                                DropdownMenuItem(value: 5, child: Text('5 s')),
                                DropdownMenuItem(
                                    value: 10, child: Text('10 s')),
                              ],
                              onChanged: (segundos) {
                                if (segundos == null) return;
                                setState(() =>
                                    _timeoutConfirmacionSegundos = segundos);
                                _config
                                    .setTimeoutConfirmacionSegundos(segundos);
                              },
                            ),
                          ),
                        _switch(
                          titulo: 'Usar aceleración GPU',
                          subtitulo:
                              'Más rápido en dispositivos compatibles. Si el delegate '
                              'no puede iniciarse, la app vuelve a CPU automáticamente.',
                          valor: _usarGPU,
                          onChanged: (v) {
                            setState(() => _usarGPU = v);
                            _config.setUsarGPU(v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _seccion('Modo En vivo'),
                    _tarjeta(
                      children: [
                        _switch(
                          titulo: 'Inferencia continua en RAM',
                          subtitulo:
                              'Analiza el video sin guardar frames y acciona la '
                              'ESP32 apenas la confianza supera el umbral.',
                          valor: _modoContinuo,
                          onChanged: (valor) async {
                            setState(() => _modoContinuo = valor);
                            await _config.setModoContinuo(valor);
                            if (valor) {
                              unawaited(
                                EspService.instancia.precalentarConexion(),
                              );
                            }
                          },
                        ),
                        if (_modoContinuo) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Disparo mecánico desde ${_umbralModoContinuo.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppColors.neonCian,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Slider(
                            value: _umbralModoContinuo,
                            min: 50,
                            max: 99,
                            divisions: 49,
                            label: '${_umbralModoContinuo.toStringAsFixed(0)}%',
                            activeColor: AppColors.neonCian,
                            onChanged: (valor) => setState(
                              () => _umbralModoContinuo = valor,
                            ),
                            onChangeEnd: _config.setUmbralModoContinuo,
                          ),
                          const Text(
                            'Consejo: empezá con 80%. Subilo si hay falsos disparos; '
                            'bajalo si cuesta reconocer residuos.',
                            style:
                                TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    _seccion('Detección de movimiento'),
                    _tarjeta(
                      children: [
                        if (_modoContinuo)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              '⏸ Esta función queda en pausa mientras usás En vivo.',
                              style: TextStyle(
                                color: AppColors.neonCian,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        _switch(
                          titulo: 'Activar modo manos libres',
                          subtitulo:
                              'Detecta cuando acercás un residuo y saca la foto sola '
                              'cuando queda quieto. Filtra cambios de luz, ruido y '
                              'manos que pasan sin dejar nada.',
                          valor: _deteccionMovimiento,
                          onChanged: (v) {
                            setState(() => _deteccionMovimiento = v);
                            _config.setDeteccionMovimiento(v);
                          },
                        ),
                        if (_deteccionMovimiento) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Sensibilidad: ${(_sensibilidadMovimiento * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const Text(
                            'Más alto = detecta movimientos más chicos.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                          Slider(
                            value: _sensibilidadMovimiento,
                            min: 0.05,
                            max: 1.0,
                            divisions: 19,
                            label:
                                '${(_sensibilidadMovimiento * 100).toStringAsFixed(0)}%',
                            onChanged: (v) =>
                                setState(() => _sensibilidadMovimiento = v),
                            onChangeEnd: (v) =>
                                _config.setSensibilidadMovimiento(v),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Quieto antes de la foto: ${(_retardoCapturaMs / 1000).toStringAsFixed(1)} s',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const Text(
                            'Más corto = más rápido; más largo = fotos más nítidas.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                          Slider(
                            value: _retardoCapturaMs.toDouble(),
                            min: 400,
                            max: 3000,
                            divisions: 13,
                            label:
                                '${(_retardoCapturaMs / 1000).toStringAsFixed(1)} s',
                            onChanged: (v) =>
                                setState(() => _retardoCapturaMs = v.round()),
                            onChangeEnd: (v) =>
                                _config.setRetardoCapturaMs(v.round()),
                          ),
                          _switch(
                            titulo: 'Priorizar el centro del visor',
                            subtitulo:
                                'Ignora casi por completo los bordes, donde suele pasar '
                                'gente caminando detrás del clasificador.',
                            valor: _zonaCentral,
                            onChanged: (v) {
                              setState(() => _zonaCentral = v);
                              _config.setZonaCentralMovimiento(v);
                            },
                          ),
                          _switch(
                            titulo: 'Capturar aunque no quede un objeto',
                            subtitulo:
                                'Dispara al terminar cualquier movimiento, aunque la '
                                'escena vuelva a quedar como antes (útil si el residuo '
                                'se arroja rápido).',
                            valor: _capturarTrasCeseMovimiento,
                            onChanged: (v) {
                              setState(() => _capturarTrasCeseMovimiento = v);
                              _config.setCapturarTrasCeseMovimiento(v);
                            },
                          ),
                          _switch(
                            titulo: 'Aceptar sin tocar',
                            subtitulo: _confirmacionManual
                                ? 'En capturas automáticas el resultado se acepta solo '
                                    'tras la cuenta regresiva; si es dudoso se descarta '
                                    'para reintentar.'
                                : 'La confirmación manual está desactivada: los '
                                    'resultados ya se aceptan solos.',
                            valor: _autoaceptarManosLibres,
                            onChanged: (v) {
                              setState(() => _autoaceptarManosLibres = v);
                              _config.setAutoaceptarManosLibres(v);
                            },
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Iluminación con la pantalla',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Con poca luz la pantalla se pone blanca y al máximo '
                            'brillo para iluminar el residuo (ideal con la cámara '
                            'frontal de la tablet).',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ModoIluminacion>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                    value: ModoIluminacion.apagada,
                                    icon: Icon(Icons.flash_off),
                                    label: Text('Apagada')),
                                ButtonSegment(
                                    value: ModoIluminacion.automatica,
                                    icon: Icon(Icons.flash_auto),
                                    label: Text('Auto')),
                                ButtonSegment(
                                    value: ModoIluminacion.siempre,
                                    icon: Icon(Icons.flash_on),
                                    label: Text('Siempre')),
                              ],
                              selected: {_modoIluminacion},
                              onSelectionChanged: (seleccion) {
                                final modo = seleccion.first;
                                setState(() => _modoIluminacion = modo);
                                _config.setModoIluminacion(modo);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    _seccion('Vinculación con ESP32'),
                    SwitchListTile(
                      title: const Text('Mantener conexión con ESP32'),
                      subtitle: const Text(
                          'En primer plano: comprueba cada 2 s y recupera el enlace con esperas de 5–60 s. Conectá y autorizá la red una vez. Nunca repite aperturas.'),
                      value: _mantenerEsp,
                      onChanged: (value) => _config.setMantenerEsp(value),
                    ),
                    const EstadoEsp(),
                    _tarjeta(
                      children: [
                        _switch(
                          titulo: 'Enviar resultado al clasificador físico',
                          subtitulo:
                              'Abre la tapa asignada a la etiqueta en la ESP32. '
                              'Al conectar aparecen los ajustes de los tres servos. Fondo nunca abre una tapa.',
                          valor: _espHabilitado,
                          onChanged: _cambiarEspHabilitado,
                        ),
                        if (_espHabilitado) ...[
                          const SizedBox(height: 12),
                          _campoTexto(
                              controlador: _espApiKeyCtrl,
                              etiqueta: 'Clave de control (API_KEY del .ino)',
                              ocultarTexto: true,
                              onSubmit: (value) => _config.setEspApiKey(value)),
                          TextButton(
                              onPressed: () =>
                                  _config.setEspApiKey(_espApiKeyCtrl.text),
                              child: const Text('Guardar clave de control')),
                          ConfiguracionServosPanel(visible: widget.visible),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _mostrarGuiaEsp,
                              icon: const Icon(Icons.help_outline),
                              label: const Text('Cómo conectar'),
                            ),
                          ),
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 12),
                          const Text(
                            'Red Wi-Fi de la ESP32',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          _campoTexto(
                            controlador: _espSsidCtrl,
                            etiqueta: 'SSID',
                            onSubmit: (_) => _guardarCamposEspSiValidos(),
                          ),
                          const SizedBox(height: 10),
                          _campoTexto(
                            controlador: _espPasswordCtrl,
                            etiqueta: 'Contraseña',
                            ocultarTexto: true,
                            onSubmit: (_) => _guardarCamposEspSiValidos(),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  _espConectando ? null : _conectarAWifiEsp,
                              icon: _espConectando
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi),
                              label: Text(_espConectando
                                  ? 'Conectando...'
                                  : 'Conectar el celular a esta red'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Si la conexión automática falla en tu dispositivo, se '
                            'abren los ajustes de Wi-Fi para elegir la '
                            'red a mano: buscá "${_espSsidCtrl.text.trim().isEmpty ? ConfigService.kEspSsidDefault : _espSsidCtrl.text.trim()}".',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white60),
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 12),
                          const Text(
                            'Servidor en la ESP32',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _campoTexto(
                                  controlador: _espIpCtrl,
                                  etiqueta: 'IP',
                                  onSubmit: (_) => _guardarCamposEspSiValidos(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: _campoTexto(
                                  controlador: _espPuertoCtrl,
                                  etiqueta: 'Puerto',
                                  soloNumeros: true,
                                  onSubmit: (_) => _guardarCamposEspSiValidos(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _espProbando ? null : _probarConexionEsp,
                              icon: _espProbando
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.network_check),
                              label: Text(_espProbando
                                  ? 'Probando...'
                                  : 'Ejecutar diagnóstico'),
                            ),
                          ),
                          if (_espMensajeEstado != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _espMensajeEstado!,
                              style: TextStyle(
                                fontSize: 12,
                                color: _espMensajeEsError
                                    ? AppColors.coral
                                    : AppColors.limaBrillante,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_ultimoDiagnostico != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DefaultTextStyle(
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Endpoint: ${_ultimoDiagnostico!.endpoint}'),
                                    Text(
                                      'Latencia: ${_ultimoDiagnostico!.duracion.inMilliseconds} ms',
                                    ),
                                    Text(
                                      'HTTP: ${_ultimoDiagnostico!.codigoHttp?.toString() ?? 'sin respuesta'}',
                                    ),
                                    if (_ultimoDiagnostico!.respuesta != null)
                                      Text(
                                        'Respuesta: ${_ultimoDiagnostico!.respuesta}',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    _seccion('Historial'),
                    _tarjeta(
                      padding: EdgeInsets.zero,
                      children: [
                        _switch(
                          titulo: 'Guardar automáticamente',
                          subtitulo:
                              'En Foto guarda imagen, fecha y hora. En vivo guarda '
                              'el evento sin conservar fotogramas.',
                          valor: _guardarHistorialAuto,
                          onChanged: (v) {
                            setState(() => _guardarHistorialAuto = v);
                            _config.setGuardarHistorialAuto(v);
                          },
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        ),
                        const Divider(
                            height: 1,
                            color: Colors.white12,
                            indent: 16,
                            endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.auto_delete_outlined),
                          title: const Text(
                            'Conservar fotografías',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Los registros y estadísticas se conservan.',
                            style:
                                TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          trailing: DropdownButton<int>(
                            value: _retencionImagenesDias,
                            items: const [
                              DropdownMenuItem(value: 7, child: Text('7 días')),
                              DropdownMenuItem(
                                  value: 30, child: Text('30 días')),
                              DropdownMenuItem(
                                  value: 90, child: Text('90 días')),
                              DropdownMenuItem(
                                  value: 0, child: Text('Siempre')),
                            ],
                            onChanged: (dias) {
                              if (dias != null) {
                                _cambiarRetencionImagenes(dias);
                              }
                            },
                          ),
                        ),
                        const Divider(
                            height: 1,
                            color: Colors.white12,
                            indent: 16,
                            endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.delete_forever,
                              color: AppColors.coral),
                          title: const Text('Borrar todo el historial',
                              style: TextStyle(color: Colors.white)),
                          onTap: _confirmarBorrarHistorial,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _seccion('DEBUG'),
                    SwitchListTile(
                      title: const Text('Activar BENCH'),
                      subtitle: const Text(
                          'Muestra la pestaña Bench. Solo se ejecuta al pulsar Ejecutar.'),
                      value: _benchHabilitado,
                      onChanged: (value) => _config.setBenchHabilitado(value),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _cambiarRetencionImagenes(int dias) async {
    setState(() => _retencionImagenesDias = dias);
    await _config.setRetencionImagenesDias(dias);
    final eliminadas =
        await DatabaseService.instancia.aplicarRetencionImagenes(dias);
    if (!mounted || eliminadas == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Se eliminaron $eliminadas fotografías vencidas; los registros se conservaron.',
        ),
      ),
    );
  }

  Future<void> _abrirTutorial() {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => PantallaBienvenida(
        repaso: true,
        manosLibresInicial: _deteccionMovimiento,
        onComenzar: (manosLibres) async {
          if (manosLibres != _deteccionMovimiento) {
            await _config.setDeteccionMovimiento(manosLibres);
          }
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    ));
  }

  Widget _tarjeta({required List<Widget> children, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _switch({
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return Padding(
      padding: padding,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(titulo,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitulo,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
        value: valor,
        onChanged: onChanged,
      ),
    );
  }

  Widget _campoTexto({
    required TextEditingController controlador,
    required String etiqueta,
    bool ocultarTexto = false,
    bool soloNumeros = false,
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: controlador,
      obscureText: ocultarTexto,
      keyboardType: soloNumeros ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      onSubmitted: onSubmit,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: etiqueta,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.limaVivo),
        ),
      ),
    );
  }

  Widget _seccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 4),
      child: Text(
        titulo.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.limaBrillante,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
