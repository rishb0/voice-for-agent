---
name: Voice for Agent
description: Install and use output-only text-to-speech for AI agents. Use when the user wants an agent to speak summaries aloud, install voice-for-agent from a GitHub URL, speak selected text with a double-tap Ctrl hotkey, control the hotkey systemd service, stop speech, check TTS status, or remove the local speech tool.
license: MIT
compatibility: Linux, WSL
---

# Voice for Agent

This skill installs a small **output-only** text-to-speech tool. The agent
writes text; the tool cleans it and speaks it. There is no microphone,
speech-to-text, or realtime duplex chat.

The full user guide is `README.md` in the repository root. The operations guide
is `AGENT_GUIDE.md`. This file is the short path for an agent.

## Requirements

- Linux or WSL, with audio output.
- Python 3.10–3.13.
- One player: `mpv`, `ffplay`, `paplay`, or `aplay`.
- For the hotkey service: systemd user units, and the user in the `input` group.

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
bash menu.sh stop
```

Status and diagnostics:

```bash
bash menu.sh status
bash menu.sh speaking
bash menu.sh log
bash menu.sh voices
bash menu.sh test
bash menu.sh config
```

## Double-tap Ctrl service

Install once:

```bash
bash menu.sh service install
```

Then control it with `systemctl --user`:

```bash
systemctl --user status voice-for-agent-hotkey.service
systemctl --user start voice-for-agent-hotkey.service
systemctl --user stop voice-for-agent-hotkey.service
systemctl --user restart voice-for-agent-hotkey.service
systemctl --user enable voice-for-agent-hotkey.service
systemctl --user disable voice-for-agent-hotkey.service
journalctl --user -u voice-for-agent-hotkey.service -n 50 --no-pager
```

Remove it:

```bash
bash menu.sh service remove
```

Tap `Ctrl` twice to speak the selection or the clipboard. Tap it twice again to
stop. The service needs `input` group membership; ask the user to run
`sudo usermod -aG input "$USER"` and log out if the log says
`no readable /dev/input devices`.

## Update

```bash
git pull --ff-only
bash install.sh
bash menu.sh service install     # only if the unit or service changed
bash menu.sh status
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

Keep voices and config:

```bash
bash menu.sh uninstall --yes --keep-voices --keep-config
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
8. Do not edit the generated unit in `~/.config/systemd/user/` by hand. Change
   `systemd/voice-for-agent-hotkey.service.in` and rerun
   `bash menu.sh service install`.

## Platform and privacy

- Linux and WSL are supported.
- macOS and native Windows are not supported by the current installer.
- `edge-tts` sends text to Microsoft. Use `--engine piper` for private text.
- Piper runs locally.
- The hotkey service reads `/dev/input` but stores no keystrokes.
- No API keys, accounts, telemetry, or network listeners.

## Defaults

- Engine: `edge`
- Edge voice: `en-IN-PrabhatNeural` (Indian English male, reads Hinglish)
- Hindi voice: `hi-IN-MadhurNeural`, used automatically for Devanagari text
- Offline voice: `en_US-ljspeech-high`
- Rate: `+0%`, pitch: `+0Hz`
- Spoken limit: `1200` characters
- License: MIT

## Chat speech vs global hotkey

- Chat `speak` comes from the MCP server, so it only works while the agent
  client is running.
- The double-tap Ctrl service is a systemd user unit and works in every app.

Stopping the hotkey service does not break chat speech, and closing the agent
does not break the hotkey.

Voices are synthetic. Never describe them as a real person's voice.
