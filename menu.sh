#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Single entry point for humans and agents.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
PY="$ROOT/.venv/bin/python"
SPEAK="$ROOT/speak.py"
DEFAULT_VOICE="en_US-ljspeech-high"
LOG_FILE="$ROOT/.run/speak.log"

log_event() {
  mkdir -p "$ROOT/.run" 2>/dev/null || true
  printf '%s menu: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a voice-for-agent "voice-for-agent" "$1" >/dev/null 2>&1 || true
  fi
}

ensure_x11() {
  if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=:0
  fi
  if [ -z "${XAUTHORITY:-}" ]; then
    local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local candidate
    for candidate in "$dir"/.mutter-Xwaylandauth.* "$HOME"/.Xauthority; do
      if [ -f "$candidate" ]; then
        export XAUTHORITY="$candidate"
        break
      fi
    done
  fi
}

read_x11() {
  local selection="$1"
  local text=""
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local candidate
  ensure_x11
  if text="$(xclip -selection "$selection" -o 2>/dev/null)"; then
    printf '%s' "$text"
    return 0
  fi
  for candidate in "$dir"/.mutter-Xwaylandauth.* "$HOME"/.Xauthority; do
    [ -f "$candidate" ] || continue
    if text="$(XAUTHORITY="$candidate" xclip -selection "$selection" -o 2>/dev/null)"; then
      printf '%s' "$text"
      return 0
    fi
  done
  return 1
}

usage() {
  cat <<'EOF'
voice-for-agent menu

Usage:
  bash menu.sh                    Open the interactive menu
  bash menu.sh install            Install or repair
  bash menu.sh speak "text"       Speak text and wait
  bash menu.sh say "text"         Same as speak
  bash menu.sh async "text"       Speak in the background
  bash menu.sh speak-clipboard    Speak clipboard text in the background
  bash menu.sh speak-selection    Speak selected text in the background
  bash menu.sh toggle             Stop if speaking, otherwise speak selection
  bash menu.sh hotkey install     Double-tap Ctrl to speak or stop (login service)
  bash menu.sh hotkey status      Show the double-tap Ctrl service
  bash menu.sh hotkey remove      Remove the double-tap Ctrl service
  bash menu.sh stop               Stop speech and clear the queue
  bash menu.sh speaking           Check if speech is currently playing
  bash menu.sh log                Show recent speech activity and errors
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

  if [ -x "$PY" ]; then
    echo "INFO: speech: $("$PY" "$SPEAK" --is-speaking 2>/dev/null || echo unknown)"
  fi

  if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx input; then
    echo "PASS: input group (double-tap Ctrl can read the keyboard)"
  else
    echo "WARN: not in the input group; double-tap Ctrl cannot read the keyboard"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    local hotkey_state
    hotkey_state="$(systemctl --user is-active voice-for-agent-hotkey.service 2>/dev/null || true)"
    if [ -n "$hotkey_state" ]; then
      echo "INFO: hotkey: $hotkey_state"
    else
      echo "INFO: hotkey: not installed (bash menu.sh hotkey install)"
    fi
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

speak_clipboard_cmd() {
  require_venv || return 1
  local text="" source=""
  log_event "speak-clipboard start"
  if command -v wl-paste >/dev/null 2>&1; then
    source="wl-paste"
    text="$(wl-paste --no-newline 2>/dev/null)" || true
  elif command -v xclip >/dev/null 2>&1; then
    source="xclip"
    text="$(read_x11 clipboard)" || text=""
  else
    log_event "speak-clipboard: no clipboard tool"
    echo "No clipboard tool found. Install wl-clipboard (Wayland) or xclip (X11)." >&2
    notify "No clipboard tool. Install wl-clipboard or xclip."
    return 1
  fi
  if [ -z "${text//[[:space:]]/}" ]; then
    log_event "speak-clipboard: empty clipboard via $source"
    echo "Clipboard is empty." >&2
    notify "Clipboard is empty. Copy text, then press the shortcut again."
    return 0
  fi
  log_event "speak-clipboard: ${#text} chars via $source"
  printf '%s' "$text" | "$PY" "$SPEAK" --async
}

speak_selection_cmd() {
  require_venv || return 1
  local text="" source=""
  log_event "speak-selection start"
  if command -v wl-paste >/dev/null 2>&1; then
    source="wl-paste"
    text="$(wl-paste --primary --no-newline 2>/dev/null)" || true
  elif command -v xclip >/dev/null 2>&1; then
    source="xclip"
    text="$(read_x11 primary)" || text=""
  else
    log_event "speak-selection: no selection tool"
    echo "No selection tool found. Install wl-clipboard (Wayland) or xclip (X11)." >&2
    notify "No selection tool. Install wl-clipboard or xclip."
    return 1
  fi
  if [ -z "${text//[[:space:]]/}" ]; then
    log_event "speak-selection: empty primary via $source, trying clipboard"
    if command -v wl-paste >/dev/null 2>&1; then
      source="wl-paste clipboard"
      text="$(wl-paste --no-newline 2>/dev/null)" || true
    else
      source="xclip clipboard"
      text="$(read_x11 clipboard)" || text=""
    fi
  fi
  if [ -z "${text//[[:space:]]/}" ]; then
    log_event "speak-selection: nothing selected or copied via $source"
    echo "No selected text." >&2
    notify "Nothing selected or copied. Highlight or copy text, then try again."
    return 0
  fi
  log_event "speak-selection: ${#text} chars via $source"
  notify "Speaking ${#text} characters."
  printf '%s' "$text" | "$PY" "$SPEAK" --async
}

stop_cmd() {
  require_venv || return 1
  log_event "stop"
  "$PY" "$SPEAK" stop
}

speaking_cmd() {
  require_venv || return 1
  "$PY" "$SPEAK" --is-speaking
}

log_cmd() {
  if [ -f "$LOG_FILE" ]; then
    tail -n "${1:-40}" "$LOG_FILE"
  else
    echo "No log yet: $LOG_FILE"
  fi
}

toggle_cmd() {
  require_venv || return 1
  local state
  state="$("$PY" "$SPEAK" --is-speaking 2>/dev/null || echo idle)"
  if [ "$state" = "speaking" ]; then
    log_event "toggle: speaking -> stop"
    "$PY" "$SPEAK" stop
  else
    log_event "toggle: idle -> speak selection"
    speak_selection_cmd
  fi
}

hotkey_cmd() {
  local action="${1:-status}"
  local unit="$HOME/.config/systemd/user/voice-for-agent-hotkey.service"
  local service="voice-for-agent-hotkey.service"
  case "$action" in
    run)
      exec python3 "$ROOT/hotkey.py"
      ;;
    install)
      if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 is required." >&2
        return 1
      fi
      mkdir -p "$(dirname "$unit")"
      cat >"$unit" <<EOF
[Unit]
Description=voice-for-agent double-tap Ctrl hotkey
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 -u $ROOT/hotkey.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
      systemctl --user daemon-reload
      systemctl --user disable "$service" >/dev/null 2>&1 || true
      systemctl --user enable "$service" >/dev/null 2>&1
      if systemctl --user restart "$service"; then
        sleep 1
        if systemctl --user is-active --quiet "$service"; then
          echo "Installed: $unit"
          echo "Double-tap Ctrl to speak the selection or stop speech."
        else
          echo "Installed, but $service is not running. Check:" >&2
          echo "  bash menu.sh hotkey status" >&2
          return 1
        fi
      else
        echo "Could not start $service" >&2
        return 1
      fi
      ;;
    remove)
      systemctl --user disable --now "$service" >/dev/null 2>&1 || true
      rm -f "$unit"
      systemctl --user daemon-reload
      echo "Removed double-tap Ctrl hotkey."
      ;;
    status)
      systemctl --user status "$service" --no-pager 2>&1 | sed -n '1,12p'
      ;;
    *)
      echo "Usage: bash menu.sh hotkey [install|status|remove|run]" >&2
      return 2
      ;;
  esac
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
    echo "10) Speak clipboard"
    echo "11) Speak selected text"
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
      10) speak_clipboard_cmd ;;
      11) speak_selection_cmd ;;
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
  speak-clipboard|clipboard) shift; speak_clipboard_cmd ;;
  speak-selection|selection) shift; speak_selection_cmd ;;
  toggle) shift; toggle_cmd ;;
  hotkey) shift; hotkey_cmd "$@" ;;
  stop) shift; stop_cmd "$@" ;;
  speaking) shift; speaking_cmd ;;
  log) shift; log_cmd "$@" ;;
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
