from __future__ import annotations

import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import mss
import numpy as np
import serial
from serial.serialutil import SerialException


SCRIPT_DIR = Path(__file__).resolve().parent
IMAGES_DIR = SCRIPT_DIR / "images"
CONFIG_FILE = SCRIPT_DIR / "config.conf"
DEFAULT_RULES_FILE = SCRIPT_DIR / "rules.conf"
MOUSE_SCALE = 32767
CLICK_SELF = "@self"

RULE_LINE_RE = re.compile(
    r"^(?P<when>.+?)\s*->\s*(?P<click>.+?)(?:\s*\|\s*(?P<threshold>[0-9.]+))?\s*$"
)


@dataclass
class Match:
    confidence: float
    center_x: int
    center_y: int


@dataclass
class Rule:
    index: int
    when_label: str
    click_label: str
    when_template: np.ndarray
    click_template: np.ndarray | None
    threshold: float | None = None

    @property
    def description(self) -> str:
        click_desc = "ela mesma" if self.click_template is None else self.click_label
        return f"se [{self.when_label}] -> clicar em [{click_desc}]"


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


def resolve_image(name: str) -> Path:
    cleaned = name.strip().strip('"').strip("'")
    path = Path(cleaned)
    if not path.is_absolute():
        path = SCRIPT_DIR / path
    if path.is_file():
        return path

    # Compat: imagem.png -> images/imagem.png
    if "/" not in cleaned and "\\" not in cleaned:
        fallback = IMAGES_DIR / cleaned
        if fallback.is_file():
            return fallback

    return path


def load_template(path: Path, label: str) -> np.ndarray:
    template = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if template is None:
        raise FileNotFoundError(f"Imagem invalida ou ausente ({label}): {path}")
    return template


def parse_rules_file(
    rules_path: Path,
    default_threshold: float,
) -> list[Rule]:
    if not rules_path.is_file():
        return []

    rules: list[Rule] = []
    for line_no, raw_line in enumerate(
        rules_path.read_text(encoding="utf-8-sig").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        match = RULE_LINE_RE.match(line)
        if not match:
            raise ValueError(
                f"Linha invalida em {rules_path.name}:{line_no}: {raw_line}\n"
                "Formato: condicao.png -> alvo.png | 0.85"
            )

        when_label = match.group("when").strip()
        click_label = match.group("click").strip()
        threshold_raw = match.group("threshold")
        threshold = float(threshold_raw) if threshold_raw else None

        when_path = resolve_image(when_label)
        when_template = load_template(when_path, f"WHEN {when_label}")

        click_template: np.ndarray | None
        if click_label.strip().lower() == CLICK_SELF.lower():
            click_template = None
        else:
            click_path = resolve_image(click_label)
            click_template = load_template(click_path, f"CLICK {click_label}")

        rules.append(
            Rule(
                index=len(rules) + 1,
                when_label=when_label,
                click_label=click_label,
                when_template=when_template,
                click_template=click_template,
                threshold=threshold,
            )
        )

    if not rules:
        return []

    return rules


def build_simple_rule(image_name: str) -> Rule:
    image_path = resolve_image(image_name)
    template = load_template(image_path, image_name)
    return Rule(
        index=1,
        when_label=image_name,
        click_label=CLICK_SELF,
        when_template=template,
        click_template=None,
    )


def load_rules(config: dict[str, str], default_threshold: float) -> tuple[list[Rule], str]:
    rules_file_name = config.get("RULES_FILE", "rules.conf").strip()
    rules_path = resolve_image(rules_file_name)

    rules = parse_rules_file(rules_path, default_threshold)
    if rules:
        return rules, f"regras ({rules_path.name}, {len(rules)} regra(s))"

    image_name = config.get("IMAGE_FILE", "images/imagem.png")
    return [build_simple_rule(image_name)], f"simples ({image_name})"


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
    message: str,
) -> None:
    arduino_x, arduino_y = pixel_to_arduino(screen_x, screen_y, monitor)
    command = f"CLIQUE {arduino_x} {arduino_y}\n"
    arduino.write(command.encode("ascii"))
    arduino.flush()
    print(f"{message} tela=({screen_x},{screen_y}) arduino=({arduino_x},{arduino_y})", flush=True)


def find_match(
    screen: np.ndarray,
    template: np.ndarray,
    monitor: dict[str, int],
    threshold: float,
) -> Match | None:
    template_height, template_width = template.shape[:2]
    if template_width > screen.shape[1] or template_height > screen.shape[0]:
        return None

    result = cv2.matchTemplate(screen, template, cv2.TM_CCOEFF_NORMED)
    _, confidence, _, location = cv2.minMaxLoc(result)
    if confidence < threshold:
        return None

    center_x = monitor["left"] + location[0] + template_width // 2
    center_y = monitor["top"] + location[1] + template_height // 2
    return Match(confidence=confidence, center_x=center_x, center_y=center_y)


def rule_threshold(rule: Rule, default_threshold: float) -> float:
    return rule.threshold if rule.threshold is not None else default_threshold


def evaluate_rule(
    screen: np.ndarray,
    monitor: dict[str, int],
    rule: Rule,
    default_threshold: float,
) -> tuple[Match | None, Match | None]:
    threshold = rule_threshold(rule, default_threshold)
    when_match = find_match(screen, rule.when_template, monitor, threshold)
    if when_match is None:
        return None, None

    if rule.click_template is None:
        return when_match, when_match

    click_match = find_match(screen, rule.click_template, monitor, threshold)
    return when_match, click_match


def main() -> int:
    config = load_config()
    port = config.get("ARDUINO_PORT", "COM7")
    baud = get_int(config, "ARDUINO_BAUD", 115200)
    default_threshold = get_float(config, "MATCH_THRESHOLD", 0.80)
    check_interval = max(0.01, get_float(config, "CHECK_INTERVAL_S", 0.10))
    click_cooldown = max(0.0, get_float(config, "CLICK_COOLDOWN_S", 1.0))
    monitor_number = get_int(config, "MONITOR", 1)

    try:
        rules, mode_label = load_rules(config, default_threshold)
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERRO de configuracao: {exc}", flush=True)
        return 1

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
                f"Modo {mode_label} | monitor {monitor_number} "
                f"({monitor['width']}x{monitor['height']}) | confianca padrao={default_threshold:.2f}",
                flush=True,
            )
            for rule in rules:
                print(f"  Regra {rule.index}: {rule.description}", flush=True)
            print("Pressione Ctrl+C para encerrar.", flush=True)

            last_click = 0.0
            while True:
                shot = np.asarray(screenshotter.grab(monitor))
                screen = cv2.cvtColor(shot, cv2.COLOR_BGRA2BGR)
                now = time.monotonic()

                if now - last_click >= click_cooldown:
                    for rule in rules:
                        when_match, click_match = evaluate_rule(
                            screen,
                            monitor,
                            rule,
                            default_threshold,
                        )
                        if when_match is None:
                            continue

                        if click_match is None:
                            print(
                                f"Regra {rule.index}: condicao [{rule.when_label}] ok "
                                f"({when_match.confidence:.2f}), mas alvo [{rule.click_label}] nao encontrado.",
                                flush=True,
                            )
                            break

                        threshold = rule_threshold(rule, default_threshold)
                        try:
                            if rule.click_template is None:
                                send_click(
                                    arduino,
                                    click_match.center_x,
                                    click_match.center_y,
                                    monitor,
                                    (
                                        f"Regra {rule.index}: [{rule.when_label}] "
                                        f"({when_match.confidence:.2f}) -> clique na condicao"
                                    ),
                                )
                            else:
                                send_click(
                                    arduino,
                                    click_match.center_x,
                                    click_match.center_y,
                                    monitor,
                                    (
                                        f"Regra {rule.index}: [{rule.when_label}] "
                                        f"({when_match.confidence:.2f}) -> [{rule.click_label}] "
                                        f"({click_match.confidence:.2f})"
                                    ),
                                )
                            last_click = now
                        except (OSError, SerialException) as exc:
                            print(f"Arduino desconectado ({exc}). Reconectando...", flush=True)
                            try:
                                arduino.close()
                            except OSError:
                                pass
                            arduino = connect_arduino(port, baud)
                        break

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
