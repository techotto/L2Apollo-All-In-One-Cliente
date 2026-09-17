from __future__ import annotations

import ctypes
from ctypes import wintypes

user32 = ctypes.windll.user32

SW_RESTORE = 9
SW_MAXIMIZE = 3
SW_SHOW = 5

EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)


def _window_title(hwnd: int) -> str:
    length = user32.GetWindowTextLengthW(hwnd)
    if length <= 0:
        return ""
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value


def find_window_by_title(substring: str) -> int | None:
    needle = substring.strip().lower()
    if not needle:
        return None

    found: list[int] = []

    def callback(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        title = _window_title(hwnd)
        if title and needle in title.lower():
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(EnumWindowsProc(callback), 0)
    return found[0] if found else None


def focus_window(hwnd: int, *, maximize: bool = False) -> bool:
    if not hwnd:
        return False
    try:
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, SW_RESTORE)
        elif maximize:
            user32.ShowWindow(hwnd, SW_MAXIMIZE)
        else:
            user32.ShowWindow(hwnd, SW_SHOW)
        user32.SetForegroundWindow(hwnd)
        return True
    except OSError:
        return False


def focus_game_window(title_substring: str, *, maximize: bool = True) -> bool:
    hwnd = find_window_by_title(title_substring)
    if hwnd is None:
        return False
    return focus_window(hwnd, maximize=maximize)
