#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Idempotent setup for voice-for-agent. Never runs sudo.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
warn() { echo "WARN: $*"; }

APT_CMD="sudo apt update && sudo apt install -y python3 python3-venv mpv ffmpeg"
DEFAULT_PIPER_VOICE="en_US-ljspeech-high"
PIPER_VOICE=""

echo "voice-for-agent install"
echo "folder: $ROOT"

# Pick a Python that both piper and the MCP SDK support.
PY=""
VENV_READY=0
if [ -x ".venv/bin/python" ] && .venv/bin/python -c \
  'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,13) else 1)' 2>/dev/null; then
  PY=".venv/bin/python"
  VENV_READY=1
  pass "existing virtualenv Python $($PY -c 'import platform; print(platform.python_version())')"
else
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" -c \
      'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,13) else 1)' 2>/dev/null; then
      PY="$candidate"
      break
    fi
  done
  if [ -z "$PY" ]; then
    for candidate in "$HOME"/.pyenv/versions/3.1[0-3]*/bin/python; do
      [ -x "$candidate" ] || continue
      if "$candidate" -c \
        'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,13) else 1)' 2>/dev/null; then
        PY="$candidate"
        break
      fi
    done
  fi
fi

if [ -z "$PY" ]; then
  echo "No supported Python 3.10-3.13 found."
  echo "Install it with:"
  echo "$APT_CMD"
  exit 1
fi
pass "Python $($PY -c 'import platform; print(platform.python_version())')"

if ! "$PY" -c "import venv, ensurepip" >/dev/null 2>&1; then
  echo "python3-venv is missing."
  echo "Install it with:"
  echo "$APT_CMD"
  exit 1
fi
pass "python3-venv"

# Playback is required. mpv is preferred; ffplay is an accepted fallback.
PLAYER=""
if command -v mpv >/dev/null 2>&1; then
  PLAYER="mpv"
elif command -v ffplay >/dev/null 2>&1; then
  PLAYER="ffplay"
  warn "mpv not found; using ffplay. To install mpv: sudo apt install -y mpv"
elif command -v paplay >/dev/null 2>&1; then
  PLAYER="paplay"
  warn "mpv and ffplay not found; using paplay for wav audio. To install mpv: sudo apt install -y mpv"
elif command -v aplay >/dev/null 2>&1; then
  PLAYER="aplay"
  warn "mpv and ffplay not found; using aplay for wav audio. To install mpv: sudo apt install -y mpv"
fi
if [ -z "$PLAYER" ]; then
  echo "No audio player found (mpv, ffplay, paplay, aplay)."
  echo "Install one with:"
  echo "$APT_CMD"
  exit 1
fi
pass "audio player: $PLAYER"

if [ "$VENV_READY" -eq 0 ]; then
  if [ -e ".venv" ]; then
    warn "existing .venv is unusable; recreating it"
    rm -rf .venv
  fi
  if ! "$PY" -m venv .venv; then
    fail "could not create .venv; install python3-venv with: $APT_CMD"
  fi
fi
if ! .venv/bin/python -c "import sys" >/dev/null 2>&1; then
  fail "virtualenv is broken; remove .venv and rerun install.sh"
fi
pass "virtualenv .venv"

if ! .venv/bin/python -m pip install --disable-pip-version-check \
  --no-cache-dir --upgrade pip >/dev/null 2>&1; then
  warn "could not upgrade pip; continuing with the bundled pip"
fi
if ! .venv/bin/python -m pip install --disable-pip-version-check \
  --no-cache-dir -r requirements.txt; then
  fail "pip install failed; check the network and rerun install.sh"
fi
pass "requirements installed"

if [ -z "$PIPER_VOICE" ]; then
  PIPER_VOICE="$DEFAULT_PIPER_VOICE"
  if [ -f config.json ]; then
    CONFIG_VOICE="$(.venv/bin/python -c '
import json
value = json.load(open("config.json", encoding="utf-8")).get("piper_voice", "")
print(value.strip() if isinstance(value, str) else "")
' 2>/dev/null || true)"
    if [ -n "$CONFIG_VOICE" ]; then
      PIPER_VOICE="$CONFIG_VOICE"
    fi
  fi
fi

mkdir -p voices .run .tmp
if [ ! -f "voices/$PIPER_VOICE.onnx" ] || \
   [ ! -f "voices/$PIPER_VOICE.onnx.json" ]; then
  if ! .venv/bin/python -m piper.download_voices "$PIPER_VOICE" \
    --data-dir voices; then
    fail "piper voice download failed; check the network and rerun install.sh"
  fi
fi
if [ ! -f "voices/$PIPER_VOICE.onnx" ] || \
   [ ! -f "voices/$PIPER_VOICE.onnx.json" ]; then
  fail "piper voice model is incomplete after download"
fi
pass "piper voice model: $PIPER_VOICE"

if bash tests/smoke_test.sh; then
  pass "smoke test"
else
  fail "smoke test"
fi

echo "PASS: install complete"
