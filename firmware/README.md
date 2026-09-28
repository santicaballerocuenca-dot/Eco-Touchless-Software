# ESP32 AI Thinker · control de tres basureros

Abrí [eco_touchless_esp32/eco_touchless_esp32.ino](eco_touchless_esp32/eco_touchless_esp32.ino) en Arduino IDE. El nombre de carpeta y sketch debe coincidir. Este firmware es para **AI Thinker ESP32-CAM con ESP32 clásico**, no ESP32-S3; **no inicializa la cámara ni la microSD**. Las fotos e inferencias siguen haciéndose en la tablet.

## Primero: alimentación y seguridad

- **No alimentar los servos desde 3V3 ni desde un adaptador USB–serial.** Usar una fuente regulada adecuada al voltaje de los servos y a la corriente de arranque/bloqueo indicada por su fabricante. Los tres comparten GND con la ESP32. La fuente de la placa debe ser estable; no unir salidas positivas de dos fuentes ni retroalimentar USB.
- Señales: servo 1 → **GPIO12**, servo 2 → **GPIO13**, servo 3 → **GPIO15**. Identificar cables de señal, positivo y masa con la ficha del servo, no solo por su color.
- **GPIO12 es un pin de arranque**: una señal externa alta durante reset puede seleccionar un voltaje de flash incorrecto e impedir arrancar. GPIO15 también es un pin de arranque. Evitar módulos de servo con pull-up que fuercen estos pines durante reset. Si la placa no inicia con servos conectados, desconectar sus señales y revisar el circuito; el firmware no puede corregir un nivel aplicado antes de arrancar. No modificar eFuses como solución improvisada. [Referencia de Espressif](https://docs.espressif.com/projects/esp-faq/en/latest/hardware-related/hardware-design.html).
- Estos GPIO también se usan para microSD en ESP32-CAM: **no insertar/usar microSD con este montaje**.
- El firmware **no deshabilita la protección brownout**. Un reinicio al abrir una compuerta requiere comprobar alimentación, conexiones y corriente del servo. El monitor serie y `/status.resetReason` ayudan a diagnosticarlo.
- Probar primero sin varillas ni tapas conectadas. Mantener manos fuera del mecanismo. Se ordenan posiciones, **no hay sensores que confirmen apertura/cierre ni detección de obstáculos**.

## 1. Preparar Arduino IDE

1. En Preferencias → URLs adicionales del Gestor de placas, agregar:
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`.
2. Instalar **esp32 by Espressif Systems**, versión **3.3.1** (entorno fijado para la comprobación de este sketch).
3. Elegir **AI Thinker ESP32-CAM**. No elegir ESP32-S3.
4. En Gestor de bibliotecas instalar **ESP32Servo 3.2.1** y **ArduinoJson 7.4.3**. WiFi, WebServer y Preferences vienen con el core.
5. Abrir el `.ino`, revisar las constantes del principio y pulsar **Verificar**.
6. Cargar manualmente usando el procedimiento de tu adaptador/placa. Un USB–serial debe usar **lógica de 3,3 V**. Si tu placa requiere GPIO0–GND para cargar, quitar ese puente antes de reiniciar para ejecutar. No alimentar motores durante la carga.
7. Abrir monitor serie a **115200 baudios**. Debe informar `AP: ECO-TOUCHLESS, ready, IP 192.168.4.1`.

## 2. Conectar desde la app

1. Instalar el APK actualizado y abrir **Ajustes**.
2. Activar **Enviar resultado al clasificador físico**.
3. Conectar la tablet a **ECO-TOUCHLESS**, contraseña inicial **resiclas2026**. Aceptar permanecer en la red aunque Android indique “sin Internet”.
4. IP **192.168.4.1**, puerto **80**. Ejecutar diagnóstico.
5. La **Clave de control** inicial es **resiclas2026-control**. Debe coincidir con `API_KEY` del sketch; pulsar **Guardar clave de control** si la cambiás.
6. El bloque **Servos de la ESP32** lee la configuración automáticamente, también al conectarse manualmente. Si hace falta, pulsar **Leer ajustes de la ESP32**.

Las contraseñas iniciales son para desarrollo. Cambiar `AP_PASSWORD` y `API_KEY` por valores propios antes de uso compartido, actualizar ambos en la app y no publicar las claves. La API HTTP es solo para la red local WPA2; no exponerla a Internet. La clave se guarda en las preferencias privadas de la app, no en un almacén criptográfico dedicado.

## 3. Ajustar cada servo

| Ajuste | Significado |
|---|---|
| Activo | Permite que una clasificación abra este servo. Desactivarlo no elimina su posición de cierre. |
| Etiqueta | Texto exacto del modelo. La app reúne etiquetas de los modelos instalados; incluye Metal, Vidrio o NoAceptar si querés asignarlos. Fondo está bloqueado. |
| Cerrado | Posición absoluta entre 0 y 180°. |
| Abierto | Otra posición absoluta entre 0 y 180°. |
| Cerrar después de | Entre 0,5 y 60 segundos, desde la orden de apertura hasta la orden de cierre. |

Ejemplos: servo normal **cerrado 0°, abierto 90°**; invertido **cerrado 180°, abierto 90°** o **cerrado 90°, abierto 0°**, según el montaje. No asignar una misma etiqueta a dos servos activos.

**Guardar en la ESP32** pide confirmación: guarda los tres ajustes en memoria no volátil y **mueve secuencialmente los tres servos a las posiciones cerradas**, incluso los desactivados. Esperar aproximadamente 3 segundos antes de clasificar. También se posicionan secuencialmente al arrancar. Los ajustes sobreviven a cortes de alimentación mediante [Preferences/NVS](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/preferences.html); no se escribe en flash en cada detección.

Los grados son una consigna nominal. `PULSE_MIN_US=1000` y `PULSE_MAX_US=2000` son conservadores; el recorrido real depende del servo y debe calibrarse con su ficha. **No introducir 360°**: un servo continuo interpreta el pulso como velocidad/sentido y no conoce su posición. Servos posicionales especiales de 270/360° necesitan una calibración y límites diferentes, no basta ampliar el número de la app. [API ESP32Servo](https://github.com/madhephaestus/ESP32Servo).

## Conexión y temporización

- Punto de acceso WPA2 independiente, canal fijo configurable (1/6/11 recomendados para elegir según interferencias), máximo dos clientes. Sin modo estación que busque otros routers durante la operación. No se reinicia el AP después de una inferencia.
- Ahorro de energía Wi-Fi desactivado; potencia de radio predeterminada, sin forzar máximo consumo. [API Wi-Fi Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/wifi.html).
- El servidor responde inmediatamente a la orden, sin esperar a que cierre la tapa. Una tarea de control independiente revisa los temporizadores cada 10 ms: perder la conexión no cancela el cierre programado y un cliente HTTP lento no bloquea ese temporizador.
- Un solo ciclo activo a la vez, seguido de 800 ms de asentamiento y 600 ms de enfriamiento. Otras aperturas reciben HTTP 409; no quedan en una cola que pueda abrir tapas después inesperadamente.
- `DETACH_CLOSED=false` conserva torque de cierre. Cambiarlo a true libera PWM después de cerrar, pero la tapa puede moverse por gravedad: solo usarlo si el mecanismo lo permite.
- La app no reintenta órdenes de apertura ni guardados ambiguos. Si vence el timeout de un guardado, volver a **Leer ajustes** antes de decidir reenviar.

## API v1

Todas las respuestas usan JSON y `Cache-Control: no-store`. `/status` es de lectura pública local; los demás endpoints exigen `X-Api-Key`. Se rechazan solicitudes con `Origin`; no hay CORS abierto.

| Método/ruta | Función |
|---|---|
| `GET /status` | Versión, placa, identificador de arranque, revisión, clientes, uptime, memoria libre, motivo de reset y estado de servos. HTTP 200 indica servidor accesible; comprobar `ready`, `storageReady`, `hardwareFault` para diagnosticar movimiento. |
| `GET /config` | Configuración completa de los GPIO12/13/15 y sus etiquetas. |
| `PUT /config` | Guardado completo validado: exige `deviceId`, `bootId`, `revision`, `apiVersion:1` y tres servos. Retorna configuración confirmada con revisión incrementada. Rechaza cambios mientras hay movimiento. |
| `GET /classify?label=...&deviceId=...&bootId=...&revision=...&requestId=...` | Busca la etiqueta en el mapa actual y programa un solo servo. La revisión y el arranque previenen órdenes basadas en configuración obsoleta. |
| `GET /plastico`, `/papel`, `/organico` | Alias de etiquetas para conservar rutas conocidas. Usan **la asignación vigente**, no una tapa fija tras remapear. Exigen también clave de control. |

Mapa inicial: **Plastico → GPIO12; Papel_carton → GPIO13; Organico → GPIO15**. Una vez remapeado, Foto y En vivo usan `/classify` y respetan el mapa de la placa. Con firmware antiguo que responda 404/405 a `/config`, la app conserva sus tres endpoints originales sin mostrar ajustes remotos; errores de clave/red no activan esa compatibilidad.

Ejemplo de configuración (los identificadores/revisión se obtienen por GET, no copiar literalmente):

```json
{"device":"eco_touchless-esp32","apiVersion":1,"deviceId":"...","bootId":"...","revision":1,"servos":[
  {"id":0,"gpio":12,"enabled":true,"label":"Metal","closedAngle":180,"openAngle":90,"holdMs":3000},
  {"id":1,"gpio":13,"enabled":true,"label":"Papel_carton","closedAngle":0,"openAngle":90,"holdMs":4000},
  {"id":2,"gpio":15,"enabled":true,"label":"Organico","closedAngle":0,"openAngle":90,"holdMs":3000}
]}
```

`requestId` admite 8–96 caracteres. El firmware recuerda las últimas 16 órdenes aceptadas durante ese arranque: repetir una de ellas devuelve ACK sin otro movimiento. No es almacenamiento persistente de órdenes; los clientes no deben reutilizar IDs. La app crea IDs nuevos y no hace reintentos automáticos. ACK significa **orden aceptada**, no confirmación física por sensor.

## Prueba física antes de usar tapas

- [ ] Arranque con señales conectadas y sin brownout; comprobar GPIO12 y fuente.
- [ ] Sin varillas, comprobar cerrado/abierto con recorridos pequeños antes de los extremos.
- [ ] Asignar Metal a GPIO12, guardar, reiniciar y comprobar que se conserve.
- [ ] Confirmar que cada etiqueta solo activa el servo elegido, y Fondo ninguno.
- [ ] Desconectar Wi-Fi inmediatamente después de abrir: debe cerrar por su temporizador.
- [ ] Consultar `/status` durante una apertura: debe seguir respondiendo.
- [ ] Probar timeout, clave incorrecta, doble solicitud, placa reiniciada y configuración desde dos tablets: sin reintentos ni aperturas pendientes.
- [ ] Repetir al menos 20 ciclos con la carga mecánica real y revisar alimentación, temperatura y topes.

Compilar no valida el cableado, la alimentación ni el movimiento real. No se carga automáticamente nada en la placa.

## Diagnóstico de cortes y cierres anticipados (firmware 1.1.0)

1. Actualizá el `.ino` y la APK. Sin mecanismos acoplados, conectá desde la app, aceptá el aviso de Android y activá **Mantener conexión con ESP32**.
2. Cambiá el tiempo a **5**, guardá y comprobá que diga **Guardado en la placa: 5.0 segundos**. Repetí con **50**. Editar o simular no guarda.
3. Una apertura captura su `holdMs` completo; la tarea de motores cierra por tiempo transcurrido, independientemente de Wi-Fi. `/status` muestra `activeHoldMs` y `remainingMs`; la app los presenta aproximadamente cada 2 s. Son órdenes/temporizadores, no sensores físicos.
4. En el monitor serie a **115200**, buscá `OPEN gpio=... hold=5000 ms` (o `50000`) y `CLOSE ... elapsed=...`. Si aparece un nuevo mensaje de arranque antes del cierre, la placa se reinició. `bootId` cambia y la app avisa; `resetReason=9` identifica brownout. Una pérdida total de alimentación puede informar encendido normal, no necesariamente brownout.
5. Si el tiempo aceptado es correcto y no cambia el arranque pero la tapa se cierra antes, revisar alimentación del servo, carga, montaje y tipo de servo. Un MG996R de rotación continua no se controla por posición como el posicional.

**No alimentar los MG996R desde el pin 3,3 V ni desde la alimentación USB de la placa.** Usá una fuente regulada para servos dimensionada para la corriente de arranque/bloqueo de las unidades reales, con masa común y cableado adecuado. El [fabricante](https://towerpro.com.tw/product/mg996R/) especifica corrientes elevadas bajo bloqueo; existen variantes y clones. El software no puede corregir una caída eléctrica ni sostener un plazo de 50 s durante un reinicio. No se deshabilitó el detector de brownout ni se reanudan órdenes previas tras arrancar.

## Verificación de la versión anterior — 17/09/2026

- Sketch compilado con `esp32:esp32:esp32cam`, core **3.3.1**, ESP32Servo **3.2.1** y ArduinoJson **7.4.3**.
- Resultado: **1.004.387 bytes de programa (31%)** y **46.180 bytes de variables globales (14%)**. Advertencias de variables no usadas dentro de ESP32Servo; sin errores de compilación.
- App **2.2.0+3**: **47 pruebas aprobadas**, análisis Flutter sin incidencias, APK debug generado y firma v2 verificada.
- Las pruebas del protocolo usan respuestas HTTP simuladas: validación, revisiones, errores, guardados ambiguos y confirmación de interfaz. No reemplazan pruebas físicas.
- No se flasheó la placa ni se probaron servos, alimentación o alcance Wi-Fi reales.
