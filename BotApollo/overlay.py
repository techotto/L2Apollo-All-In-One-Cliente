from __future__ import annotations

import ctypes
import threading
import time
import tkinter as tk
from collections.abc import Callable
from ctypes import wintypes
from dataclasses import dataclass


user32 = ctypes.windll.user32

WM_HOTKEY = 0x0312
MOD_NOREPEAT = 0x4000
PM_REMOVE = 0x0001

VK_MAP = {
    "F1": 0x70,
    "F2": 0x71,
    "F3": 0x72,
    "F4": 0x73,
    "F5": 0x74,
    "F6": 0x75,
    "F7": 0x76,
    "F8": 0x77,
    "F9": 0x78,
    "F10": 0x79,
    "F11": 0x7A,
    "F12": 0x7B,
    "PAUSE": 0x13,
    "SCROLL": 0x91,
}


@dataclass
class OverlayStatus:
    enabled: bool = True
    arduino_ok: bool = False
    fixed_pending: bool = False
    last_action: str = "aguardando..."


def _parse_hotkey(spec: str) -> tuple[int, int] | None:
    """Retorna (modifiers, vk) ou None. Ex.: F8, CTRL+SHIFT+F8, PAUSE."""
    raw = (spec or "").strip().upper().replace(" ", "")
    if not raw:
        return None

    mods = 0
    key = raw
    for part in raw.split("+"):
        if part in {"CTRL", "CONTROL"}:
            mods |= 0x0002
        elif part == "ALT":
            mods |= 0x0001
        elif part == "SHIFT":
            mods |= 0x0004
        elif part == "WIN":
            mods |= 0x0008
        else:
            key = part

    vk = VK_MAP.get(key)
    if vk is None and len(key) == 1:
        vk = ord(key)
    if vk is None:
        return None
    return mods, vk


class GlobalHotkeyWatcher:
    """
    RegisterHotKey em thread propria — funciona sem foco na janela
    (jogo em primeiro plano, outro app, etc.).
    """

    def __init__(
        self,
        *,
        hotkey: str,
        on_press: Callable[[], None],
        schedule: Callable[[Callable[[], None]], None],
        hotkey_id: int = 1,
    ) -> None:
        self._hotkey = hotkey
        self._on_press = on_press
        self._schedule = schedule
        self._hotkey_id = hotkey_id
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._ok = False
        self._last_fire = 0.0
        self.error = ""

    @property
    def ok(self) -> bool:
        return self._ok

    def start(self) -> None:
        self._thread = threading.Thread(
            target=self._loop,
            name="global-hotkey",
            daemon=True,
        )
        self._thread.start()
        for _ in range(50):
            if self._ok or self.error:
                break
            time.sleep(0.01)

    def stop(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.5)

    def _fire(self) -> None:
        now = time.monotonic()
        if now - self._last_fire < 0.35:
            return
        self._last_fire = now
        try:
            self._schedule(self._on_press)
        except Exception:
            pass

    def _loop(self) -> None:
        parsed = _parse_hotkey(self._hotkey)
        if parsed is None:
            self.error = "invalido"
            return

        mods, vk = parsed
        registered = False
        for attempt in (mods | MOD_NOREPEAT, mods):
            if user32.RegisterHotKey(None, self._hotkey_id, attempt, vk):
                registered = True
                self._ok = True
                break

        if not registered:
            self.error = "ocupado"
            return

        msg = wintypes.MSG()
        try:
            while not self._stop.is_set():
                while user32.PeekMessageW(
                    ctypes.byref(msg),
                    0,
                    WM_HOTKEY,
                    WM_HOTKEY,
                    PM_REMOVE,
                ):
                    if int(msg.wParam) == self._hotkey_id:
                        self._fire()
                self._stop.wait(0.03)
        finally:
            try:
                user32.UnregisterHotKey(None, self._hotkey_id)
            except OSError:
                pass
            self._ok = False


class BotOverlay:
    """Painel sem barra do Windows, sempre no topo, com fade e atalho global."""

    BG = "#12151a"
    BG_SOFT = "#1a1f27"
    FG = "#e8eaed"
    MUTED = "#8b929a"
    GREEN = "#3dd68c"
    GREEN_DIM = "#1e3d2f"
    AMBER = "#f0a020"
    AMBER_DIM = "#3d2e12"
    RED = "#f07178"
    RED_DIM = "#3a1e22"
    BLUE = "#5b9cff"
    BLUE_DIM = "#1a2a44"

    def __init__(
        self,
        *,
        on_toggle: Callable[[bool], None],
        on_quit: Callable[[], None],
        get_status: Callable[[], OverlayStatus],
        title: str = "Robo - L2 Apollo",
        hotkey: str = "F8",
    ) -> None:
        self._on_toggle = on_toggle
        self._on_quit = on_quit
        self._get_status = get_status
        self._title = title
        self._hotkey_spec = hotkey.strip() or "F8"
        self._enabled = True
        self._drag_x = 0
        self._drag_y = 0
        self._alpha = 0.0
        self._target_alpha = 0.72
        self._pulse_until = 0.0
        self._hotkey: GlobalHotkeyWatcher | None = None

        self.root = tk.Tk()
        self.root.title(title)
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", 0.0)
        self.root.resizable(False, False)
        self.root.configure(bg=self.BG)
        self.root.protocol("WM_DELETE_WINDOW", self._quit)
        self.root.geometry("+48+96")

        shell = tk.Frame(self.root, bg=self.BG, highlightthickness=1, highlightbackground="#2a313c")
        shell.pack(fill="both", expand=True)
        self._shell = shell

        pad = tk.Frame(shell, bg=self.BG, padx=8, pady=6)
        pad.pack(fill="both", expand=True)

        header = tk.Frame(pad, bg=self.BG)
        header.pack(fill="x")
        for widget in (header, pad, shell):
            widget.bind("<ButtonPress-1>", self._start_drag)
            widget.bind("<B1-Motion>", self._on_drag)

        self._title_lbl = tk.Label(
            header,
            text=title,
            fg=self.FG,
            bg=self.BG,
            font=("Segoe UI Semibold", 9),
            cursor="fleur",
            anchor="w",
        )
        self._title_lbl.pack(side="left", fill="x", expand=True)
        self._title_lbl.bind("<ButtonPress-1>", self._start_drag)
        self._title_lbl.bind("<B1-Motion>", self._on_drag)

        self._close_btn = tk.Label(
            header,
            text="✕",
            fg=self.MUTED,
            bg=self.BG,
            font=("Segoe UI", 8),
            cursor="hand2",
            padx=2,
        )
        self._close_btn.pack(side="right")
        self._close_btn.bind("<Button-1>", lambda _e: self._quit())
        self._close_btn.bind("<Enter>", lambda _e: self._close_btn.configure(fg=self.RED))
        self._close_btn.bind("<Leave>", lambda _e: self._close_btn.configure(fg=self.MUTED))

        self._subtitle = tk.Label(
            pad,
            text=f"{self._hotkey_spec} · arraste",
            fg=self.MUTED,
            bg=self.BG,
            font=("Segoe UI", 7),
            anchor="w",
        )
        self._subtitle.pack(fill="x", pady=(0, 4))

        self._btn = tk.Label(
            pad,
            text="ATIVO",
            font=("Segoe UI Semibold", 10),
            fg="#0b1a12",
            bg=self.GREEN,
            padx=8,
            pady=4,
            cursor="hand2",
        )
        self._btn.pack(fill="x")
        self._btn.bind("<Button-1>", lambda _e: self._toggle())

        status_row = tk.Frame(pad, bg=self.BG)
        status_row.pack(fill="x", pady=(5, 0))

        self._arduino_card = tk.Frame(status_row, bg=self.RED_DIM, padx=4, pady=2)
        self._arduino_card.pack(side="left", fill="x", expand=True, padx=(0, 3))
        self._arduino_dot = tk.Label(
            self._arduino_card, text="●", fg=self.RED, bg=self.RED_DIM, font=("Segoe UI", 7)
        )
        self._arduino_dot.pack(side="left")
        self._arduino_lbl = tk.Label(
            self._arduino_card,
            text="Machine off",
            fg=self.FG,
            bg=self.RED_DIM,
            font=("Segoe UI", 7),
            anchor="w",
        )
        self._arduino_lbl.pack(side="left", padx=(3, 0))

        self._fixed_card = tk.Frame(status_row, bg=self.BG_SOFT, padx=4, pady=2)
        self._fixed_card.pack(side="left", fill="x", expand=True, padx=(3, 0))
        self._fixed_dot = tk.Label(
            self._fixed_card, text="●", fg=self.MUTED, bg=self.BG_SOFT, font=("Segoe UI", 7)
        )
        self._fixed_dot.pack(side="left")
        self._fixed_lbl = tk.Label(
            self._fixed_card,
            text="Fixed —",
            fg=self.MUTED,
            bg=self.BG_SOFT,
            font=("Segoe UI", 7),
            anchor="w",
        )
        self._fixed_lbl.pack(side="left", padx=(3, 0))

        self._action_lbl = tk.Label(
            pad,
            text="...",
            fg=self.MUTED,
            bg=self.BG,
            font=("Segoe UI", 7),
            anchor="w",
            wraplength=168,
            justify="left",
        )
        self._action_lbl.pack(fill="x", pady=(4, 0))

        self.root.bind("<Escape>", lambda _e: self._quit())
        self._start_global_hotkey()

        self._refresh_ui()
        self.root.after(16, self._fade_tick)
        self.root.after(80, self._tick)

    def _start_global_hotkey(self) -> None:
        def schedule(cb: Callable[[], None]) -> None:
            self.root.after(0, cb)

        self._hotkey = GlobalHotkeyWatcher(
            hotkey=self._hotkey_spec,
            on_press=self._toggle,
            schedule=schedule,
        )
        self._hotkey.start()
        if self._hotkey.ok:
            self._subtitle.configure(text=f"{self._hotkey_spec} global · arraste")
        elif self._hotkey.error == "ocupado":
            self._subtitle.configure(text=f"{self._hotkey_spec} ocupado")
        elif self._hotkey.error == "invalido":
            self._subtitle.configure(text="atalho invalido")
        else:
            self._subtitle.configure(text="atalho falhou")

    def _start_drag(self, event: tk.Event) -> None:
        self._drag_x = event.x_root - self.root.winfo_x()
        self._drag_y = event.y_root - self.root.winfo_y()

    def _on_drag(self, event: tk.Event) -> None:
        x = event.x_root - self._drag_x
        y = event.y_root - self._drag_y
        self.root.geometry(f"+{x}+{y}")

    def _toggle(self) -> None:
        self._enabled = not self._enabled
        self._on_toggle(self._enabled)
        self._pulse_until = time.monotonic() + 0.42
        self._refresh_ui()

    def _quit(self) -> None:
        if self._hotkey is not None:
            self._hotkey.stop()
            self._hotkey = None
        self._on_quit()
        self.root.destroy()

    def _set_card(
        self,
        card: tk.Frame,
        dot: tk.Label,
        label: tk.Label,
        *,
        text: str,
        fg: str,
        bg: str,
    ) -> None:
        card.configure(bg=bg)
        dot.configure(fg=fg, bg=bg)
        label.configure(text=text, fg=self.FG if fg != self.MUTED else self.MUTED, bg=bg)

    def _refresh_ui(self) -> None:
        if self._enabled:
            self._btn.configure(text="ATIVO", bg=self.GREEN, fg="#0b1a12")
            self._shell.configure(highlightbackground="#2f4a3c")
        else:
            self._btn.configure(text="PAUSADO", bg=self.AMBER, fg="#1a1200")
            self._shell.configure(highlightbackground="#4a3a1c")

    def _fade_tick(self) -> None:
        now = time.monotonic()
        target = self._target_alpha
        if now < self._pulse_until:
            phase = int((self._pulse_until - now) * 12) % 2
            target = 0.55 if phase == 0 else 0.78

        step = 0.07
        if abs(self._alpha - target) < step:
            self._alpha = target
        elif self._alpha < target:
            self._alpha = min(target, self._alpha + step)
        else:
            self._alpha = max(target, self._alpha - step)

        try:
            self.root.attributes("-alpha", max(0.0, min(1.0, self._alpha)))
        except tk.TclError:
            return
        self.root.after(16, self._fade_tick)

    def _tick(self) -> None:
        try:
            status = self._get_status()
        except Exception:
            status = OverlayStatus()

        self._enabled = status.enabled
        self._refresh_ui()

        if status.arduino_ok:
            self._set_card(
                self._arduino_card,
                self._arduino_dot,
                self._arduino_lbl,
                text="Machine ok",
                fg=self.GREEN,
                bg=self.GREEN_DIM,
            )
        else:
            self._set_card(
                self._arduino_card,
                self._arduino_dot,
                self._arduino_lbl,
                text="Machine off",
                fg=self.RED,
                bg=self.RED_DIM,
            )

        if status.fixed_pending:
            self._set_card(
                self._fixed_card,
                self._fixed_dot,
                self._fixed_lbl,
                text="Fixed!",
                fg=self.BLUE,
                bg=self.BLUE_DIM,
            )
        else:
            self._set_card(
                self._fixed_card,
                self._fixed_dot,
                self._fixed_lbl,
                text="Fixed —",
                fg=self.MUTED,
                bg=self.BG_SOFT,
            )

        action = status.last_action or "aguardando..."
        self._action_lbl.configure(text=action)
        self.root.after(80, self._tick)

    def run(self) -> None:
        try:
            self.root.mainloop()
        finally:
            if self._hotkey is not None:
                self._hotkey.stop()
                self._hotkey = None
