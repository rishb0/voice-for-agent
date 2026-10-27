#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# EDIT: replace /ABSOLUTE/PATH/TO/voice-for-agent with this folder's absolute path.
# Run this once with: bash examples/claude-code.sh
# It registers the server for the current user.
claude mcp add --scope user voice-for-agent -- \
  /ABSOLUTE/PATH/TO/voice-for-agent/.venv/bin/python \
  /ABSOLUTE/PATH/TO/voice-for-agent/mcp_server.py
