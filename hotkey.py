#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Double-tap Ctrl hotkey for voice-for-agent.

Reads keyboard events straight from /dev/input so it does not depend on
GNOME custom shortcuts. Two clean Ctrl taps toggle speech: if nothing is
playing it speaks the current selection (or clipboard), otherwise it stops.

Privacy: keystrokes are never stored or sent anywhere. The daemon only
looks at Ctrl press/release timing and a flag for "another key was pressed
in between". Nothing else is logged.
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
RESCAN_SECONDS = 5.0
EV_KEY = 1
CTRL_CODES = {29, 97}  # KEY_LEFTCTRL, KEY_RIGHTCTRL
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


def open_devices(existing: dict[int, str]) -> dict[int, str]:
    known = set(existing.values())
    for path in sorted(glob.glob("/dev/input/event*")):
        if path in known:
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


def main() -> int:
    devices: dict[int, str] = open_devices({})
    if not devices:
        message = "no readable /dev/input devices; add the user to the input group"
        log(message)
        print(f"voice-for-agent hotkey: {message}", file=sys.stderr)
        return 1

    log(f"watching {len(devices)} input device(s)")
    last_tap = 0.0
    ctrl_down = False
    dirty = False
    last_scan = time.monotonic()

    while True:
        try:
            readable, _, _ = select.select(list(devices), [], [], 0.5)
        except (OSError, ValueError):
            readable = []

        for fd in readable:
            try:
                data = os.read(fd, EVENT.size * 64)
            except OSError:
                data = b""
            if not data:
                path = devices.pop(fd, "")
                try:
                    os.close(fd)
                except OSError:
                    pass
                if path:
                    log(f"device closed: {path}")
                continue
            for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _sec, _usec, etype, code, value = EVENT.unpack_from(data, offset)
                if etype != EV_KEY:
                    continue
                if code in CTRL_CODES:
                    if value == 1:
                        ctrl_down = True
                        dirty = False
                    elif value == 0 and ctrl_down:
                        ctrl_down = False
                        if dirty:
                            dirty = False
                            last_tap = 0.0
                        else:
                            now = time.monotonic()
                            if last_tap and now - last_tap <= DOUBLE_TAP_SECONDS:
                                last_tap = 0.0
                                trigger()
                            else:
                                last_tap = now
                    continue
                if value == 1:
                    if ctrl_down:
                        dirty = True
                    last_tap = 0.0

        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            last_scan = now
            devices = open_devices(devices)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
