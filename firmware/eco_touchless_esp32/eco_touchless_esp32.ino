/*
 * ResiClas-IA - AI Thinker ESP32-CAM (ESP32 clásico, NO ESP32-S3).
 * Arduino IDE: placa "AI Thinker ESP32-CAM", core ESP32 3.x.
 * Bibliotecas: ESP32Servo y ArduinoJson 7.x; WiFi/WebServer/Preferences son del core.
 * NO usa la cámara ni la microSD: GPIO 12/13/15 quedan para los servos.
 * Leer ../README.md ANTES de conectar motores. No desactivar el brownout.
 * Los límites son para servos POSICIONALES 0..180°, no de rotación continua.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <ESP32Servo.h>
#include <ArduinoJson.h>
#include <esp_system.h>
#include <esp_wifi.h>

// Cambiar también en Ajustes de la app. No publicar estas claves en producción.
constexpr char AP_SSID[] = "ECO-TOUCHLESS";
constexpr char AP_PASSWORD[] = "resiclas2026";
constexpr char API_KEY[] = "resiclas2026-control";
constexpr uint8_t AP_CHANNEL = 6;       // Elegir 1, 6 u 11 según interferencias.
constexpr uint8_t MAX_CLIENTS = 2;
constexpr uint8_t PINS[] = {12, 13, 15};
constexpr size_t NUM_SERVOS = 3;
constexpr int PULSE_MIN_US = 1000;      // Conservadores; calibrar con la ficha del servo.
constexpr int PULSE_MAX_US = 2000;      // NO ampliar sin comprobar topes mecánicos.
constexpr uint32_t SETTLE_MS = 800;     // Tiempo para completar el cierre, sin sensor de posición.
constexpr uint32_t COOLDOWN_MS = 600;   // Evita ciclos consecutivos demasiado rápidos.
constexpr bool DETACH_CLOSED = false;  // true ahorra torque, pero la tapa puede moverse libremente.
constexpr bool LEGACY_ENDPOINTS = true;

struct ServoConfig {
  char label[65];
  bool enabled;
  int closedAngle;
  int openAngle;
  uint32_t holdMs;
};
// Prototipos explícitos para que el preprocesador del Arduino IDE conozca los tipos.
bool decodeServos(JsonVariantConst value, ServoConfig* output, String& error);
void configDocument(JsonDocument& doc, const ServoConfig* values, uint32_t rev);

ServoConfig settings[NUM_SERVOS] = {
  {"Plastico", true, 0, 90, 3000},
  {"Papel_carton", true, 0, 90, 3000},
  {"Organico", true, 0, 90, 3000}
};
Servo motors[NUM_SERVOS];
WebServer server(80);
Preferences preferences;
SemaphoreHandle_t motorMutex;
bool storageReady = false;
bool hardwareReady = false;
bool hardwareFault = false;
int activeServo = -1;
bool closing = false;
bool needsPositioning = true;
size_t nextPositioning = 0;
uint32_t phaseStart = 0;
uint32_t activeHoldMs = 0; // Snapshot of the accepted command, never a UI timer.
uint32_t lastClosed = 0;
uint32_t revision = 1;
String deviceId;
String bootId;
String recentCommands[16];
size_t commandCursor = 0;

bool takeLock() { return xSemaphoreTake(motorMutex, pdMS_TO_TICKS(100)) == pdTRUE; }
void unlock() { xSemaphoreGive(motorMutex); }

void sendJson(int code, JsonDocument& doc) {
  String body;
  serializeJson(doc, body);
  server.client().setNoDelay(true);
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json; charset=utf-8", body);
}
void sendError(int code, const String& error) {
  JsonDocument doc;
  doc["ok"] = false;
  doc["error"] = error;
  sendJson(code, doc);
}
bool authorized() {
  // This is a private WPA2 network, not an Internet-facing API. No permissive CORS.
  if (server.hasHeader("Origin")) { sendError(403, "Browser origins are not allowed"); return false; }
  if (server.header("X-Api-Key") != API_KEY) { sendError(401, "Invalid control key"); return false; }
  return true;
}
bool validLabel(const char* label) {
  if (!label || strlen(label) > 64) return false;
  for (const unsigned char* p = reinterpret_cast<const unsigned char*>(label); *p; p++) {
    if (*p < 32 || *p == 127) return false;
  }
  return true;
}
// Etiqueta especial: un servo con "Plastico_Metal_Vidrio" abre para las tres clases,
// que siguen siendo distintas para la IA pero comparten una sola tapa.
const char* const GROUP_LABEL = "Plastico_Metal_Vidrio";
bool inGroup(const char* label) {
  return strcmp(label, "Plastico") == 0 || strcmp(label, "Metal") == 0 || strcmp(label, "Vidrio") == 0;
}
// 'configured' es la etiqueta guardada en un servo; 'incoming' la clase detectada.
bool labelMatches(const char* configured, const char* incoming) {
  if (strcmp(configured, incoming) == 0) return true;
  return strcmp(configured, GROUP_LABEL) == 0 && inGroup(incoming);
}
// Dos servos activos no pueden responder a una misma clase.
bool labelsOverlap(const char* a, const char* b) {
  if (strcmp(a, b) == 0) return true;
  if (strcmp(a, GROUP_LABEL) == 0) return inGroup(b);
  if (strcmp(b, GROUP_LABEL) == 0) return inGroup(a);
  return false;
}
bool decodeServos(JsonVariantConst value, ServoConfig* output, String& error) {
  if (!value.is<JsonArrayConst>() || value.size() != NUM_SERVOS) { error = "Exactly three servos required"; return false; }
  bool seen[NUM_SERVOS] = {false, false, false};
  for (JsonObjectConst item : value.as<JsonArrayConst>()) {
    if (!item["id"].is<int>() || !item["gpio"].is<int>() || !item["enabled"].is<bool>() ||
        !item["label"].is<const char*>() || !item["closedAngle"].is<int>() ||
        !item["openAngle"].is<int>() || !item["holdMs"].is<uint32_t>()) {
      error = "Missing or incorrectly typed servo fields"; return false;
    }
    int id = item["id"];
    if (id < 0 || id >= static_cast<int>(NUM_SERVOS) || seen[id] || item["gpio"].as<int>() != PINS[id]) {
      error = "Invalid servo id or GPIO"; return false;
    }
    seen[id] = true;
    const char* label = item["label"];
    bool enabled = item["enabled"];
    int closedAngle = item["closedAngle"];
    int openAngle = item["openAngle"];
    uint32_t hold = item["holdMs"];
    String trimmed = label;
    trimmed.trim();
    if (!validLabel(label) || (enabled && (trimmed.length() == 0 || strcmp(label, "Fondo") == 0)) ||
        closedAngle < 0 || closedAngle > 180 || openAngle < 0 || openAngle > 180 ||
        (enabled && closedAngle == openAngle) || hold < 500 || hold > 60000) {
      error = "Invalid label, angle (0..180) or holdMs (500..60000)"; return false;
    }
    strlcpy(output[id].label, label, sizeof(output[id].label));
    output[id].enabled = enabled;
    output[id].closedAngle = closedAngle;
    output[id].openAngle = openAngle;
    output[id].holdMs = hold;
  }
  for (size_t a = 0; a < NUM_SERVOS; a++) {
    for (size_t b = a + 1; b < NUM_SERVOS; b++) {
      if (output[a].enabled && output[b].enabled && labelsOverlap(output[a].label, output[b].label)) {
        error = "Enabled servos must have different labels (Plastico_Metal_Vidrio includes Plastico, Metal and Vidrio)"; return false;
      }
    }
  }
  return true;
}
void configDocument(JsonDocument& doc, const ServoConfig* values, uint32_t rev) {
  doc["device"] = "eco_touchless-esp32";
  doc["apiVersion"] = 1;
  doc["deviceId"] = deviceId;
  doc["bootId"] = bootId;
  doc["revision"] = rev;
  doc["angleMax"] = 180;
  JsonArray list = doc["servos"].to<JsonArray>();
  for (size_t i = 0; i < NUM_SERVOS; i++) {
    JsonObject item = list.add<JsonObject>();
    item["id"] = i;
    item["gpio"] = PINS[i];
    item["label"] = values[i].label;
    item["enabled"] = values[i].enabled;
    item["closedAngle"] = values[i].closedAngle;
    item["openAngle"] = values[i].openAngle;
    item["holdMs"] = values[i].holdMs;
  }
}
void loadSettings() {
  storageReady = preferences.begin("eco_touchless", false);
  if (!storageReady) { Serial.println("NVS unavailable: motion disabled"); return; }
  String raw = preferences.getString("config", "");
  if (raw.length() == 0) return;
  JsonDocument doc;
  ServoConfig loaded[NUM_SERVOS];
  String error;
  if (deserializeJson(doc, raw) || doc["apiVersion"] != 1 || !doc["revision"].is<uint32_t>() || doc["revision"].as<uint32_t>() == 0 || !decodeServos(doc["servos"], loaded, error)) {
    // Do not silently replace a corrupt calibration with possibly dangerous angles.
    storageReady = false;
    Serial.println("Stored configuration invalid: motion disabled. Inspect/erase NVS manually.");
    return;
  }
  memcpy(settings, loaded, sizeof(settings));
  revision = doc["revision"];
}
bool positionServo(size_t index, int angle) {
  if (!motors[index].attached()) {
    motors[index].setPeriodHertz(50);
    motors[index].attach(PINS[index], PULSE_MIN_US, PULSE_MAX_US);
  }
  if (!motors[index].attached()) { hardwareFault = true; return false; }
  motors[index].write(angle);
  return true;
}
// Independent task: a slow/disconnected HTTP client cannot block the close timer.
void motorTask(void*) {
  for (;;) {
    if (takeLock()) {
      uint32_t now = millis();
      if (storageReady && !hardwareFault) {
        if (activeServo >= 0) {
          const ServoConfig& config = settings[activeServo];
          if (!closing && static_cast<uint32_t>(now - phaseStart) >= activeHoldMs) {
            Serial.printf("CLOSE gpio=%d elapsed=%lu hold=%lu ms\n", PINS[activeServo],
                static_cast<unsigned long>(now - phaseStart), static_cast<unsigned long>(activeHoldMs));
            positionServo(activeServo, config.closedAngle);
            closing = true;
            phaseStart = now;
          } else if (closing && static_cast<uint32_t>(now - phaseStart) >= SETTLE_MS) {
            if (DETACH_CLOSED) motors[activeServo].detach();
            activeServo = -1;
            lastClosed = now;
          }
        }
        // Sequential boot/reconfiguration positioning avoids three startup surges.
        if (needsPositioning && activeServo < 0) {
          if (nextPositioning < NUM_SERVOS) {
            activeServo = static_cast<int>(nextPositioning++);
            closing = true;
            phaseStart = now;
            positionServo(activeServo, settings[activeServo].closedAngle);
          } else { needsPositioning = false; hardwareReady = true; }
        }
      }
      unlock();
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}
void handleStatus() {
  if (!takeLock()) { sendError(503, "Controller busy"); return; }
  JsonDocument doc;
  doc["device"] = "eco_touchless-esp32";
  doc["apiVersion"] = 1;
  doc["firmware"] = "1.1.0";
  doc["deviceId"] = deviceId;
  doc["bootId"] = bootId;
  doc["revision"] = revision;
  doc["ready"] = hardwareReady && !hardwareFault && storageReady;
  doc["activeServo"] = activeServo;
  doc["closing"] = closing;
  const uint32_t elapsed = static_cast<uint32_t>(millis() - phaseStart);
  doc["activeHoldMs"] = activeServo >= 0 && !closing ? activeHoldMs : 0;
  doc["remainingMs"] = activeServo >= 0 && !closing && elapsed < activeHoldMs ? activeHoldMs - elapsed : 0;
  doc["positionConfirmed"] = false; // No physical angle/limit sensor is installed.
  doc["uptimeMs"] = millis();
  doc["resetReason"] = static_cast<int>(esp_reset_reason());
  doc["clients"] = WiFi.softAPgetStationNum();
  doc["freeHeap"] = ESP.getFreeHeap();
  doc["storageReady"] = storageReady;
  doc["hardwareFault"] = hardwareFault;
  unlock();
  sendJson(200, doc);
}
void handleGetConfig() {
  if (!authorized()) return;
  if (!takeLock()) { sendError(503, "Controller busy"); return; }
  JsonDocument doc;
  configDocument(doc, settings, revision);
  unlock();
  sendJson(200, doc);
}
void handlePutConfig() {
  if (!authorized()) return;
  if (!server.hasArg("plain") || server.arg("plain").length() > 4096) { sendError(400, "Invalid body size"); return; }
  JsonDocument input;
  ServoConfig proposed[NUM_SERVOS];
  String error;
  if (deserializeJson(input, server.arg("plain")) || input["apiVersion"] != 1 || !decodeServos(input["servos"], proposed, error)) {
    sendError(400, error.length() ? error : "Invalid JSON or API version"); return;
  }
  if (!takeLock()) { sendError(503, "Controller busy"); return; }
  if (!storageReady || hardwareFault) { unlock(); sendError(503, "Storage or servo fault"); return; }
  if (activeServo >= 0 || needsPositioning || input["deviceId"].as<String>() != deviceId || input["bootId"].as<String>() != bootId ||
      !input["revision"].is<uint32_t>() || input["revision"].as<uint32_t>() != revision || revision == UINT32_MAX) {
    unlock(); sendError(409, "Busy, restarted or stale configuration; read config again"); return;
  }
  JsonDocument saved;
  configDocument(saved, proposed, revision + 1);
  String raw;
  serializeJson(saved, raw);
  // One NVS value = one consistent configuration; never write on each detection.
  if (preferences.putString("config", raw) != raw.length()) { unlock(); sendError(500, "Could not persist configuration"); return; }
  memcpy(settings, proposed, sizeof(settings));
  revision++;
  hardwareReady = false;
  needsPositioning = true;
  nextPositioning = 0;
  unlock();
  // Saving applies the three CLOSED positions sequentially. App requires confirmation.
  sendJson(200, saved);
}
void handleLabel(const String& label, bool modern) {
  if (!authorized()) return;
  if (label == "Fondo" || !validLabel(label.c_str()) || label.length() == 0) { sendError(422, "Label cannot actuate"); return; }
  String command = server.arg("requestId");
  if (modern && (command.length() < 8 || command.length() > 96)) { sendError(400, "requestId required (8..96 chars)"); return; }
  if (!takeLock()) { sendError(503, "Controller busy"); return; }
  if (modern && (server.arg("deviceId") != deviceId || server.arg("bootId") != bootId || server.arg("revision") != String(revision))) {
    unlock(); sendError(409, "Stale board/configuration"); return;
  }
  if (command.length()) {
    for (const String& seen : recentCommands) {
      if (seen == command) { unlock(); JsonDocument response; response["ok"] = true; response["duplicate"] = true; sendJson(200, response); return; }
    }
  }
  if (!storageReady || !hardwareReady || hardwareFault) { unlock(); sendError(503, "Servos not ready; consult status"); return; }
  if (activeServo >= 0 || static_cast<uint32_t>(millis() - lastClosed) < COOLDOWN_MS) { unlock(); sendError(409, "Servo cycle in progress"); return; }
  int target = -1;
  for (size_t i = 0; i < NUM_SERVOS; i++) if (settings[i].enabled && labelMatches(settings[i].label, label.c_str())) target = i;
  if (target < 0) { unlock(); sendError(422, "No enabled servo assigned to label"); return; }
  if (!positionServo(target, settings[target].openAngle)) { unlock(); sendError(503, "PWM allocation failed"); return; }
  activeServo = target;
  closing = false;
  phaseStart = millis();
  activeHoldMs = settings[target].holdMs;
  Serial.printf("OPEN gpio=%d hold=%lu ms boot=%s\n", PINS[target],
      static_cast<unsigned long>(activeHoldMs), bootId.c_str());
  if (command.length()) { recentCommands[commandCursor] = command; commandCursor = (commandCursor + 1) % 16; }
  JsonDocument response;
  response["ok"] = true;
  response["servo"] = target;
  response["gpio"] = PINS[target];
  response["holdMs"] = settings[target].holdMs;
  unlock();
  sendJson(200, response);  // ACK means scheduled/commanded, not sensor-confirmed position.
}
void setup() {
  Serial.begin(115200);
  deviceId = String(static_cast<uint32_t>(ESP.getEfuseMac() >> 32), HEX) + String(static_cast<uint32_t>(ESP.getEfuseMac()), HEX);
  bootId = String(esp_random(), HEX) + String(esp_random(), HEX);
  Serial.printf("ResiClas-IA boot, reset reason=%d\n", static_cast<int>(esp_reset_reason()));
  motorMutex = xSemaphoreCreateMutex();
  if (!motorMutex) { Serial.println("Fatal: mutex allocation failed"); return; }
  loadSettings();
  if (xTaskCreate(motorTask, "servo-timers", 4096, nullptr, 2, nullptr) != pdPASS) {
    hardwareFault = true;
    Serial.println("Fatal: motor task allocation failed");
  }
  WiFi.persistent(false);
  WiFi.mode(WIFI_AP); // AP only: never roam to another router during a servo cycle.
  WiFi.setSleep(false);
  WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0));
  const bool started = WiFi.softAP(AP_SSID, AP_PASSWORD, AP_CHANNEL, false, MAX_CLIENTS);
  esp_wifi_set_ps(WIFI_PS_NONE);
  // Default radio power; do not force maximum current on a marginal supply.
  Serial.printf("AP: %s, %s, IP %s\n", AP_SSID, started ? "ready" : "FAILED", WiFi.softAPIP().toString().c_str());
  const char* headers[] = {"X-Api-Key", "Origin"};
  server.collectHeaders(headers, 2);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/config", HTTP_GET, handleGetConfig);
  server.on("/config", HTTP_PUT, handlePutConfig);
  server.on("/classify", HTTP_GET, []() { handleLabel(server.arg("label"), true); });
  if (LEGACY_ENDPOINTS) {
    server.on("/plastico", HTTP_GET, []() { handleLabel("Plastico", false); });
    server.on("/papel", HTTP_GET, []() { handleLabel("Papel_carton", false); });
    server.on("/organico", HTTP_GET, []() { handleLabel("Organico", false); });
  }
  server.onNotFound([]() { sendError(404, "Unknown endpoint"); });
  server.begin();
}
void loop() {
  if (motorMutex) server.handleClient();
  delay(1); // Yield to Wi-Fi/RTOS; never delay for the lid-open timeout here.
}
