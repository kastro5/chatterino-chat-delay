# Chat Delay (Chatterino plugin)

Holds chat messages back by a fixed delay per channel, so chat lines up with a
delayed stream (sports broadcasts, a delayed restream, etc.).

**Requires a Chatterino nightly build.** It uses `Channel:on_message_appended`,
which isn't in 2.5.5. See [FEASIBILITY.md](FEASIBILITY.md) for how it works.

## Install

1. Install a [nightly build](https://github.com/Chatterino/chatterino2/releases/tag/nightly-build).
2. Link the plugin into Chatterino's plugin folder:
   ```sh
   ln -s "$PWD/plugin" ~/.local/share/chatterino/Plugins/chat-delay
   ```
   (Windows: `%APPDATA%\Chatterino2\Plugins\chat-delay`, macOS:
   `~/Library/Application Support/chatterino/Plugins/chat-delay`.)
3. Settings → Plugins: enable plugin support, then enable **Chat Delay**.
   Step-by-step for Windows, including a test checklist: [TESTING-WINDOWS.md](TESTING-WINDOWS.md).
   Chatterino creates `plugin/data/` for the plugin's settings. Git ignores it.

## Usage

Type these in the split for the channel you want to delay:

| Command | Effect |
|---|---|
| `/delay` | Show this channel's delay and how many messages are being held |
| `/delay 30` · `2.5s` · `800ms` · `2m` · `1:30` | Set the delay |
| `/delay +5` · `/delay -1.5` | Nudge the delay while syncing |
| `/delay off` | Show everything that's held and stop delaying |
| `/delay persist on` / `off` | Save delays across restarts (off by default, so delays are memory-only) |
| `/delay selftest` | Run a quick self-check in this channel (~3s) |

Right-clicking a message gives a **Chat delay** submenu with ±1s / ±5s / Off.

**Syncing tip:** find a moment both chat and the stream react to, like a goal.
Set a rough delay first, then nudge it with `+`/`-`. A change also re-times
messages that are already being held.

Your own messages and client-only notices (command output, connection status)
are always shown right away.

## Known limitations

These come from the plugin API. A Chatterino fork would be needed to fix them.

- **Sounds, notifications and mentions aren't delayed.** Highlight sounds,
  desktop notifications, the `/mentions` split, tab highlighting and logs all
  fire when a message arrives, not when it's shown.
- **Opening a new split for a delayed channel can leak a message.** Messages
  arriving in the ~0.5s after a split for that channel is (re)opened may show
  immediately.
- Messages being held when the plugin reloads or Chatterino closes are dropped
  from view.
- The "user timed out N times" counter may not stack for timeouts during the delay.

## Development

- `plugin/init.lua`: commands, the 100ms release tick, hooking open channels, and the context menu
- `plugin/delayer.lua`: hold/release (the placeholder swap)
- `plugin/config.lua`: per-channel delays, persistence, and duration parsing
- `plugin/selftest.lua`: `/delay selftest`
- `types/`: LuaLS definitions copied from chatterino2 `docs/lua-meta`. Note
  that `c2.ChannelType` keys are lowercase at runtime (`twitch`), unlike these
  definitions.

**Headless testing:** if `plugin/data/autotest` contains a channel name, the
self-test runs there once the channel has loaded. The results go to
`plugin/data/autotest-result.txt` and to the log (`SELFTEST ...` lines, with
`QT_LOGGING_RULES=chatterino.lua=true`).
