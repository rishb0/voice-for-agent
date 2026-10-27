#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unit tests for the double-tap Ctrl detector."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from hotkey import DoubleCtrlDetector, EV_KEY  # noqa: E402

KEY_A = 30
PRESS = 1
RELEASE = 0
REPEAT = 2
EV_SYN = 0


class DoubleCtrlDetectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = DoubleCtrlDetector(window=0.45)

    def tap(self, start: float, code: int = 29) -> bool:
        self.assertFalse(self.detector.feed(EV_KEY, code, PRESS, start))
        return self.detector.feed(EV_KEY, code, RELEASE, start + 0.05)

    def test_single_tap_does_not_trigger(self) -> None:
        self.assertFalse(self.tap(0.0))

    def test_double_tap_triggers(self) -> None:
        self.assertFalse(self.tap(0.0))
        self.assertTrue(self.tap(0.2))

    def test_slow_double_tap_does_not_trigger(self) -> None:
        self.assertFalse(self.tap(0.0))
        self.assertFalse(self.tap(1.0))
        self.assertTrue(self.tap(1.2))

    def test_key_between_taps_blocks(self) -> None:
        self.assertFalse(self.tap(0.0))
        self.detector.feed(EV_KEY, KEY_A, PRESS, 0.1)
        self.detector.feed(EV_KEY, KEY_A, RELEASE, 0.15)
        self.assertFalse(self.tap(0.2))

    def test_ctrl_combo_does_not_trigger(self) -> None:
        # Ctrl+C followed by a clean Ctrl tap must not count as a double tap.
        self.detector.feed(EV_KEY, 29, PRESS, 0.0)
        self.detector.feed(EV_KEY, KEY_A, PRESS, 0.05)
        self.detector.feed(EV_KEY, KEY_A, RELEASE, 0.1)
        self.assertFalse(self.detector.feed(EV_KEY, 29, RELEASE, 0.15))
        self.assertFalse(self.tap(0.2))

    def test_right_ctrl_counts(self) -> None:
        self.assertFalse(self.tap(0.0, 97))
        self.assertTrue(self.tap(0.2, 97))

    def test_mixed_ctrl_keys_count(self) -> None:
        self.assertFalse(self.tap(0.0, 29))
        self.assertTrue(self.tap(0.2, 97))

    def test_autorepeat_is_ignored(self) -> None:
        self.detector.feed(EV_KEY, KEY_A, REPEAT, 0.1)
        self.assertFalse(self.tap(0.0))
        self.assertTrue(self.tap(0.2))

    def test_non_key_events_are_ignored(self) -> None:
        self.assertFalse(self.detector.feed(EV_SYN, 0, 0, 0.0))
        self.assertFalse(self.tap(0.0))
        self.assertTrue(self.tap(0.2))

    def test_ctrl_held_without_release_does_not_trigger(self) -> None:
        self.assertFalse(self.detector.feed(EV_KEY, 29, PRESS, 0.0))
        self.assertFalse(self.detector.feed(EV_KEY, 29, PRESS, 0.2))

    def test_trigger_resets_sequence(self) -> None:
        self.assertFalse(self.tap(0.0))
        self.assertTrue(self.tap(0.2))
        self.assertFalse(self.tap(0.4))
        self.assertTrue(self.tap(0.6))

    def test_dirty_ctrl_tap_is_dropped(self) -> None:
        # Ctrl down, A down/up, Ctrl up: not a tap.
        self.detector.feed(EV_KEY, 29, PRESS, 0.0)
        self.detector.feed(EV_KEY, KEY_A, PRESS, 0.05)
        self.detector.feed(EV_KEY, KEY_A, RELEASE, 0.1)
        self.detector.feed(EV_KEY, 29, RELEASE, 0.15)
        # The next clean tap is the first of a new pair.
        self.assertFalse(self.tap(0.2))
        self.assertTrue(self.tap(0.4))

    def test_supports_ctrl_falls_back_when_sysfs_is_missing(self) -> None:
        import hotkey

        self.assertTrue(hotkey.supports_ctrl("/dev/input/event-does-not-exist"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
