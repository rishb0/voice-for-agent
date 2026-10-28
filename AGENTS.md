# Voice output rules for agents

The `speak` and `stop_speaking` tools come from the voice-for-agent MCP server.

For install, uninstall, status, tests, config, or the menu, read
`AGENT_GUIDE.md` and use `bash menu.sh <command>`. Do not guess commands.

For the double-tap Ctrl hotkey service, use `systemctl --user`:

```bash
systemctl --user start|stop|restart|status voice-for-agent-hotkey.service
```

Do not edit the unit in `~/.config/systemd/user/` by hand. Change
`systemd/voice-for-agent-hotkey.service.in` and rerun
`bash menu.sh service install`.

Default: do not speak unless the user asks.

- "speak", "read aloud", "say it", "voice this": call `speak` with a 2-4
  sentence plain-language summary.
- "read it fully": call `speak` with the full answer in chunks.
- "voice on" or "auto speak": after each answer, call `speak` with a 2-4
  sentence summary until the user says "voice off".
- "voice off", "mute", "stop talking", "stop": call `stop_speaking` and do not
  speak again until the user asks.
- Before calling `speak`, say "Speaking." in chat.
- Keep the full detailed answer on screen.
- Do not read code, commands, paths, or long lists aloud. Say what they are.
- Do not send secrets or private data through edge-tts.

Check the audio state with `bash menu.sh speaking`.
