# ♻️ ECO-TOUCHLESS: SOFTWARE

Aplicación Flutter para clasificar residuos en tiempo real mediante inteligencia artificial ejecutada directamente en el dispositivo, con integración opcional a un clasificador físico basado en ESP32.

[![Versión](https://img.shields.io/badge/versi%C3%B3n-1.1.0-21c997)](../../releases/tag/v1.1.0)
[![Flutter](https://img.shields.io/badge/Flutter-3.35.2-02569B?logo=flutter)](https://flutter.dev/)

## Características

- Clasificación local con modelos TensorFlow Lite, sin enviar imágenes a servidores.
- Detección de plástico, vidrio, metal, papel/cartón y residuos orgánicos.
- Filtros para pilas, personas, fondos y objetos no aceptados.
- Modos de interfaz limpio, fácil, detallado y desarrollador.
- Historial y estadísticas almacenados localmente con SQLite.
- Exportación de historial y resultados.
- Catálogo y benchmarking de modelos `.tflite`.
- Comunicación Wi-Fi con una ESP32 para controlar el clasificador físico. (Parte proyecto)
## Principales Funciones

- Uso de detección de movimiento para capturar fotos automaticamente sin necesidad de tocar la tablet.
- Opción para ingresar tu propio modelo en la app desde el codigo fuente.
- Al usarlo con el ESP32, puedes crear un aparato clasificador de residuos automático para plazas públicas, hospitales, etc.

## Descarga

La versión más reciente está disponible en [GitHub Releases](../../releases/latest).

> El APK publicado actualmente es una compilación de depuración instalable para pruebas. La distribución de producción requiere configurar una clave privada de firma Android.

## Estructura

```text
.
├── eco_touchless/              # Aplicación Flutter
├── firmware/
│   └── eco_touchless_esp32/  # Firmware del clasificador
└── .github/workflows/        # Integración continua
```

El nombre visible del producto es `ECO-TOUCHLESS`, el paquete Dart es `eco_touchless` y el identificador nativo es `com.ecotouchless.app`.

## Desarrollo

Requisitos:

- Flutter 3.35.2 o compatible.
- Dart 3.9 o compatible.
- Android Studio y Android SDK para compilar el APK.

```bash
cd eco_touchless
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

## Firmware ESP32

El sketch se encuentra en [`firmware/eco_touchless_esp32/eco_touchless_esp32.ino`](firmware/eco_touchless_esp32/eco_touchless_esp32.ino). La red predeterminada del clasificador es `ECO-TOUCHLESS`.

Consulta la [guía de instalación, cableado y calibración](firmware/README.md) antes de conectar los servos.

## Privacidad

La inferencia, el historial y la configuración se procesan localmente. La aplicación no necesita un servidor remoto para clasificar residuos.

## Pagina Web

El proyecto tiene una pagina web existente, el link a esta es:

https://santicaballerocuenca-dot.github.io/Eco-Touchless-Software/

## 📄 Licencia

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Este proyecto está distribuido bajo la licencia MIT. Consulta el archivo [LICENSE](LICENSE) para obtener más información.
Siéntete libre de usar, modificar y distribuir este proyecto. Se requiere mantener el aviso de derechos de autor y la nota de licencia original.
