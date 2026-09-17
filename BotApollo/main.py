from __future__ import annotations

import re
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import mss
import numpy as np
import serial
from serial.serialutil import SerialException

from overlay import BotOverlay, OverlayStatus
from screen_capture import grab_game_window, grab_pil, grab_rect_gdi
from win_focus import focus_game_window


SCRIPT_DIR = Path(__file__).resolve().parent
IMAGES_DIR = SCRIPT_DIR / "images"
CONFIG_FILE = SCRIPT_DIR / "config.conf"
DEFAULT_RULES_FILE = SCRIPT_DIR / "rules.conf"
FIXED_FLAG = Path(r"C:\Users\Public\l2apollo.botapollo.fixed")
MOUSE_SCALE = 32767
CLICK_SELF = "@self"
CAPTURE_RETRIES = 3
RESTART_DELAY_S = 3.0
_CAPTURE_FAIL_NOTE_TS = 0.0


def enable_dpi_awareness() -> None:
    """Evita BitBlt/mss falhar com DPI scaling do Windows."""
    if sys.platform != "win32":
        return
    try:
        import ctypes

        try:
            # Per-monitor v2 quando disponivel
            ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
        except Exception:
            try:
                ctypes.windll.shcore.SetProcessDpiAwareness(2)
            except Exception:
                ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass


def open_screenshotter():
    return mss.mss()


def close_screenshotter(screenshotter) -> None:
    if screenshotter is None:
        return
    try:
        screenshotter.close()
    except Exception:
        pass


def resolve_monitor(screenshotter, monitor_number: int) -> dict | None:
    if monitor_number < 1 or monitor_number >= len(screenshotter.monitors):
        return None
    return dict(screenshotter.monitors[monitor_number])


def _note_capture_fail(runtime: "BotRuntime", msg: str) -> None:
    global _CAPTURE_FAIL_NOTE_TS
    now = time.monotonic()
    if now - _CAPTURE_FAIL_NOTE_TS < 5.0:
        return
    _CAPTURE_FAIL_NOTE_TS = now
    print(f"AVISO: {msg}", flush=True)
    runtime.note(msg)


def grab_screen_bgr(
    screenshotter,
    monitor: dict,
    monitor_number: int,
    runtime: "BotRuntime",
    game_title: str = "",
):
    """1) mss/BitBlt → 2) GDI BitBlt → 3) PrintWindow do jogo → 4) Pillow.

    Nunca derruba o loop/Machine. Devolve (bgr|None, screenshotter, monitor).
    """
    last_err: Exception | str | None = None

    # --- 1) mss (BitBlt) ---
    for attempt in range(1, CAPTURE_RETRIES + 1):
        try:
            if screenshotter is None:
                screenshotter = open_screenshotter()
                monitor = resolve_monitor(screenshotter, monitor_number) or monitor
            raw = screenshotter.grab(monitor)
            shot = np.asarray(raw)
            if shot.ndim != 3 or shot.shape[2] < 3 or shot.size == 0:
                raise RuntimeError("frame mss vazio")
            return cv2.cvtColor(shot, cv2.COLOR_BGRA2BGR), screenshotter, monitor
        except Exception as exc:
            last_err = exc
            close_screenshotter(screenshotter)
            screenshotter = None
            time.sleep(0.04 * attempt)

    # --- 2) GDI BitBlt direto na area do monitor ---
    try:
        gdi = grab_rect_gdi(
            int(monitor["left"]),
            int(monitor["top"]),
            int(monitor["width"]),
            int(monitor["height"]),
        )
        if gdi is not None and gdi.size > 0:
            runtime.note("captura: fallback GDI")
            return gdi, screenshotter, monitor
    except Exception as exc:
        last_err = exc

    # --- 3) PrintWindow da janela do jogo ---
    try:
        win_img, win_mon = grab_game_window(game_title)
        if win_img is not None and win_mon is not None:
            runtime.note("captura: fallback janela")
            return win_img, screenshotter, win_mon
    except Exception as exc:
        last_err = exc

    # --- 4) Pillow ImageGrab (se tiver) ---
    try:
        pil = grab_pil(monitor)
        if pil is not None and pil.size > 0:
            runtime.note("captura: fallback PIL")
            return pil, screenshotter, monitor
    except Exception as exc:
        last_err = exc

    _note_capture_fail(runtime, f"captura falhou ({last_err})")
    if screenshotter is None:
        try:
            screenshotter = open_screenshotter()
            monitor = resolve_monitor(screenshotter, monitor_number) or monitor
        except Exception:
            pass
    return None, screenshotter, monitor

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


class BotRuntime:
    def __init__(self) -> None:
        self.enabled = True
        self.arduino_ok = False
        self.fixed_pending = False
        self.last_action = "iniciando..."
        self.stop = False
        self.machine_fail_alerted = False
        self._lock = threading.Lock()

    def set_enabled(self, value: bool) -> None:
        with self._lock:
            self.enabled = value
            self.last_action = "ATIVO" if value else "PAUSADO"

    def snapshot(self) -> OverlayStatus:
        with self._lock:
            return OverlayStatus(
                enabled=self.enabled,
                arduino_ok=self.arduino_ok,
                fixed_pending=self.fixed_pending,
                last_action=self.last_action,
            )

    def note(self, text: str) -> None:
        with self._lock:
            self.last_action = text


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


def get_bool(config: dict[str, str], key: str, default: bool) -> bool:
    raw = config.get(key)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on", "sim"}


def resolve_image(name: str) -> Path:
    cleaned = name.strip().strip('"').strip("'")
    path = Path(cleaned)
    if not path.is_absolute():
        path = SCRIPT_DIR / path
    if path.is_file():
        return path

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


def connect_arduino(port: str, baud: int, *, settle_s: float = 2.0) -> serial.Serial:
    print(f"Conectando Machine (Apollo) em {port} ({baud} baud)...", flush=True)
    connection = serial.Serial(port, baud, timeout=1)
    time.sleep(settle_s)
    print(f"Machine (Apollo) conectada em {port}.", flush=True)
    return connection


def _normalize_com(port: str) -> str:
    raw = port.strip().upper().replace(" ", "")
    if not raw:
        return ""
    if raw.isdigit():
        return f"COM{raw}"
    if raw.startswith("COM"):
        return raw
    return raw


def _port_looks_like_machine(description: str, hwid: str, manufacturer: str) -> bool:
    blob = f"{description} {hwid} {manufacturer}".lower()
    needles = (
        "arduino",
        "ch340",
        "ch341",
        "cp210",
        "ftdi",
        "usb serial",
        "usb-serial",
        "leonardo",
        "promicro",
        "sparkfun",
        "cdc",
    )
    return any(n in blob for n in needles)


def _banner_looks_like_machine(text: str) -> bool:
    low = text.lower()
    return ("pronto" in low) or ("arduino" in low) or ("mouse" in low and "teclado" in low)


def list_candidate_com_ports(preferred: str, scan_max: int) -> list[str]:
    """
    Ordem: porta preferida (se houver) -> COM1, COM2, COM3... ate SCAN_MAX.
    """
    preferred_n = _normalize_com(preferred)
    auto = preferred_n in {"", "AUTO", "AUTODETECT", "SCAN"}

    ordered: list[str] = []
    seen: set[str] = set()

    def add(port: str) -> None:
        p = _normalize_com(port)
        if not p or p in seen:
            return
        seen.add(p)
        ordered.append(p)

    if not auto and preferred_n:
        add(preferred_n)

    existing: set[str] = set()
    try:
        from serial.tools import list_ports

        for info in list_ports.comports():
            dev = _normalize_com(info.device or "")
            if dev:
                existing.add(dev)
    except Exception:
        pass

    for idx in range(1, max(1, scan_max) + 1):
        port = f"COM{idx}"
        # Se o Windows listou portas, pula as que nao existem (mais rapido)
        if existing and port not in existing:
            continue
        add(port)

    if not ordered:
        for idx in range(1, max(1, scan_max) + 1):
            add(f"COM{idx}")

    return ordered


def probe_machine_port(port: str, baud: int) -> serial.Serial | None:
    """Abre a porta e valida se parece a Machine (banner ou porta tipica)."""
    ser: serial.Serial | None = None
    try:
        ser = serial.Serial(port, baud, timeout=0.4)
        # Leonardo/Pro Micro reinicia ao abrir serial
        time.sleep(1.6)
        chunks: list[str] = []
        deadline = time.monotonic() + 1.2
        while time.monotonic() < deadline:
            waiting = ser.in_waiting
            if waiting:
                chunks.append(ser.read(waiting).decode("utf-8", errors="ignore"))
                if _banner_looks_like_machine("".join(chunks)):
                    ser.timeout = 1
                    return ser
            else:
                time.sleep(0.05)

        banner = "".join(chunks)
        if _banner_looks_like_machine(banner):
            ser.timeout = 1
            return ser

        # Sem banner: ainda aceita se a porta estiver listada como Arduino-like
        try:
            from serial.tools import list_ports

            for info in list_ports.comports():
                if _normalize_com(info.device or "") != _normalize_com(port):
                    continue
                if _port_looks_like_machine(
                    info.description or "",
                    info.hwid or "",
                    info.manufacturer or "",
                ):
                    ser.timeout = 1
                    return ser
        except Exception:
            pass

        # Ultimo recurso: se abriu COM e nao deu erro, e so restou esta
        # (quem chama decide). Aqui devolvemos None pra continuar o scan.
        ser.close()
        return None
    except (OSError, SerialException, ValueError):
        if ser is not None:
            try:
                ser.close()
            except Exception:
                pass
        return None


def _alert_machine_failed(scan_max: int) -> None:
    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(
            0,
            (
                f"Machine (Apollo) nao encontrada.\n\n"
                f"Varri COM1 ate COM{scan_max} e nenhuma respondeu.\n"
                f"Conecte o cabo USB e reinicie o Robo, ou defina\n"
                f"ARDUINO_PORT=COMx no config.conf."
            ),
            "Robo - L2 Apollo",
            0x10,  # MB_ICONERROR
        )
    except Exception:
        pass


def find_machine(
    preferred: str,
    baud: int,
    scan_max: int,
    runtime: BotRuntime | None = None,
) -> tuple[serial.Serial | None, str]:
    """
    Tenta a porta preferida e depois COM1, COM2... ate achar a Machine.
    Retorna (conexao, porta) ou (None, '').
    """
    preferred_n = _normalize_com(preferred)
    auto = preferred_n in {"", "AUTO", "AUTODETECT", "SCAN"}
    candidates = list_candidate_com_ports(preferred, scan_max)
    print(
        f"Procurando Machine (Apollo) em {len(candidates)} porta(s) "
        f"(ate COM{scan_max})...",
        flush=True,
    )
    if runtime is not None:
        runtime.note(f"procurando ate COM{scan_max}...")

    for port in candidates:
        if runtime is not None and runtime.stop:
            return None, ""
        if runtime is not None:
            runtime.note(f"testando {port}...")
        print(f"  Testando {port}...", flush=True)
        found = probe_machine_port(port, baud)
        if found is not None:
            print(f"Machine (Apollo) encontrada em {port}.", flush=True)
            if runtime is not None:
                runtime.machine_fail_alerted = False
                runtime.note(f"Machine ok ({port})")
            return found, port

    # Porta fixa no config: tenta abrir mesmo sem banner (compat).
    if not auto and preferred_n:
        try:
            if runtime is not None:
                runtime.note(f"abrindo {preferred_n}...")
            ser = connect_arduino(preferred_n, baud, settle_s=1.8)
            if runtime is not None:
                runtime.machine_fail_alerted = False
                runtime.note(f"Machine ok ({preferred_n})")
            return ser, preferred_n
        except (OSError, SerialException) as exc:
            print(f"Falha em {preferred_n}: {exc}", flush=True)

    fail_msg = f"FALHOU: Machine nao achada ate COM{scan_max}"
    print(fail_msg, flush=True)
    if runtime is not None:
        runtime.note(fail_msg)
        if not runtime.machine_fail_alerted:
            runtime.machine_fail_alerted = True
            _alert_machine_failed(scan_max)
    else:
        _alert_machine_failed(scan_max)
    return None, ""


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


def is_fixed_rule(rule: Rule) -> bool:
    label = f"{rule.when_label} {rule.click_label}".lower()
    return "fixed" in label


def ordered_rules_for_tick(rules: list[Rule]) -> list[Rule]:
    """
    Fixed so roda quando o script Delphi emitir o pedido
    (arquivo C:\\Users\\Public\\l2apollo.botapollo.fixed).
    Sem o sinal: ignora regras Fixed (morte no meio do evento nao clica).
    """
    fixed_rules = [r for r in rules if is_fixed_rule(r)]
    other_rules = [r for r in rules if not is_fixed_rule(r)]
    if FIXED_FLAG.is_file():
        return fixed_rules + other_rules
    return other_rules


def maybe_focus_game(
    runtime: BotRuntime,
    *,
    enabled: bool,
    title: str,
    maximize: bool,
    was_pending: bool,
    now_pending: bool,
) -> None:
    if not enabled or not title.strip():
        return
    if now_pending and not was_pending:
        ok = focus_game_window(title, maximize=maximize)
        msg = "jogo em foco" if ok else f"janela nao achada ({title})"
        runtime.note(msg)
        print(f"Fixed: {msg}", flush=True)


def bot_loop(config: dict[str, str], runtime: BotRuntime) -> int:
    preferred_port = config.get("ARDUINO_PORT", "AUTO")
    baud = get_int(config, "ARDUINO_BAUD", 115200)
    scan_max = get_int(config, "ARDUINO_SCAN_MAX", 40)
    rescan_every = max(3.0, get_float(config, "ARDUINO_RESCAN_S", 8.0))
    default_threshold = get_float(config, "MATCH_THRESHOLD", 0.80)
    check_interval = max(0.01, get_float(config, "CHECK_INTERVAL_S", 0.10))
    click_cooldown = max(0.0, get_float(config, "CLICK_COOLDOWN_S", 1.0))
    monitor_number = get_int(config, "MONITOR", 1)
    focus_on_fixed = get_bool(config, "FOCUS_GAME_ON_FIXED", True)
    game_title = config.get("GAME_WINDOW_TITLE", "Lineage").strip()
    maximize_game = get_bool(config, "GAME_WINDOW_MAXIMIZE", True)

    try:
        rules, mode_label = load_rules(config, default_threshold)
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERRO de configuracao: {exc}", flush=True)
        runtime.note(f"erro config: {exc}")
        return 1

    arduino: serial.Serial | None = None
    active_port = ""
    arduino, active_port = find_machine(preferred_port, baud, scan_max, runtime)
    runtime.arduino_ok = arduino is not None
    if arduino is None:
        runtime.note("Machine off — continua procurando")
    next_rescan = time.monotonic() + rescan_every

    screenshotter = None
    try:
        screenshotter = open_screenshotter()
        monitor = resolve_monitor(screenshotter, monitor_number)
        if monitor is None:
            print(
                f"ERRO: monitor {monitor_number} invalido. "
                f"Monitores disponiveis: 1 a {len(screenshotter.monitors) - 1}.",
                flush=True,
            )
            runtime.note("monitor invalido")
            return 1

        print(
            f"Modo {mode_label} | monitor {monitor_number} "
            f"({monitor['width']}x{monitor['height']}) | confianca padrao={default_threshold:.2f}",
            flush=True,
        )
        for rule in rules:
            print(f"  Regra {rule.index}: {rule.description}", flush=True)
        print("Overlay: ATIVO/PAUSADO | Ctrl+C ou Sair na janela.", flush=True)

        last_click = 0.0
        was_fixed = False
        while not runtime.stop:
            if arduino is None and time.monotonic() >= next_rescan:
                arduino, active_port = find_machine(
                    preferred_port, baud, scan_max, runtime
                )
                runtime.arduino_ok = arduino is not None
                next_rescan = time.monotonic() + rescan_every

            fixed_now = FIXED_FLAG.is_file()
            runtime.fixed_pending = fixed_now
            maybe_focus_game(
                runtime,
                enabled=focus_on_fixed,
                title=game_title,
                maximize=maximize_game,
                was_pending=was_fixed,
                now_pending=fixed_now,
            )
            was_fixed = fixed_now

            if not runtime.enabled:
                time.sleep(check_interval)
                continue

            if arduino is None:
                time.sleep(check_interval)
                continue

            if screenshotter is None:
                try:
                    screenshotter = open_screenshotter()
                    monitor = resolve_monitor(screenshotter, monitor_number) or monitor
                except Exception as exc:
                    runtime.note(f"mss: {exc}")
                    time.sleep(check_interval)
                    continue

            screen, screenshotter, monitor = grab_screen_bgr(
                screenshotter,
                monitor,
                monitor_number,
                runtime,
                game_title=game_title,
            )
            if screen is None:
                time.sleep(check_interval)
                continue

            now = time.monotonic()

            active_rules = ordered_rules_for_tick(rules)
            effective_cooldown = (
                min(click_cooldown, 0.35) if fixed_now else click_cooldown
            )
            if now - last_click >= effective_cooldown:
                for rule in active_rules:
                    when_match, click_match = evaluate_rule(
                        screen,
                        monitor,
                        rule,
                        default_threshold,
                    )
                    if when_match is None:
                        continue

                    if click_match is None:
                        msg = (
                            f"Regra {rule.index}: [{rule.when_label}] ok, "
                            f"alvo [{rule.click_label}] nao achado"
                        )
                        print(msg, flush=True)
                        runtime.note(msg)
                        break

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
                        runtime.note(f"clicou regra {rule.index}")
                    except (OSError, SerialException) as exc:
                        print(f"Machine desconectada ({exc}). Reconectando...", flush=True)
                        runtime.arduino_ok = False
                        runtime.note("reconnect Machine...")
                        try:
                            arduino.close()
                        except OSError:
                            pass
                        arduino = None
                        active_port = ""
                        arduino, active_port = find_machine(
                            preferred_port, baud, scan_max, runtime
                        )
                        runtime.arduino_ok = arduino is not None
                        next_rescan = time.monotonic() + rescan_every
                    break

            time.sleep(check_interval)
    except KeyboardInterrupt:
        print("\nBot encerrado pelo usuario.", flush=True)
        runtime.note("encerrado")
    finally:
        # Nao seta runtime.stop aqui — deixa o worker reiniciar se caiu sozinho.
        close_screenshotter(screenshotter)
        if arduino is not None:
            try:
                arduino.close()
            except OSError:
                pass
            runtime.arduino_ok = False

    return 0


def main() -> int:
    enable_dpi_awareness()
    config = load_config()
    runtime = BotRuntime()
    use_ui = get_bool(config, "UI_ENABLED", True)

    if not use_ui:
        while not runtime.stop:
            try:
                code = bot_loop(config, runtime)
                if runtime.stop or code == 0:
                    return 0 if runtime.stop else code
                print(
                    f"Loop saiu com codigo {code}. Reiniciando em {RESTART_DELAY_S:.0f}s...",
                    flush=True,
                )
                runtime.note("reiniciando loop...")
            except KeyboardInterrupt:
                print("\nBot encerrado pelo usuario.", flush=True)
                return 0
            except Exception as exc:
                print(f"ERRO no loop: {exc}. Reiniciando...", flush=True)
                runtime.note(f"recupera: {exc}")
            time.sleep(RESTART_DELAY_S)
        return 0

    result: dict[str, int] = {"code": 0}

    def worker() -> None:
        while not runtime.stop:
            try:
                result["code"] = bot_loop(config, runtime)
                if runtime.stop:
                    break
                print(
                    f"Loop saiu (codigo {result['code']}). "
                    f"Reiniciando em {RESTART_DELAY_S:.0f}s...",
                    flush=True,
                )
                runtime.note("reiniciando loop...")
            except Exception as exc:
                print(f"ERRO inesperado no loop: {exc}", flush=True)
                runtime.note(f"recupera: {exc}")
                result["code"] = 1
                if runtime.stop:
                    break
            time.sleep(RESTART_DELAY_S)

    thread = threading.Thread(target=worker, name="bot-loop", daemon=True)
    thread.start()

    def on_toggle(enabled: bool) -> None:
        runtime.set_enabled(enabled)
        print(f"Bot {'ATIVO' if enabled else 'PAUSADO'}", flush=True)

    def on_quit() -> None:
        runtime.stop = True
        print("Saindo pela interface...", flush=True)

    hotkey = config.get("UI_HOTKEY", "F8").strip() or "F8"
    overlay = BotOverlay(
        on_toggle=on_toggle,
        on_quit=on_quit,
        get_status=runtime.snapshot,
        title="Robo - L2 Apollo",
        hotkey=hotkey,
    )
    overlay.run()

    runtime.stop = True
    thread.join(timeout=5.0)
    return result.get("code", 0)


if __name__ == "__main__":
    try:
        # Uma instancia so: se ja tiver Robo desta pasta, mata e sobe o novo.
        import atexit
        import os

        logs = SCRIPT_DIR / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        pid_path = logs / "robo.pid"

        def _pid_alive(pid: int) -> bool:
            if pid <= 0:
                return False
            try:
                import ctypes

                SYNCHRONIZE = 0x00100000
                h = ctypes.windll.kernel32.OpenProcess(SYNCHRONIZE, False, pid)
                if h:
                    ctypes.windll.kernel32.CloseHandle(h)
                    return True
            except Exception:
                pass
            try:
                os.kill(pid, 0)
                return True
            except OSError:
                return False

        if pid_path.is_file():
            try:
                old = int(pid_path.read_text(encoding="utf-8").strip() or "0")
            except ValueError:
                old = 0
            if old and old != os.getpid() and _pid_alive(old):
                try:
                    import ctypes

                    PROCESS_TERMINATE = 0x0001
                    handle = ctypes.windll.kernel32.OpenProcess(
                        PROCESS_TERMINATE, False, old
                    )
                    if handle:
                        ctypes.windll.kernel32.TerminateProcess(handle, 1)
                        ctypes.windll.kernel32.CloseHandle(handle)
                except Exception:
                    try:
                        os.kill(old, 9)
                    except OSError:
                        pass
                time.sleep(0.3)

        pid_path.write_text(str(os.getpid()), encoding="utf-8")

        def _clear_pid() -> None:
            try:
                if pid_path.is_file() and pid_path.read_text(encoding="utf-8").strip() == str(
                    os.getpid()
                ):
                    pid_path.unlink(missing_ok=True)
            except OSError:
                pass

        atexit.register(_clear_pid)

        sys.exit(main())
    except Exception as exc:
        print(f"ERRO inesperado: {exc}", flush=True)
        sys.exit(1)
