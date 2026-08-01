#include <AbsMouse.h>
#include <Keyboard.h>

// Python envia coordenadas 0..32767 relativas ao MONITOR PRIMARIO.
const long ESCALA = 32767;

void setup() {
  Serial.begin(115200);
  AbsMouse.init(ESCALA, ESCALA);
  Keyboard.begin();
  Serial.println("Arduino pronto (mouse + teclado)!");
}

void typeText(const String &text) {
  for (unsigned int i = 0; i < text.length(); i++) {
    Keyboard.write(text.charAt(i));
    delay(45);
  }
}

void pressKey(uint8_t key, const char *label) {
  Keyboard.releaseAll();
  delay(25);
  Keyboard.press(key);
  delay(80);
  Keyboard.release(key);
  delay(80);
  Keyboard.releaseAll();
  delay(40);
  if (label != nullptr && label[0] != '\0') {
    Serial.print("OK:");
    Serial.println(label);
  }
}

// Versao mais rapida que TECLA, mas ainda registra no jogo.
void pressKeyRapido(uint8_t key) {
  Keyboard.press(key);
  delay(20);
  Keyboard.release(key);
  delay(20);
}

void cliqueAbsoluto(long x, long y) {
  AbsMouse.move(x, y);
  delay(80);
  AbsMouse.press(MOUSE_LEFT);
  delay(40);
  AbsMouse.release(MOUSE_LEFT);
  delay(80);
}

uint8_t resolveKey(const String &key) {
  if (key == "TAB") return KEY_TAB;
  if (key == "ENTER") return KEY_RETURN;
  if (key == "BACKSPACE") return KEY_BACKSPACE;
  if (key == "F1") return KEY_F1;
  if (key == "F2") return KEY_F2;
  if (key == "F3") return KEY_F3;
  if (key == "F4") return KEY_F4;
  if (key == "F5") return KEY_F5;
  if (key == "F6") return KEY_F6;
  if (key == "F7") return KEY_F7;
  if (key == "F8") return KEY_F8;
  if (key == "F9") return KEY_F9;
  if (key == "F10") return KEY_F10;
  if (key == "F11") return KEY_F11;
  if (key == "F12") return KEY_F12;
  return 0;
}

void handleTecla(const String &keyRaw, bool rapido) {
  String key = keyRaw;
  key.trim();
  key.toUpperCase();

  uint8_t code = resolveKey(key);
  if (code == 0) {
    Serial.print("ERR:UNKNOWN ");
    Serial.println(key);
    return;
  }

  if (rapido) {
    pressKeyRapido(code);
  } else {
    pressKey(code, key.c_str());
  }
}

void loop() {
  if (!Serial.available()) {
    return;
  }

  String cmd = Serial.readStringUntil('\n');
  cmd.trim();

  if (cmd.startsWith("CLIQUE_RAPIDO")) {
    int p1 = cmd.indexOf(' ', 13);
    int p2 = cmd.indexOf(' ', p1 + 1);
    long x = cmd.substring(13, p1).toInt();
    long y = cmd.substring(p1 + 1, p2).toInt();
    int count = cmd.substring(p2 + 1).toInt();
    if (count < 1) count = 1;
    if (count > 10) count = 10;

    for (int i = 0; i < count; i++) {
      cliqueAbsoluto(x, y);
      if (i < count - 1) delay(55);
    }
  } else if (cmd.startsWith("CLIQUE")) {
    int espaco = cmd.indexOf(' ', 7);
    long x = cmd.substring(7, espaco).toInt();
    long y = cmd.substring(espaco + 1).toInt();
    cliqueAbsoluto(x, y);
  } else if (cmd.startsWith("DIGITAR ")) {
    String text = cmd.substring(8);
    Serial.print("Digitando: ");
    Serial.println(text);
    typeText(text);
  } else if (cmd.startsWith("TECLA_RAPIDA ")) {
    handleTecla(cmd.substring(13), true);
  } else if (cmd.startsWith("TECLA ")) {
    handleTecla(cmd.substring(6), false);
  } else if (cmd == "STOP") {
    Keyboard.releaseAll();
    Serial.println("OK:STOP");
  } else if (cmd == "PING") {
    Serial.println("OK:PONG");
  }
}
