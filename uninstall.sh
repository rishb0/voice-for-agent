#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Remove generated files without touching source or documentation.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

YES=0
DRY_RUN=0
KEEP_VOICES=0
KEEP_CONFIG=0

usage() {
  cat <<'EOF'
Usage: bash uninstall.sh [options]

Removes generated files from this folder:
  .venv/  voices/  .run/  .tmp/  config.json  __pycache__/  *.pyc

Options:
  --yes             Do not ask for confirmation
  --dry-run         Show what would be removed
  --keep-voices     Keep downloaded voice models in voices/
  --keep-config     Keep config.json
  -h, --help        Show this help

Source files, README, LICENSE, examples, and tests are never removed.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --keep-voices) KEEP_VOICES=1 ;;
    --keep-config) KEEP_CONFIG=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Guard against running from a different folder that happens to contain a
# similarly named script.
if [ ! -f "$ROOT/speak.py" ] || [ ! -f "$ROOT/mcp_server.py" ]; then
  echo "Refusing to uninstall: this does not look like voice-for-agent." >&2
  exit 1
fi

TARGETS=(.venv .run .tmp __pycache__)
if [ "$KEEP_VOICES" -eq 0 ]; then
  TARGETS+=(voices)
fi
if [ "$KEEP_CONFIG" -eq 0 ]; then
  TARGETS+=(config.json)
fi

echo "voice-for-agent uninstall"
echo "folder: $ROOT"
echo
echo "Will remove:"
FOUND=0
for target in "${TARGETS[@]}"; do
  if [ -e "$ROOT/$target" ]; then
    echo "  $target"
    FOUND=1
  fi
done
if [ "$FOUND" -eq 0 ]; then
  echo "  (nothing; already clean)"
fi
echo
echo "Will keep: source files, README, LICENSE, examples, tests"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: nothing was removed."
  exit 0
fi

if [ "$YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    echo "No terminal available. Re-run with --yes to confirm." >&2
    exit 1
  fi
  printf "Type 'yes' to continue: "
  IFS= read -r answer || exit 1
  if [ "$answer" != "yes" ]; then
    echo "Cancelled."
    exit 0
  fi
fi

for target in "${TARGETS[@]}"; do
  rm -rf "${ROOT:?}/$target"
done
find "$ROOT" -maxdepth 2 -name '*.pyc' -delete 2>/dev/null || true

HOTKEY_UNIT="$HOME/.config/systemd/user/voice-for-agent-hotkey.service"
if [ -f "$HOTKEY_UNIT" ]; then
  systemctl --user disable --now voice-for-agent-hotkey.service >/dev/null 2>&1 || true
  rm -f "$HOTKEY_UNIT"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "Removed double-tap Ctrl service."
fi

echo
echo "Removed generated files. Source and documentation remain."
echo "To reinstall: bash install.sh"
