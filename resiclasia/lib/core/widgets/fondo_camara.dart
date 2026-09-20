import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fondo compartido por toda la app: la cámara en vivo, atenuada y con blur,
/// para que ninguna pantalla (ni siquiera Configuración o Estadísticas)
/// tenga que caer en un fondo negro/plano. Si no hay cámara disponible
/// todavía, cae a un degradé de marca en vez de negro puro.
///
/// [intensidadBlur] y [oscurecido] controlan cuánto "compite" la cámara de
/// fondo con el contenido de encima: la pantalla de Clasificación la quiere
/// nítida y sin blur (es el visor real), mientras que Configuración y
/// Estadísticas la quieren muy desenfocada y oscurecida (es solo ambiente).
class FondoCamara extends StatelessWidget {
  final CameraController? controller;
  final double intensidadBlur;
  final double oscurecido;
  final Widget? child;
  final BoxFit ajuste;

  const FondoCamara({
    super.key,
    required this.controller,
    this.intensidadBlur = 0,
    this.oscurecido = 0,
    this.child,
    this.ajuste = BoxFit.cover,
  });

  bool get _camaraLista =>
      controller != null && controller!.value.isInitialized;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _camaraLista ? _visorCamara(context) : _degradeDeMarca(),
        if (intensidadBlur > 0)
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: intensidadBlur,
              sigmaY: intensidadBlur,
            ),
            child: const SizedBox.expand(),
          ),
        if (oscurecido > 0)
          Container(color: Colors.black.withValues(alpha: oscurecido)),
        if (child != null) child!,
      ],
    );
  }

  Widget _visorCamara(BuildContext context) {
    final previewSize = controller!.value.previewSize;
    if (previewSize == null) return _degradeDeMarca();
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return ClipRect(
        child: OverflowBox(
      alignment: Alignment.center,
      child: FittedBox(
        fit: ajuste,
        child: SizedBox(
          // El preview de camera viene "acostado" (width/height del sensor
          // intercambiados respecto a la orientación portrait de la UI).
          width: portrait ? previewSize.height : previewSize.width,
          height: portrait ? previewSize.width : previewSize.height,
          child: CameraPreview(controller!),
        ),
      ),
    ));
  }

  Widget _degradeDeMarca() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bosque,
            AppColors.bosqueProfundo,
          ],
        ),
      ),
    );
  }
}
