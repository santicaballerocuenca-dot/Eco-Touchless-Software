import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/classification/data/camara_service.dart';
import '../features/classification/presentation/pantalla_clasificacion.dart';
import '../features/settings/data/config_service.dart';
import '../features/settings/presentation/pantalla_configuracion.dart';
import '../features/statistics/presentation/pantalla_estadisticas.dart';
import '../features/statistics/data/database_service.dart';
import 'pantalla_bienvenida.dart';
import '../features/bench/presentation/pantalla_bench.dart';
import '../features/esp/data/esp_conexion_monitor.dart';

class ResiClasIAApp extends StatelessWidget {
  const ResiClasIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VisionIA',
      theme: AppTheme.claro(),
      darkTheme: AppTheme.oscuro(),
      themeMode: ThemeMode.dark,
      home: const _InicioApp(),
    );
  }
}

class _InicioApp extends StatefulWidget {
  const _InicioApp();

  @override
  State<_InicioApp> createState() => _InicioAppState();
}

class _InicioAppState extends State<_InicioApp> {
  bool? _bienvenidaCompletada;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarEstadoInicial();
  }

  Future<void> _cargarEstadoInicial() async {
    try {
      final completada =
          await ConfigService.instancia.getBienvenidaCompletada();
      final retencion =
          await ConfigService.instancia.getRetencionImagenesDias();
      await DatabaseService.instancia.aplicarRetencionImagenes(retencion);
      if (!mounted) return;
      setState(() {
        _bienvenidaCompletada = completada;
        _error = null;
      });
      if (completada) unawaited(CamaraService.instancia.inicializar());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la configuración local.');
    }
  }

  Future<void> _completarBienvenida() async {
    await ConfigService.instancia.setBienvenidaCompletada(true);
    if (!mounted) return;
    setState(() => _bienvenidaCompletada = true);
    unawaited(CamaraService.instancia.inicializar());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 52),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _cargarEstadoInicial,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_bienvenidaCompletada == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_bienvenidaCompletada!) {
      return PantallaBienvenida(onComenzar: _completarBienvenida);
    }
    return const PantallaPrincipal();
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indiceActual = 0;
  bool _bench = false;
  bool _benchEjecutando = false;
  @override
  void initState() {
    super.initState();
    ConfigService.instancia.addListener(_actualizarBench);
    EspConexionMonitor.instancia.iniciar();
    _actualizarBench();
  }

  Future<void> _actualizarBench() async {
    final enabled = await ConfigService.instancia.getBenchHabilitado();
    if (mounted) {
      setState(() {
        _bench = enabled;
        if (!enabled && _indiceActual == 3) _indiceActual = 1;
      });
    }
  }

  @override
  void dispose() {
    ConfigService.instancia.removeListener(_actualizarBench);
    super.dispose();
  }

  static const _titulos = [
    'VisionIA',
    'Configuración',
    'Estadísticas',
    'Bench'
  ];

  static const _destinos = [
    NavigationDestination(
      icon: Icon(Icons.camera_alt_outlined),
      selectedIcon: Icon(Icons.camera_alt),
      label: 'Clasificar',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: 'Ajustes',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Estadísticas',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _indiceActual == 0
          ? null
          : AppBar(title: Text(_titulos[_indiceActual])),
      body: IndexedStack(
        index: _indiceActual,
        children: [
          PantallaClasificacion(visible: _indiceActual == 0),
          PantallaConfiguracion(visible: _indiceActual == 1),
          const PantallaEstadisticas(),
          if (_bench)
            PantallaBench(onRunning: (value) {
              if (mounted) setState(() => _benchEjecutando = value);
            }),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indiceActual,
        onDestinationSelected:
            _benchEjecutando ? null : (i) => setState(() => _indiceActual = i),
        destinations: [
          ..._destinos,
          if (_bench)
            const NavigationDestination(
                icon: Icon(Icons.science_outlined),
                selectedIcon: Icon(Icons.science),
                label: 'Bench')
        ],
      ),
    );
  }
}
