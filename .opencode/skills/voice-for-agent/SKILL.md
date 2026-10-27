---
name: Voice for Agent
description: Install and use output-only text-to-speech for AI agents. Use when the user wants an agent to speak summaries aloud, install voice-for-agent from a GitHub URL, stop speech, check TTS status, or remove the local speech tool.
license: MIT
compatibility: Linux, WSL
---

# Voice for Agent

This skill installs a small **output-only** text-to-speech tool. The agent
writes text; the tool cleans it and speaks it. There is no microphone,
speech-to-text, or realtime duplex chat.

The canonical portable skill and full install instructions are in the
repository root `SKILL.md`. The operations guide is `AGENT_GUIDE.md`.

## Install from a GitHub URL

Use the repository URL, not the `/tree/...` folder URL.

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"

if [ -d "$TARGET/.git" ]; then
  git -C "$TARGET" pull --ff-only
else
  git clone --depth 1 https://github.com/rishb0/voice-for-agent.git "$TARGET"
fi

cd "$TARGET"
bash install.sh
bash menu.sh status
```

Or, from a checkout:

```bash
bash bootstrap.sh --repo https://github.com/rishb0/voice-for-agent.git
```

The bootstrap can also register the MCP server globally in OpenCode:

```bash
bash bootstrap.sh \
  --repo https://github.com/rishb0/voice-for-agent.git \
  --register-opencode
```

Manual OpenCode registration:

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
opencode mcp add voice-for-agent --global -- \
  "$TARGET/.venv/bin/python" "$TARGET/mcp_server.py"
```

## Use

Preferred when the MCP server is registered:

- `speak(text)` — queue a 2–4 sentence plain-language summary.
- `stop_speaking()` — stop current speech and clear the queue.

CLI fallback:

```bash
bash menu.sh speak "Build finished. All tests passed."
bash menu.sh async "Build finished. All tests passed."
bash menu.sh speak-clipboard
bash menu.sh speak-selection
bash menu.sh toggle
bash menu.sh hotkey install
bash menu.sh stop
```

Other commands:

```bash
bash menu.sh status
bash menu.sh speaking
bash menu.sh voices
bash menu.sh test
bash menu.sh config
```

## Remove

Confirm with the user first:

```bash
bash menu.sh uninstall --yes
```

Preview:

```bash
bash menu.sh uninstall --dry-run
```

## Rules

1. Do not run `sudo`. If a system package is missing, show the user the exact
   `apt` command printed by the installer and wait.
2. Do not install Python packages globally. `install.sh` uses a local `.venv/`.
3. Do not delete files manually. Use `uninstall.sh`.
4. Do not read code, commands, paths, or long lists aloud. Say what they are.
5. Keep the full detailed answer on screen. Speak only when the user asks or
   after "voice on".
6. Do not commit `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/`, or `config.json`.
7. If the user asks to stop talking or mute, call `stop_speaking` and do not
   speak again until told otherwise.

## Platform and privacy

- Linux and WSL are supported.
- macOS and native Windows are not supported by the current installer.
- `edge-tts` sends text to Microsoft. Use `--engine piper` for private text.
- Piper runs locally.
- No API keys, accounts, telemetry, or network listeners.

## Defaults

- Engine: `edge`
- Edge voice: `en-US-AriaNeural`
- Offline voice: `en_US-ljspeech-high`
- Rate: `+0%`
- Spoken limit: `1200` characters
- License: MIT
