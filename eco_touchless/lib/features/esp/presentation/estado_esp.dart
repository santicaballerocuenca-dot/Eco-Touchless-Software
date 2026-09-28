import 'package:flutter/material.dart';
import '../data/esp_conexion_monitor.dart';

class EstadoEsp extends StatelessWidget {
  const EstadoEsp({super.key});
  @override
  Widget build(BuildContext context) {
    final monitor = EspConexionMonitor.instancia;
    return ListenableBuilder(
        listenable: monitor,
        builder: (context, _) {
          if (!monitor.activo) return const SizedBox.shrink();
          final ok = monitor.conectado;
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Icon(ok == true ? Icons.wifi : Icons.wifi_off,
                          color: ok == true
                              ? Colors.greenAccent
                              : Colors.orangeAccent),
                      Text(ok == true
                          ? 'ESP32 conectada'
                          : ok == null
                              ? 'Verificando ESP32…'
                              : 'ESP32 sin respuesta'),
                      if (ok == false)
                        TextButton(
                            onPressed: monitor.reconectando
                                ? null
                                : monitor.reconectar,
                            child: Text(monitor.reconectando
                                ? 'Conectando…'
                                : 'Reconectar')),
                      if (monitor.errorRetencion != null)
                        Text(monitor.errorRetencion!),
                      if (monitor.avisoReinicio != null)
                        Text(monitor.avisoReinicio!,
                            style: const TextStyle(color: Colors.orangeAccent)),
                      if (ok == true && monitor.controlador != null)
                        Text(!monitor.controlador!.ready
                            ? 'Preparando servos…'
                            : monitor.controlador!.servo < 0
                                ? 'Controlador listo'
                                : monitor.controlador!.closing
                                    ? 'Servo ${monitor.controlador!.servo + 1}: cerrando (orden enviada)'
                                    : 'Servo ${monitor.controlador!.servo + 1}: cierre en ~${(monitor.controlador!.remainingMs / 1000).ceil()} s · tiempo aceptado ${monitor.controlador!.holdMs / 1000} s'),
                    ],
                  )));
        });
  }
}
