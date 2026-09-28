# ♻️ ECO-TOUCHLESS: SOFTWARE (Android App)

> **Sistema de clasificación de residuos en tiempo real con Inteligencia Artificial On-Device totalmente privado.**

Esta aplicación Android (.APK) es la interfaz y el motor de procesamiento inteligente diseñado originalmente para interactuar con un sistema físico de clasificación de residuos. Sin embargo, su arquitectura modular permite utilizarla de forma independiente o integrarla en otros proyectos de robótica, IoT y reciclaje.

---

## 📸 Demostración Visual / Capturas

| Clasificación en Vivo | Estadísticas | Benchs & ML |
| :---: | :---: | :---: |
| ![Clasificación](link-a-tu-imagen-clasificacion.png) | ![Estadísticas](link-a-tu-imagen-estadisticas.png) | ![Benchs](link-a-tu-imagen-benchs.png) |

---

## ✨ Funcionalidades y Módulos

La aplicación cuenta con 3 secciones principales y 1 módulo avanzado para desarrolladores:

### 1. 🔍 Clasificación (Tiempo Real)
* **Categorías detectadas y aceptadas:**
  * 🥤 Plásticos
  * 🍾 Vidrios
  * 🥫 Metales
  * 📦 Papeles y Cartones
  * 🍎 Residuos Orgánicos
* **Filtros de rechazo (Seguridad):**
  * 🔋 Pilas
  * 🖼️ Fondos / Vacíos
  * 👤 Personas (evita falsos positivos en entornos concurridos)

### 2. ⚙️ Ajustes
* Configuración de parámetros de la cámara.
* Ajustes de sensibilidad y umbral de confianza para la detección.
* Configuración de comunicación con la estructura física/hardware.

### 3. 📊 Estadísticas
* Histórico de materiales detectados y procesados.
* Métricas visuales del rendimiento del sistema guardadas localmente.

### 4. 🧪 Benchs & Modelos Personalizados *(Módulo Avanzado)*
* **Carga de modelos propios:** Permite importar archivos de modelos personalizados en formato `.tflite`.
* **Benchmarking:** Mide en tiempo real la velocidad de inferencia (FPS), latencia y precisión de tu modelo dentro de la app.

---

## 🛠️ Tecnologías Utilizadas

* **Motor de IA / Inferencia:** [TensorFlow Lite (TFLite)](https://www.tensorflow.org/lite) – Permite ejecutar inferencias de Deep Learning de manera 100% local (*on-device*) sin necesidad de conexión a internet ni servidor.
* **Base de Datos Local:** [SQLite](https://www.sqlite.org/) – Almacenamiento rápido y eficiente para guardar configuraciones, registros e historial de estadísticas.
* **Plataforma:** Android (Java / Kotlin)

---

## 📦 Instalación y Uso

1. Descarga el ultimo archivo `.apk` disponible en la sección de **Releases** de este repositorio.
2. Instala la APK en tu dispositivo Android.
3. Otorga los permisos requeridos de **Cámara** y **Almacenamiento**.
4. *(Opcional)* Carga tu propio modelo `.tflite` desde el codigo fuente para probar tus propias redes neuronales en Assets/Models/ y compararlo con otros modelos(debes tener dart,flutter e android instalado, ademas de compilar la app para este paso).

---

## 📄 Licencia

Este proyecto está bajo ninguna licencia. Pero yo autorizo su uso libre y mejoras al proyecto original.
