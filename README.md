# voice-for-agent

Output-only text-to-speech for AI agents. The agent writes text; this tool
cleans it, speaks it, and gets out of the way. There is no microphone, no
speech-to-text, and no realtime duplex chat.

- Primary engine: `edge-tts` (online, natural neural voices).
- Offline fallback: `piper` with a local voice model.
- Playback: `mpv`, then `ffplay`, then `paplay`/`aplay`.
- Interfaces: a CLI, an MCP stdio server, and an optional global hotkey service.
- No API keys, GPU, paid service, or cloud account.

## Contents

1. [What you get](#what-you-get)
2. [Requirements](#requirements)
3. [Install](#install)
4. [First check](#first-check)
5. [Speak from the command line](#speak-from-the-command-line)
6. [Double-tap Ctrl service](#double-tap-ctrl-service)
7. [Using the service with systemctl](#using-the-service-with-systemctl)
8. [Voices](#voices)
9. [Configuration](#configuration)
10. [CLI reference](#cli-reference)
11. [MCP server](#mcp-server)
12. [Agent rules and skill](#agent-rules-and-skill)
13. [Update](#update)
14. [Uninstall](#uninstall)
15. [Files and layout](#files-and-layout)
16. [Tests](#tests)
17. [Troubleshooting](#troubleshooting)
18. [Platform support](#platform-support)
19. [Privacy and security](#privacy-and-security)
20. [Limits](#limits)
21. [Voice models and licensing](#voice-models-and-licensing)
22. [Publish to GitHub](#publish-to-github)

## What you get

| Piece | What it does | Needs the agent open? |
|---|---|---|
| `speak.py` | Speak text from the CLI, a file, or stdin | no |
| MCP server | `speak` and `stop_speaking` tools inside your agent | yes |
| Double-tap Ctrl service | Speak the selection or stop, in any app | no |

The hotkey service and the MCP server are independent. Closing the agent does
not break the hotkey. Stopping the hotkey service does not break chat speech.

## Requirements

- Linux with working audio output. Tested on Debian/Kali-style Linux and WSL.
- Python 3.10–3.13. Python 3.14 is not supported by the pinned piper/onnxruntime
  stack.
- One playback program: `mpv` (preferred), `ffplay` (from FFmpeg), `paplay`, or
  `aplay`.
- Network access for the first install and for `edge-tts`. The piper fallback
  works offline after the voice model is installed.

Optional, only for the double-tap Ctrl service:

- `systemd` user services, available on any modern desktop Linux.
- Membership in the `input` group, so the service can read `/dev/input`.
- `wl-clipboard` on Wayland, or `xclip` on X11, to read the selected or copied
  text. On Wayland, `wl-clipboard` is strongly recommended: X11 tools cannot see
  selections made in native Wayland apps.

`install.sh` never runs `sudo`. If a system package is missing, it prints the
`apt` command for you to run yourself.

## Install

### Option 1: clone and install

```bash
git clone https://github.com/rishb0/voice-for-agent.git
cd voice-for-agent
bash install.sh
```

### Option 2: install into a stable data folder

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"

if [ -d "$TARGET/.git" ]; then
  git -C "$TARGET" pull --ff-only
else
  git clone --depth 1 https://github.com/rishb0/voice-for-agent.git "$TARGET"
fi

cd "$TARGET"
bash install.sh
```

### Option 3: one-command bootstrap

```bash
bash bootstrap.sh \
  --repo https://github.com/rishb0/voice-for-agent.git \
  --register-opencode
```

### Install with the hotkey service in one step

```bash
bash install.sh --with-service
```

This runs the normal install and then installs and enables the double-tap Ctrl
user service. Without the flag, the service is not touched.

### What `install.sh` does

1. Finds a supported Python 3.10–3.13 and checks `python3-venv`.
2. Checks for an audio player: `mpv`, `ffplay`, `paplay`, or `aplay`.
3. Creates a local `.venv/` if needed.
4. Installs the pinned packages from `requirements.txt` into `.venv/`.
5. Reads `piper_voice` from `config.json` if present; otherwise uses
   `en_US-ljspeech-high`.
6. Downloads the piper `.onnx` model and `.onnx.json` config into `voices/`.
7. Runs the smoke tests.
8. With `--with-service`, installs and enables
   `voice-for-agent-hotkey.service`.
9. Exits non-zero if a required step fails.

It is idempotent: running it again repairs the install. It does not run `sudo`,
install system packages, or change the system Python.

If `python3-venv` or an audio player is missing, install it and rerun:

```bash
sudo apt update && sudo apt install -y python3 python3-venv mpv ffmpeg
```

## First check

```bash
bash menu.sh status
```

This checks the virtualenv, packages, piper voice model, audio player, config
file, MCP import, `input` group membership, and the hotkey service state.

Speak one sentence:

```bash
bash menu.sh speak "Build finished. All tests passed."
```

Stop it:

```bash
bash menu.sh stop
```

## Speak from the command line

```bash
bash menu.sh speak "Deployment finished. Two tests failed."   # wait until done
bash menu.sh async "Deployment finished."                     # return immediately
bash menu.sh stop                                             # stop and clear queue
bash menu.sh speaking                                         # is it talking?
bash menu.sh log                                              # recent activity
```

Directly, without the wrapper:

```bash
./.venv/bin/python speak.py "Deployment finished."
./.venv/bin/python speak.py --async "Deployment finished."
./.venv/bin/python speak.py stop
```

Read from a file or stdin:

```bash
./.venv/bin/python speak.py --file notes.md
./.venv/bin/python speak.py --file - < notes.md
cat notes.md | ./.venv/bin/python speak.py
```

Speak text you selected or copied, without sending a chat message:

```bash
bash menu.sh speak-selection     # highlight text, then run this
bash menu.sh speak-clipboard     # copy text, then run this
bash menu.sh toggle              # stop if speaking, else speak selection
```

`speak-selection` reads the primary selection and falls back to the clipboard.
Some apps, especially terminal UIs, copy the selection to the clipboard instead
of the primary selection; in that case the clipboard is used automatically.

On Wayland, install `wl-clipboard` so selections from native Wayland apps are
readable:

```bash
sudo apt install -y wl-clipboard
```

If the hotkey keeps speaking old text, force one source in `config.json`:

```json
{ "selection_source": "clipboard" }
```

## Double-tap Ctrl service

This is a small background service that reads Ctrl presses from `/dev/input`.
It does not use GNOME custom shortcuts, which are unreliable on Wayland.

Install it once:

```bash
bash menu.sh service install
```

Use it:

- tap `Ctrl` twice quickly → speak the selection, or the clipboard if nothing is
  selected;
- tap `Ctrl` twice again while speaking → stop.

The service starts at login and runs for your whole desktop session. It never
stores keystrokes. It only measures Ctrl press and release timing, and it ignores
any tap where another key was pressed while Ctrl was held, so `Ctrl+C`,
`Ctrl+V`, and `Ctrl+Z` never trigger it.

Reading `/dev/input` requires the `input` group:

```bash
sudo usermod -aG input "$USER"
```

Log out and back in afterwards, then check:

```bash
id -nG | tr ' ' '\n' | grep -x input
```

## Using the service with systemctl

The service is a normal **systemd user unit** named
`voice-for-agent-hotkey.service`. After installing it once, control it directly
with `systemctl`. You do not need `menu.sh` for daily use.

```bash
# state
systemctl --user status voice-for-agent-hotkey.service

# start and stop on demand
systemctl --user start voice-for-agent-hotkey.service
systemctl --user stop voice-for-agent-hotkey.service

# apply a change
systemctl --user restart voice-for-agent-hotkey.service

# login behaviour
systemctl --user enable voice-for-agent-hotkey.service     # start at login
systemctl --user disable voice-for-agent-hotkey.service    # do not start at login

# logs
journalctl --user -u voice-for-agent-hotkey.service -n 50 --no-pager
journalctl --user -u voice-for-agent-hotkey.service -f
```

Short forms work too:

```bash
systemctl --user restart voice-for-agent-hotkey
journalctl --user -u voice-for-agent-hotkey -f
```

### Notifications

The service shows one desktop notification when it starts and one when it stops.
Speaking shows no notification at all.

The only other notifications are errors, such as "nothing selected or copied",
because otherwise the hotkey looks broken when there is nothing to read.

### Where the unit lives

```text
${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/voice-for-agent-hotkey.service
```

It is generated from `systemd/voice-for-agent-hotkey.service.in` so the unit
points at your install folder and a system Python. Reinstalling regenerates it:

```bash
bash menu.sh service install     # render unit, reload, enable, start
```

### Remove the service

```bash
bash menu.sh service remove
```

That stops it, disables it, deletes the unit, and reloads systemd. `bash
uninstall.sh` does the same as part of a full removal.

### `menu.sh` service wrappers

These are thin wrappers around `systemctl` if you prefer them:

```bash
bash menu.sh service install    # same as hotkey install
bash menu.sh service start
bash menu.sh service stop
bash menu.sh service restart
bash menu.sh service status
bash menu.sh service enable
bash menu.sh service disable
bash menu.sh service logs       # journal for the unit
bash menu.sh service remove
```

Run the daemon in the foreground for debugging:

```bash
bash menu.sh hotkey run
```

## Voices

The default configuration speaks Hinglish and English with Indian voices, and
picks the voice from the script of each chunk:

| Text | Voice | Notes |
|---|---|---|
| Latin script, e.g. `Bhai ye kaam ho gaya` | `en-IN-PrabhatNeural` | Indian English male, reads Hinglish naturally |
| Devanagari, e.g. `नमस्ते, काम हो गया` | `hi-IN-MadhurNeural` | Hindi male |

Mixed text that contains Devanagari uses the Hindi voice. `auto_voice` in
`config.json` controls this. Passing `--voice` explicitly turns auto-selection
off for that call.

```bash
./.venv/bin/python speak.py --voice en-IN-PrabhatNeural "Bhai, test pass ho gaya."
./.venv/bin/python speak.py --voice-hi hi-IN-MadhurNeural "नमस्ते, सब ठीक है।"
./.venv/bin/python speak.py --no-auto-voice "Force the main voice."
```

These are synthetic neural voices. They are not a clone of any real person.

### List available voices

```bash
./.venv/bin/python speak.py --list-voices
bash menu.sh voices
```

This lists edge-tts voices when online and every installed piper model in
`voices/`. The default piper voice is marked `default`.

Useful edge-tts voices:

| Voice | Language | Gender |
|---|---|---|
| `en-IN-PrabhatNeural` | Indian English | male |
| `en-IN-NeerjaNeural` | Indian English | female |
| `hi-IN-MadhurNeural` | Hindi | male |
| `hi-IN-SwaraNeural` | Hindi | female |
| `en-US-AriaNeural` | US English | female |

### Change the voice

Edit `config.json`:

```bash
bash menu.sh config edit
```

Then speak again. No reinstall is needed; every new job reads the config.

## Configuration

Create `config.json` from the example:

```bash
cp config.example.json config.json
```

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

| Key | Type | Meaning |
|---|---|---|
| `engine` | `edge` or `piper` | `edge` is online and natural; `piper` is offline. |
| `voice` | string | edge-tts voice for Latin-script text. |
| `voice_hi` | string | edge-tts voice for Devanagari text. |
| `auto_voice` | boolean | Pick `voice_hi` automatically for Devanagari. |
| `selection_source` | string | `auto`, `primary`, or `clipboard` for the hotkey. |
| `piper_voice` | string | Installed piper model name, without `.onnx`. |
| `rate` | string | `+10%`, `-5%`, or `0%`. |
| `pitch` | string | `+10Hz`, `-8Hz`, or `0Hz`. |
| `max_spoken_chars` | number | Spoken character limit before "the rest is on screen". |

Precedence is: command-line option, then `config.json`, then built-in defaults.
`config.json` is ignored by git, so your local voice and tone stay private.

`piper_voice` is the stem of an `.onnx` file in `voices/`. The installer reads
this value and downloads that voice if it is missing. To add a voice later:

```bash
./.venv/bin/python -m piper.download_voices en_US-ljspeech-high --data-dir voices
```

Check the voice's `MODEL_CARD` before using it commercially. Several Piper
voices have non-commercial or research-only terms.

## CLI reference

### Speak text

```bash
./.venv/bin/python speak.py "Deployment finished. Two tests failed."
```

The default engine is `edge`. If edge-tts fails, for example with no network,
the tool logs one line and falls back to piper automatically.

### Clean text without speaking

```bash
./.venv/bin/python speak.py --clean-only --file notes.md
```

The cleaner removes fenced code blocks, markdown marks, URLs, file paths,
hashes, tables, emoji, and ANSI escapes. It keeps the readable words.

### Synthesize to a file instead of playing

```bash
./.venv/bin/python speak.py --engine edge --output speech.mp3 "Hello."
./.venv/bin/python speak.py --engine piper --output speech.wav "Hello."
```

The output container follows the engine: edge writes MP3, piper writes WAV. If
you pass a different extension it is corrected, and the actual path is printed.
If edge-tts falls back to piper, the actual `.wav` path is printed.

### Choose an engine, voice, rate, or pitch

```bash
./.venv/bin/python speak.py --engine piper --piper-voice en_US-ljspeech-high "Offline speech."
./.venv/bin/python speak.py --engine edge --voice en-IN-PrabhatNeural --rate +10% "Faster speech."
./.venv/bin/python speak.py --rate -5% "Slower speech."
./.venv/bin/python speak.py --pitch -8Hz "Deeper speech."
```

### Options

| Option | Meaning |
|---|---|
| `TEXT...` | Text to speak. |
| `--file PATH` | Read text from a file. Use `-` for stdin. |
| `--async` | Queue speech and return immediately. |
| `--engine {edge,piper}` | Force one synthesis engine. |
| `--voice NAME` | edge-tts voice for Latin-script text. |
| `--voice-hi NAME` | edge-tts voice for Devanagari text. |
| `--auto-voice` / `--no-auto-voice` | Pick the Hindi voice automatically for Devanagari. |
| `--piper-voice NAME` | Installed piper voice name (file stem). |
| `--rate +10%` | Speech rate adjustment. |
| `--pitch -8Hz` | Speech pitch adjustment in hertz. |
| `--max-chars N` | Maximum characters spoken before "the rest is on screen". |
| `--output PATH` | Synthesize to a file instead of playing. |
| `--clean-only` | Print cleaned text and exit. |
| `--list-voices` | List edge-tts and installed piper voices. |
| `--is-speaking` | Print `speaking` or `idle`. |
| `stop` | Stop current speech and invalidate every queued job. |

Negative values are accepted as separate arguments: `--rate -5%`, `--pitch -8Hz`.

## MCP server

The MCP server exposes two tools:

- `speak(text)` — queue a short spoken summary and return `"queued"` immediately.
- `stop_speaking()` — stop current speech and clear every queued job.

The server speaks with the same `config.json` as the CLI. It uses stdio, so it
does not open a network port.

### OpenCode

```bash
opencode mcp add voice-for-agent -- \
  "$PWD/.venv/bin/python" "$PWD/mcp_server.py"
```

Or use the manual V2 configuration in `examples/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "voice-for-agent": {
        "type": "local",
        "command": [
          "/ABSOLUTE/PATH/TO/voice-for-agent/.venv/bin/python",
          "/ABSOLUTE/PATH/TO/voice-for-agent/mcp_server.py"
        ],
        "codemode": false
      }
    }
  }
}
```

### Claude Code

```bash
claude mcp add --scope user voice-for-agent -- \
  "$PWD/.venv/bin/python" "$PWD/mcp_server.py"
```

The same command is in `examples/claude-code.sh`.

### Gemini CLI

Use the `mcpServers` block in `examples/gemini-settings.json`. Replace
`/ABSOLUTE/PATH/TO/voice-for-agent` with this folder's absolute path.

### Tool names

The server name is `voice-for-agent`. Some clients prefix tool names, so the
tools may appear as `voice-for-agent_speak` and
`voice-for-agent_stop_speaking`. The underlying names are `speak` and
`stop_speaking`.

## Agent rules and skill

| File | Purpose |
|---|---|
| `AGENTS.md` | Pasteable rules: when and how the agent should speak. |
| `AGENT_GUIDE.md` | Operations guide: install, service, status, tests, config, safety. |
| `SKILL.md` | Portable skill entry point for any agent given this repository URL. |
| `.opencode/skills/voice-for-agent/SKILL.md` | OpenCode-discoverable skill. |

`AGENTS.md` tells the agent to:

- stay silent by default;
- speak when the user says "speak", "read aloud", "say it", or "voice this";
- speak after every answer only after the user says "voice on";
- keep the spoken summary to 2–4 plain sentences;
- avoid reading code, commands, paths, or long lists aloud;
- call `stop_speaking` when the user says "stop talking", "mute", or
  "voice off".

The full answer stays on screen. Only the short summary is spoken. Check the
current audio state with `bash menu.sh speaking`.

## Update

```bash
cd /path/to/voice-for-agent
git pull --ff-only
bash install.sh
bash menu.sh service install     # only if the unit or service changed
bash menu.sh status
```

With the bootstrap install folder:

```bash
cd "${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
git pull --ff-only
bash install.sh
```

`config.json`, `voices/`, and `.run/` are untouched by `git pull`.

## Uninstall

Preview what will be removed:

```bash
bash uninstall.sh --dry-run
```

Remove with a confirmation prompt:

```bash
bash uninstall.sh
```

Remove without prompting, for an agent after the user confirms:

```bash
bash uninstall.sh --yes
```

Keep downloaded voices and local config:

```bash
bash uninstall.sh --yes --keep-voices --keep-config
```

`uninstall.sh` removes:

- `.venv/`
- `voices/` (unless `--keep-voices`)
- `.run/`
- `.tmp/`
- `config.json` (unless `--keep-config`)
- `__pycache__/` and `*.pyc`
- the `voice-for-agent-hotkey.service` user unit, if installed

It never removes source files, documentation, examples, tests, `LICENSE`, or
`THIRD_PARTY_NOTICES.md`.

After a full uninstall, remove the MCP registration from your agent client, and
optionally leave the `input` group:

```bash
sudo gpasswd -d "$USER" input
```

## Files and layout

| Path | What it is |
|---|---|
| `menu.sh` | Single entry point: interactive menu and all commands. |
| `speak.py` | CLI, text cleaner, chunker, synthesis, playback, queue, stop. |
| `mcp_server.py` | Thin FastMCP stdio wrapper exposing `speak` and `stop_speaking`. |
| `hotkey.py` | Double-tap Ctrl daemon that reads `/dev/input`. |
| `systemd/voice-for-agent-hotkey.service.in` | Unit template, rendered on install. |
| `install.sh` | Idempotent setup and self-test. Never uses `sudo`. |
| `uninstall.sh` | Removes generated files, config, voices, and the user unit. |
| `bootstrap.sh` | Clone or update from a Git URL, install, optionally register OpenCode. |
| `requirements.txt` | Pinned Python dependencies. |
| `config.example.json` | Example local configuration. |
| `AGENTS.md` | Pasteable speaking rules for agents. |
| `AGENT_GUIDE.md` | Operations guide for agents. |
| `SKILL.md` | Portable agent-skill entry point. |
| `.opencode/skills/voice-for-agent/SKILL.md` | OpenCode-discoverable skill. |
| `examples/` | Registration snippets for OpenCode, Claude Code, Gemini CLI. |
| `tests/smoke_test.sh` | End-to-end tests. |
| `tests/test_hotkey.py` | Double-tap Ctrl detector unit tests. |
| `tests/test_voice.py` | Voice selection, rate, and pitch unit tests. |
| `tests/test_selection.sh` | Primary selection vs clipboard decision tests. |
| `.github/workflows/ci.yml` | CI: syntax checks and unit tests. |
| `LICENSE` | MIT License for this project. |
| `THIRD_PARTY_NOTICES.md` | Dependency and voice-model license notes. |
| `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/` | Generated locally, ignored by git. |

Everything persistent stays inside the install folder, except the optional user
unit in `~/.config/systemd/user/`.

| Path | Approximate size | Purpose |
|---|---:|---|
| `.venv/` | 284 MB | Local Python environment and packages. |
| `voices/` | 109 MB for the default voice | Downloaded piper model and config. |
| `.run/` | small | Locks, generation counter, log. |
| `.tmp/` | small | Temporary audio, deleted after playback. |
| `config.json` | small | Optional local configuration. |

```bash
du -sh .venv voices .run .tmp 2>/dev/null
```

Pip caching is disabled with `--no-cache-dir`, so no persistent package cache is
kept in `~/.cache/pip`.

## Tests

```bash
bash menu.sh test
```

or directly:

```bash
bash tests/smoke_test.sh
```

The smoke test checks:

1. edge-tts produces audio (requires network);
2. piper produces audio offline;
3. the text cleaner removes markdown, URLs, code, paths, hashes, tables, emoji;
4. the MCP server starts and lists `speak` and `stop_speaking`;
5. real playback works, or an audio-file fallback passes with no audio device;
6. the double-tap Ctrl detector unit tests;
7. voice selection, rate, and pitch unit tests;
8. primary selection vs clipboard decision tests.

`install.sh` runs the same suite at the end.

## Troubleshooting

Start here:

```bash
bash menu.sh status
bash menu.sh log
systemctl --user status voice-for-agent-hotkey.service
```

### Service problems

**`Unit voice-for-agent-hotkey.service could not be found`** — the unit is not
installed. Run `bash menu.sh service install`.

**Service is `active` but double-tap Ctrl does nothing** — check group access and
the log:

```bash
id -nG | tr ' ' '\n' | grep -x input
bash menu.sh log 20
journalctl --user -u voice-for-agent-hotkey.service -n 30 --no-pager
```

The log line `hotkey: watching N input device(s)` means it found keyboards. If it
says `no readable /dev/input devices`, add yourself to the `input` group and log
out and back in.

**Double-tap works, but nothing is spoken** — the selection may be empty. The
daemon falls back to the clipboard. Check that `xclip` or `wl-clipboard` is
installed, and look at `.run/speak.log` for `speak-selection` lines.

**Double-tap speaks old text** — the app put the new selection in the clipboard
while the X11 primary selection stayed stale. Install `wl-clipboard` on Wayland,
or set `"selection_source": "clipboard"` in `config.json`. The log line
`speak-selection: N chars via ... (mode=...)` shows which source was used.

**Service dies after a crash** — `Restart=on-failure` with `RestartSec=5` brings
it back automatically. Confirm with `systemctl --user status`.

**Service does not start at login** — enable it:

```bash
systemctl --user enable voice-for-agent-hotkey.service
```

### Speech problems

**`edge-tts failed, falling back to piper`** — edge-tts needs network access.
Piper still works offline. To force local speech, use `--engine piper`.

**`piper voice model missing`** — the selected `piper_voice` is not installed.
Run `bash install.sh`, or download it with
`./.venv/bin/python -m piper.download_voices NAME --data-dir voices`.

**`no audio player found`** — install `mpv` or FFmpeg:

```bash
sudo apt update && sudo apt install -y mpv ffmpeg
```

**`playback failed`** — the player exists but cannot reach an audio device.
Check desktop audio, PipeWire/PulseAudio, or WSL audio. Run `ffplay` manually to
see the error.

**No sound but no error** — synthesize a file and play it with your normal player:

```bash
./.venv/bin/python speak.py --engine piper --output test.wav "test"
```

**`nothing to speak`** — the input was empty, or the cleaner removed everything
(code blocks and URLs only). Check with `--clean-only`.

**Wrong language voice** — Devanagari uses `voice_hi`; Latin script uses `voice`.
Set `auto_voice` to `false` to always use `voice`.

### Agent and MCP problems

**MCP client does not show the tools** — use absolute paths to
`.venv/bin/python` and `mcp_server.py`, then run the command manually to see
startup errors. The server must run where `mcp` is installed, which is `.venv/`.

**`install.sh` cannot find a supported Python** — install Python 3.11 or 3.12
and `python3-venv`. Python 3.14 is intentionally rejected by the piper stack.

**A queued job will not stop** — run `./.venv/bin/python speak.py stop`. If a
stale process remains, inspect it with `ps -ef | grep speak.py` before killing
anything.

## Platform support

- **Linux:** supported.
- **WSL:** supported; audio depends on the WSL audio setup. systemd user services
  need systemd enabled in WSL.
- **macOS:** not supported by the current installer or player list. The Python
  code uses Unix features, but `install.sh` is Debian/apt-specific and there is
  no `afplay` support yet.
- **Native Windows:** not supported. `speak.py` uses `fcntl` and Unix process
  groups for queueing and stop. Use WSL instead.

## Privacy and security

- **edge-tts sends the text to Microsoft.** Do not send secrets or private data
  through the edge engine.
- **piper runs locally.** Use `--engine piper` when the text must stay on the
  machine.
- There are no API keys, accounts, telemetry, or network listeners.
- The MCP server uses stdio only.
- The hotkey service reads `/dev/input` but stores no keystrokes. It keeps only
  Ctrl press and release timing in memory and never writes key data to disk.
- Text is passed to subprocesses as argument lists, not through a shell.
- `--file` reads any path the current user can read; treat it like any other
  file-reading CLI.
- Async errors go to `.run/speak.log`. Temporary audio is deleted after each
  chunk and by `stop`.

## Limits

- Output only: no microphone, no speech-to-text, no realtime duplex chat.
- edge-tts needs internet; piper is offline but less expressive.
- Long text is truncated for speech, not summarized. The agent's full answer
  stays on screen.
- Speech is serialized. A second job waits for the first unless you call `stop`.
- One piper voice is installed by default. Add more with the download command.
- The hotkey service needs `systemd` user units and `input` group access.
- No native Windows or macOS installer is included. WSL/Linux is the tested path.

## Voice models and licensing

The default piper voice is `en_US-ljspeech-high`:

- trained from scratch on the LJ Speech dataset;
- dataset license: public domain;
- model card:
  <https://huggingface.co/rhasspy/piper-voices/raw/main/en/en_US/ljspeech/high/MODEL_CARD>.

The model files are downloaded by `install.sh` and are ignored by git. They are
not part of this repository.

Piper voice licensing is inconsistent. Many English voices are fine-tuned from
the Lessac voice and carry research-only or non-commercial terms. The older
`en_US-lessac-medium` voice, for example, uses the Blizzard 2013 research
license and is not suitable for commercial use. Check the `MODEL_CARD` of any
voice you redistribute or use commercially.

Edge-tts voices are provided by Microsoft under its terms of service.

This project's own code is licensed under the **MIT License**. It uses
third-party dependencies under their own terms: `edge-tts` is LGPL-3.0,
`piper-tts` is GPL-3.0-or-later, and `mcp` and `onnxruntime` are MIT. See
`LICENSE` and `THIRD_PARTY_NOTICES.md`.

If you redistribute a combined package that includes `piper-tts`, follow the
GPL-3.0-or-later terms for that combined distribution.

## Repository hygiene

Generated and private files are ignored by git:

- `.venv/` — local Python environment;
- `voices/*.onnx` and `voices/*.onnx.json` — downloaded voice models;
- `.run/` and `.tmp/` — runtime state and temporary audio;
- `config.json` — local configuration;
- `__pycache__/`, `*.pyc`, audio files, and logs.

Before publishing, run `git status` and confirm none of those appear. The
example registration files use `/ABSOLUTE/PATH/TO/voice-for-agent` placeholders.

## Publish to GitHub

Create an empty **public** repository named `voice-for-agent` on GitHub. From a
fresh copy of this folder:

```bash
git init
git add .
git commit -m "Initial public release"
git branch -M main
git remote add origin https://github.com/rishb0/voice-for-agent.git
git push -u origin main
```

Confirm `git status` does not show `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/`,
or `config.json`.

The documentation uses `rishb0` as the publishing account. If you push to a
different account or organization, replace `rishb0` in `README.md`, `SKILL.md`,
`AGENT_GUIDE.md`, `bootstrap.sh`, and the `.opencode` skill. Set the repository
visibility to public, enable Issues, and add topics such as `text-to-speech`,
`tts`, `mcp`, `opencode`, `piper`, and `edge-tts`.

The GitHub Actions workflow runs syntax checks and the unit tests on every push
and pull request. It does not need network, audio hardware, or the piper voice
model.
