from __future__ import annotations

import sys
import time
from pathlib import Path

import cv2
import mss
import numpy as np
import serial
from serial.serialutil import SerialException


SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "config.conf"
MOUSE_SCALE = 32767


def load_config() -> dict[str, str]:
    if not CONFIG_FILE.is_file():
        raise FileNotFoundError(f"Arquivo de configuracao nao encontrado: {CONFIG_FILE}")

    values: dict[str, str] = {}
    for raw_line in CONFIG_FILE.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip().upper()] = value.strip()
    return values


def get_float(config: dict[str, str], key: str, default: float) -> float:
    try:
        return float(config.get(key, default))
    except (TypeError, ValueError):
        return default


def get_int(config: dict[str, str], key: str, default: int) -> int:
    try:
        return int(config.get(key, default))
    except (TypeError, ValueError):
        return default


def connect_arduino(port: str, baud: int) -> serial.Serial:
    print(f"Conectando ao Arduino em {port} ({baud} baud)...", flush=True)
    connection = serial.Serial(port, baud, timeout=1)
    time.sleep(2)
    print("Arduino conectado.", flush=True)
    return connection


def pixel_to_arduino(
    screen_x: int,
    screen_y: int,
    monitor: dict[str, int],
) -> tuple[int, int]:
    relative_x = screen_x - monitor["left"]
    relative_y = screen_y - monitor["top"]
    width = max(1, monitor["width"] - 1)
    height = max(1, monitor["height"] - 1)
    arduino_x = round(relative_x / width * MOUSE_SCALE)
    arduino_y = round(relative_y / height * MOUSE_SCALE)
    return (
        max(0, min(MOUSE_SCALE, arduino_x)),
        max(0, min(MOUSE_SCALE, arduino_y)),
    )


def send_click(
    arduino: serial.Serial,
    screen_x: int,
    screen_y: int,
    monitor: dict[str, int],
) -> None:
    arduino_x, arduino_y = pixel_to_arduino(screen_x, screen_y, monitor)
    command = f"CLIQUE {arduino_x} {arduino_y}\n"
    arduino.write(command.encode("ascii"))
    arduino.flush()
    print(
        f"Imagem encontrada: clique tela=({screen_x},{screen_y}) "
        f"arduino=({arduino_x},{arduino_y})",
        flush=True,
    )


def main() -> int:
    config = load_config()
    port = config.get("ARDUINO_PORT", "COM7")
    baud = get_int(config, "ARDUINO_BAUD", 115200)
    image_name = config.get("IMAGE_FILE", "imagem.png")
    threshold = get_float(config, "MATCH_THRESHOLD", 0.80)
    check_interval = max(0.01, get_float(config, "CHECK_INTERVAL_S", 0.10))
    click_cooldown = max(0.0, get_float(config, "CLICK_COOLDOWN_S", 1.0))
    monitor_number = get_int(config, "MONITOR", 1)

    image_path = Path(image_name)
    if not image_path.is_absolute():
        image_path = SCRIPT_DIR / image_path

    template = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if template is None:
        print(f"ERRO: imagem nao encontrada ou invalida: {image_path}", flush=True)
        return 1

    template_height, template_width = template.shape[:2]

    try:
        arduino = connect_arduino(port, baud)
    except SerialException as exc:
        print(f"ERRO ao conectar ao Arduino: {exc}", flush=True)
        print("Confira ARDUINO_PORT no config.conf.", flush=True)
        return 1

    try:
        with mss.MSS() as screenshotter:
            if monitor_number < 1 or monitor_number >= len(screenshotter.monitors):
                print(
                    f"ERRO: monitor {monitor_number} invalido. "
                    f"Monitores disponiveis: 1 a {len(screenshotter.monitors) - 1}.",
                    flush=True,
                )
                return 1

            monitor = screenshotter.monitors[monitor_number]
            print(
                f"Monitorando {image_path.name} no monitor {monitor_number} "
                f"({monitor['width']}x{monitor['height']}) | confianca={threshold:.2f}",
                flush=True,
            )
            print("Pressione Ctrl+C para encerrar.", flush=True)
            last_click = 0.0

            while True:
                shot = np.asarray(screenshotter.grab(monitor))
                screen = cv2.cvtColor(shot, cv2.COLOR_BGRA2BGR)

                if (
                    template_width > screen.shape[1]
                    or template_height > screen.shape[0]
                ):
                    print("ERRO: a imagem de busca e maior que o monitor.", flush=True)
                    return 1

                result = cv2.matchTemplate(screen, template, cv2.TM_CCOEFF_NORMED)
                _, confidence, _, location = cv2.minMaxLoc(result)
                now = time.monotonic()

                if confidence >= threshold and now - last_click >= click_cooldown:
                    center_x = monitor["left"] + location[0] + template_width // 2
                    center_y = monitor["top"] + location[1] + template_height // 2
                    try:
                        send_click(arduino, center_x, center_y, monitor)
                        last_click = now
                    except (OSError, SerialException) as exc:
                        print(f"Arduino desconectado ({exc}). Reconectando...", flush=True)
                        try:
                            arduino.close()
                        except OSError:
                            pass
                        arduino = connect_arduino(port, baud)

                time.sleep(check_interval)
    except KeyboardInterrupt:
        print("\nBot encerrado pelo usuario.", flush=True)
    finally:
        try:
            arduino.close()
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERRO inesperado: {exc}", flush=True)
        sys.exit(1)
