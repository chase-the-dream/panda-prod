# tracker.py - sidecar process for PandaProd. Watches the Windows foreground window
# and sends {"app", "title", "pid", "ts"} as JSON over localhost UDP to tracker.gd.
# Stdlib only. Normally spawned by tracker.gd; can also be run by hand for testing:
#   python sidecar/tracker.py [--port 47823] [--interval 0.25] [--parent-pid N]
from __future__ import annotations  # the tuple[...] hints below on Python 3.7/3.8

import argparse
import ctypes
import json
import os
import socket
import sys
import time
from ctypes import wintypes

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SYNCHRONIZE = 0x00100000
WAIT_TIMEOUT = 0x102
HEARTBEAT_SECONDS = 2.0

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

user32.GetForegroundWindow.argtypes = []
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
user32.GetWindowTextLengthW.restype = ctypes.c_int
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD

kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)
]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL


def process_name(pid: int) -> str:
    """Exe name (e.g. "chrome.exe") for a pid, or "?" if it can't be opened (elevated)."""
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return "?"
    try:
        size = wintypes.DWORD(1024)
        buf = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return "?"
        return os.path.basename(buf.value)
    finally:
        kernel32.CloseHandle(handle)


def get_foreground() -> tuple[str, str, int]:
    """(app, title, pid) of the foreground window; ("", "", 0) if there is none."""
    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return "", "", 0
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return process_name(pid.value), buf.value, pid.value


def open_parent(pid: int):
    """Handle used to detect when the parent (Godot) exits, or None if unavailable."""
    return kernel32.OpenProcess(SYNCHRONIZE, False, pid) or None


def parent_alive(handle) -> bool:
    return kernel32.WaitForSingleObject(handle, 0) == WAIT_TIMEOUT


def main() -> int:
    parser = argparse.ArgumentParser(description="PandaProd active-window tracker sidecar")
    parser.add_argument("--port", type=int, default=47823)
    parser.add_argument("--interval", type=float, default=0.25)
    parser.add_argument("--parent-pid", type=int, default=0)
    args = parser.parse_args()
    # Window titles can contain characters the console codepage can't encode. No stdout at all
    # (pythonw) is fine: print() then does nothing.
    if sys.stdout is not None:
        sys.stdout.reconfigure(errors="replace")

    parent = open_parent(args.parent_pid) if args.parent_pid else None
    if args.parent_pid and parent is None:
        print(f"[tracker] parent pid {args.parent_pid} not found, exiting", flush=True)
        return 1

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = ("127.0.0.1", args.port)
    print(f"[tracker] sending to {target[0]}:{target[1]}", flush=True)

    # Our parent too: started through the py launcher, this console window belongs to py.exe.
    ignored_pids = {os.getpid(), os.getppid(), args.parent_pid} - {0}
    state = None  # (app, title, pid) last reported
    last_send = 0.0
    try:
        while True:
            if parent is not None and not parent_alive(parent):
                print("[tracker] parent exited, stopping", flush=True)
                break

            app, title, pid = get_foreground()
            # Focusing the pet or this sidecar's own console shouldn't count as switching apps.
            if pid not in ignored_pids:
                changed = state is None or (app, title) != state[:2]
                if changed:
                    state = (app, title, pid)
                    print(f"[tracker] {app or '(nothing)'} | {title}", flush=True)
            else:
                changed = False

            now = time.monotonic()
            if state is not None and (changed or now - last_send >= HEARTBEAT_SECONDS):
                packet = {"app": state[0], "title": state[1], "pid": state[2], "ts": time.time()}
                try:
                    sock.sendto(json.dumps(packet).encode("utf-8"), target)
                except OSError:
                    pass  # Nobody listening yet (ICMP port unreachable); retry on heartbeat.
                last_send = now

            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        if parent is not None:
            kernel32.CloseHandle(parent)
    return 0


if __name__ == "__main__":
    sys.exit(main())
