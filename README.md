# voice-for-agent

Output-only text-to-speech for AI agents. The agent writes text; this tool
cleans it, speaks it, and gets out of the way. There is no microphone, no
speech-to-text, and no realtime duplex chat.

- Primary engine: `edge-tts` (online, natural voices).
- Offline fallback: `piper` with a local voice model.
- Playback: `mpv`, then `ffplay`, then `paplay`/`aplay`.
- Interfaces: a small CLI and an MCP stdio server.
- No API keys, GPU, paid service, or cloud account.

## Requirements

- Linux with working audio output. Tested on Debian/Kali-style Linux and WSL.
- Python 3.10–3.13. Python 3.14 is not supported by the pinned piper/onnxruntime
  stack.
- One playback program: `mpv` (preferred), `ffplay` (from FFmpeg), `paplay`, or
  `aplay`.
- Network access for the first install and for `edge-tts`. The piper fallback
  works offline after the voice model is installed.

`install.sh` never runs `sudo`. If a system package is missing, it prints the
`apt` command to run yourself.

## Quick start

```bash
cd /path/to/voice-for-agent
bash install.sh

./.venv/bin/python speak.py "Build finished. All tests passed."
```

`bash install.sh` creates `.venv`, installs the pinned Python packages,
downloads the default piper voice, and runs the smoke test. It is safe to run
again.

Stop current speech and clear the queue:

```bash
./.venv/bin/python speak.py stop
```

Speak in the background and return immediately:

```bash
./.venv/bin/python speak.py --async "Build finished. All tests passed."
```

## Menu and single entry point

If you do not want to remember individual commands, use `menu.sh`:

```bash
bash menu.sh
```

That opens a numbered menu for install, speak, stop, status, voices, tests,
config, and uninstall.

The same script works non-interactively, which is what agents should use:

```bash
bash menu.sh install
bash menu.sh speak "Build finished. All tests passed."
bash menu.sh async "Build finished. All tests passed."
bash menu.sh speak-clipboard
bash menu.sh speak-selection
bash menu.sh toggle
bash menu.sh hotkey install
bash menu.sh stop
bash menu.sh speaking
bash menu.sh log
bash menu.sh status
bash menu.sh voices
bash menu.sh test
bash menu.sh config
bash menu.sh uninstall
```

Run `bash menu.sh help` for the full list.

### Speak selected or copied text without chat

You do not need to send a chat message. From a terminal:

```bash
bash menu.sh speak-clipboard
bash menu.sh speak-selection
```

`speak-clipboard` reads the clipboard. `speak-selection` reads the current
primary selection: the text you highlighted. Both speak in the background.

### Double-tap Ctrl (recommended on GNOME Wayland)

GNOME custom shortcuts can be unreliable on Wayland, so this uses a small
login service that reads Ctrl presses directly:

```bash
bash menu.sh hotkey install
```

Then:

- tap `Ctrl` twice quickly → speak the selection, or the clipboard if nothing
  is selected;
- tap `Ctrl` twice again while speaking → stop.

The service starts at login and keeps running in the background. It never
stores keystrokes; it only measures Ctrl press and release timing.

```bash
bash menu.sh hotkey status
bash menu.sh hotkey remove
bash menu.sh hotkey run      # run in the foreground to debug
```

Reading `/dev/input` requires the user to be in the `input` group:

```bash
sudo usermod -aG input "$USER"   # log out and back in afterwards
```

### GNOME custom shortcuts (alternative)

1. Install a clipboard tool if missing:
   - Wayland: `sudo apt install wl-clipboard`
   - X11: `sudo apt install xclip`
2. Open **Settings → Keyboard → Keyboard Shortcuts → Custom Shortcuts**.
3. Add:
   - Name: `Speak selection`
     Command: `bash /path/to/voice-for-agent/menu.sh speak-selection`
     Shortcut: `Super+Shift+S`
   - Name: `Stop speech`
     Command: `bash /path/to/voice-for-agent/menu.sh stop`
     Shortcut: `Super+Shift+X`

Select text anywhere, press the shortcut, and it speaks without touching the
chat. Use the real install path in the command.

### Shell aliases for zsh

```bash
alias say='bash /path/to/voice-for-agent/menu.sh speak'
alias say-clip='bash /path/to/voice-for-agent/menu.sh speak-clipboard'
alias say-sel='bash /path/to/voice-for-agent/menu.sh speak-selection'
alias say-stop='bash /path/to/voice-for-agent/menu.sh stop'
alias say-toggle='bash /path/to/voice-for-agent/menu.sh toggle'
```

## Use as an agent skill

This repository is also a portable agent skill. Give an agent the repository
URL and tell it to read `SKILL.md`:

```text
https://github.com/rishb0/voice-for-agent
```

A folder URL such as `/tree/main` should be converted to the repository URL
ending in `.git` for cloning. If you fork this repository, replace `rishb0` with
your own GitHub account or organization.

The skill tells the agent to install into:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent
```

Manual agent install:

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

One-command bootstrap:

```bash
bash bootstrap.sh --repo https://github.com/rishb0/voice-for-agent.git
```

Register the MCP server globally in OpenCode:

```bash
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent"
opencode mcp add voice-for-agent --global -- \
  "$TARGET/.venv/bin/python" "$TARGET/mcp_server.py"
```

Or let the bootstrap do it:

```bash
bash bootstrap.sh \
  --repo https://github.com/rishb0/voice-for-agent.git \
  --register-opencode
```

From a raw URL:

```bash
curl -fsSL https://raw.githubusercontent.com/rishb0/voice-for-agent/main/bootstrap.sh \
  | bash -s -- --repo https://github.com/rishb0/voice-for-agent.git --register-opencode
```

OpenCode automatically discovers the project skill at
`.opencode/skills/voice-for-agent/SKILL.md` when working inside this repository.
For other agents, point them at `SKILL.md` or `AGENT_GUIDE.md`.

## How to read this repository

| Path | What it is |
|---|---|
| `menu.sh` | Single entry point: interactive menu and `install`/`speak`/`stop`/`status`/`test`/`uninstall` commands. |
| `bootstrap.sh` | Clone or update from a Git URL, install, and optionally register OpenCode globally. |
| `SKILL.md` | Portable agent-skill entry point for any agent that receives this repository URL. |
| `.opencode/skills/voice-for-agent/SKILL.md` | OpenCode-discoverable skill definition. |
| `speak.py` | CLI, text cleaner, chunker, synthesis, playback, queue, and stop logic. |
| `mcp_server.py` | Thin FastMCP stdio wrapper exposing `speak` and `stop_speaking`. |
| `install.sh` | Idempotent setup and self-test. Does not use `sudo`. |
| `uninstall.sh` | Removes generated files, voices, and local config without touching source. |
| `requirements.txt` | Pinned Python dependencies. |
| `config.example.json` | Example local configuration. |
| `AGENTS.md` | Pasteable rules that tell an agent when and how to speak. |
| `AGENT_GUIDE.md` | Operations guide for any agent: install, remove, status, test, config, and safety. |
| `examples/` | Registration snippets for OpenCode, Claude Code, and Gemini CLI. |
| `tests/smoke_test.sh` | End-to-end tests for edge-tts, piper, text cleaning, MCP tools, and playback. |
| `.github/workflows/ci.yml` | Public-repo CI: syntax checks and a text-cleaner smoke test. |
| `LICENSE` | MIT License for this project. |
| `THIRD_PARTY_NOTICES.md` | Dependency and voice-model license notes. |
| `.venv/`, `voices/*.onnx`, `.run/`, `.tmp/` | Generated locally and ignored by git. |

## What `install.sh` does and where files go

`bash install.sh` performs these steps:

1. Finds a supported Python 3.10–3.13 and checks `python3-venv`.
2. Checks for an audio player: `mpv`, `ffplay`, `paplay`, or `aplay`.
3. Creates a local `.venv/` if needed.
4. Installs the pinned packages from `requirements.txt` into `.venv/`.
5. Reads `piper_voice` from `config.json` if present; otherwise uses
   `en_US-ljspeech-high`.
6. Downloads the piper `.onnx` model and `.onnx.json` config into `voices/`.
7. Runs the five smoke tests.
8. Exits non-zero if a required step fails.

It does **not** run `sudo`, install system packages, change the system Python,
create a service, add a startup entry, or install anything globally. If a system
package is missing, it prints the `apt` command for you to run.

Everything persistent stays inside the install folder. The default bootstrap
install folder is `${XDG_DATA_HOME:-$HOME/.local/share}/voice-for-agent`.

| Path | Approximate size | Purpose |
|---|---:|---|
| `.venv/` | 284 MB | Local Python environment and packages. |
| `voices/` | 109 MB for the default voice | Downloaded piper model and config. |
| `.run/` | small | Locks, generation counter, async log. |
| `.tmp/` | small | Temporary audio, deleted after playback. |
| `config.json` | small | Optional local configuration. |
| `__pycache__/` | small | Python bytecode, safe to delete. |

Pip caching is disabled with `--no-cache-dir`, so the install does not keep a
persistent package cache in `~/.cache/pip`. Pip and the voice download may still
use temporary files under `/tmp` while running. The project does not write to
`/usr`, `/opt`, a system service directory, or other home-directory locations
outside the install folder.

To see the current sizes:

```bash
du -sh .venv voices .run .tmp 2>/dev/null
```

## Platform support

- **Linux:** supported.
- **WSL:** supported; audio depends on the WSL audio setup.
- **macOS:** not supported by the current installer or player list. The Python
  code uses Unix features, but `install.sh` is Debian/apt-specific and there is
  no `afplay` support yet.
- **Native Windows:** not supported. `speak.py` uses `fcntl` and Unix process
  groups for queueing and stop. Use WSL instead.

## CLI usage

### Speak text

```bash
./.venv/bin/python speak.py "Deployment finished. Two tests failed."
```

The default engine is `edge`. If edge-tts fails (for example, no network), the
tool logs one line and falls back to piper automatically.

### Read from a file or stdin

```bash
./.venv/bin/python speak.py --file notes.md
./.venv/bin/python speak.py --file - < notes.md
cat notes.md | ./.venv/bin/python speak.py
```

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
you pass a different extension, it is corrected and the actual path is printed.
If edge-tts falls back to piper, the actual `.wav` path is printed.

### List available voices

```bash
./.venv/bin/python speak.py --list-voices
```

This lists edge-tts voices when online and every installed piper model in
`voices/`. The default piper voice is marked `default`.

### Choose an engine, voice, or rate

```bash
./.venv/bin/python speak.py --engine piper --piper-voice en_US-ljspeech-high "Offline speech."
./.venv/bin/python speak.py --engine edge --voice en-US-AriaNeural --rate +10% "Faster speech."
./.venv/bin/python speak.py --rate -5% "Slower speech."
```

`--voice` selects an edge-tts voice. `--piper-voice` selects an installed piper
model by its file stem. `--rate` accepts values such as `+10%`, `-5%`, or `0%`.

### CLI options

| Option | Meaning |
|---|---|
| `TEXT...` | Text to speak. |
| `--file PATH` | Read text from a file. Use `-` for stdin. |
| `--async` | Queue speech and return immediately. |
| `--engine {edge,piper}` | Force one synthesis engine. |
| `--voice NAME` | edge-tts voice name. |
| `--piper-voice NAME` | Installed piper voice name (file stem). |
| `--rate +10%` | Speech rate adjustment. |
| `--max-chars N` | Maximum characters spoken before "the rest is on screen". |
| `--output PATH` | Synthesize to a file instead of playing. |
| `--clean-only` | Print cleaned text and exit. |
| `--list-voices` | List edge-tts and installed piper voices. |
| `stop` | Stop current speech and invalidate every queued job. |

## Uninstall

Preview what will be removed:

```bash
bash uninstall.sh --dry-run
```

Remove generated files with a confirmation prompt:

```bash
bash uninstall.sh
```

Remove without prompting, for an agent after the user confirms:

```bash
bash uninstall.sh --yes
```

Keep downloaded voices and/or local config:

```bash
bash uninstall.sh --yes --keep-voices --keep-config
```

`uninstall.sh` removes `.venv/`, `voices/`, `.run/`, `.tmp/`, `config.json`,
`__pycache__/`, and `*.pyc`. It never removes source files, documentation,
examples, tests, `LICENSE`, or `THIRD_PARTY_NOTICES.md`.

## Configuration

Copy the example and edit it:

```bash
cp config.example.json config.json
```

```json
{
  "engine": "edge",
  "voice": "en-US-AriaNeural",
  "piper_voice": "en_US-ljspeech-high",
  "rate": "+0%",
  "max_spoken_chars": 1200
}
```

Precedence is: command-line option, then `config.json`, then built-in defaults.
`config.json` is ignored by git.

`piper_voice` is the stem of an `.onnx` file in `voices/`. The installer reads
this value and downloads that voice if it is missing. To add a voice later:

```bash
./.venv/bin/python -m piper.download_voices en_US-ljspeech-high --data-dir voices
```

Check the voice's `MODEL_CARD` before using it commercially. Several Piper
voices have non-commercial or research-only terms.

## MCP server

The MCP server exposes two tools:

- `speak(text)` — queue a short spoken summary and return `"queued"` immediately.
- `stop_speaking()` — stop current speech and clear every queued job.

The server speaks with the same `config.json` as the CLI. It uses stdio, so it
does not open a network port.

### OpenCode

From this folder:

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

## Agent rules

`AGENTS.md` contains the speaking policy. `AGENT_GUIDE.md` contains the
operations policy: install, uninstall, status, tests, config, and safety. Paste
`AGENTS.md` into the rules file of the agent you use, after registering the MCP
server. Tell the agent to read `AGENT_GUIDE.md` before running install, remove,
or repair commands.

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

## How it works

1. Read text from arguments, a file, or stdin.
2. Clean markdown, URLs, code blocks, paths, hashes, tables, and emoji.
3. Limit the spoken text to `max_spoken_chars` and append "The rest is on screen."
4. Split the result into chunks of about 200 characters.
5. Synthesize each chunk with edge-tts, or piper after an edge failure.
6. Play the chunk through the first available player.
7. Delete the temporary audio and release the queue.

Speech jobs are serialized with `flock`, so two agents do not talk over each
other. `stop` increments a generation counter and kills the current worker and
player process group; queued workers see the new generation and exit without
speaking.

Runtime state lives in `.run/`. Temporary audio lives in `.tmp/`. Both are
ignored by git.

## Tests

```bash
bash tests/smoke_test.sh
```

Or use the menu entry point:

```bash
bash menu.sh test
```

The smoke test checks:

1. edge-tts produces audio (requires network);
2. piper produces audio offline;
3. the text cleaner removes markdown, URLs, code, paths, hashes, tables, and emoji;
4. the MCP server starts and lists `speak` and `stop_speaking`;
5. real playback works, or an audio-file fallback passes when no audio device is
   available.

`install.sh` runs the same test at the end.

## Troubleshooting

Start with:

```bash
bash menu.sh status
```

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
Check your desktop audio, PipeWire/PulseAudio, or WSL audio setup. `ffplay` is a
useful diagnostic because it prints errors when run manually.

**No sound but no error** — synthesize a file and play it with your normal audio
player:

```bash
./.venv/bin/python speak.py --engine piper --output test.wav "test"
```

**`nothing to speak`** — the input was empty, or the cleaner removed everything
(code blocks and URLs only). Check with `--clean-only`.

**MCP client does not show the tools** — use absolute paths to
`.venv/bin/python` and `mcp_server.py`, then run the command manually to see
startup errors. The server must run from an environment where `mcp` is installed.

**`install.sh` cannot find a supported Python** — install Python 3.11 or 3.12
and `python3-venv`. Python 3.14 is intentionally rejected by the piper stack.

**A queued job will not stop** — run `./.venv/bin/python speak.py stop`. If a
stale process remains, inspect it with `ps -ef | grep speak.py` before killing
anything.

## Privacy and security

- **edge-tts sends the text to Microsoft.** Do not send secrets or private data
  through the edge engine.
- **piper runs locally.** Use `--engine piper` when the text must stay on the
  machine.
- There are no API keys, accounts, telemetry, or network listeners.
- The MCP server uses stdio only.
- Text is passed to subprocesses as argument lists, not through a shell.
- `--file` reads any path the current user can read; treat it like any other
  file-reading CLI.
- Async fallback errors go to `.run/speak.log`. Temporary audio is deleted after
  each chunk and by `stop`.

## Limits

- Output only: no microphone, no speech-to-text, no realtime duplex chat.
- edge-tts needs internet; piper is offline but less expressive.
- Long text is truncated for speech, not summarized. The agent's full answer
  stays on screen.
- Speech is serialized. A second job waits for the first unless you call `stop`.
- One piper voice is installed by default. Add more with the download command.
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

This project's own code is licensed under the **MIT License**. It uses
third-party dependencies under their own terms: `edge-tts` is LGPL-3.0,
`piper-tts` is GPL-3.0-or-later, and `mcp` and `onnxruntime` are MIT. See
`LICENSE` and `THIRD_PARTY_NOTICES.md`.

If you redistribute a combined package that includes `piper-tts`, follow the
GPL-3.0-or-later terms for that combined distribution.

## Repository hygiene

The repository is set up so generated and private files are not committed:

- `.venv/` — local Python environment;
- `voices/*.onnx` and `voices/*.onnx.json` — downloaded voice models;
- `.run/` and `.tmp/` — runtime state and temporary audio;
- `config.json` — local configuration;
- `__pycache__/`, `*.pyc`, audio files, and logs.

Before publishing, run `git status` and confirm none of those appear. The
example registration files use `/ABSOLUTE/PATH/TO/voice-for-agent` placeholders;
replace them with your own absolute path locally, but do not commit machine-
specific paths.

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

Before committing, confirm `git status` does not show:

- `.venv/`
- `voices/*.onnx`
- `.run/`
- `.tmp/`
- `config.json`

The documentation already uses `rishb0` as the publishing account. If you push
to a different account or organization, replace `rishb0` in `README.md`,
`SKILL.md`, `AGENT_GUIDE.md`, `bootstrap.sh`, and the `.opencode` skill. Set the
GitHub repository visibility to public, enable Issues, and add topics such as
`text-to-speech`, `tts`, `mcp`, `opencode`, `piper`, and `edge-tts`.

The included GitHub Actions workflow runs syntax checks and a text-cleaner smoke
test on every push and pull request. It does not need network, audio hardware, or
the piper voice model.
