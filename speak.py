#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Small text-to-speech output tool for AI agents.

Output only: clean text, split it into chunks, synthesize with edge-tts
(online) or piper (offline), and play through mpv/ffplay/paplay/aplay.
"""

from __future__ import annotations

import argparse
import asyncio
import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import unicodedata
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

BASE_DIR = Path(__file__).resolve().parent
RUN_DIR = BASE_DIR / ".run"
TMP_DIR = BASE_DIR / ".tmp"
VOICES_DIR = BASE_DIR / "voices"
PIPER_VOICE = "en_US-ljspeech-high"
CONFIG_FILE = BASE_DIR / "config.json"
SPEECH_LOCK = RUN_DIR / "speech.lock"
CONTROL_LOCK = RUN_DIR / "control.lock"
ACTIVE_FILE = RUN_DIR / "active.json"
GENERATION_FILE = RUN_DIR / "generation"
LOG_FILE = RUN_DIR / "speak.log"

DEFAULT_CONFIG = {
    "engine": "edge",
    "voice": "en-US-AriaNeural",
    "voice_hi": "hi-IN-MadhurNeural",
    "auto_voice": True,
    "piper_voice": PIPER_VOICE,
    "rate": "+0%",
    "pitch": "+0Hz",
    "max_spoken_chars": 1200,
}
MAX_CHUNK_CHARS = 200
RATE_RE = re.compile(r"^[+-]?\d+%$")
PITCH_RE = re.compile(r"^[+-]?\d+Hz$")
TMP_SUFFIXES = {".mp3", ".wav"}


@dataclass
class Options:
    engine: str = "edge"
    voice: str = "en-US-AriaNeural"
    voice_hi: str = "hi-IN-MadhurNeural"
    auto_voice: bool = True
    piper_voice: str = PIPER_VOICE
    rate: str = "+0%"
    pitch: str = "+0Hz"
    max_chars: int = 1200


def log(message: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"{stamp} voice-for-agent: {message}", file=sys.stderr, flush=True)


def ensure_dirs() -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)


def load_config() -> dict:
    config = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        try:
            loaded = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                config.update({k: v for k, v in loaded.items() if k in DEFAULT_CONFIG})
        except Exception as exc:
            log(f"ignoring bad config.json: {_one_line(exc)}")
    return config


def _one_line(value: object, limit: int = 200) -> str:
    return str(value).replace("\n", " ").replace("\r", " ")[:limit]


def _is_decorative(ch: str) -> bool:
    cp = ord(ch)
    if cp in (0x200D, 0xFE0E, 0xFE0F, 0x20E3):
        return True
    if 0x1F000 <= cp <= 0x1FAFF:
        return True
    if 0x2600 <= cp <= 0x27BF:
        return True
    if 0x2B00 <= cp <= 0x2BFF:
        return True
    if 0x1F1E6 <= cp <= 0x1F1FF:
        return True
    return unicodedata.category(ch) in {"So", "Sk", "Cs", "Co", "Cn"}


def _looks_like_hash(value: str) -> bool:
    return any(c.isdigit() for c in value) and any(c.isalpha() for c in value)


def clean_text(raw: str) -> str:
    """Turn markdown-ish agent output into short plain sentences."""
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)

    # Fenced code blocks are never read aloud.
    text = re.sub(r"```.*?```", " Code block omitted. ", text, flags=re.S)
    text = re.sub(r"~~~.*?~~~", " Code block omitted. ", text, flags=re.S)
    text = text.replace("```", " ").replace("~~~", " ")

    # Inline code: keep the words, drop the marks.
    text = re.sub(r"`([^`\n]+)`", r"\1", text)

    # Images, markdown links, and autolinks.
    text = re.sub(
        r"!\[([^\]]*)\]\([^)]+\)",
        lambda m: m.group(1) or "image",
        text,
    )
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"<https?://[^>]+>", " link ", text, flags=re.I)

    # URLs and long paths.
    text = re.sub(r"(?:https?://|ftp://|www\.)\S+", " link ", text, flags=re.I)
    text = re.sub(
        r"(?<![\w/])(?:[A-Za-z]:\\|\.{0,2}/)[^\s`'\"()\[\]{}<>]{3,}",
        " file path ",
        text,
    )
    text = re.sub(
        r"\b[\w.-]+/[\w./-]+\.[A-Za-z0-9]{1,6}\b",
        " file path ",
        text,
    )

    # Hashes and commit ids.
    text = re.sub(
        r"\b[0-9a-fA-F]{7,64}\b",
        lambda m: " hash " if _looks_like_hash(m.group(0)) else m.group(0),
        text,
    )

    # HTML tags.
    text = re.sub(r"<[^>\n]+>", " ", text)

    # Tables: drop separator rows, turn cells into commas.
    lines: list[str] = []
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        if "|" in stripped and re.fullmatch(r"\|?[\s:|-]+\|?", stripped):
            continue
        if stripped.count("|") >= 2:
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            stripped = ", ".join(c for c in cells if c)
            if stripped and stripped[-1] not in ".!?;:":
                stripped += "."
        lines.append(stripped)
    text = "\n".join(lines)

    # Headings, quotes, rules, bullets, numbered lists.
    cleaned_lines: list[str] = []
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        if re.fullmatch(r"([-*_])\1{2,}", stripped):
            continue
        heading = re.match(r"^#{1,6}\s*(.*)$", stripped)
        if heading:
            stripped = heading.group(1).strip()
            if stripped and stripped[-1] not in ".!?;:":
                stripped += "."
        stripped = re.sub(r"^>\s*", "", stripped)
        bullet = re.match(r"^(?:[-*+]|\d+[.)])\s+(.*)$", stripped)
        if bullet:
            stripped = bullet.group(1).strip()
            if stripped and stripped[-1] not in ".!?;:":
                stripped += "."
        cleaned_lines.append(stripped)
    text = " ".join(cleaned_lines)

    # Markdown emphasis and leftover symbols.
    text = re.sub(r"\*\*|__|~~", "", text)
    text = re.sub(r"[*_~#|>]+", " ", text)

    # Emojis and decorative unicode.
    text = "".join(ch for ch in text if not _is_decorative(ch))

    # Whitespace and punctuation cleanup.
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"\s+([,.;:!?])", r"\1", text)
    text = re.sub(r"([,.;:!?])\1+", r"\1", text)
    text = re.sub(r"\(\s*\)|\[\s*\]", " ", text)
    text = text.strip(" -:;,.")
    if text and text[-1] not in ".!?":
        text += "."
    return text


def limit_text(text: str, max_chars: int) -> str:
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    cut = text[:max_chars]
    boundary = max(cut.rfind(". "), cut.rfind("! "), cut.rfind("? "))
    if boundary > max_chars // 2:
        cut = cut[: boundary + 1]
    return cut.rstrip() + " The rest is on screen."


def chunk_text(text: str, limit: int = MAX_CHUNK_CHARS) -> list[str]:
    sentences = re.split(r"(?<=[.!?])\s+", text)
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        if len(sentence) > limit:
            if current:
                chunks.append(current)
                current = ""
            chunks.extend(_split_long(sentence, limit))
        elif not current:
            current = sentence
        elif len(current) + 1 + len(sentence) <= limit:
            current += " " + sentence
        else:
            chunks.append(current)
            current = sentence
    if current:
        chunks.append(current)
    return [c for c in chunks if c]


def _split_long(text: str, limit: int) -> list[str]:
    parts: list[str] = []
    remaining = text.strip()
    while len(remaining) > limit:
        cut = remaining.rfind(" ", 0, limit)
        if cut < limit // 2:
            cut = limit
        parts.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()
    if remaining:
        parts.append(remaining)
    return parts


def normalize_rate(rate: str) -> str:
    rate = (rate or "+0%").strip()
    if not RATE_RE.match(rate):
        raise ValueError(f"invalid rate {rate!r}; use a value like +10% or -10%")
    if rate[0] not in "+-":
        rate = "+" + rate
    return rate


def normalize_pitch(pitch: str) -> str:
    pitch = (pitch or "+0Hz").strip()
    if not PITCH_RE.match(pitch):
        raise ValueError(f"invalid pitch {pitch!r}; use a value like +0Hz or -10Hz")
    if pitch[0] not in "+-":
        pitch = "+" + pitch
    return pitch


def _piper_length_scale(rate: str) -> float:
    try:
        percent = int(rate.rstrip("%"))
    except ValueError:
        percent = 0
    speed = max(0.5, min(2.0, 1.0 + percent / 100.0))
    return 1.0 / speed


def synth_edge(
    text: str,
    voice: str,
    rate: str,
    output: Path,
    pitch: str = "+0Hz",
) -> None:
    import edge_tts

    async def _save() -> None:
        communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        await communicate.save(str(output))

    asyncio.run(_save())
    if not output.exists() or output.stat().st_size < 100:
        raise RuntimeError("edge-tts produced no audio")


_piper_voices: dict[str, Any] = {}


def synth_piper(text: str, piper_voice: str, rate: str, output: Path) -> None:
    model = VOICES_DIR / f"{piper_voice}.onnx"
    if not model.exists():
        raise FileNotFoundError(f"piper voice model missing: {model}")

    import wave

    from piper import PiperVoice, SynthesisConfig

    model_key = str(model)
    voice = _piper_voices.get(model_key)
    if voice is None:
        voice = PiperVoice.load(model_key)
        _piper_voices[model_key] = voice
    config = SynthesisConfig(length_scale=_piper_length_scale(rate))
    with wave.open(str(output), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file, syn_config=config)
    if not output.exists() or output.stat().st_size < 100:
        raise RuntimeError("piper produced no audio")


def player_commands(path: Path) -> list[list[str]]:
    commands: list[list[str]] = []
    if shutil.which("mpv"):
        commands.append(["mpv", "--no-video", "--really-quiet", str(path)])
    if shutil.which("ffplay"):
        commands.append(
            ["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", str(path)]
        )
    if path.suffix.lower() == ".wav":
        if shutil.which("paplay"):
            commands.append(["paplay", str(path)])
        if shutil.which("aplay"):
            commands.append(["aplay", "-q", str(path)])
    return commands


def _read_generation() -> int:
    try:
        return int(GENERATION_FILE.read_text(encoding="utf-8").strip())
    except Exception:
        return 0


def _bump_generation() -> int:
    ensure_dirs()
    with open(CONTROL_LOCK, "a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        value = _read_generation() + 1
        tmp = GENERATION_FILE.with_suffix(".tmp")
        tmp.write_text(str(value), encoding="utf-8")
        os.replace(tmp, GENERATION_FILE)
        fcntl.flock(lock, fcntl.LOCK_UN)
    return value


def _write_active(data: dict) -> None:
    ensure_dirs()
    tmp = ACTIVE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, ACTIVE_FILE)


def _read_active() -> dict:
    try:
        data = json.loads(ACTIVE_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _clear_active(job_pid: int | None = None) -> None:
    if job_pid is not None:
        current = _read_active()
        if current.get("job") not in (None, job_pid):
            return
    try:
        ACTIVE_FILE.unlink()
    except FileNotFoundError:
        pass


def is_speaking() -> bool:
    """Return True when an active job or player process is still running."""
    state = _read_active()
    for key in ("job", "player"):
        pid = state.get(key)
        if not isinstance(pid, int):
            continue
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        except PermissionError:
            return True
        return True
    return False


def _kill_pid(pid: int | None, sig: int = signal.SIGTERM) -> None:
    if not pid:
        return
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        return
    except PermissionError:
        return


def _kill_group(pid: int | None, sig: int = signal.SIGTERM) -> None:
    if not pid:
        return
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        return
    except PermissionError:
        return


def _wait_dead(pid: int | None, timeout: float = 1.5) -> bool:
    if not pid:
        return True
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        time.sleep(0.05)
    return False


def stop_speaking() -> None:
    """Stop the current job and invalidate every queued job."""
    ensure_dirs()
    log("stop requested")
    _bump_generation()
    state = _read_active()
    old_job = state.get("job")
    old_job_id = state.get("job_id")
    player = state.get("player")
    if isinstance(player, int):
        _kill_pid(player, signal.SIGTERM)
    if isinstance(old_job, int):
        _kill_group(old_job, signal.SIGTERM)
    if isinstance(player, int) and not _wait_dead(player):
        _kill_pid(player, signal.SIGKILL)
    if isinstance(old_job, int) and not _wait_dead(old_job):
        _kill_group(old_job, signal.SIGKILL)
    if isinstance(old_job, int):
        _clear_active(old_job)
    if isinstance(old_job_id, str):
        _cleanup_job_audio(old_job_id)
    elif isinstance(old_job, int):
        _cleanup_temp_audio()


def _cleanup_temp_audio() -> None:
    for item in TMP_DIR.iterdir():
        if item.is_file() and item.suffix.lower() in TMP_SUFFIXES:
            try:
                item.unlink()
            except OSError:
                pass


def _cleanup_job_audio(job_id: str) -> None:
    for item in TMP_DIR.glob(f"{job_id}-*"):
        try:
            item.unlink()
        except OSError:
            pass


def _play_file(path: Path, generation: int, job_pid: int, job_id: str) -> bool:
    commands = player_commands(path)
    if not commands:
        log("no audio player found; install mpv or ffmpeg")
        return False

    for command in commands:
        if _read_generation() != generation:
            return False
        _write_active(
            {
                "job": job_pid,
                "player": None,
                "generation": generation,
                "job_id": job_id,
            }
        )
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        log(f"play: {' '.join(command)}")
        _write_active(
            {
                "job": job_pid,
                "player": process.pid,
                "generation": generation,
                "job_id": job_id,
            }
        )
        try:
            returncode = process.wait()
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        _write_active(
            {
                "job": job_pid,
                "player": None,
                "generation": generation,
                "job_id": job_id,
            }
        )
        if returncode == 0:
            return True
        log(f"player exited {returncode}: {' '.join(command)}")
    log("playback failed; install mpv or ffmpeg and check the audio device")
    return False


DEVANAGARI_RE = re.compile(r"[\u0900-\u097F]")


def _has_devanagari(text: str) -> bool:
    return bool(DEVANAGARI_RE.search(text))


def _voice_for(text: str, options: Options) -> str:
    """Pick the Hindi voice for Devanagari, the main voice otherwise."""
    if options.auto_voice and _has_devanagari(text):
        return options.voice_hi
    return options.voice


def _synthesize(
    text: str,
    engine: str,
    options: Options,
    output: Path,
) -> tuple[str, Path]:
    if engine == "edge":
        voice = _voice_for(text, options)
        try:
            synth_edge(text, voice, options.rate, output, options.pitch)
            log(f"voice: {voice}")
            return "edge", output
        except Exception as exc:
            log(f"edge-tts failed, falling back to piper: {_one_line(exc)}")
            engine = "piper"
    wav_output = output.with_suffix(".wav")
    synth_piper(text, options.piper_voice, options.rate, wav_output)
    return "piper", wav_output


def run_job(raw_text: str, options: Options, generation: int) -> int:
    ensure_dirs()
    job_pid = os.getpid()
    job_id = uuid.uuid4().hex[:12]

    lock_handle = open(SPEECH_LOCK, "a+", encoding="utf-8")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        if _read_generation() != generation:
            return 0

        cleaned = limit_text(clean_text(raw_text), options.max_chars)
        if not cleaned:
            log("nothing to speak after cleaning")
            return 0
        chunks = chunk_text(cleaned)
        log(
            f"job {job_id}: {len(cleaned)} chars, {len(chunks)} chunk(s), "
            f"engine={options.engine}"
        )
        _write_active(
            {
                "job": job_pid,
                "player": None,
                "generation": generation,
                "job_id": job_id,
            }
        )

        engine = options.engine
        pending_output: Path | None = None
        try:
            for index, chunk in enumerate(chunks):
                if _read_generation() != generation:
                    return 0
                output = TMP_DIR / f"{job_id}-{index}.mp3"
                try:
                    engine, output = _synthesize(chunk, engine, options, output)
                except Exception as exc:
                    log(f"synthesis failed: {_one_line(exc)}")
                    return 1
                pending_output = output
                if _read_generation() != generation:
                    return 0
                if not _play_file(output, generation, job_pid, job_id):
                    return 1
                try:
                    output.unlink()
                except OSError:
                    pass
                pending_output = None
            log(f"job {job_id}: done")
            return 0
        finally:
            if pending_output is not None:
                try:
                    pending_output.unlink()
                except OSError:
                    pass
            _cleanup_job_audio(job_id)
            _clear_active(job_pid)
    except KeyboardInterrupt:
        state = _read_active()
        if state.get("job") == job_pid and isinstance(state.get("player"), int):
            _kill_pid(state["player"], signal.SIGTERM)
        return 130
    finally:
        try:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)
        finally:
            lock_handle.close()


def _worker_stderr() -> None:
    # Async workers log to a file so the agent's stdout/stderr stays clean.
    ensure_dirs()
    handle = open(LOG_FILE, "a", encoding="utf-8", buffering=1)
    os.dup2(handle.fileno(), 2)


def enqueue(raw_text: str, options: Options, wait: bool = False) -> int:
    """Start one worker process. The speech lock serializes jobs in order."""
    ensure_dirs()
    generation = _read_generation()
    command = [
        sys.executable,
        str(BASE_DIR / "speak.py"),
        "--worker",
        "--generation",
        str(generation),
        "--engine",
        options.engine,
        "--voice",
        options.voice,
        "--voice-hi",
        options.voice_hi,
        "--auto-voice" if options.auto_voice else "--no-auto-voice",
        "--piper-voice",
        options.piper_voice,
        f"--rate={options.rate}",
        f"--pitch={options.pitch}",
        "--max-chars",
        str(options.max_chars),
    ]
    env = os.environ.copy()
    if not wait:
        env["VOICE_FOR_AGENT_QUIET"] = "1"
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL if not wait else None,
        text=True,
        start_new_session=True,
        env=env,
    )
    try:
        assert process.stdin is not None
        process.stdin.write(raw_text)
        process.stdin.close()
    except BrokenPipeError:
        pass

    if not wait:
        return 0

    try:
        return process.wait()
    except KeyboardInterrupt:
        state = _read_active()
        job_id = state.get("job_id")
        if state.get("job") == process.pid:
            player = state.get("player")
            if isinstance(player, int):
                _kill_pid(player, signal.SIGTERM)
        _kill_group(process.pid, signal.SIGTERM)
        if not _wait_dead(process.pid):
            _kill_group(process.pid, signal.SIGKILL)
        _clear_active(process.pid)
        if isinstance(job_id, str):
            _cleanup_job_audio(job_id)
        return 130


def _read_input(args: argparse.Namespace, parser: argparse.ArgumentParser) -> str:
    if args.file:
        if args.file == "-":
            return sys.stdin.read()
        try:
            return Path(args.file).read_text(encoding="utf-8")
        except OSError as exc:
            log(f"cannot read {args.file}: {_one_line(exc)}")
            raise SystemExit(1)
    if args.text:
        return " ".join(args.text)
    if not sys.stdin.isatty():
        return sys.stdin.read()
    parser.error("no text given; pass text, --file, or stdin")


def _options_from_args(args: argparse.Namespace) -> Options:
    config = load_config()
    engine = args.engine or config["engine"]
    if engine not in ("edge", "piper"):
        raise ValueError(f"invalid engine {engine!r}; use edge or piper")
    voice = args.voice or config["voice"]
    voice_hi = args.voice_hi or config.get("voice_hi", DEFAULT_CONFIG["voice_hi"])
    if not isinstance(voice_hi, str) or not voice_hi.strip():
        raise ValueError("hindi voice must be a non-empty voice name")
    auto_voice = config.get("auto_voice", DEFAULT_CONFIG["auto_voice"])
    if not isinstance(auto_voice, bool):
        auto_voice = DEFAULT_CONFIG["auto_voice"]
    if args.voice is not None:
        auto_voice = False
    if getattr(args, "auto_voice", None) is not None:
        auto_voice = bool(args.auto_voice)
    piper_voice = args.piper_voice or config["piper_voice"]
    if not isinstance(piper_voice, str) or not piper_voice.strip():
        raise ValueError("piper voice must be a non-empty voice name")
    rate = normalize_rate(args.rate or config["rate"])
    pitch = normalize_pitch(args.pitch or config["pitch"])
    max_chars = args.max_chars if args.max_chars is not None else config["max_spoken_chars"]
    if int(max_chars) <= 0:
        raise ValueError("max chars must be greater than zero")
    return Options(
        engine=engine,
        voice=voice,
        voice_hi=voice_hi.strip(),
        auto_voice=auto_voice,
        piper_voice=piper_voice.strip(),
        rate=rate,
        pitch=pitch,
        max_chars=int(max_chars),
    )


def default_options() -> Options:
    """Options from config.json and defaults, with no CLI overrides."""
    return _options_from_args(
        argparse.Namespace(
            engine=None,
            voice=None,
            voice_hi=None,
            auto_voice=None,
            piper_voice=None,
            rate=None,
            pitch=None,
            max_chars=None,
        )
    )


def list_voices() -> int:
    try:
        import edge_tts

        voices = asyncio.run(edge_tts.list_voices())
        for voice in sorted(voices, key=lambda v: v["ShortName"]):
            print(
                f"edge\t{voice['ShortName']}\t{voice.get('Gender', '')}\t"
                f"{voice.get('Locale', '')}"
            )
    except Exception as exc:
        log(f"edge-tts voices unavailable: {_one_line(exc)}")

    installed = sorted(VOICES_DIR.glob("*.onnx")) if VOICES_DIR.exists() else []
    installed_names = {model.stem for model in installed}
    for model in installed:
        label = "default" if model.stem == PIPER_VOICE else "local"
        print(f"piper\t{model.stem}\t{label}\tlocal")
    if PIPER_VOICE not in installed_names:
        print(f"piper\t{PIPER_VOICE}\tmissing\tlocal")
    return 0


def synthesize_to_file(text: str, options: Options, output: Path) -> int:
    output.parent.mkdir(parents=True, exist_ok=True)
    cleaned = limit_text(clean_text(text), options.max_chars)
    if not cleaned:
        log("nothing to synthesize after cleaning")
        return 1
    # Keep the container and extension consistent with the engine. If edge-tts
    # fails and piper takes over, _synthesize returns the actual .wav path.
    suffix = ".mp3" if options.engine == "edge" else ".wav"
    if output.suffix.lower() != suffix:
        output = output.with_suffix(suffix)
    try:
        _, actual = _synthesize(cleaned, options.engine, options, output)
    except Exception as exc:
        log(f"synthesis failed: {_one_line(exc)}")
        return 1
    print(actual)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Speak agent text with edge-tts or piper."
    )
    parser.add_argument("text", nargs="*", help="text to speak")
    parser.add_argument("--file", help="read text from a file, or - for stdin")
    parser.add_argument(
        "--async",
        dest="async_mode",
        action="store_true",
        help="return immediately and speak in the background",
    )
    parser.add_argument("--engine", choices=("edge", "piper"))
    parser.add_argument("--voice", help="edge-tts voice name")
    parser.add_argument(
        "--voice-hi",
        dest="voice_hi",
        help="edge-tts voice used for Devanagari text",
    )
    parser.add_argument(
        "--auto-voice",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="use the Hindi voice automatically for Devanagari text",
    )
    parser.add_argument("--piper-voice", help="installed piper voice name")
    parser.add_argument("--rate")
    parser.add_argument("--pitch")
    parser.add_argument("--max-chars", type=int, dest="max_chars")
    parser.add_argument("--list-voices", action="store_true")
    parser.add_argument(
        "--is-speaking",
        action="store_true",
        help="print speaking or idle and exit",
    )
    parser.add_argument(
        "--clean-only",
        action="store_true",
        help="print cleaned text and exit",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="synthesize to this file instead of playing",
    )
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument(
        "--generation", type=int, default=-1, help=argparse.SUPPRESS
    )
    return parser


def _normalize_argv(argv: list[str] | None) -> list[str]:
    """Keep negative rate and pitch values from looking like options."""
    values = list(sys.argv[1:] if argv is None else argv)
    result: list[str] = []
    index = 0
    while index < len(values):
        item = values[index]
        if (
            item in ("--rate", "--pitch")
            and index + 1 < len(values)
            and values[index + 1].startswith("-")
            and not values[index + 1].startswith("--")
        ):
            result.append(f"{item}={values[index + 1]}")
            index += 2
            continue
        result.append(item)
        index += 1
    return result


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(_normalize_argv(argv))

    if args.list_voices:
        return list_voices()

    if args.is_speaking:
        print("speaking" if is_speaking() else "idle")
        return 0

    if args.text == ["stop"] and not args.file and not args.output:
        stop_speaking()
        return 0

    try:
        options = _options_from_args(args)
    except (ValueError, TypeError) as exc:
        log(str(exc))
        return 2

    if args.worker:
        raw_text = sys.stdin.read()
        if os.environ.get("VOICE_FOR_AGENT_QUIET") == "1":
            _worker_stderr()
        return run_job(raw_text, options, args.generation)

    text = _read_input(args, parser)

    if args.clean_only:
        print(clean_text(text))
        return 0

    if args.output:
        return synthesize_to_file(text, options, args.output)

    if not text.strip():
        log("nothing to speak")
        return 0

    if args.async_mode:
        code = enqueue(text, options, wait=False)
        if code == 0:
            print("queued")
        return code

    return enqueue(text, options, wait=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except OSError:
            pass
        raise SystemExit(0)
