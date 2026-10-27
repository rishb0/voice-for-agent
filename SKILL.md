---
name: Voice for Agent
description: Install and use output-only text-to-speech for AI agents. Use when the user wants an agent to speak summaries aloud, install voice-for-agent from a GitHub URL, stop speech, check TTS status, or remove the local speech tool.
license: MIT
compatibility: Linux, WSL
metadata:
  opencode/autoinvoke: true
---

# Voice for Agent

This is a portable agent skill. It installs a small **output-only**
text-to-speech tool for AI agents. The agent writes text; the tool cleans it,
speaks it, and stops. There is no microphone, speech-to-text, or realtime duplex
chat.

## When to use

Use this skill when the user asks to:

- install or set up voice-for-agent from a GitHub URL;
- make an agent speak short summaries aloud;
- stop or mute speech;
- check whether the local TTS setup works;
- change voice, engine, rate, or spoken character limit;
- remove the tool and its generated files.

## Install from a GitHub URL

If the user gives a GitHub folder URL such as
`https://github.com/rishb0/voice-for-agent`, use the repository URL
`https://github.com/rishb0/voice-for-agent.git`.

Default install directory:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent
```

Run:

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

If the repository is already cloned somewhere, run `bash install.sh` from that
checkout instead.

The one-command bootstrap is equivalent:

```bash
bash bootstrap.sh --repo https://github.com/rishb0/voice-for-agent.git
```

From a raw URL:

```bash
curl -fsSL https://raw.githubusercontent.com/rishb0/voice-for-agent/main/bootstrap.sh \
  | bash -s -- --repo https://github.com/rishb0/voice-for-agent.git
```

## Register with OpenCode

Global registration makes the `speak` and `stop_speaking` tools available in
every project:

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
opencode mcp add voice-for-agent --global -- \
  "$TARGET/.venv/bin/python" "$TARGET/mcp_server.py"
```

For a project-local registration, omit `--global` and run the command from that
project.

The bootstrap can do this after install:

```bash
bash bootstrap.sh \
  --repo https://github.com/rishb0/voice-for-agent.git \
  --register-opencode
```

After registration, the tools appear as `speak` and `stop_speaking`, or with a
client prefix such as `voice-for-agent_speak`.

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

Read `AGENT_GUIDE.md` in the installed folder for the full operations guide.
Read `AGENTS.md` for the speaking behaviour rules.

## Remove

Confirm with the user first, then:

```bash
bash menu.sh uninstall --yes
```

Preview without deleting:

```bash
bash menu.sh uninstall --dry-run
```

Keep downloaded voices or config:

```bash
bash menu.sh uninstall --yes --keep-voices --keep-config
```

`uninstall.sh` removes generated files only. It never removes source,
documentation, examples, tests, or `LICENSE`.

## Agent rules

1. Do not run `sudo`. If a system package is missing, show the user the exact
   `apt` command printed by the installer and wait for them to run it.
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

## Repository

`README.md` is the user guide. `AGENT_GUIDE.md` is the operations guide for
agents. `AGENTS.md` is the speaking policy. `THIRD_PARTY_NOTICES.md` lists
dependency and voice-model licenses.
