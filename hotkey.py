#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Double-tap Ctrl hotkey for voice-for-agent.

Reads keyboard events straight from /dev/input so it does not depend on
GNOME custom shortcuts. Two clean Ctrl taps toggle speech: if nothing is
playing it speaks the current selection (or clipboard), otherwise it stops.

Privacy: keystrokes are never stored or sent anywhere. The detector only
looks at Ctrl press/release timing and a flag for "another key was pressed
in between". Nothing else is logged.

The detector is a pure function of (event, time) so it can be unit tested
without touching real keyboards. See tests/test_hotkey.py.
"""

from __future__ import annotations

import glob
import os
import select
import struct
import subprocess
import sys
import time
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
MENU = BASE_DIR / "menu.sh"
LOG = BASE_DIR / ".run" / "speak.log"

DOUBLE_TAP_SECONDS = 0.45
TRIGGER_COOLDOWN_SECONDS = 0.8
RESCAN_SECONDS = 5.0
RETRY_SECONDS = 60.0
DEDUP_SECONDS = 0.04
EV_KEY = 1
KEY_LEFTCTRL = 29
KEY_RIGHTCTRL = 97
CTRL_CODES = frozenset({KEY_LEFTCTRL, KEY_RIGHTCTRL})
EVENT = struct.Struct("=llHHi")


def log(message: str) -> None:
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(
                f"{time.strftime('%Y-%m-%d %H:%M:%S')} hotkey: {message}\n"
            )
    except OSError:
        pass


class DoubleCtrlDetector:
    """Detect two clean Ctrl taps inside a short window.

    A tap is clean when Ctrl goes down and up again without any other key
    being pressed while it is held. That keeps Ctrl+C, Ctrl+V and Ctrl+Z
    from counting, so normal typing never fires the hotkey.
    """

    def __init__(self, window: float = DOUBLE_TAP_SECONDS) -> None:
        self.window = window
        self.last_tap = 0.0
        self.ctrl_down = False
        self.dirty = False

    def feed(self, etype: int, code: int, value: int, now: float) -> bool:
        if etype != EV_KEY:
            return False
        if code in CTRL_CODES:
            if value == 1:
                self.ctrl_down = True
                self.dirty = False
            elif value == 0 and self.ctrl_down:
                self.ctrl_down = False
                if self.dirty:
                    self.dirty = False
                    self.last_tap = 0.0
                else:
                    if self.last_tap and now - self.last_tap <= self.window:
                        self.last_tap = 0.0
                        return True
                    self.last_tap = now
            return False
        if value == 1:
            if self.ctrl_down:
                self.dirty = True
            self.last_tap = 0.0
        return False


def supports_ctrl(path: str) -> bool:
    """Return True when the device can emit a Ctrl key.

    sysfs exposes a hex bitmap of key codes per event device. Reading it
    keeps cameras, power buttons and other noise out of the event loop.
    If the bitmap cannot be read, assume the device is usable.
    """
    name = os.path.basename(path)
    cap_path = f"/sys/class/input/{name}/device/capabilities/key"
    try:
        words = Path(cap_path).read_text(encoding="utf-8").split()
    except OSError:
        return True
    bits = 0
    for word in words:
        try:
            bits = (bits << 64) | int(word, 16)
        except ValueError:
            return True
    return bool((bits >> KEY_LEFTCTRL) & 1 or (bits >> KEY_RIGHTCTRL) & 1)


def open_devices(existing: dict[int, str]) -> dict[int, str]:
    known = set(existing.values())
    for path in sorted(glob.glob("/dev/input/event*")):
        if path in known or not supports_ctrl(path):
            continue
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        existing[fd] = path
    return existing


def trigger() -> None:
    log("double Ctrl: toggle speech")
    try:
        subprocess.Popen(
            ["bash", str(MENU), "toggle"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        log(f"cannot run menu.sh toggle: {exc}")


def close_device(devices: dict[int, str], fd: int) -> None:
    path = devices.pop(fd, "")
    try:
        os.close(fd)
    except OSError:
        pass
    if path:
        log(f"device closed: {path}")


def run(devices: dict[int, str]) -> None:
    detector = DoubleCtrlDetector()
    last_scan = time.monotonic()
    suppress_until = 0.0
    last_sig: tuple[int, int] | None = None
    last_sig_time = 0.0

    while True:
        if not devices:
            log(f"no readable input devices; retrying in {RETRY_SECONDS:.0f}s")
            time.sleep(RETRY_SECONDS)
            devices = open_devices(devices)
            continue

        try:
            readable, _, _ = select.select(list(devices), [], [], 0.5)
        except (OSError, ValueError):
            for fd in list(devices):
                close_device(devices, fd)
            continue

        for fd in readable:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:
                data = b""
            if not data:
                close_device(devices, fd)
                continue
            for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _sec, _usec, etype, code, value = EVENT.unpack_from(data, offset)
                now = time.monotonic()
                signature = (code, value)
                if (
                    etype == EV_KEY
                    and signature == last_sig
                    and now - last_sig_time < DEDUP_SECONDS
                ):
                    continue
                last_sig = signature
                last_sig_time = now
                if detector.feed(etype, code, value, now):
                    if now < suppress_until:
                        log("double Ctrl ignored (cooldown)")
                        continue
                    suppress_until = now + TRIGGER_COOLDOWN_SECONDS
                    trigger()

        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            last_scan = now
            devices = open_devices(devices)


def main() -> int:
    devices = open_devices({})
    if not devices:
        log("no readable /dev/input devices; is the user in the input group?")
    else:
        log(f"watching {len(devices)} input device(s)")
    try:
        run(devices)
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
