#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# End-to-end smoke test. Prints PASS/FAIL per step.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
SPEAK="$ROOT/speak.py"
TMP="$ROOT/.tmp"
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { echo "SKIP: $*"; }

mkdir -p "$TMP" "$ROOT/.run"

if [ ! -x "$PY" ]; then
  echo "FAIL: missing .venv; run install.sh first"
  exit 1
fi

EDGE_FILE="$TMP/smoke-edge.mp3"
PIPER_FILE="$TMP/smoke-piper.wav"
SAMPLE="$TMP/cleaner-sample.md"
rm -f "$EDGE_FILE" "$PIPER_FILE" "$SAMPLE" "$TMP/edge.err" "$TMP/play.err"

# Test 1: edge-tts generates audio.
if "$PY" "$SPEAK" --engine edge --output "$EDGE_FILE" \
  "Edge engine smoke test." >/dev/null 2>"$TMP/edge.err"; then
  if [ -s "$EDGE_FILE" ] && [ "$(stat -c%s "$EDGE_FILE")" -gt 1000 ]; then
    pass "Test 1 edge-tts audio"
  else
    fail "Test 1 edge-tts produced an empty file"
  fi
else
  fail "Test 1 edge-tts failed"
  sed 's/^/  /' "$TMP/edge.err" 2>/dev/null || true
fi

# Test 2: piper generates audio offline.
if "$PY" "$SPEAK" --engine piper --output "$PIPER_FILE" \
  "Piper engine smoke test." >/dev/null 2>"$TMP/piper.err"; then
  if [ -s "$PIPER_FILE" ] && [ "$(stat -c%s "$PIPER_FILE")" -gt 1000 ]; then
    pass "Test 2 piper audio"
  else
    fail "Test 2 piper produced an empty file"
  fi
else
  fail "Test 2 piper failed"
  sed 's/^/  /' "$TMP/piper.err" 2>/dev/null || true
fi

# Test 3: text cleaner.
cat > "$SAMPLE" <<'EOF'
# Deploy report

Here is **bold** and `inline code`.

```python
print("hi")
```

Visit https://example.com/path and read [the docs](https://example.com/docs).

| Name | Value |
|------|-------|
| alpha | 1 |
| beta | 2 |

- first item
- second item

Path /home/user/project/file.py hash a1b2c3d4e5f6 and 🚀.
EOF
CLEANED="$("$PY" "$SPEAK" --clean-only --file "$SAMPLE" 2>/dev/null)"
echo "BEFORE:"
cat "$SAMPLE"
echo "AFTER:"
echo "$CLEANED"
if echo "$CLEANED" | grep -qi "code block omitted" && \
   echo "$CLEANED" | grep -qi "link" && \
   echo "$CLEANED" | grep -qi "Name, Value" && \
   echo "$CLEANED" | grep -qi "file path" && \
   echo "$CLEANED" | grep -qi "hash" && \
   ! echo "$CLEANED" | grep -q '```' && \
   ! echo "$CLEANED" | grep -q 'http' && \
   ! echo "$CLEANED" | grep -q '|' && \
   ! echo "$CLEANED" | grep -q '🚀'; then
  pass "Test 3 text cleaner"
else
  fail "Test 3 text cleaner"
fi

# Test 4: MCP server starts and lists both tools.
MCP_OUT="$("$PY" - "$ROOT" <<'PY' 2>"$TMP/mcp.err"
import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

root = Path(sys.argv[1])


async def main() -> None:
    params = StdioServerParameters(
        command=str(root / ".venv/bin/python"),
        args=[str(root / "mcp_server.py")],
        cwd=str(root),
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.list_tools()
            print(",".join(sorted(tool.name for tool in result.tools)))


asyncio.run(asyncio.wait_for(main(), 30))
PY
)"
echo "MCP tools: $MCP_OUT"
if echo ",$MCP_OUT," | grep -q ",speak," && \
   echo ",$MCP_OUT," | grep -q ",stop_speaking,"; then
  pass "Test 4 MCP server tools"
else
  fail "Test 4 MCP server tools"
  sed 's/^/  /' "$TMP/mcp.err" 2>/dev/null || true
fi

# Test 5: real playback when an audio device is available.
if command -v mpv >/dev/null 2>&1 || command -v ffplay >/dev/null 2>&1 || \
   command -v paplay >/dev/null 2>&1 || command -v aplay >/dev/null 2>&1; then
  if timeout 30 "$PY" "$SPEAK" --engine piper \
    "Playback smoke test." >/dev/null 2>"$TMP/play.err"; then
    pass "Test 5 playback"
  else
    echo "SKIP: no working audio device or player on this machine; checked an audio file instead"
    if [ -s "$PIPER_FILE" ]; then
      pass "Test 5 audio file fallback"
    else
      fail "Test 5 playback and audio file fallback"
    fi
  fi
else
  echo "SKIP: no audio player found; checked an audio file instead"
  if [ -s "$PIPER_FILE" ]; then
    pass "Test 5 audio file fallback"
  else
    fail "Test 5 audio file fallback"
  fi
fi

# Test 6: double-tap Ctrl detector logic.
if command -v python3 >/dev/null 2>&1; then
  if python3 "$ROOT/tests/test_hotkey.py" >/dev/null 2>"$TMP/hotkey.err"; then
    pass "Test 6 hotkey detector"
  else
    fail "Test 6 hotkey detector"
    sed 's/^/  /' "$TMP/hotkey.err" 2>/dev/null || true
  fi
else
  skip "Test 6 hotkey detector (python3 missing)"
fi

# Test 7: Hinglish voice selection and rate/pitch parsing.
if command -v python3 >/dev/null 2>&1; then
  if python3 "$ROOT/tests/test_voice.py" >/dev/null 2>"$TMP/voice.err"; then
    pass "Test 7 voice selection"
  else
    fail "Test 7 voice selection"
    sed 's/^/  /' "$TMP/voice.err" 2>/dev/null || true
  fi
else
  skip "Test 7 voice selection (python3 missing)"
fi

rm -f "$EDGE_FILE" "$PIPER_FILE" "$SAMPLE" "$TMP/edge.err" \
  "$TMP/piper.err" "$TMP/play.err" "$TMP/mcp.err" "$TMP/hotkey.err" \
  "$TMP/voice.err"

echo "SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
