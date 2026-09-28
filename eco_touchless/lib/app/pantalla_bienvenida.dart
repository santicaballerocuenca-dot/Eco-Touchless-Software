import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class PantallaBienvenida extends StatefulWidget {
  const PantallaBienvenida({required this.onComenzar, super.key});

  final Future<void> Function() onComenzar;

  @override
  State<PantallaBienvenida> createState() => _PantallaBienvenidaState();
}

class _PantallaBienvenidaState extends State<PantallaBienvenida> {
  final _controlador = PageController();
  int _pagina = 0;
  bool _guardando = false;

  static const _paginas = [
    _ContenidoBienvenida(
      icono: Icons.recycling,
      titulo: 'Clasificá residuos con IA',
      descripcion:
          'Apuntá la cámara a un residuo y obtené su categoría y nivel de confianza en segundos.',
    ),
    _ContenidoBienvenida(
      icono: Icons.privacy_tip_outlined,
      titulo: 'Procesamiento privado',
      descripcion:
          'Las imágenes y el modelo se procesan en este dispositivo. El historial queda guardado localmente y podés borrarlo cuando quieras.',
    ),
    _ContenidoBienvenida(
      icono: Icons.camera_alt_outlined,
      titulo: 'Vos controlás los permisos',
      descripcion:
          'La cámara es necesaria para clasificar. La ubicación o dispositivos cercanos solo se solicitan si decidís conectar el clasificador físico ESP32.',
    ),
  ];

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    if (_pagina < _paginas.length - 1) {
      await _controlador.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.onComenzar();
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ECO-TOUCHLESS',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.limaBrillante,
                      ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controlador,
                  itemCount: _paginas.length,
                  onPageChanged: (pagina) => setState(() => _pagina = pagina),
                  itemBuilder: (context, index) => _paginas[index],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _paginas.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: index == _pagina ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _pagina
                          ? AppColors.limaVivo
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _guardando ? null : _continuar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_pagina == _paginas.length - 1
                          ? 'Comenzar'
                          : 'Continuar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContenidoBienvenida extends StatelessWidget {
  const _ContenidoBienvenida({
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      namesRoute: true,
      label: '$titulo. $descripcion',
      child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            decoration: const BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icono,
                                size: 58, color: AppColors.limaVivo),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            titulo,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            descripcion,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              height: 1.5,
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ))))),
    );
  }
}
