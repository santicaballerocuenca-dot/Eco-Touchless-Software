import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Pure UI: this widget has no network or actuator dependency.
class SimuladorServo extends StatefulWidget {
  const SimuladorServo(
      {super.key,
      required this.gpio,
      required this.cerrado,
      required this.abierto,
      required this.segundos});
  final int gpio;
  final int? cerrado, abierto;
  final double? segundos;
  @override
  State<SimuladorServo> createState() => _SimuladorServoState();
}

class _SimuladorServoState extends State<SimuladorServo> {
  bool _abierto = false;
  Timer? _cierre, _tick;
  final _reloj = Stopwatch();
  double _restante = 0;
  bool get _valido =>
      widget.cerrado != null &&
      widget.abierto != null &&
      widget.cerrado! >= 0 &&
      widget.cerrado! <= 180 &&
      widget.abierto! >= 0 &&
      widget.abierto! <= 180 &&
      widget.segundos != null &&
      widget.segundos!.isFinite &&
      widget.segundos! >= 0.5 &&
      widget.segundos! <= 60;

  void _parar() {
    _cierre?.cancel();
    _tick?.cancel();
    _reloj.stop();
    _restante = 0;
  }

  void _posicion(bool abierta) {
    _parar();
    setState(() => _abierto = abierta);
  }

  void _ciclo() {
    _parar();
    setState(() {
      _abierto = true;
      _restante = widget.segundos!;
    });
    _reloj
      ..reset()
      ..start();
    _cierre = Timer(Duration(milliseconds: (widget.segundos! * 1000).round()),
        () => _posicion(false));
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() => _restante =
          math.max(0, widget.segundos! - _reloj.elapsedMilliseconds / 1000));
    });
  }

  @override
  void didUpdateWidget(covariant SimuladorServo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cerrado != widget.cerrado ||
        oldWidget.abierto != widget.abierto ||
        oldWidget.segundos != widget.segundos) {
      _parar();
      _abierto = false;
    }
  }

  @override
  void dispose() {
    _parar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _abierto ? Colors.tealAccent.shade700 : Colors.blue;
    final angulo = (_abierto ? widget.abierto : widget.cerrado) ?? 0;
    return Column(children: [
      const SizedBox(height: 12),
      Text('Simulación MG996R · GPIO ${widget.gpio}',
          style: Theme.of(context).textTheme.titleSmall),
      const Text('Solo visual: NO mueve el servo ni guarda ajustes.'),
      TweenAnimationBuilder<double>(
        tween: Tween(end: angulo.clamp(0, 180).toDouble()),
        duration: const Duration(milliseconds: 400),
        builder: (context, angle, _) => CustomPaint(
            size: const Size(220, 105), painter: _ServoPainter(angle, color)),
      ),
      Text(
          '${_abierto ? 'Simulación abierta' : 'Simulación cerrada'} · $angulo°'),
      if (_restante > 0)
        Text('Cierre virtual en ${_restante.toStringAsFixed(1)} s'),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        OutlinedButton(
            onPressed: _valido ? () => _posicion(false) : null,
            child: const Text('Ver cerrado')),
        OutlinedButton(
            onPressed: _valido ? () => _posicion(true) : null,
            child: const Text('Ver abierto')),
        FilledButton.tonal(
            onPressed: _valido ? _ciclo : null,
            child: const Text('Probar ciclo virtual')),
      ]),
      const Text(
          '0° a la derecha · 90° arriba · 180° a la izquierda. '
          'La orientación real depende del montaje del brazo; calibrá sin carga.',
          textAlign: TextAlign.center),
    ]);
  }
}

class _ServoPainter extends CustomPainter {
  const _ServoPainter(this.angle, this.color);
  final double angle;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 82);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 70, height: 40),
            const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: 0.25));
    final rail = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 62), math.pi,
        math.pi, false, rail);
    final tip = center +
        Offset(math.cos(angle * math.pi / 180) * 62,
            -math.sin(angle * math.pi / 180) * 62);
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ServoPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.color != color;
}
