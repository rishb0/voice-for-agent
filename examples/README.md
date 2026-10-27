# Registration examples

For install, uninstall, status, tests, and the menu, read `../AGENT_GUIDE.md`
and use `bash menu.sh <command>` from the project root.

Edit the placeholder `/ABSOLUTE/PATH/TO/voice-for-agent` in each example so it points at this folder. Use the absolute path to `.venv/bin/python` and `mcp_server.py`.

Run the Claude Code example with `bash examples/claude-code.sh` after editing it.

OpenCode uses `opencode.jsonc` (or `opencode.json`) with the `mcp.servers` shape. Claude Code uses the `claude mcp add` command. Gemini CLI uses `settings.json`.

The server name in these examples is `voice-for-agent`, so the tools appear as `voice-for-agent_speak` and `voice-for-agent_stop_speaking` in OpenCode after name normalization.
