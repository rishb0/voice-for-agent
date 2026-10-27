# Third-party notices

`voice-for-agent` is licensed under the MIT License. It uses the following
third-party software and models, each under its own license. This file is a
summary, not legal advice. Check each upstream project for the authoritative
license text.

The MIT license covers this repository's own code. `piper-tts` is
GPL-3.0-or-later; if you redistribute a combined work that includes it, comply
with piper's license terms.

## Runtime dependencies

| Component | Version | License | Upstream |
|---|---|---|---|
| edge-tts | 7.3.1 | LGPL-3.0 (one file is MIT) | https://github.com/rany2/edge-tts |
| piper-tts | 1.8.0 | GPL-3.0-or-later | https://github.com/OHF-Voice/piper1-gpl |
| mcp | 1.30.0 | MIT | https://github.com/modelcontextprotocol/python-sdk |
| onnxruntime | 1.31.1 | MIT | https://github.com/microsoft/onnxruntime |

`edge-tts` sends text to Microsoft's Edge speech service. Review Microsoft's
terms and privacy policy before sending sensitive text through that engine.
`piper-tts` and `onnxruntime` run locally and do not send text to a service.

## Default piper voice

The installer downloads `en_US-ljspeech-high` from the
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) repository.

- Model card: https://huggingface.co/rhasspy/piper-voices/raw/main/en/en_US/ljspeech/high/MODEL_CARD
- Dataset: [LJ Speech Dataset](https://keithito.com/LJ-Speech-Dataset/)
- Dataset license: public domain
- Training: trained from scratch for 1000 epochs on the LJ Speech dataset

The model files are downloaded by `install.sh` and are intentionally ignored by
git. They are not part of this repository.

If you change `piper_voice` in `config.json`, check that voice's `MODEL_CARD`
before redistributing or using it commercially. Several Piper voices are
fine-tuned from the Lessac voice and carry research-only or non-commercial
terms. The previous default, `en_US-lessac-medium`, uses the Blizzard 2013
research license, which is not suitable for commercial use.

## System playback tools

`mpv`, `ffplay`, `paplay`, and `aplay` are system tools and are not bundled.
Their licenses depend on the distribution and build. `ffplay` is part of
FFmpeg; FFmpeg builds may be LGPL or GPL depending on their configuration.

## Python dependencies

The complete Python dependency set is pinned in `requirements.txt`. Transitive
dependencies keep their own licenses. Run `pip-licenses` in the virtualenv if
you need a complete inventory for redistribution.
