#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Install voice-for-agent from a Git URL into a stable local directory.
set -uo pipefail

REPO_URL=""
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
BRANCH="main"
REGISTER_OPENCODE=0
WITH_SERVICE=0

usage() {
  cat <<'EOF'
Usage: bash bootstrap.sh [options]

Options:
  --repo URL              Git repository URL to clone or update
  --dir PATH              Install directory
                          (default: ${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent)
  --branch NAME           Git branch (default: main)
  --register-opencode     Register the MCP server globally in OpenCode
  --with-service          Also install and enable the double-tap Ctrl user unit
  -h, --help              Show this help

If --repo is omitted, bootstrap.sh uses the current checkout when it contains
install.sh and speak.py. Otherwise it uses --dir if that already contains an
installation.

Examples:
  bash bootstrap.sh --repo https://github.com/rishb0/voice-for-agent.git
  bash bootstrap.sh --repo https://github.com/rishb0/voice-for-agent.git --register-opencode
  curl -fsSL https://raw.githubusercontent.com/rishb0/voice-for-agent/main/bootstrap.sh \
    | bash -s -- --repo https://github.com/rishb0/voice-for-agent.git --register-opencode

It never runs sudo. It does not install system packages.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO_URL="${2:-}"; shift 2 ;;
    --dir) TARGET="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --register-opencode) REGISTER_OPENCODE=1; shift ;;
    --with-service) WITH_SERVICE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Install directory cannot be empty." >&2
  exit 2
fi

SOURCE_DIR=""

if [ -n "$REPO_URL" ]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required to install from a repository URL." >&2
    exit 1
  fi
  if [ -d "$TARGET/.git" ]; then
    echo "Updating: $TARGET"
    if ! git -C "$TARGET" pull --ff-only; then
      echo "Could not update $TARGET with git pull --ff-only." >&2
      exit 1
    fi
  elif [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    echo "Target exists and is not a git checkout: $TARGET" >&2
    echo "Choose another --dir or remove that directory yourself." >&2
    exit 1
  else
    mkdir -p "$(dirname "$TARGET")" || exit 1
    echo "Cloning: $REPO_URL"
    if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET"; then
      echo "git clone failed." >&2
      exit 1
    fi
  fi
  SOURCE_DIR="$TARGET"
elif [ -f "$PWD/install.sh" ] && [ -f "$PWD/speak.py" ]; then
  SOURCE_DIR="$PWD"
elif [ -f "$TARGET/install.sh" ] && [ -f "$TARGET/speak.py" ]; then
  SOURCE_DIR="$TARGET"
else
  echo "No --repo given and no local checkout found." >&2
  echo "Pass --repo https://github.com/rishb0/voice-for-agent.git" >&2
  exit 2
fi

cd "$SOURCE_DIR" || exit 1
echo "Installing from: $SOURCE_DIR"
if [ "$WITH_SERVICE" -eq 1 ]; then
  if ! bash install.sh --with-service; then
    echo "install.sh failed." >&2
    exit 1
  fi
elif ! bash install.sh; then
  echo "install.sh failed." >&2
  exit 1
fi

if [ "$REGISTER_OPENCODE" -eq 1 ]; then
  if command -v opencode >/dev/null 2>&1; then
    if opencode mcp add voice-for-agent --global -- \
      "$SOURCE_DIR/.venv/bin/python" "$SOURCE_DIR/mcp_server.py"; then
      echo "Registered OpenCode MCP server globally: voice-for-agent"
    else
      echo "OpenCode MCP registration failed." >&2
      echo "Register manually with:" >&2
      echo "  opencode mcp add voice-for-agent --global -- \"$SOURCE_DIR/.venv/bin/python\" \"$SOURCE_DIR/mcp_server.py\"" >&2
      exit 1
    fi
  else
    echo "opencode command not found; MCP registration skipped." >&2
    echo "Register manually with:" >&2
    echo "  opencode mcp add voice-for-agent --global -- \"$SOURCE_DIR/.venv/bin/python\" \"$SOURCE_DIR/mcp_server.py\"" >&2
  fi
fi

cat <<EOF

Installed: $SOURCE_DIR
Speak:     "$SOURCE_DIR/menu.sh" speak "Build finished. All tests passed."
Status:    "$SOURCE_DIR/menu.sh" status
Stop:      "$SOURCE_DIR/menu.sh" stop
Remove:    "$SOURCE_DIR/menu.sh" uninstall

EOF
