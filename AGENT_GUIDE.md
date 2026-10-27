# Agent operations guide

This file is for any AI agent using this folder. It explains how to install,
run, repair, and remove the tool without guessing commands.

## Golden rules

1. Use `bash menu.sh <command>` as the single entry point.
2. Do not install Python packages globally. Use `bash menu.sh install`.
3. Do not run `sudo`. `install.sh` prints the `apt` command for the user if a
   system package is missing.
4. Do not delete files manually. Use `bash menu.sh uninstall`.
5. Do not commit `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/`, or `config.json`.
6. Read `AGENTS.md` for how to speak. Read this file for how to operate.
7. Keep the full answer on screen. Speak only when the user asks or after
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
| "make a shortcut", "double tap ctrl" | `bash menu.sh hotkey install` |
| "shortcut status" | `bash menu.sh hotkey status` |
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
8. Runs the five smoke tests.
9. Stops with a non-zero exit code if a required step fails.

It does **not** run `sudo`, install system packages, change the system Python,
create a service, add a startup entry, or write outside this folder. It may use
temporary directories under `/tmp` during installation. Pip caching is disabled
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

The install does not write to `/usr`, `/opt`, a system service directory, or
other home-directory locations outside the install folder. The only outside
writes are temporary files under `/tmp` during package installation and
downloads. If the user runs an `apt` command themselves, those system packages
are installed by the OS package manager, not by this project.

To see the exact current sizes:

```bash
du -sh .venv voices .run .tmp 2>/dev/null
```

## Remove: what it does

`bash menu.sh uninstall` calls `uninstall.sh`. It removes:

- `.venv/`
- `voices/` (unless `--keep-voices`)
- `.run/`
- `.tmp/`
- `config.json` (unless `--keep-config`)
- `__pycache__/` and `*.pyc`

It never removes `speak.py`, `mcp_server.py`, `menu.sh`, `install.sh`,
`uninstall.sh`, `README.md`, `AGENTS.md`, `AGENT_GUIDE.md`, `LICENSE`,
`THIRD_PARTY_NOTICES.md`, `examples/`, or `tests/`.

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

## Status and tests

```bash
bash menu.sh status
bash menu.sh test
```

`status` checks the virtualenv, packages, voice model, audio player, config
JSON, and MCP import. `test` runs the same five checks as `install.sh`:

1. edge-tts audio (network);
2. piper audio (offline);
3. text cleaner;
4. MCP tool listing;
5. playback, or an audio-file fallback if no audio device is available.

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
  "voice": "en-US-AriaNeural",
  "piper_voice": "en_US-ljspeech-high",
  "rate": "+0%",
  "max_spoken_chars": 1200
}
```

- `engine`: `edge` (online) or `piper` (offline).
- `voice`: edge-tts voice name.
- `piper_voice`: installed piper model name, without `.onnx`.
- `rate`: `+10%`, `-5%`, or `0%`.
- `max_spoken_chars`: spoken character limit before "the rest is on screen".

If the user changes `piper_voice`, install that voice:

```bash
./.venv/bin/python -m piper.download_voices NAME --data-dir voices
```

Then run `bash menu.sh status`.

## Platform support

- **Linux:** supported.
- **WSL:** supported; audio depends on WSL audio configuration.
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
- `--file` reads any path the current user can read.
- Do not send secrets through the edge engine.
- Do not run `rm -rf` on the project folder. Use `uninstall.sh`.
- Do not commit generated files. The `.gitignore` already excludes them.

## If something fails

1. Run `bash menu.sh status`.
2. Read the exact error line.
3. Use `README.md` troubleshooting.
4. If a system package is missing, show the printed `apt` command and wait for
   the user.
5. If the voice is missing, rerun `bash menu.sh install` or download the voice.
6. If MCP tools do not appear, check the absolute path to `.venv/bin/python` and
   `mcp_server.py` in the client configuration.

Do not modify source files to work around an environment problem unless the user
asks for a code change.
