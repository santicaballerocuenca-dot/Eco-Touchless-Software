# VisionIA 3.0

## Elegir lo que aparece en pantalla

Abrí **Ajustes → Tu espacio VisionIA → Modo de interfaz**.

| Modo | Pantalla principal |
| --- | --- |
| Limpio | Visor centrado y disparador grande. En vivo solo muestra el visor. |
| Fácil (predeterminado) | Resultado sencillo arriba, visor, cambio de cámara y disparador en Foto. Sin diagnósticos técnicos. |
| Detallado | Resultado, confianza, tiempo de inferencia, conexión y errores. Tarjetas desplazables para no tapar el visor. |
| Desarrollador | Añade selector Foto/En vivo, cambio rápido de modelo, diagnóstico y últimas inferencias de la sesión. |

La navegación inferior sigue visible para poder salir del modo Limpio. **Foto/En vivo también se cambia desde Ajustes**. Los modos visuales no desactivan la confirmación manual, el guardado ni la automatización configurada. Limpio/Fácil ocultan errores de la pantalla principal: usá Detallado o Ajustes para diagnosticarlos.

## Exportar el historial

1. Entrá en **Estadísticas**, buscá **Historial** y elegí la categoría o **Todos**.
2. Tocá el icono de descarga y elegí un formato.
3. Seleccioná en el menú del sistema dónde compartir o guardar el archivo. Cancelar ese menú no borra nada del historial.

- **Texto (.txt):** fecha/hora local y tipo clasificado.
- **Excel (.xlsx):** fecha, tipo, aceptación, ESP32 vinculada, modo y confianza. Fecha y confianza son valores numéricos, con formatos legibles, filtros y encabezado fijo.
- **Excel con imágenes (.xlsx):** mismos datos y miniaturas incrustadas de 180×120; se conserva la proporción con márgenes. No requiere archivos externos. Se marca cada foto no disponible.
- **Solo imágenes (.zip):** originales disponibles, con nombres de fecha, índice y categoría. No modifica ni reduce los originales.

Se exportan **todos los registros del filtro**, no solo los 25 inicialmente visibles. En vivo no almacena fotos; las imágenes eliminadas por retención no se reconstruyen. La app informa cuántos registros quedaron sin imagen.

La aceptación distingue confirmado/corregido manualmente y autoaceptado en los registros nuevos. Los antiguos no permiten reconstruir esa diferencia de forma fiable: figuran como **No registrado**. La confianza corresponde a la predicción de la IA, incluso si la categoría se corrigió después. ESP32 vinculada representa el último estado de conexión observado al capturar, no una confirmación de apertura física; puede ser desconocido.

Para proteger la memoria del dispositivo, cada archivo admite hasta 10.000 registros, imágenes individuales de hasta 32 MB y un presupuesto de 64 MB de imágenes para comprimir. Para crear miniaturas se admiten hasta 24 megapíxeles por foto. Si se exceden estos límites, se informa sin exportar un archivo incompleto. Filtrá por categoría o exportá sin imágenes. El trabajo de imágenes/compresión se ejecuta fuera del hilo de la interfaz.

Los archivos se preparan en la caché privada antes de compartir; **guardalos fuera de la app si querés conservarlos**. El sistema puede eliminar la caché. No se envían automáticamente a ningún servicio.

## Alcance de esta actualización

Nombre visible VisionIA, nueva paleta azul noche/menta, controles redondeados y fondos sin cámara en Ajustes/Estadísticas. El icono queda pendiente del logo nuevo. Se mantiene el paquete `com.resiclasia.app` y `resiclasia.db` para conservar instalaciones e historial.

Esta actualización no modifica firmware, GPIO, credenciales, protocolo ni servicios de conexión ESP32. Añade únicamente la lectura del estado ya disponible para registrarlo en el historial.

## Verificación antes de distribuir

- [ ] Instalar la actualización sobre la app anterior y comprobar que conserva el historial.
- [ ] Probar los cuatro modos, Foto/En vivo, rotación y texto grande en una tablet real.
- [ ] Exportar registros antiguos, nuevos, corregidos y autoaceptados.
- [ ] Abrir ambos XLSX en Excel/LibreOffice; verificar filtros, fechas, confianza y ubicación de imágenes.
- [ ] Extraer el ZIP; verificar originales y aviso por fotos ausentes.
- [ ] Probar cancelar el menú de compartir y repetir una exportación.
- [ ] Verificar captura, permisos y rendimiento en dispositivo. Las pruebas sin cámara no sustituyen esta comprobación.

La APK debug es para instalación y pruebas. Para distribución pública se necesita el keystore de producción y una compilación release firmada.

Verificación local del 20/09/2026: 69 pruebas unitarias/widgets aprobadas; capturas de los cuatro modos revisadas sin cámara real; APK 3.0.0+5 compilada con nombre visible VisionIA y firma v2 verificada. Las pruebas de exportación inspeccionan el contenido del XLSX/ZIP y las imágenes incrustadas; la apertura en Excel y el flujo de compartir en una tablet quedan pendientes. El análisis global conserva un aviso de estilo anterior en `lib/features/esp/domain/estado_controlador.dart`, que no se modificó por estar fuera del alcance.
