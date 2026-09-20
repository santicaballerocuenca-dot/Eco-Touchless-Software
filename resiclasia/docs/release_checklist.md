# Checklist de release y pruebas en dispositivo

## Antes de generar el build

- [ ] Actualizar `version` y número de compilación en `pubspec.yaml`.
- [ ] Confirmar que `applicationId` y Bundle ID sean `com.resiclasia.app`.
- [ ] Ejecutar `flutter pub get` con el Flutter fijado por CI.
- [ ] Ejecutar `dart format --output=none --set-exit-if-changed lib test integration_test`.
- [ ] Ejecutar `flutter analyze --fatal-infos`.
- [ ] Ejecutar `flutter test --coverage`.
- [ ] Revisar cambios de dependencias con `flutter pub outdated`.
- [ ] Confirmar que modelo, etiquetas e íconos sean los definitivos.
- [ ] Verificar que todos los `.tflite` de `assets/modelos/` aparezcan por nombre en Ajustes.
- [ ] Cambiar entre modelos, reiniciar la app y confirmar que la selección persista.
- [ ] Probar Foto, movimiento y En vivo con cada modelo incluido.
- [ ] Confirmar que cada modelo tenga entrada/salida `float32`, RGB cuadrada y la cantidad correcta de etiquetas.
- [ ] Verificar que no se versionen `key.properties`, keystores o contraseñas reales.

## Pruebas Android en dispositivo físico

- [ ] Cargar manualmente el nuevo sketch y seguir `firmware/README.md`; verificar alimentación y GPIO12 al arrancar.
- [ ] Configurar etiqueta/ángulos/cierre de cada servo desde la tablet, guardar y reiniciar la ESP32 para verificar persistencia.
- [ ] Guardar pide confirmación y aplica cierres secuencialmente; servos invertidos probados primero sin varillas.
- [ ] Asignar Metal o Vidrio y comprobar funcionamiento tanto en Foto como En vivo; Fondo bloqueado.
- [ ] Revisiones obsoletas, dos tablets, clave incorrecta y pérdida de ACK no provocan guardados silenciosos ni reintentos de apertura.
- [ ] Desconectar Wi-Fi con tapa abierta y confirmar cierre automático y servidor disponible durante todo el ciclo.

- [ ] Instalación limpia y actualización sobre la versión anterior.
- [ ] Onboarding completo con fuente grande y lector de pantalla.
- [ ] Permiso de cámara: concedido, denegado y denegado permanentemente.
- [ ] Cámaras trasera/frontal, pausa/reanudación, bloqueo/desbloqueo y las cuatro orientaciones.
- [ ] Comparar el encuadre del visor y la imagen inferida en Foto/En vivo, con ambas lentes y en horizontal.
- [ ] Cambiar cámara con movimiento y En vivo activos sin stream duplicado ni disparo espurio.
- [ ] Input X/Y 96×96, 160×160 y rectangular; validar límites, center-crop, letterbox, RGB/BGR y normalización con imágenes de referencia.
- [ ] Confirmar que EfficientNet insignia conserva su preparación y los perfiles experimentales persisten por modelo.
- [ ] Comparación: misma foto para los modelos seleccionados, errores visibles y ninguna apertura de compuerta.
- [ ] DEBUG: Bench oculto inicialmente, aparece al activarlo, no se ejecuta sin pulsar el botón.
- [ ] Bench: 35 imágenes × todos los modelos, cancelar, segundo plano y repetir sin fuga de memoria.
- [ ] Verificar manualmente algunos aciertos, accuracy, promedio general y modelos empatados; no tomar confianza como accuracy.
- [ ] Mantener ESP: abrir 20 veces una compuerta, observar conexión, apagar/encender placa y usar Reconectar; comprobar que nunca repite una apertura por timeout.
- [ ] Revisar alimentación y registro de reinicio si la ESP32 se pierde al mover un servo.
- [ ] Clasificación manual con CPU y GPU.
- [ ] Alternar FOTO/EN VIVO varias veces sin congelamiento ni doble stream de cámara.
- [ ] En vivo: comprobar inferencia desde RAM con CPU y GPU durante al menos 15 minutos.
- [ ] En vivo: verificar umbrales 50%, 80% y 99%, incluida su persistencia tras reiniciar.
- [ ] En vivo: una categoría accionable dispara al superar el umbral y no repite mientras el mismo objeto permanezca delante de la cámara.
- [ ] En vivo: retirar el objeto durante tres lecturas, volver a colocarlo y verificar que se rearme.
- [ ] En vivo: Fondo, No aceptado, Metal y Vidrio nunca accionan la ESP32.
- [ ] En vivo: abrir la guía inicial y volver a abrirla desde el botón de ayuda.
- [ ] En vivo: si el historial está activo, guardar el evento como “En vivo” sin archivo de imagen y exportarlo con `modo=en_vivo`.
- [ ] Resultado correcto confirmado y resultado corregido a otra categoría.
- [ ] Confirmación desactivada: aceptación automática después de 3/5/10 segundos.
- [ ] Resultado cancelado: no debe guardarse ni accionar la ESP32.
- [ ] Detección de movimiento y disparo automático.
- [ ] Detector v2 ante cambios de iluminación, movimiento breve y ruido de cámara.
- [ ] Captura cancelada al cesar el movimiento y captura conservada con la opción activada.
- [ ] Historial: filtros, detalle, paginación, borrado y CSV.
- [ ] Retención de 7/30/90 días y opción “Siempre”.
- [ ] Borrado total sin fotografías huérfanas.
- [ ] ESP32 apagada, IP incorrecta, timeout, HTTP no exitoso y diagnóstico correcto.
- [ ] Medir latencia del primer disparo En vivo con conexión precalentada y verificar que no haya reintentos físicos.
- [ ] Conexión automática y alternativa desde ajustes Wi-Fi.
- [ ] Plástico, Papel/Cartón y Orgánico accionan la tapa correcta una sola vez.
- [ ] Metal, Vidrio y No aceptado no accionan tapas.
- [ ] Uso sin Internet y con modo avión, excepto la red local de la ESP32.
- [ ] Reinicio de la aplicación conservando ajustes e historial.
- [ ] Consumo de memoria y temperatura durante 15 minutos de uso continuo.

## Pruebas iOS en dispositivo físico

## Regresión ESP32 / Android 2.3

- [ ] Autorizar conexión una vez, activar retención; apagar y encender solo la ESP32 y comprobar recuperación sin nuevas aperturas.
- [ ] Probar rechazo del diálogo y permisos denegados: sin bucle de solicitudes.
- [ ] Probar Wi-Fi apagado, segundo plano y retorno, cambio de SSID/IP y distintos Android/fabricantes.
- [ ] Mantener la app abierta más que el timeout de pantalla: encendida; ir al inicio de Android: vuelve el timeout normal.
- [ ] Simular GPIO12/13/15 con posiciones invertidas: ninguna petición de apertura/guardado ni movimiento físico.
- [ ] Guardar 5 s y 50 s, releer y medir apertura real con cronómetro y registro serie.
- [ ] Durante apertura, perder Wi-Fi sin cortar alimentación: el cierre mantiene su plazo.
- [ ] Comprobar aviso por cambio de bootId y brownout; no confundir cierre de arranque con cierre temporizado.
- [ ] Cargar firmware nuevo manualmente; verificar alimentación independiente de servos y masa común antes de probar con carga.

## Pruebas iOS en dispositivo físico (continuación)

- [ ] Compilar y firmar desde macOS/Xcode.
- [ ] Validar cámara, red local y permisos declarados en `Info.plist`.
- [ ] Validar conexión al AP ESP32 y retorno a una red con Internet.
- [ ] Repetir clasificación, corrección, historial, retención y ciclo de vida.

## Publicación

- [ ] Generar `flutter build appbundle --release` con el keystore de producción.
- [ ] Conservar de forma segura el keystore y sus contraseñas.
- [ ] Probar el AAB mediante una pista interna de Google Play.
- [ ] Revisar nombre, ícono, capturas, política de privacidad y ficha de datos.
- [ ] Descargar y archivar artefactos, símbolos y reporte de CI.
- [ ] Crear tag de Git y notas de versión.
