import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/visor_escaner.dart';

/// Logo oficial recortado (sticker con borde blanco, fondo transparente).
const kLogoEcoTouchless = 'assets/branding/logo_eco_touchless.png';

/// Tutorial de introducción: portada con el logo, cómo se clasifica, el modo
/// manos libres, consejos para mejores fotos y privacidad.
///
/// También se puede abrir desde Ajustes como repaso ([repaso]).
class PantallaBienvenida extends StatefulWidget {
  const PantallaBienvenida({
    required this.onComenzar,
    this.repaso = false,
    this.manosLibresInicial = true,
    super.key,
  });

  /// Recibe si el usuario dejó activado el modo manos libres.
  final Future<void> Function(bool manosLibres) onComenzar;
  final bool repaso;
  final bool manosLibresInicial;

  @override
  State<PantallaBienvenida> createState() => _PantallaBienvenidaState();
}

class _PantallaBienvenidaState extends State<PantallaBienvenida>
    with SingleTickerProviderStateMixin {
  static const _totalPaginas = 5;

  final _controlador = PageController();
  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  late bool _manosLibres = widget.manosLibresInicial;
  int _pagina = 0;
  bool _guardando = false;

  bool get _ultima => _pagina == _totalPaginas - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respeta "reducir movimiento" del sistema: escena fija, sin bucles.
    if (MediaQuery.disableAnimationsOf(context)) {
      _animacion
        ..stop()
        ..value = 0.75;
    } else if (!_animacion.isAnimating) {
      _animacion.repeat();
    }
  }

  @override
  void dispose() {
    _animacion.dispose();
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _irA(int pagina) => _controlador.animateToPage(
        pagina,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );

  Future<void> _continuar() async {
    if (!_ultima) return _irA(_pagina + 1);
    setState(() => _guardando = true);
    try {
      await widget.onComenzar(_manosLibres);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      _PaginaPortada(animacion: _animacion, repaso: widget.repaso),
      _PaginaComoFunciona(animacion: _animacion),
      _PaginaManosLibres(
        animacion: _animacion,
        activado: _manosLibres,
        onCambio: (valor) => setState(() => _manosLibres = valor),
      ),
      const _PaginaConsejos(),
      const _PaginaPrivacidad(),
    ];
    assert(paginas.length == _totalPaginas);

    return Scaffold(
      backgroundColor: AppColors.bosqueProfundo,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.25,
            colors: [Color(0xFF173246), AppColors.bosqueProfundo],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        opacity: _pagina > 0 ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          tooltip: 'Anterior',
                          onPressed:
                              _pagina > 0 ? () => _irA(_pagina - 1) : null,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const Spacer(),
                      if (!_ultima)
                        TextButton(
                          onPressed: () => _irA(_totalPaginas - 1),
                          child: const Text('Saltar'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controlador,
                    onPageChanged: (pagina) => setState(() => _pagina = pagina),
                    children: paginas,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Paso ${_pagina + 1} de $_totalPaginas',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _totalPaginas,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: index == _pagina ? 26 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: index == _pagina
                              ? AppColors.limaVivo
                              : index < _pagina
                                  ? AppColors.limaVivo.withValues(alpha: 0.45)
                                  : Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _guardando ? null : _continuar,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.limaVivo,
                          foregroundColor: AppColors.bosqueProfundo,
                          minimumSize: const Size(48, 54),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_ultima
                                ? (widget.repaso ? 'Listo' : 'Comenzar')
                                : 'Continuar'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estructura común de cada página
// ---------------------------------------------------------------------------

/// Ilustración + textos. En pantallas apaisadas (tablet horizontal) se
/// ubican lado a lado; en vertical, apilados y desplazables.
class _PaginaTutorial extends StatelessWidget {
  const _PaginaTutorial({
    required this.titulo,
    required this.ilustracion,
    this.descripcion,
    this.contenido = const [],
    this.etiqueta,
  });

  final String titulo;
  final String? descripcion;
  final String? etiqueta;
  final Widget Function(double tamano) ilustracion;
  final List<Widget> contenido;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      namesRoute: true,
      label: titulo,
      child: LayoutBuilder(builder: (context, box) {
        final apaisada =
            box.maxWidth >= 600 && box.maxWidth > box.maxHeight * 1.15;
        final textos = Column(
          crossAxisAlignment:
              apaisada ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (etiqueta != null) ...[
              Text(
                etiqueta!.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.limaVivo,
                  fontSize: 12,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              titulo,
              textAlign: apaisada ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
            ),
            if (descripcion != null) ...[
              const SizedBox(height: 10),
              Text(
                descripcion!,
                textAlign: apaisada ? TextAlign.start : TextAlign.center,
                style: const TextStyle(
                  height: 1.45,
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
            ],
            if (contenido.isNotEmpty) const SizedBox(height: 18),
            ...contenido,
          ],
        );

        if (apaisada) {
          final tamano = math.min(box.maxHeight * 0.82, box.maxWidth * 0.4);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                SizedBox(
                  width: box.maxWidth * 0.42,
                  child: Center(child: ilustracion(tamano)),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: textos,
                  ),
                ),
              ],
            ),
          );
        }

        final tamano = (box.maxHeight * 0.38).clamp(72.0, 260.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ilustracion(tamano),
                      const SizedBox(height: 24),
                      textos,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Páginas
// ---------------------------------------------------------------------------

class _PaginaPortada extends StatelessWidget {
  const _PaginaPortada({required this.animacion, required this.repaso});

  final Animation<double> animacion;
  final bool repaso;

  @override
  Widget build(BuildContext context) {
    return _PaginaTutorial(
      titulo: repaso ? 'Repasemos lo básico' : 'Bienvenido a ECO-TOUCHLESS',
      descripcion:
          'Clasificá residuos con inteligencia artificial, sin tocar la pantalla.',
      ilustracion: (tamano) => _LogoAnimado(
        animacion: animacion,
        // El logo es vertical: se le da un poco más de alto que al resto.
        alto: tamano * 1.15,
      ),
      contenido: const [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(icono: Icons.memory, texto: 'IA en el dispositivo'),
            _Chip(icono: Icons.do_not_touch_outlined, texto: 'Manos libres'),
            _Chip(icono: Icons.delete_outline, texto: 'Tapas automáticas'),
          ],
        ),
      ],
    );
  }
}

class _PaginaComoFunciona extends StatelessWidget {
  const _PaginaComoFunciona({required this.animacion});

  final Animation<double> animacion;

  @override
  Widget build(BuildContext context) {
    return _PaginaTutorial(
      etiqueta: 'Cómo funciona',
      titulo: 'Así de simple',
      ilustracion: (tamano) =>
          _EscenaClasificacion(animacion: animacion, tamano: tamano),
      contenido: const [
        _Paso(
          numero: 1,
          icono: Icons.back_hand_outlined,
          titulo: 'Acercá el residuo',
          texto: 'Mostralo frente a la cámara, dentro del recuadro.',
        ),
        _Paso(
          numero: 2,
          icono: Icons.center_focus_strong,
          titulo: 'Mantenelo quieto un instante',
          texto: 'La app saca la foto sola cuando deja de moverse.',
        ),
        _Paso(
          numero: 3,
          icono: Icons.auto_awesome,
          titulo: 'La IA lo clasifica',
          texto: 'Ves la categoría y, con el clasificador físico, se abre '
              'la tapa correcta.',
        ),
      ],
    );
  }
}

class _PaginaManosLibres extends StatelessWidget {
  const _PaginaManosLibres({
    required this.animacion,
    required this.activado,
    required this.onCambio,
  });

  final Animation<double> animacion;
  final bool activado;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    return _PaginaTutorial(
      etiqueta: 'Modo manos libres',
      titulo: 'Sin tocar la tablet',
      ilustracion: (tamano) =>
          _EscenaManosLibres(animacion: animacion, tamano: tamano),
      contenido: [
        const _Vineta(
          icono: Icons.motion_photos_on_outlined,
          texto: 'Detecta cuando acercás algo a la cámara.',
        ),
        const _Vineta(
          icono: Icons.timer_outlined,
          texto: 'Saca la foto cuando el residuo queda quieto. Una mano que '
              'pasa sin dejar nada no dispara.',
        ),
        const _Vineta(
          icono: Icons.light_mode_outlined,
          texto: 'Si hay poca luz, la pantalla se ilumina en blanco para '
              'una foto más clara.',
        ),
        const _Vineta(
          icono: Icons.replay,
          texto: 'Retirá el residuo y queda lista para el siguiente.',
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.limaVivo.withValues(alpha: activado ? 0.14 : 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: activado ? AppColors.limaVivo : Colors.white24,
            ),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              'Activar modo manos libres',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Podés cambiarlo cuando quieras en Ajustes.'),
            value: activado,
            onChanged: onCambio,
          ),
        ),
      ],
    );
  }
}

class _PaginaConsejos extends StatelessWidget {
  const _PaginaConsejos();

  static const _consejos = [
    (Icons.looks_one_outlined, 'Un residuo por vez'),
    (Icons.center_focus_strong, 'Centrado en el recuadro'),
    (Icons.wb_sunny_outlined, 'Buena luz, sin contraluz'),
    (Icons.crop_free, 'Fondo despejado'),
    (Icons.straighten, 'A un palmo de la cámara'),
    (Icons.edit_outlined, 'Si se equivoca, corregilo'),
  ];

  @override
  Widget build(BuildContext context) {
    return _PaginaTutorial(
      etiqueta: 'Consejos',
      titulo: 'Para mejores resultados',
      descripcion: 'La IA acierta más cuando la foto es clara.',
      ilustracion: (tamano) => _IconoGrande(
        tamano: tamano * 0.8,
        icono: Icons.tips_and_updates_outlined,
      ),
      contenido: [
        LayoutBuilder(builder: (context, box) {
          final columnas = box.maxWidth >= 420 ? 2 : 1;
          final ancho = (box.maxWidth - (columnas - 1) * 10) / columnas;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (icono, texto) in _consejos)
                SizedBox(
                  width: ancho,
                  child: _Tarjeta(icono: icono, texto: texto),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _PaginaPrivacidad extends StatelessWidget {
  const _PaginaPrivacidad();

  @override
  Widget build(BuildContext context) {
    return _PaginaTutorial(
      etiqueta: 'Privacidad',
      titulo: 'Privado y bajo tu control',
      ilustracion: (tamano) => _IconoGrande(
        tamano: tamano * 0.8,
        icono: Icons.verified_user_outlined,
      ),
      contenido: const [
        _Vineta(
          icono: Icons.phonelink_lock,
          texto: 'Las imágenes y el modelo se procesan en este dispositivo. '
              'Nada se sube a internet.',
        ),
        _Vineta(
          icono: Icons.history,
          texto: 'El historial queda guardado localmente y podés borrarlo '
              'cuando quieras.',
        ),
        _Vineta(
          icono: Icons.camera_alt_outlined,
          texto: 'La cámara es necesaria para clasificar. La ubicación o '
              'dispositivos cercanos solo se piden si conectás el '
              'clasificador físico ESP32.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ilustraciones animadas
// ---------------------------------------------------------------------------

/// Logo flotando suavemente con un halo que respira.
class _LogoAnimado extends StatelessWidget {
  const _LogoAnimado({required this.animacion, required this.alto});

  final Animation<double> animacion;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Logo de ECO-TOUCHLESS',
      child: AnimatedBuilder(
        animation: animacion,
        builder: (context, child) {
          final onda = math.sin(animacion.value * 2 * math.pi);
          return SizedBox(
            height: alto,
            width: alto * 0.8,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: alto * (0.78 + onda * 0.03),
                  height: alto * (0.78 + onda * 0.03),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.limaVivo.withValues(alpha: 0.32),
                      AppColors.limaVivo.withValues(alpha: 0),
                    ]),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, onda * alto * 0.018),
                  child: child,
                ),
              ],
            ),
          );
        },
        child: Image.asset(
          kLogoEcoTouchless,
          height: alto * 0.92,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => Icon(
            Icons.recycling,
            size: alto * 0.5,
            color: AppColors.limaVivo,
          ),
        ),
      ),
    );
  }
}

/// Un residuo entra al visor, se queda quieto (anillo de progreso) y la IA
/// lo reconoce.
class _EscenaClasificacion extends StatelessWidget {
  const _EscenaClasificacion({required this.animacion, required this.tamano});

  final Animation<double> animacion;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: animacion,
        builder: (context, _) {
          final t = animacion.value;
          final entrada = Curves.easeOutBack.transform(_tramo(t, 0.0, 0.28));
          final quietud = _tramo(t, 0.32, 0.62);
          final resultado = Curves.easeOut.transform(_tramo(t, 0.64, 0.74));
          final salida = _tramo(t, 0.92, 1.0);
          final color = resultado > 0 ? AppColors.limaVivo : AppColors.ambar;
          return _Marco(
            tamano: tamano,
            fondo: AppColors.bosque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VisorEscaner(
                  tamano: tamano * 0.74,
                  color: color.withValues(alpha: 0.9),
                  largoEsquina: tamano * 0.12,
                ),
                if (quietud > 0 && resultado == 0)
                  SizedBox.square(
                    dimension: tamano * 0.5,
                    child: CircularProgressIndicator(
                      value: quietud,
                      strokeWidth: 4,
                      color: AppColors.limaVivo,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                Opacity(
                  opacity: 1 - salida,
                  child: Transform.translate(
                    offset: Offset(0, (1 - entrada) * tamano * 0.6),
                    child: Icon(
                      Icons.local_drink,
                      size: tamano * 0.3,
                      color: AppColors.porTipoResiduo['Plastico'],
                    ),
                  ),
                ),
                Positioned(
                  bottom: tamano * 0.08,
                  child: Opacity(
                    opacity: resultado * (1 - salida),
                    child: Transform.scale(
                      scale: 0.7 + resultado * 0.3,
                      child: const _Chip(
                        icono: Icons.check_circle,
                        texto: 'Plástico · 94%',
                        resaltado: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Una mano acerca algo en una escena oscura; la pantalla se ilumina en
/// blanco y se toma la foto.
class _EscenaManosLibres extends StatelessWidget {
  const _EscenaManosLibres({required this.animacion, required this.tamano});

  final Animation<double> animacion;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: animacion,
        builder: (context, _) {
          final t = animacion.value;
          final acercar = Curves.easeInOut.transform(_tramo(t, 0.0, 0.35));
          final luz = Curves.easeInOut.transform(_tramo(t, 0.42, 0.55));
          final apagar = _tramo(t, 0.9, 1.0);
          final iluminado = (luz * (1 - apagar)).clamp(0.0, 1.0);
          final foto = _tramo(t, 0.62, 0.7);
          final fondo =
              Color.lerp(const Color(0xFF070B12), Colors.white, iluminado)!;
          final tinta =
              Color.lerp(Colors.white70, AppColors.bosqueProfundo, iluminado)!;
          final vaiven = math.sin(t * 6 * math.pi) * (1 - luz) * tamano * 0.03;
          return _Marco(
            tamano: tamano,
            fondo: fondo,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: tamano * 0.08,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iluminado > 0.5
                            ? Icons.light_mode
                            : Icons.dark_mode_outlined,
                        size: tamano * 0.1,
                        color: iluminado > 0.5 ? AppColors.ambar : tinta,
                      ),
                      SizedBox(width: tamano * 0.03),
                      Text(
                        iluminado > 0.5 ? 'Iluminando' : 'Poca luz',
                        style: TextStyle(
                          color: tinta,
                          fontSize: tamano * 0.07,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(
                    vaiven,
                    (1 - acercar) * tamano * 0.35,
                  ),
                  child: Icon(
                    Icons.back_hand,
                    size: tamano * 0.34,
                    color: Color.lerp(
                      AppColors.limaVivo,
                      AppColors.bosqueClaro,
                      iluminado,
                    ),
                  ),
                ),
                Positioned(
                  bottom: tamano * 0.08,
                  child: Opacity(
                    opacity: (foto * (1 - apagar)).clamp(0.0, 1.0),
                    child: const _Chip(
                      icono: Icons.photo_camera,
                      texto: '¡Foto!',
                      resaltado: true,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

double _tramo(double t, double inicio, double fin) =>
    ((t - inicio) / (fin - inicio)).clamp(0.0, 1.0).toDouble();

/// Pantalla de tablet estilizada donde ocurren las escenas.
class _Marco extends StatelessWidget {
  const _Marco({
    required this.tamano,
    required this.fondo,
    required this.child,
  });

  final double tamano;
  final Color fondo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(tamano * 0.14),
        border: Border.all(color: Colors.white24, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.limaVivo.withValues(alpha: 0.18),
            blurRadius: tamano * 0.18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _IconoGrande extends StatelessWidget {
  const _IconoGrande({required this.tamano, required this.icono});

  final double tamano;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.limaVivo.withValues(alpha: 0.4)),
      ),
      child: Icon(icono, size: tamano * 0.48, color: AppColors.limaVivo),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas de texto
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icono,
    required this.texto,
    this.resaltado = false,
  });

  final IconData icono;
  final String texto;
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resaltado
            ? AppColors.bosqueProfundo.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: resaltado ? AppColors.limaVivo : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: AppColors.limaVivo),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  final int numero;
  final IconData icono;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.limaVivo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.limaVivo.withValues(alpha: 0.6),
                  ),
                ),
                child: Icon(icono, color: AppColors.limaVivo),
              ),
              Positioned(
                top: -6,
                left: -6,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.limaVivo,
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      color: AppColors.bosqueProfundo,
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
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(texto, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Vineta extends StatelessWidget {
  const _Vineta({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: AppColors.limaVivo, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: Colors.white,
                height: 1.4,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icono, color: AppColors.limaVivo),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
