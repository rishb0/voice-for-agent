#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Single entry point for humans and agents.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
PY="$ROOT/.venv/bin/python"
SPEAK="$ROOT/speak.py"
DEFAULT_VOICE="en_US-ljspeech-high"

usage() {
  cat <<'EOF'
voice-for-agent menu

Usage:
  bash menu.sh                    Open the interactive menu
  bash menu.sh install            Install or repair
  bash menu.sh speak "text"       Speak text and wait
  bash menu.sh say "text"         Same as speak
  bash menu.sh async "text"       Speak in the background
  bash menu.sh stop               Stop speech and clear the queue
  bash menu.sh status             Check the installation and audio setup
  bash menu.sh voices             List edge and installed piper voices
  bash menu.sh test               Run the smoke tests
  bash menu.sh config             Create config.json if needed and print its path
  bash menu.sh config edit        Open config.json in $EDITOR or a fallback editor
  bash menu.sh uninstall          Remove generated files (asks for confirmation)
  bash menu.sh uninstall --yes    Remove generated files without prompting
  bash menu.sh help               Show this help

All commands operate on this folder. Nothing is installed globally.
EOF
}

require_venv() {
  if [ ! -x "$PY" ]; then
    echo "voice-for-agent is not installed yet." >&2
    echo "Run: bash menu.sh install" >&2
    return 1
  fi
}

status() {
  local ok=0
  local voice="$DEFAULT_VOICE"
  local player=""

  echo "voice-for-agent status"
  echo "folder: $ROOT"

  if [ -x "$PY" ]; then
    echo "PASS: virtualenv Python $("$PY" -c 'import platform; print(platform.python_version())' 2>/dev/null)"
  else
    echo "FAIL: .venv is missing"
    ok=1
  fi

  if [ -x "$PY" ] && "$PY" -c 'import edge_tts, piper, mcp, onnxruntime' >/dev/null 2>&1; then
    echo "PASS: Python packages"
  elif [ -x "$PY" ]; then
    echo "FAIL: Python packages are missing or broken"
    ok=1
  fi

  if [ -f config.json ] && [ -x "$PY" ]; then
    voice="$("$PY" -c '
import json
value = json.load(open("config.json", encoding="utf-8")).get("piper_voice", "")
print(value.strip() if isinstance(value, str) and value.strip() else "en_US-ljspeech-high")
' 2>/dev/null || echo "$DEFAULT_VOICE")"
  fi

  if [ -f "voices/$voice.onnx" ] && [ -f "voices/$voice.onnx.json" ]; then
    echo "PASS: piper voice: $voice"
  else
    echo "FAIL: piper voice missing: $voice"
    ok=1
  fi

  for candidate in mpv ffplay paplay aplay; do
    if command -v "$candidate" >/dev/null 2>&1; then
      player="$candidate"
      break
    fi
  done
  if [ -n "$player" ]; then
    echo "PASS: audio player: $player"
  else
    echo "FAIL: no audio player (install mpv or ffmpeg)"
    ok=1
  fi

  if [ -f config.json ]; then
    if [ -x "$PY" ] && "$PY" -c 'import json; json.load(open("config.json", encoding="utf-8"))' >/dev/null 2>&1; then
      echo "PASS: config.json"
    else
      echo "FAIL: config.json is not valid JSON"
      ok=1
    fi
  else
    echo "INFO: config.json not present; using defaults"
  fi

  if [ -x "$PY" ] && "$PY" -c 'import mcp_server' >/dev/null 2>&1; then
    echo "PASS: MCP server imports"
  elif [ -x "$PY" ]; then
    echo "FAIL: MCP server import failed"
    ok=1
  fi

  echo
  if [ "$ok" -eq 0 ]; then
    echo "STATUS: ready"
  else
    echo "STATUS: needs attention"
  fi
  return "$ok"
}

install_cmd() {
  bash "$ROOT/install.sh"
}

speak_cmd() {
  require_venv || return 1
  if [ "$#" -eq 0 ]; then
    printf "Text to speak: "
    IFS= read -r text || return 1
    [ -n "$text" ] || { echo "Nothing to speak."; return 0; }
    set -- "$text"
  fi
  "$PY" "$SPEAK" "$@"
}

async_cmd() {
  require_venv || return 1
  if [ "$#" -eq 0 ]; then
    printf "Text to speak in background: "
    IFS= read -r text || return 1
    [ -n "$text" ] || { echo "Nothing to speak."; return 0; }
    set -- "$text"
  fi
  "$PY" "$SPEAK" --async "$@"
}

stop_cmd() {
  require_venv || return 1
  "$PY" "$SPEAK" stop
}

voices_cmd() {
  require_venv || return 1
  "$PY" "$SPEAK" --list-voices
}

test_cmd() {
  require_venv || return 1
  bash "$ROOT/tests/smoke_test.sh"
}

config_cmd() {
  if [ ! -f "$ROOT/config.json" ]; then
    cp "$ROOT/config.example.json" "$ROOT/config.json"
    echo "Created: $ROOT/config.json"
  else
    echo "Config: $ROOT/config.json"
  fi
  if [ "${1:-}" = "edit" ]; then
    if [ -n "${EDITOR:-}" ]; then
      "$EDITOR" "$ROOT/config.json"
    elif command -v nano >/dev/null 2>&1; then
      nano "$ROOT/config.json"
    elif command -v vi >/dev/null 2>&1; then
      vi "$ROOT/config.json"
    else
      echo "No editor found. Edit the file above with your preferred editor."
    fi
  fi
}

uninstall_cmd() {
  bash "$ROOT/uninstall.sh" "$@"
}

interactive_menu() {
  while true; do
    echo
    echo "voice-for-agent"
    echo "1) Install or repair"
    echo "2) Speak text"
    echo "3) Speak in background"
    echo "4) Stop speech"
    echo "5) Status"
    echo "6) List voices"
    echo "7) Test"
    echo "8) Edit config"
    echo "9) Uninstall"
    echo "0) Exit"
    printf "Choose: "
    IFS= read -r choice || exit 0
    case "$choice" in
      1) install_cmd ;;
      2) speak_cmd ;;
      3) async_cmd ;;
      4) stop_cmd ;;
      5) status ;;
      6) voices_cmd ;;
      7) test_cmd ;;
      8) config_cmd edit ;;
      9) uninstall_cmd ;;
      0) exit 0 ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

case "${1:-menu}" in
  menu) interactive_menu ;;
  install) shift; install_cmd "$@" ;;
  speak|say) shift; speak_cmd "$@" ;;
  async) shift; async_cmd "$@" ;;
  stop) shift; stop_cmd "$@" ;;
  status) shift; status ;;
  voices) shift; voices_cmd ;;
  test) shift; test_cmd ;;
  config) shift; config_cmd "$@" ;;
  uninstall) shift; uninstall_cmd "$@" ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
