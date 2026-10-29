# Agent operations guide

This file is for any AI agent using this folder. It explains how to install,
run, repair, and remove the tool without guessing commands.

## Golden rules

1. Use `bash menu.sh <command>` as the single entry point for install, speak,
   status, tests, config, and uninstall.
2. Use `systemctl --user` to control the hotkey service. It is a normal user
   unit, not something that needs `menu.sh`.
3. Do not install Python packages globally. Use `bash menu.sh install`.
4. Do not run `sudo`. `install.sh` prints the `apt` command for the user if a
   system package is missing. The only user-run `sudo` commands in this project
   are the optional `input` group and package installs.
5. Do not delete files manually. Use `bash menu.sh uninstall`.
6. Do not commit `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/`, or `config.json`.
7. Read `AGENTS.md` for how to speak. Read this file for how to operate.
8. Keep the full answer on screen. Speak only when the user asks or after
   "voice on".

## Intent map

| User says | Run |
|---|---|
| "install", "set up", "repair" | `bash menu.sh install` |
| "remove", "uninstall", "delete it" | `bash menu.sh uninstall` (confirm first) |
| "speak", "say it", "read this aloud" | MCP tool `speak`, or `bash menu.sh speak "text"` |
| "speak in background" | MCP tool `speak`, or `bash menu.sh async "text"` |
| "speak clipboard" | `bash menu.sh speak-clipboard` |
| "speak selected text" | `bash menu.sh speak-selection` |
| "toggle speech" | `bash menu.sh toggle` |
| "make a shortcut", "double tap ctrl" | `bash menu.sh service install` |
| "shortcut status" | `systemctl --user status voice-for-agent-hotkey.service` |
| "start the hotkey service" | `systemctl --user start voice-for-agent-hotkey.service` |
| "stop the hotkey service" | `systemctl --user stop voice-for-agent-hotkey.service` |
| "restart the hotkey service" | `systemctl --user restart voice-for-agent-hotkey.service` |
| "is the hotkey service running?" | `systemctl --user status voice-for-agent-hotkey.service` |
| "do not start it at login" | `systemctl --user disable voice-for-agent-hotkey.service` |
| "start it at login again" | `systemctl --user enable voice-for-agent-hotkey.service` |
| "hotkey service logs" | `journalctl --user -u voice-for-agent-hotkey.service -n 50 --no-pager` |
| "remove the hotkey service" | `bash menu.sh service remove` |
| "stop", "mute", "stop talking" | MCP tool `stop_speaking`, or `bash menu.sh stop` |
| "is it speaking?" | `bash menu.sh speaking` |
| "show speech log" | `bash menu.sh log` |
| "status", "is it working?" | `bash menu.sh status` |
| "list voices" | `bash menu.sh voices` |
| "test it" | `bash menu.sh test` |
| "show menu" | `bash menu.sh` |
| "change config", "change voice" | `bash menu.sh config` then `bash menu.sh config edit` |

If the MCP server is not registered in the current client, use the CLI fallback
shown above. Do not invent other commands.

## Install from a GitHub URL

If the user gives a repository URL, install into the stable data directory:

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

If the repository is already checked out locally, run `bash install.sh` from
that checkout instead.

The one-command bootstrap does the same thing and can register OpenCode:

```bash
bash bootstrap.sh \
  --repo https://github.com/rishb0/voice-for-agent.git \
  --register-opencode
```

To install the double-tap Ctrl service at the same time:

```bash
bash install.sh --with-service
```

Global OpenCode registration:

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
opencode mcp add voice-for-agent --global -- \
  "$TARGET/.venv/bin/python" "$TARGET/mcp_server.py"
```

A folder URL such as `/tree/main` is not a clone URL. Use the repository URL
ending in `.git`.

Run the remaining `menu.sh` commands from the installed folder, or use their
absolute paths:

```bash
"$TARGET/menu.sh" status
"$TARGET/menu.sh" speak "Build finished."
```

## Install: what it does

`bash menu.sh install` calls `install.sh`. It:

1. Checks for Python 3.10–3.13.
2. Checks for `python3-venv`.
3. Checks for an audio player: `mpv`, `ffplay`, `paplay`, or `aplay`.
4. Creates a local `.venv/` if needed.
5. Installs the pinned packages from `requirements.txt` into `.venv/`.
6. Reads `piper_voice` from `config.json` if present; otherwise uses
   `en_US-ljspeech-high`.
7. Downloads the piper `.onnx` model and `.onnx.json` config into `voices/`.
8. Runs the smoke tests.
9. With `--with-service`, installs and enables the hotkey user unit.
10. Stops with a non-zero exit code if a required step fails.

It does **not** run `sudo`, install system packages, change the system Python,
or write outside this folder, except the optional user unit in
`~/.config/systemd/user/` when `--with-service` is used. Pip caching is disabled
with `--no-cache-dir`.

If install fails because a system package is missing, show the user the exact
`apt` command printed by the script. Wait for the user to run it. Then rerun
`bash menu.sh install`.

## Where files go

Everything persistent is inside the install folder. The default bootstrap
install folder is `${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent`.

| Path | Size | Purpose |
|---|---:|---|
| `.venv/` | about 284 MB | Local Python environment and packages. |
| `voices/` | about 109 MB for the default voice | Downloaded piper model and config. |
| `.run/` | small | Locks, generation counter, async log. |
| `.tmp/` | small | Temporary audio files, deleted after playback. |
| `config.json` | small | Optional local configuration. |
| `__pycache__/` | small | Python bytecode, safe to delete. |

The only outside write is the optional user unit:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/voice-for-agent-hotkey.service
```

To see the exact current sizes:

```bash
du -sh .venv voices .run .tmp 2>/dev/null
```

## Speak and stop

Preferred path when the MCP server is registered:

- `speak(text)` — queue a 2–4 sentence plain-language summary.
- `stop_speaking()` — stop current speech and clear the queue.

CLI fallback:

```bash
bash menu.sh speak "Build finished. All tests passed."
bash menu.sh async "Build finished. All tests passed."
bash menu.sh stop
```

Do not read code, commands, paths, or long lists aloud. Say what they are
instead. The full detailed answer stays on screen.

### Chat speech vs the global hotkey

Two separate pieces:

- The MCP server (`speak`, `stop_speaking`) is started by the client, so chat
  speech only exists while the agent client is running.
- `voice-for-agent-hotkey.service` is a systemd user unit that listens for a
  double Ctrl tap. It works in every app, with or without the agent open.

Stopping the hotkey service does not break chat `speak`. Stopping the agent does
not break the hotkey.

## The hotkey service

Install it once:

```bash
bash menu.sh service install
```

This renders `systemd/voice-for-agent-hotkey.service.in` into
`~/.config/systemd/user/`, reloads systemd, enables it at login, and starts it.

After that, use `systemctl` directly:

```bash
systemctl --user status voice-for-agent-hotkey.service
systemctl --user start voice-for-agent-hotkey.service
systemctl --user stop voice-for-agent-hotkey.service
systemctl --user restart voice-for-agent-hotkey.service
systemctl --user enable voice-for-agent-hotkey.service
systemctl --user disable voice-for-agent-hotkey.service
journalctl --user -u voice-for-agent-hotkey.service -n 50 --no-pager
```

Do not edit the generated unit by hand. Change the template and rerun
`bash menu.sh service install`, or edit the unit and run
`systemctl --user daemon-reload`.

Remove it:

```bash
bash menu.sh service remove
```

`bash uninstall.sh` also removes it.

Notifications: the unit shows one desktop notification when it starts and one
when it stops. Speech itself is silent. Errors such as "nothing selected" still
notify, so a silent hotkey is not mistaken for a broken one.

The service needs the `input` group to read `/dev/input`. If the log says
`no readable /dev/input devices`, tell the user to run:

```bash
sudo usermod -aG input "$USER"
```

and then log out and back in. Do not run `sudo` yourself.

## Voice selection

The default configuration speaks Hinglish and English with Indian voices:

| Text | Voice |
|---|---|
| Latin script (Hinglish or English) | `en-IN-PrabhatNeural` |
| Devanagari | `hi-IN-MadhurNeural` |

`auto_voice` chooses between them per chunk. Passing `--voice` disables
auto-selection for that call. These are synthetic neural voices, not a clone of
a real person. Never claim a voice is a real person's voice.

## Status and tests

```bash
bash menu.sh status
bash menu.sh test
```

`status` checks the virtualenv, packages, voice model, audio player, config
JSON, MCP import, `input` group access, and hotkey service state. `test` runs:

1. edge-tts audio (network);
2. piper audio (offline);
3. text cleaner;
4. MCP tool listing;
5. playback, or an audio-file fallback if no audio device is available;
6. double-tap Ctrl detector unit tests;
7. voice selection and rate/pitch unit tests;
8. primary selection vs clipboard decision tests.

## Configuration

Create or locate `config.json`:

```bash
bash menu.sh config
```

Open it in an editor:

```bash
bash menu.sh config edit
```

The fields are:

```json
{
  "engine": "edge",
  "voice": "en-IN-PrabhatNeural",
  "voice_hi": "hi-IN-MadhurNeural",
  "auto_voice": true,
  "selection_source": "auto",
  "piper_voice": "en_US-ljspeech-high",
  "rate": "-5%",
  "pitch": "-8Hz",
  "max_spoken_chars": 1200
}
```

- `engine`: `edge` (online) or `piper` (offline).
- `voice`: edge-tts voice name for Latin-script text.
- `voice_hi`: edge-tts voice name for Devanagari text.
- `auto_voice`: `true` picks `voice_hi` automatically for Devanagari.
- `selection_source`: `auto`, `primary`, or `clipboard` for the hotkey. `auto`
  prefers the source that changed most recently.
- `piper_voice`: installed piper model name, without `.onnx`.
- `rate`: `+10%`, `-5%`, or `0%`.
- `pitch`: `+10Hz`, `-8Hz`, or `0Hz`.
- `max_spoken_chars`: spoken character limit before "the rest is on screen".

If the user changes `piper_voice`, install that voice:

```bash
./.venv/bin/python -m piper.download_voices NAME --data-dir voices
```

Then run `bash menu.sh status`.

## Update

```bash
git pull --ff-only
bash install.sh
bash menu.sh service install     # only if the unit or service changed
bash menu.sh status
```

## Remove: what it does

`bash menu.sh uninstall` calls `uninstall.sh`. It removes:

- `.venv/`
- `voices/` (unless `--keep-voices`)
- `.run/`
- `.tmp/`
- `config.json` (unless `--keep-config`)
- `__pycache__/` and `*.pyc`
- the `voice-for-agent-hotkey.service` user unit, if installed

It never removes `speak.py`, `mcp_server.py`, `menu.sh`, `install.sh`,
`uninstall.sh`, `hotkey.py`, `systemd/`, `README.md`, `AGENTS.md`,
`AGENT_GUIDE.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `examples/`, or `tests/`.

For an agent, confirm with the user first, then run:

```bash
bash menu.sh uninstall --yes
```

To keep downloaded voices and config:

```bash
bash menu.sh uninstall --yes --keep-voices --keep-config
```

To preview without deleting:

```bash
bash menu.sh uninstall --dry-run
```

## Platform support

- **Linux:** supported.
- **WSL:** supported; audio depends on WSL audio configuration, and systemd user
  services need systemd enabled in WSL.
- **macOS:** not supported by the current installer or player list. The Python
  code uses Unix features, but `install.sh` is apt/Debian-specific and there is
  no `afplay` support yet.
- **Native Windows:** not supported. `speak.py` uses `fcntl` and Unix process
  groups for queueing and stop. Use WSL instead.

Do not claim Windows or macOS support unless the user asks for a port and the
code is changed and tested.

## Safety and privacy

- `edge-tts` sends text to Microsoft. For private text, use `--engine piper`.
- Piper runs locally.
- There are no API keys, accounts, telemetry, or network listeners.
- The MCP server uses stdio only.
- The hotkey service reads `/dev/input` but stores no keystrokes. It keeps only
  Ctrl timing in memory.
- `--file` reads any path the current user can read.
- Do not send secrets through the edge engine.
- Do not run `rm -rf` on the project folder. Use `uninstall.sh`.
- Do not commit generated files. The `.gitignore` already excludes them.

## If something fails

1. Run `bash menu.sh status`.
2. Read the exact error line.
3. Use the troubleshooting section in `README.md`.
4. For the hotkey, run `systemctl --user status voice-for-agent-hotkey.service`
   and `journalctl --user -u voice-for-agent-hotkey.service -n 50`.
5. If a system package is missing, show the printed `apt` command and wait for
   the user.
6. If the voice is missing, rerun `bash menu.sh install` or download the voice.
7. If MCP tools do not appear, check the absolute path to `.venv/bin/python` and
   `mcp_server.py` in the client configuration.

Do not modify source files to work around an environment problem unless the user
asks for a code change.
