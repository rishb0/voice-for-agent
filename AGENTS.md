# Voice output rules for agents

Paste this into any agent's rules file. The `speak` and `stop_speaking` tools
come from the voice-for-agent MCP server.

For install, uninstall, status, tests, config, or the menu, read
`AGENT_GUIDE.md` and use `bash menu.sh <command>`. Do not guess commands.

After finishing each task or answer, call the `speak` tool once with a 2-4 sentence plain-language summary of what you just did or found.

Do not read code, commands, paths, or long lists aloud. Say what they are instead.

Keep the full detailed answer on screen as normal.

If the user says "read it fully", speak the full answer in chunks.

If the user says "stop talking" or "mute", call `stop_speaking` and do not call `speak` again until told otherwise.
