import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/domain/categoria_residuo.dart';
import '../../../core/widgets/fondo_camara.dart';
import '../../classification/data/camara_service.dart';
import '../../classification/domain/clasificacion.dart';
import '../data/database_service.dart';
import '../data/historial_export_service.dart';
import '../data/historial_xlsx.dart';

class PantallaEstadisticas extends StatefulWidget {
  const PantallaEstadisticas({super.key});

  @override
  State<PantallaEstadisticas> createState() => _PantallaEstadisticasState();
}

class _PantallaEstadisticasState extends State<PantallaEstadisticas> {
  final _camara = CamaraService.instancia;

  bool _cargando = true;
  int _total = 0;
  List<ConteoPorLabel> _porLabel = [];
  List<ConteoPorDia> _porDia = [];
  List<Clasificacion> _historial = [];
  int _ultimaSolicitud = 0;
  String? _error;
  String? _filtroLabel;
  int _totalFiltrado = 0;
  int _cantidadVisible = 25;
  bool _exportando = false;

  static const int _incrementoHistorial = 25;

  @override
  void initState() {
    super.initState();
    DatabaseService.instancia.addListener(_onHistorialActualizado);
    _cargarDatos();
  }

  void _onHistorialActualizado() {
    _cargarDatos();
  }

  @override
  void dispose() {
    DatabaseService.instancia.removeListener(_onHistorialActualizado);
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final solicitud = ++_ultimaSolicitud;
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final db = DatabaseService.instancia;
      final resultados = await Future.wait<dynamic>([
        db.contarTotal(),
        db.contarTotal(label: _filtroLabel),
        db.contarPorLabel(),
        db.contarPorDia(diasAtras: 14),
        db.obtenerHistorial(
          limite: _cantidadVisible,
          label: _filtroLabel,
        ),
      ]);

      if (!mounted || solicitud != _ultimaSolicitud) return;
      setState(() {
        _total = resultados[0] as int;
        _totalFiltrado = resultados[1] as int;
        _porLabel = resultados[2] as List<ConteoPorLabel>;
        _porDia = resultados[3] as List<ConteoPorDia>;
        _historial = resultados[4] as List<Clasificacion>;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('No se pudieron cargar las estadísticas: $e');
      if (!mounted || solicitud != _ultimaSolicitud) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los datos guardados.';
      });
    }
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
        intensidadBlur: 22,
        oscurecido: 0.6,
        child: SafeArea(
          child: _cargando && _historial.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.limaVivo))
              : _error != null
                  ? _estadoError()
                  : (_total == 0 ? _estadoVacio() : _contenido()),
        ),
      ),
    );
  }

  Widget _estadoError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_outlined, size: 56, color: Colors.white54),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargarDatos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estadoVacio() {
    return RefreshIndicator(
      onRefresh: _cargarDatos,
      color: AppColors.limaVivo,
      child: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.insights_outlined, size: 64, color: Colors.white38),
          const SizedBox(height: 12),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Todavía no hay clasificaciones registradas.\n'
                'Andá a la pestaña de Clasificación para empezar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    return RefreshIndicator(
      onRefresh: _cargarDatos,
      color: AppColors.limaVivo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        children: [
          _tarjetaTotal(),
          const SizedBox(height: 20),
          _seccion('Clasificaciones por tipo'),
          _graficoPorLabel(),
          const SizedBox(height: 20),
          _seccion('Clasificaciones por día (últimas 2 semanas)'),
          _graficoPorDia(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _seccion('Historial')),
              IconButton(
                tooltip: 'Exportar historial',
                onPressed: _exportando ? null : _elegirExportacion,
                icon: const Icon(Icons.file_download_outlined),
              ),
            ],
          ),
          _filtrosHistorial(),
          if (_exportando)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Column(children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Preparando archivo… Podés seguir usando la app.')
                ])),
          const SizedBox(height: 8),
          if (_historial.isEmpty)
            _tarjetaBase(
              child: const Text(
                'No hay clasificaciones para este filtro.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ..._historial.map(_tarjetaHistorial),
          if (_historial.length < _totalFiltrado)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: _cargando ? null : _mostrarMas,
                icon: _cargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(
                  'Mostrar más (${_historial.length} de $_totalFiltrado)',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filtrosHistorial() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Todos'),
              selected: _filtroLabel == null,
              onSelected: (_) => _seleccionarFiltro(null),
            ),
          ),
          for (final conteo in _porLabel)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  '${CategoriaResiduo.nombreVisible(conteo.label)} (${conteo.cantidad})',
                ),
                selected: _filtroLabel == conteo.label,
                onSelected: (_) => _seleccionarFiltro(conteo.label),
              ),
            ),
        ],
      ),
    );
  }

  void _seleccionarFiltro(String? label) {
    if (_filtroLabel == label) return;
    setState(() {
      _filtroLabel = label;
      _cantidadVisible = _incrementoHistorial;
    });
    _cargarDatos();
  }

  void _mostrarMas() {
    setState(() => _cantidadVisible += _incrementoHistorial);
    _cargarDatos();
  }

  Future<void> _elegirExportacion() async {
    final formato = await showModalBottomSheet<FormatoHistorial>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Exportar historial',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                              'Todos los registros del filtro: ${_filtroLabel ?? 'Todas las categorías'}. No solo los visibles.'),
                          const SizedBox(height: 12),
                          for (final formato in FormatoHistorial.values)
                            ListTile(
                                leading: Icon(switch (formato) {
                                  FormatoHistorial.texto => Icons.notes_rounded,
                                  FormatoHistorial.excel =>
                                    Icons.table_chart_outlined,
                                  FormatoHistorial.excelImagenes =>
                                    Icons.image_search_rounded,
                                  FormatoHistorial.imagenes =>
                                    Icons.photo_library_outlined,
                                }),
                                title: Text(formato.titulo),
                                subtitle: Text(formato.descripcion),
                                onTap: () => Navigator.pop(context, formato)),
                          const SizedBox(height: 12),
                          const Text(
                              'Las fotografías se incluyen solo si siguen disponibles. '
                              'En vivo no guarda imágenes. Revisá el contenido antes de compartirlo.'),
                        ])))));
    if (formato != null && mounted) await _exportar(formato);
  }

  Future<void> _exportar(FormatoHistorial formato) async {
    if (_exportando) return;
    final filtro = _filtroLabel;
    setState(() => _exportando = true);
    try {
      final historial =
          await DatabaseService.instancia.obtenerHistorial(label: filtro);
      final temporal = await getTemporaryDirectory();
      final exportacion = await HistorialExportService.exportar(
          historial, formato, p.join(temporal.path, 'eco_touchless_exports'));
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
          files: [XFile(exportacion.ruta, mimeType: formato.mime)],
          title: 'Historial ECO-TOUCHLESS',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Archivo preparado: ${exportacion.registros} registros'
            '${exportacion.sinImagen > 0 ? ' · ${exportacion.sinImagen} sin imagen disponible' : ''}.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo exportar el historial: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is FormatException
                ? e.message
                : 'No se pudo exportar. Revisá el espacio disponible e intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _tarjetaBase({required Widget child, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _tarjetaTotal() {
    return _tarjetaBase(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.recycling, size: 40, color: AppColors.limaVivo),
          const SizedBox(width: 16),
          Flexible(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_total',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Text('basuras clasificadas en total',
                  style: TextStyle(color: Colors.white70)),
            ],
          )),
        ],
      ),
    );
  }

  Widget _graficoPorLabel() {
    final maxCantidad =
        _porLabel.map((e) => e.cantidad).reduce((a, b) => a > b ? a : b);

    return _tarjetaBase(
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (maxCantidad * 1.2).ceilToDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= _porLabel.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        CategoriaResiduo.nombreVisible(_porLabel[idx].label),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (int i = 0; i < _porLabel.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: _porLabel[i].cantidad.toDouble(),
                      color: AppColors.colorParaResiduo(_porLabel[i].label),
                      width: 22,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _graficoPorDia() {
    if (_porDia.isEmpty || _porDia.every((dia) => dia.cantidad == 0)) {
      return _tarjetaBase(
        padding: const EdgeInsets.all(20),
        child: const Text('No hay datos en las últimas 2 semanas.',
            style: TextStyle(color: Colors.white70)),
      );
    }

    final maxCantidad =
        _porDia.map((e) => e.cantidad).reduce((a, b) => a > b ? a : b);

    return _tarjetaBase(
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: (maxCantidad * 1.3).ceilToDouble(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) =>
                  FlLine(color: Colors.white10, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= _porDia.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        DateFormat('d/M').format(_porDia[idx].dia),
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white70),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < _porDia.length; i++)
                    FlSpot(i.toDouble(), _porDia[i].cantidad.toDouble()),
                ],
                isCurved: true,
                color: AppColors.limaVivo,
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.limaVivo.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaHistorial(Clasificacion c) {
    final archivoExiste =
        c.rutaImagen.isNotEmpty && File(c.rutaImagen).existsSync();
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm:ss');
    final color = AppColors.colorParaResiduo(c.label);

    return Dismissible(
      key: ValueKey(c.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmarEliminar(c),
      onDismissed: (_) => _eliminar(c),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.coral,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: ListTile(
          onTap: () => _mostrarDetalle(c),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Hero(
            tag: 'clasificacion-${c.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: archivoExiste
                  ? Image.file(File(c.rutaImagen),
                      width: 52, height: 52, fit: BoxFit.cover)
                  : Container(
                      width: 52,
                      height: 52,
                      color: Colors.white12,
                      child: Icon(
                        c.esEnVivo
                            ? Icons.videocam_outlined
                            : Icons.image_not_supported,
                        color: c.esEnVivo ? AppColors.neonCian : Colors.white38,
                      ),
                    ),
            ),
          ),
          title: Text(CategoriaResiduo.nombreVisible(c.label),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: Text(
              '${c.corregida ? 'Corregida desde ${CategoriaResiduo.nombreVisible(c.labelOriginal)} · ' : ''}${formatoFecha.format(c.fecha)}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          trailing: Text(
            '${c.confianza.toStringAsFixed(1)}%',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmarEliminar(Clasificacion clasificacion) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Eliminar clasificación?'),
            content: Text(
              clasificacion.esEnVivo
                  ? 'Se eliminará este evento En vivo de ${CategoriaResiduo.nombreVisible(clasificacion.label)}.'
                  : 'Se eliminará el registro de ${CategoriaResiduo.nombreVisible(clasificacion.label)} y su fotografía.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _eliminar(Clasificacion clasificacion) async {
    final id = clasificacion.id;
    if (id == null) return;
    try {
      await DatabaseService.instancia.eliminar(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clasificación eliminada.')),
      );
    } catch (e) {
      debugPrint('No se pudo eliminar la clasificación: $e');
      if (!mounted) return;
      _cargarDatos();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar el registro.')),
      );
    }
  }

  Future<void> _mostrarDetalle(Clasificacion clasificacion) async {
    final archivo = File(clasificacion.rutaImagen);
    final existe =
        clasificacion.rutaImagen.isNotEmpty && await archivo.exists();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(CategoriaResiduo.nombreVisible(clasificacion.label)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: existe
                    ? Image.file(archivo, fit: BoxFit.cover)
                    : AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ColoredBox(
                          color: Colors.white12,
                          child: Icon(
                            clasificacion.esEnVivo
                                ? Icons.videocam_outlined
                                : Icons.image_not_supported,
                            size: 48,
                            color: clasificacion.esEnVivo
                                ? AppColors.neonCian
                                : Colors.white38,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                'Confianza: ${clasificacion.confianza.toStringAsFixed(1)}%',
              ),
              if (clasificacion.corregida) ...[
                const SizedBox(height: 4),
                Text(
                  'Corrección manual: ${CategoriaResiduo.nombreVisible(clasificacion.labelOriginal)} → ${CategoriaResiduo.nombreVisible(clasificacion.label)}',
                ),
              ],
              const SizedBox(height: 4),
              Text(
                clasificacion.esEnVivo
                    ? 'Detección En vivo · fotograma procesado solo en RAM'
                    : HistorialXlsx.aceptacion(clasificacion),
              ),
              const SizedBox(height: 4),
              Text(
                'Fecha: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(clasificacion.fecha)}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _seccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
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
