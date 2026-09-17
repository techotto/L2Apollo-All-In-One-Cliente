from __future__ import annotations

import ctypes
from ctypes import wintypes

import numpy as np

from win_focus import find_window_by_title

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

SRCCOPY = 0x00CC0020
BI_RGB = 0
DIB_RGB_COLORS = 0
PW_CLIENTONLY = 1
PW_RENDERFULLCONTENT = 2


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]


def _bitmap_to_bgr(hdc, hbmp, width: int, height: int) -> np.ndarray | None:
    if width <= 0 or height <= 0:
        return None
    bmi = BITMAPINFO()
    ctypes.memset(ctypes.byref(bmi), 0, ctypes.sizeof(bmi))
    bmi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.bmiHeader.biWidth = width
    bmi.bmiHeader.biHeight = -height  # top-down
    bmi.bmiHeader.biPlanes = 1
    bmi.bmiHeader.biBitCount = 32
    bmi.bmiHeader.biCompression = BI_RGB

    buf_len = width * height * 4
    buf = (ctypes.c_char * buf_len)()
    got = gdi32.GetDIBits(hdc, hbmp, 0, height, buf, ctypes.byref(bmi), DIB_RGB_COLORS)
    if got == 0:
        return None
    arr = np.frombuffer(buf, dtype=np.uint8).reshape((height, width, 4))
    # BGRA -> BGR
    return np.ascontiguousarray(arr[:, :, :3])


def grab_rect_gdi(left: int, top: int, width: int, height: int) -> np.ndarray | None:
    """Fallback GDI BitBlt da área da tela (sem mss)."""
    hdc = user32.GetDC(0)
    if not hdc:
        return None
    memdc = gdi32.CreateCompatibleDC(hdc)
    hbmp = gdi32.CreateCompatibleBitmap(hdc, width, height)
    old = gdi32.SelectObject(memdc, hbmp)
    ok = gdi32.BitBlt(memdc, 0, 0, width, height, hdc, left, top, SRCCOPY)
    img = _bitmap_to_bgr(memdc, hbmp, width, height) if ok else None
    gdi32.SelectObject(memdc, old)
    gdi32.DeleteObject(hbmp)
    gdi32.DeleteDC(memdc)
    user32.ReleaseDC(0, hdc)
    return img


def grab_window_print(hwnd: int) -> tuple[np.ndarray | None, dict | None]:
    """Fallback PrintWindow da janela do jogo (funciona quando BitBlt desktop falha)."""
    if not hwnd:
        return None, None
    rect = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return None, None
    left, top = int(rect.left), int(rect.top)
    width = int(rect.right - rect.left)
    height = int(rect.bottom - rect.top)
    if width < 2 or height < 2:
        return None, None

    hdc = user32.GetWindowDC(hwnd)
    if not hdc:
        return None, None
    memdc = gdi32.CreateCompatibleDC(hdc)
    hbmp = gdi32.CreateCompatibleBitmap(hdc, width, height)
    old = gdi32.SelectObject(memdc, hbmp)

    img = None
    for flags in (PW_RENDERFULLCONTENT, 0):
        if user32.PrintWindow(hwnd, memdc, flags):
            img = _bitmap_to_bgr(memdc, hbmp, width, height)
            if img is not None and img.size > 0:
                break
            img = None

    gdi32.SelectObject(memdc, old)
    gdi32.DeleteObject(hbmp)
    gdi32.DeleteDC(memdc)
    user32.ReleaseDC(hwnd, hdc)

    if img is None:
        return None, None
    monitor = {"left": left, "top": top, "width": width, "height": height}
    return img, monitor


def grab_game_window(title_substring: str) -> tuple[np.ndarray | None, dict | None]:
    hwnd = find_window_by_title(title_substring) if title_substring.strip() else None
    if hwnd is None:
        return None, None
    return grab_window_print(hwnd)


def grab_pil(monitor: dict) -> np.ndarray | None:
    """Fallback Pillow ImageGrab (se instalado)."""
    try:
        from PIL import ImageGrab
    except ImportError:
        return None
    left = int(monitor["left"])
    top = int(monitor["top"])
    right = left + int(monitor["width"])
    bottom = top + int(monitor["height"])
    try:
        img = ImageGrab.grab(bbox=(left, top, right, bottom), all_screens=True)
    except TypeError:
        img = ImageGrab.grab(bbox=(left, top, right, bottom))
    except Exception:
        return None
    rgb = np.asarray(img)
    if rgb.ndim != 3 or rgb.size == 0:
        return None
    # RGB -> BGR
    return np.ascontiguousarray(rgb[:, :, ::-1])
