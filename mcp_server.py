#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Thin MCP stdio wrapper around speak.py."""

from __future__ import annotations

import logging
import sys

from mcp.server.fastmcp import FastMCP

import speak as tts

logging.basicConfig(stream=sys.stderr, level=logging.WARNING)

mcp = FastMCP(
    "voice-for-agent",
    instructions=(
        "Use speak for a short spoken summary of completed work. "
        "Use stop_speaking when the user asks to stop or mute."
    ),
    log_level="ERROR",
)

SPEAK_DESCRIPTION = (
    "Speak a SHORT spoken summary (2-4 sentences, plain language, no code, "
    "no markdown) of what you just did or found. Returns immediately after "
    "queueing; it never blocks the agent."
)


@mcp.tool(description=SPEAK_DESCRIPTION)
def speak(text: str) -> str:
    """Speak a SHORT spoken summary of what you just did or found."""
    if not text or not text.strip():
        return "nothing to speak"
    tts.enqueue(text, tts.default_options(), wait=False)
    return "queued"


@mcp.tool(
    description=(
        "Stop the current speech and clear every queued speech job. "
        "Use when the user says stop talking or mute."
    )
)
def stop_speaking() -> str:
    """Stop current speech and clear the queue."""
    tts.stop_speaking()
    return "stopped"


if __name__ == "__main__":
    mcp.run(transport="stdio")
