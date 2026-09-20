import 'package:flutter/material.dart';

/// El elemento de firma visual de ResiClas-IA: un marco con esquinas tipo
/// "escáner" (como un visor de cámara de laboratorio) en vez de un simple
/// rectángulo con borde continuo. Refuerza la idea de "la IA está leyendo
/// esta zona" y cambia de color según el estado de la clasificación.
class VisorEscaner extends StatelessWidget {
  final double tamano;
  final Color color;
  final double grosor;
  final double largoEsquina;

  const VisorEscaner({
    super.key,
    required this.tamano,
    required this.color,
    this.grosor = 3,
    this.largoEsquina = 34,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamano,
      height: tamano,
      child: CustomPaint(
        painter: _EsquinasPainter(
          color: color,
          grosor: grosor,
          largo: largoEsquina,
        ),
      ),
    );
  }
}

class _EsquinasPainter extends CustomPainter {
  final Color color;
  final double grosor;
  final double largo;

  _EsquinasPainter({
    required this.color,
    required this.grosor,
    required this.largo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const radio = 14.0;

    // Esquina superior izquierda
    canvas.drawPath(
      Path()
        ..moveTo(0, largo)
        ..lineTo(0, radio)
        ..arcToPoint(Offset(radio, 0), radius: const Radius.circular(radio))
        ..lineTo(largo, 0),
      paint,
    );

    // Esquina superior derecha
    canvas.drawPath(
      Path()
        ..moveTo(size.width - largo, 0)
        ..lineTo(size.width - radio, 0)
        ..arcToPoint(Offset(size.width, radio),
            radius: const Radius.circular(radio))
        ..lineTo(size.width, largo),
      paint,
    );

    // Esquina inferior derecha
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height - largo)
        ..lineTo(size.width, size.height - radio)
        ..arcToPoint(Offset(size.width - radio, size.height),
            radius: const Radius.circular(radio))
        ..lineTo(size.width - largo, size.height),
      paint,
    );

    // Esquina inferior izquierda
    canvas.drawPath(
      Path()
        ..moveTo(largo, size.height)
        ..lineTo(radio, size.height)
        ..arcToPoint(Offset(0, size.height - radio),
            radius: const Radius.circular(radio))
        ..lineTo(0, size.height - largo),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _EsquinasPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.grosor != grosor ||
        oldDelegate.largo != largo;
  }
}
