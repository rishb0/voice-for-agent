#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unit tests for Hinglish voice selection and rate/pitch parsing."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from speak import (  # noqa: E402
    Options,
    _has_devanagari,
    _normalize_argv,
    _voice_for,
    normalize_pitch,
    normalize_rate,
)


class VoiceSelectionTest(unittest.TestCase):
    def options(self, **kwargs) -> Options:
        base = {
            "voice": "en-IN-PrabhatNeural",
            "voice_hi": "hi-IN-MadhurNeural",
            "auto_voice": True,
        }
        base.update(kwargs)
        return Options(**base)

    def test_devanagari_detected(self) -> None:
        self.assertTrue(_has_devanagari("नमस्ते दोस्त"))
        self.assertTrue(_has_devanagari("hello नमस्ते"))

    def test_latin_hinglish_is_not_devanagari(self) -> None:
        self.assertFalse(_has_devanagari("Bhai ye kaam ho gaya"))

    def test_auto_voice_picks_hindi_for_devanagari(self) -> None:
        options = self.options()
        self.assertEqual(_voice_for("नमस्ते", options), "hi-IN-MadhurNeural")

    def test_auto_voice_keeps_main_voice_for_hinglish(self) -> None:
        options = self.options()
        self.assertEqual(
            _voice_for("Bhai ye kaam ho gaya", options), "en-IN-PrabhatNeural"
        )

    def test_mixed_script_uses_hindi_voice(self) -> None:
        options = self.options()
        self.assertEqual(
            _voice_for("नमस्ते, deploy ho gaya", options), "hi-IN-MadhurNeural"
        )

    def test_auto_voice_can_be_disabled(self) -> None:
        options = self.options(auto_voice=False)
        self.assertEqual(_voice_for("नमस्ते", options), "en-IN-PrabhatNeural")


class RatePitchTest(unittest.TestCase):
    def test_negative_rate_is_accepted(self) -> None:
        self.assertEqual(normalize_rate("-5%"), "-5%")

    def test_rate_gets_sign(self) -> None:
        self.assertEqual(normalize_rate("5%"), "+5%")

    def test_invalid_rate_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            normalize_rate("fast")

    def test_negative_pitch_is_accepted(self) -> None:
        self.assertEqual(normalize_pitch("-8Hz"), "-8Hz")

    def test_invalid_pitch_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            normalize_pitch("-8%")

    def test_negative_rate_argv_is_merged(self) -> None:
        self.assertEqual(
            _normalize_argv(["--rate", "-5%", "--pitch", "-8Hz", "hello"]),
            ["--rate=-5%", "--pitch=-8Hz", "hello"],
        )

    def test_positive_rate_argv_is_untouched(self) -> None:
        self.assertEqual(_normalize_argv(["--rate", "+5%"]), ["--rate", "+5%"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
