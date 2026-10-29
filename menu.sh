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

hash_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -c1-16
  else
    printf '%s' "${#1}:$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  fi
}

config_value() {
  # $1 key, $2 fallback. Reads config.json without touching the venv.
  local key="$1" fallback="$2"
  if [ -f "$ROOT/config.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$ROOT/config.json" "$key" "$fallback" <<'PY' 2>/dev/null || printf '%s\n' "$fallback"
import json, sys
path, key, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    value = json.load(open(path, encoding="utf-8")).get(key)
except Exception:
    value = None
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, str) and value.strip():
    print(value.strip())
else:
    print(fallback)
PY
  else
    printf '%s\n' "$fallback"
  fi
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
  bash menu.sh hotkey install     Install the double-tap Ctrl service (once)
  bash menu.sh hotkey status      Show the double-tap Ctrl service
  bash menu.sh hotkey remove      Remove the double-tap Ctrl service
  bash menu.sh service install    Same as hotkey install
  bash menu.sh service start      Start the service now
  bash menu.sh service stop       Stop it until started again
  bash menu.sh service restart    Restart it
  bash menu.sh service status     Show the service state
  bash menu.sh service enable     Start it at login again
  bash menu.sh service disable    Do not start it at login
  bash menu.sh service logs       Show the service journal
  bash menu.sh service remove     Remove the service
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

All commands operate on this folder. Only the optional double-tap Ctrl service
is installed outside it, as a user login service.
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

  if [ -n "${WAYLAND_DISPLAY:-}" ] && ! command -v wl-paste >/dev/null 2>&1; then
    echo "WARN: Wayland session without wl-clipboard; selections from Wayland apps"
    echo "      may not be readable. Install it: sudo apt install -y wl-clipboard"
  elif command -v wl-paste >/dev/null 2>&1; then
    echo "PASS: wl-clipboard (native Wayland selections)"
  elif command -v xclip >/dev/null 2>&1; then
    echo "PASS: xclip (X11 selections)"
  else
    echo "WARN: no clipboard tool; install wl-clipboard or xclip"
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

choose_selection() {
  # Pick primary selection or clipboard. Writes the decision to the state dir.
  # $1 mode (auto|primary|clipboard), $2 primary text, $3 clipboard text,
  # $4 state dir, $5 default source when both look fresh (primary|clipboard).
  # Prints the chosen text; the source is in $4/last-source.
  local mode="$1" primary="$2" clipboard="$3" state="$4"
  local default_source="${5:-primary}"
  local last_primary="" last_clipboard="" last_source="" text="" source=""
  local p_hash="" c_hash="" p_same=0 c_same=0

  if [ -f "$state/last-primary" ]; then
    last_primary="$(cat "$state/last-primary" 2>/dev/null || true)"
  fi
  if [ -f "$state/last-clipboard" ]; then
    last_clipboard="$(cat "$state/last-clipboard" 2>/dev/null || true)"
  fi
  if [ -f "$state/last-source" ]; then
    last_source="$(cat "$state/last-source" 2>/dev/null || true)"
  fi

  case "$mode" in
    clipboard)
      text="$clipboard"
      source="clipboard"
      ;;
    primary)
      text="$primary"
      source="primary"
      ;;
    *)
      if [ -z "${primary//[[:space:]]/}" ]; then
        text="$clipboard"
        source="clipboard"
      elif [ -z "${clipboard//[[:space:]]/}" ]; then
        text="$primary"
        source="primary"
      elif [ "$primary" = "$clipboard" ]; then
        text="$primary"
        source="primary"
      else
        p_hash="$(hash_text "$primary")"
        c_hash="$(hash_text "$clipboard")"
        [ -n "$last_primary" ] && [ "$p_hash" = "$last_primary" ] && p_same=1
        [ -n "$last_clipboard" ] && [ "$c_hash" = "$last_clipboard" ] && c_same=1
        if [ "$p_same" -eq 1 ] && [ "$c_same" -eq 0 ]; then
          # Primary did not change but the clipboard did: the app copied the
          # new selection, so the clipboard is the fresh text.
          text="$clipboard"
          source="clipboard"
        elif [ "$p_same" -eq 0 ] && [ "$c_same" -eq 1 ]; then
          text="$primary"
          source="primary"
        elif [ "$p_same" -eq 1 ] && [ "$c_same" -eq 1 ]; then
          # Nothing changed. Repeat whatever was used last, so pressing again
          # re-reads the same text instead of jumping to a stale buffer.
          if [ "$last_source" = "clipboard" ]; then
            text="$clipboard"
            source="clipboard"
          else
            text="$primary"
            source="primary"
          fi
        else
          # Both changed, or there is no history yet. Use the caller's default.
          if [ "$default_source" = "clipboard" ]; then
            text="$clipboard"
            source="clipboard"
          else
            text="$primary"
            source="primary"
          fi
        fi
      fi
      ;;
  esac

  mkdir -p "$state" 2>/dev/null || true
  hash_text "$primary" >"$state/last-primary" 2>/dev/null || true
  hash_text "$clipboard" >"$state/last-clipboard" 2>/dev/null || true
  printf '%s\n' "$source" >"$state/last-source" 2>/dev/null || true
  printf '%s' "$text"
}

speak_selection_cmd() {
  require_venv || return 1
  local primary="" clipboard="" psrc="none" csrc="none"
  local text="" source="" mode="" state="$ROOT/.run" default_source="primary"
  log_event "speak-selection start"
  mode="$(config_value selection_source auto)"
  case "$mode" in
    auto | primary | clipboard) ;;
    *)
      log_event "speak-selection: invalid selection_source '$mode', using auto"
      mode="auto"
      ;;
  esac

  if command -v wl-paste >/dev/null 2>&1; then
    psrc="wl-paste primary"
    primary="$(wl-paste --primary --no-newline 2>/dev/null)" || primary=""
    csrc="wl-paste clipboard"
    clipboard="$(wl-paste --no-newline 2>/dev/null)" || clipboard=""
  elif command -v xclip >/dev/null 2>&1; then
    psrc="xclip primary"
    primary="$(read_x11 primary)" || primary=""
    csrc="xclip clipboard"
    clipboard="$(read_x11 clipboard)" || clipboard=""
  else
    log_event "speak-selection: no selection tool"
    echo "No selection tool found. Install wl-clipboard (Wayland) or xclip (X11)." >&2
    notify "No selection tool. Install wl-clipboard or xclip."
    return 1
  fi

  if ! command -v wl-paste >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    # X11 tools cannot see native Wayland selections, so the bridged clipboard
    # is the only source that is likely to hold what the user just selected.
    default_source="clipboard"
    log_event "speak-selection: wl-clipboard missing; Wayland selections can be stale (install wl-clipboard)"
  fi

  text="$(choose_selection "$mode" "$primary" "$clipboard" "$state" "$default_source")"
  case "$(cat "$state/last-source" 2>/dev/null || true)" in
    clipboard) source="$csrc" ;;
    *) source="$psrc" ;;
  esac

  if [ -z "${text//[[:space:]]/}" ]; then
    log_event "speak-selection: nothing selected or copied via $source"
    echo "No selected text." >&2
    notify "Nothing selected or copied. Highlight or copy text, then try again."
    return 0
  fi
  log_event "speak-selection: ${#text} chars via $source (mode=$mode)"
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

UNIT_NAME="voice-for-agent-hotkey.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"
UNIT_TEMPLATE="$ROOT/systemd/$UNIT_NAME.in"

render_unit() {
  local template="$UNIT_TEMPLATE"
  local python_bin=""
  local candidate
  if [ ! -f "$template" ]; then
    echo "Missing unit template: $template" >&2
    return 1
  fi
  # Prefer a fixed system interpreter: systemd does not load shell profiles,
  # so pyenv or asdf shims can fail inside the service.
  for candidate in /usr/bin/python3 /usr/local/bin/python3; do
    if [ -x "$candidate" ] && "$candidate" -c 'import sys' >/dev/null 2>&1; then
      python_bin="$candidate"
      break
    fi
  done
  if [ -z "$python_bin" ]; then
    candidate="$(command -v python3 || true)"
    if [ -n "$candidate" ] && "$candidate" -c 'import sys' >/dev/null 2>&1; then
      python_bin="$candidate"
    fi
  fi
  if [ -z "$python_bin" ]; then
    echo "python3 is required to run the hotkey service." >&2
    return 1
  fi
  mkdir -p "$UNIT_DIR" || return 1
  local root_uri="${ROOT// /%20}"
  sed -e "s|@ROOT_URI@|$root_uri|g" \
    -e "s|@ROOT@|$ROOT|g" \
    -e "s|@PYTHON@|$python_bin|g" \
    "$template" >"$UNIT_PATH" || return 1
}

unit_installed() {
  [ -f "$UNIT_PATH" ]
}

hotkey_cmd() {
  local action="${1:-status}"
  case "$action" in
    run)
      exec python3 "$ROOT/hotkey.py"
      ;;
    install)
      render_unit || return 1
      systemctl --user daemon-reload || return 1
      systemctl --user disable "$UNIT_NAME" >/dev/null 2>&1 || true
      systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1
      if systemctl --user restart "$UNIT_NAME"; then
        sleep 1
        if systemctl --user is-active --quiet "$UNIT_NAME"; then
          echo "Installed: $UNIT_PATH"
          echo "Enabled at login: $UNIT_NAME"
          echo "Control it with systemctl --user start|stop|status $UNIT_NAME"
        else
          echo "Installed, but $UNIT_NAME is not running. Check:" >&2
          echo "  systemctl --user status $UNIT_NAME" >&2
          return 1
        fi
      else
        echo "Could not start $UNIT_NAME" >&2
        return 1
      fi
      ;;
    remove)
      systemctl --user disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
      rm -f "$UNIT_PATH"
      systemctl --user daemon-reload
      echo "Removed $UNIT_NAME"
      ;;
    status)
      systemctl --user status "$UNIT_NAME" --no-pager 2>&1 | sed -n '1,12p'
      ;;
    *)
      echo "Usage: bash menu.sh hotkey [install|status|remove|run]" >&2
      return 2
      ;;
  esac
}

service_cmd() {
  local action="${1:-status}"
  case "$action" in
    install)
      hotkey_cmd install
      return $?
      ;;
    remove | uninstall)
      hotkey_cmd remove
      return $?
      ;;
    logs)
      journalctl --user -u "$UNIT_NAME" -n "${2:-50}" --no-pager
      return $?
      ;;
  esac
  if ! unit_installed; then
    echo "$UNIT_NAME is not installed." >&2
    echo "Install it once with: bash menu.sh service install" >&2
    return 1
  fi
  case "$action" in
    start)
      systemctl --user start "$UNIT_NAME" && echo "Started $UNIT_NAME"
      ;;
    stop)
      systemctl --user stop "$UNIT_NAME" && echo "Stopped $UNIT_NAME"
      ;;
    restart)
      systemctl --user restart "$UNIT_NAME" && echo "Restarted $UNIT_NAME"
      ;;
    enable)
      systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1 && echo "Enabled at login"
      ;;
    disable)
      systemctl --user disable "$UNIT_NAME" >/dev/null 2>&1 && echo "Disabled at login"
      ;;
    status)
      systemctl --user status "$UNIT_NAME" --no-pager 2>&1 | sed -n '1,12p'
      ;;
    *)
      echo "Usage: bash menu.sh service [install|start|stop|restart|status|enable|disable|logs|remove]" >&2
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
    echo "12) Install hotkey service"
    echo "13) Hotkey service status"
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
      12) service_cmd install ;;
      13) service_cmd status ;;
      0) exit 0 ;;
      *) echo "Invalid choice: $choice" ;;
    esac
  done
}

if [ "${VFA_LIB:-0}" = "1" ]; then
  # Sourced by tests: define functions only.
  return 0 2>/dev/null || exit 0
fi

case "${1:-menu}" in
  menu) interactive_menu ;;
  install) shift; install_cmd "$@" ;;
  speak|say) shift; speak_cmd "$@" ;;
  async) shift; async_cmd "$@" ;;
  speak-clipboard|clipboard) shift; speak_clipboard_cmd ;;
  speak-selection|selection) shift; speak_selection_cmd ;;
  toggle) shift; toggle_cmd ;;
  hotkey) shift; hotkey_cmd "$@" ;;
  service) shift; service_cmd "$@" ;;
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
