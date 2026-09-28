# ECO-TOUCHLESS

Versión 3.0: [guía de interfaz y exportaciones](docs/eco_touchless_3.md). El proyecto usa el nombre comercial `ECO-TOUCHLESS`, el paquete Dart `eco_touchless` y el identificador nativo `com.ecotouchless.app`.

Aplicación Flutter para clasificar residuos con un modelo TensorFlow Lite ejecutado localmente. Puede guardar un historial, mostrar estadísticas y enviar órdenes opcionales a un clasificador físico basado en ESP32.

## Funciones

- Clasificación local y sin conexión a Internet.
- Catálogo modular para alternar entre varios modelos TFLite desde Ajustes.
- Aceleración GPU con retorno automático a CPU.
- Captura manual o automática mediante detección de movimiento v2.
- Modo **En vivo** con inferencia continua de frames YUV directamente en RAM.
- Disparo inmediato de la ESP32 al superar un umbral configurable (80% por defecto).
- Historial local con fotografías, filtros, detalle y eliminación individual.
- Confirmación o corrección manual antes de guardar o accionar una tapa.
- Confirmación desactivable con aceptación automática configurable (5 s por defecto).
- Retención configurable de fotografías sin perder registros estadísticos.
- Estadísticas por categoría y por día.
- Exportación a texto, Excel sin imágenes, Excel con miniaturas y ZIP de fotografías originales.
- Interfaz configurable: Limpio, Fácil, Detallado y Desarrollador.
- Conexión opcional a un punto de acceso ESP32.
- Diagnóstico del ESP32 con endpoint, latencia, HTTP y respuesta.

Las fotografías y predicciones no se envían a servicios externos. La única comunicación de red de la app son las órdenes locales al ESP32 cuando esa opción está habilitada.

En **En vivo**, los fotogramas no se convierten a JPEG ni se escriben en disco: se recortan, redimensionan y normalizan desde YUV420 directamente al tensor del modelo. La interfaz descarta trabajo mientras una inferencia está en curso, limita la frecuencia máxima para evitar saturar el teléfono y muestra la latencia observada. Un enclavamiento impide que el mismo residuo accione repetidamente la tapa; se rearma cuando el residuo sale del encuadre. Los eventos pueden guardarse en el historial, pero sin fotografía, porque los frames permanecen únicamente en RAM.

El selector **FOTO / EN VIVO** está sobre la cámara. La primera activación abre una guía visual de tres pasos y el botón de ayuda permite verla de nuevo. El umbral se ajusta en **Ajustes → Modo En vivo** entre 50% y 99%.

El detector de movimiento v2 compensa cambios globales de iluminación, aprende el ruido habitual de la cámara y usa histéresis para reducir falsos positivos. Opcionalmente puede conservar el disparo programado aunque el movimiento termine antes de la captura.

## Requisitos

- Flutter 3.35.2 o posterior.
- Dart 3.3 o posterior.
- Android 8.0/API 26 o posterior.
- Para iOS, macOS con una versión de Xcode compatible con Flutter.
- Developer Mode habilitado en Windows para que Flutter pueda crear enlaces simbólicos de plugins.

## Puesta en marcha

```bash
flutter pub get
flutter analyze
flutter run
```

## Calidad y pruebas

```bash
flutter analyze --fatal-infos
flutter test --coverage
flutter test integration_test -d <device-id>
```

Las pruebas unitarias y de widgets viven en `test/`; el smoke test para dispositivo está en `integration_test/`. El workflow [Flutter CI](.github/workflows/flutter.yml) ejecuta formato, análisis, pruebas, cobertura y compilación Android en cada pull request y push a `main` o `master`.

Antes de publicar, completar [el checklist de release y dispositivo](docs/release_checklist.md).

## Modelos experimentales

El modelo inicial está en `assets/modelos/EfficientNet B0.tflite`. Para probar otro:

1. Copiar el nuevo archivo, por ejemplo `MobileNet V2.tflite`, dentro de `assets/modelos/`.
2. Volver a compilar la aplicación, porque los assets se incorporan dentro del APK.
3. Abrir **Ajustes → Modelo de clasificación → Modelo activo**.
4. Elegir `MobileNet V2`; el nombre visible se obtiene automáticamente del nombre del archivo.

No hace falta modificar Dart ni `pubspec.yaml`: la carpeta completa ya está declarada como asset. El modelo seleccionado se conserva al reiniciar y se utiliza en captura Foto, movimiento y En vivo.

Para funcionar automáticamente con `assets/labels.txt`, cada modelo debe cumplir:

- Tensor de entrada `float32` con formato `[1, N, N, 3]`. `N` se detecta automáticamente entre 32 y 1024.
- Preprocesamiento configurado según el entrenamiento. EfficientNet B0 es el **modelo insignia**: RGB, center-crop y normalización ImageNet (`mean = [0.485, 0.456, 0.406]`, `std = [0.229, 0.224, 0.225]`), protegido de cambios experimentales.
- Tensor de salida `float32` cuya última dimensión tenga la misma cantidad y orden de categorías que `assets/labels.txt`.

Si un experimento usa otras categorías, se puede colocar un archivo `.txt` con el mismo nombre junto al modelo —por ejemplo, `MobileNet V2.txt`— con una etiqueta por línea. Esas categorías podrán clasificarse y guardarse, pero solo `Plastico`, `Papel_carton` y `Organico` tienen actualmente endpoints físicos configurados en la ESP32.

La arquitectura interna puede ser MobileNet, EfficientNet u otra; lo importante es respetar el contrato de tensores y el preprocesamiento anterior. Si no lo cumple, la app rechaza ese modelo con un mensaje descriptivo y permite volver a seleccionar otro.

### Perfiles de entrada y cámara

Al seleccionar un modelo distinto de EfficientNet B0 aparecen **Input X / Input Y**, center-crop/letterbox, normalización **0…1 / −1…1 / ImageNet** y el interruptor **RGB → BGR**. Pulsar **Guardar perfil de este modelo** para aplicarlos a Foto, movimiento, En vivo, comparación y Bench.

Los dos MobileNet incluidos parten de **160×160, 0…1, center-crop, BGR**, según las pruebas del usuario. Los modelos experimentales nuevos heredan ese punto de partida: revisar siempre su entrenamiento. La app acepta logits o probabilidades normalizadas sin aplicar softmax por duplicado.

Para una captura cuadrada estricta, usar el acceso rápido **96×96** o escribir el mismo número en ambos campos. También admite dimensiones rectangulares entre 16 y 1024. Es una resolución intermedia: **no cambia el tensor fijo del TFLite**; un MobileNet 160×160 sigue recibiendo un tensor 160×160 después de adaptar la captura. Letterbox preserva el contenido con bandas negras; center-crop llena el encuadre recortando los bordes. En Foto se conserva la captura preparada en el historial. En vivo hace el muestreo en RAM, sin JPEG, usando interpolación aproximada de vecino más próximo; pequeñas diferencias frente a Foto son esperables.

La interfaz permite orientación vertical y horizontal. En la pantalla principal, el botón de **cámaras con flechas** cambia entre trasera y frontal; se deshabilita durante una captura o si falta alguna cámara. La rotación del tensor en vivo tiene en cuenta sensor, orientación y lente, además de la rotación del visor.

### Comparación y Bench

- **Ajustes → Comparar modelos:** seleccionar modelos, encuadrar y pulsar **Capturar y comparar**. Todos reciben los mismos bytes de una sola foto, con su propio perfil. Se ejecutan por turnos en CPU y fuera del hilo de interfaz para limitar memoria. Muestra etiqueta, confianza y tiempo; sin etiqueta real no afirma cuál es más preciso.
- **Ajustes → DEBUG → Activar BENCH:** habilita la nueva pestaña **Bench**. No inicia trabajo por sí sola.
- **Bench → Ejecutar todos los modelos:** procesa 35 imágenes empaquetadas, cinco por cada clase de `assets/labels.txt`. Muestra aciertos/35, accuracy, errores, resultados individuales y tiempo medio de inferencia en CPU. Al completar todos los modelos muestra el mejor resultado (puede haber empates) y el promedio de accuracies. No confundir ese promedio con la precisión de un ensemble.
- Un error de imagen cuenta como no acierto; un modelo que no carga se señala como error y no se presenta un promedio completo engañoso. Cancelar conserva resultados parciales claramente identificados. El ranking solo aparece al terminar todos los modelos. La navegación queda bloqueada durante Bench; pasar la app a segundo plano cancela al terminar la imagen en curso.
- Ni comparación ni Bench escriben historial o envían órdenes a la ESP32. Los tiempos excluyen carga del modelo, decodificación y transformación; incluyen la primera inferencia (sin calentamiento). Comparar en el mismo teléfono y condiciones térmicas.

Las imágenes se extrajeron de `D:\resiclasai\testing` usando **las etiquetas de `info.labels`**, no adivinando por el nombre. El manifiesto `assets/bench/manifest.json` conserva el archivo de origen. Selección determinista de cinco archivos espaciados en el orden alfabético de cada clase; no es una muestra estadística aleatoria. Con solo 35 imágenes, cada fallo cambia el accuracy en ~2,86 puntos: sirve para explorar, no para asegurar precisión en producción.

Para regenerar la misma selección (sin cambiar el dataset original):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/extract_bench.ps1
```

`tool/inspect_models.dart` inspecciona los tensores de los modelos sin inferencia. Los archivos actuales tienen entradas float32 224×224 (EfficientNet) y 160×160 (ambos MobileNet), con siete salidas.

## Compilación Android

El identificador de la aplicación es `com.ecotouchless.app`. Para una compilación release:

1. Crear un keystore de publicación y guardarlo fuera del control de versiones.
2. Copiar `android/key.properties.example` como `android/key.properties`.
3. Completar las cuatro propiedades con los datos reales del keystore.
4. Ejecutar `flutter build appbundle --release`.

La compilación release falla deliberadamente si no existe una configuración de firma válida; nunca utiliza la clave debug como respaldo.

## Organización

```text
lib/
├── app/                         # raíz, navegación e introducción inicial
├── core/
│   ├── domain/                  # conceptos compartidos
│   ├── theme/                   # identidad visual
│   └── widgets/                 # componentes reutilizables
└── features/
    ├── classification/          # cámara, inferencia, dominio y pantalla
    ├── bench/                   # comparación de modelos y evaluación etiquetada
    ├── esp/                     # comunicación HTTP y conexión Wi-Fi
    ├── settings/                # preferencias y pantalla de ajustes
    └── statistics/              # SQLite, exportación e historial
```

Cada funcionalidad separa, cuando corresponde:

- `data/`: acceso a plugins, almacenamiento o red.
- `domain/`: entidades y reglas sin interfaz.
- `presentation/`: widgets y estado de pantalla.

## ESP32

### Firmware configurable para AI Thinker

El sketch está en [firmware/eco_touchless_esp32/eco_touchless_esp32.ino](../firmware/eco_touchless_esp32/eco_touchless_esp32.ino). Seguir la [guía de Arduino IDE, cableado y calibración](../firmware/README.md) antes de conectar servos. La carga a la placa es manual.

Con la versión 2.2 de la app: **Ajustes → Enviar resultado al clasificador físico → conectar Wi-Fi → Servos de la ESP32**. Asignar una etiqueta por servo (GPIO12/13/15), posiciones absolutas de cierre/apertura de 0–180° y cierre automático de 0,5–60 s. **Guardar en la ESP32** conserva todo en NVS y aplica secuencialmente las posiciones cerradas, previa confirmación. Los servos invertidos se ajustan cambiando esas dos posiciones; 360° no es una posición válida para un servo convencional o de rotación continua.

Foto y En vivo consultan la asignación de la placa; Metal, Vidrio y NoAceptar pueden tener tapa si se asignan explícitamente. Fondo queda bloqueado. Se detecta firmware anterior mediante 404/405 de `/config`, manteniendo solo entonces el mapa fijo original. Usar la **Clave de control** igual a `API_KEY` del sketch (predeterminada de desarrollo: `resiclas2026-control`), además de la contraseña WPA2. Cambiar ambas antes de uso compartido.

El AP y el servidor no esperan el tiempo de apertura: una tarea independiente cierra los servos. La app no reintenta órdenes físicas y la placa rechaza ciclos simultáneos, configuraciones obsoletas e IDs de órdenes duplicados recientes. El tiempo de cierre es una orden programada; no existe realimentación de posición ni protección física contra obstáculos.

**Alimentación:** servos con fuente adecuada y GND común, nunca desde 3V3. GPIO12 es pin de arranque y no debe quedar forzado alto por el circuito al resetear; no usar la microSD con esos GPIO. No se puede arreglar por software una caída de tensión al mover el servo.

Los valores iniciales son:

- SSID: `ECO-TOUCHLESS`
- IP: `192.168.4.1`
- Puerto: `80`

La contraseña, dirección y puerto pueden modificarse desde Ajustes. La primera activación muestra una guía de conexión y el diagnóstico comprueba `/status`. Por seguridad, la app solo acepta IPv4 privadas o nombres mDNS terminados en `.local`. Las órdenes que accionan tapas no se reintentan automáticamente para evitar una doble activación física.

Para reducir la latencia, la configuración y las URI de órdenes se almacenan en memoria, se reutiliza un único cliente HTTP con conexión persistente y al activar **En vivo** se intenta precalentar la conexión con `/status`. Este precalentamiento nunca bloquea el inicio del modo; si falla, la orden real conserva el manejo normal de errores.

**Ajustes → Mantener conexión con ESP32**, junto con la vinculación habilitada, activa retención Wi-Fi Android. En primer plano se comprueba `/status` cada dos segundos (sin solapar consultas); dos fallos consecutivos marcan la desconexión. La recuperación usa esperas progresivas de 5, 10, 20, 40 y hasta 60 segundos, renueva HTTP y nunca reenvía órdenes físicas. En Android 10+ una única solicitud nativa de red local se conserva y vuelve a vincular el proceso cuando la ESP32 reaparece. Primero conectá desde la app y aceptá el permiso del sistema. Los intentos automáticos no solicitan permisos; ante rechazo/no disponibilidad que Android comunica, se requiere intervención manual para no encadenar diálogos. Android anterior e iOS conservan el conector de respaldo sin este mecanismo nativo. Al pasar a segundo plano se detienen las comprobaciones y se libera el Wi-Fi lock. Ver [API de conexiones locales de Android](https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap).

Esto no puede evitar un reinicio eléctrico de la ESP32 ni garantizar retención contra todas las políticas del fabricante. Si la pérdida coincide exactamente con el movimiento del servo, comprobar fuente, caída de tensión, masa compartida y registro de reinicio de la placa. El [firmware incluido y su guía](firmware/README.md) exponen identidad de arranque, motivo de reinicio, tiempo aceptado y tiempo restante. Un reinicio interrumpe el temporizador y el arranque ordena cerrar: no es un límite de dos segundos.

En ajustes de servos, **Ver cerrado / Ver abierto / Probar ciclo virtual** simulan cada MG996R sin enviar nada a la placa. La simulación ilustra ángulos; no conoce el montaje ni mide posiciones. El tiempo editado solo se aplica tras **Guardar en la ESP32**; se muestra también el valor confirmado por la placa. Android mantiene la pantalla encendida únicamente mientras la actividad está en primer plano.

## Datos locales

El historial se almacena en SQLite y las fotografías persistentes dentro del directorio privado de documentos de la aplicación. Al eliminar un registro se elimina también su fotografía. La retención puede configurarse en 7, 30 o 90 días, o conservarse siempre; al vencer una fotografía se conserva su clasificación para las estadísticas. La opción “Borrar todo el historial” limpia además imágenes huérfanas de versiones anteriores.

## Plataformas

Android es la plataforma verificada actualmente. La configuración nativa de iOS está preparada, pero cualquier entrega iOS debe compilarse y probarse en macOS/Xcode, especialmente permisos de red local, cámara y firma.
