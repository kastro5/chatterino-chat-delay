# Chat Delay for Chatterino

Watching a delayed stream, like a sports broadcast or a restream? Chat reacts to
the goal before you see it. **Chat Delay** holds Twitch chat back by however many
seconds you set, per channel, so chat lines up with your stream.

<!-- TODO: screenshot or GIF of chat going quiet and catching up
![Chat Delay in action](docs/demo.gif)
-->

> [!IMPORTANT]
> **Requires a Chatterino nightly build.** The plugin relies on plugin APIs
> (`Channel:on_message_appended`, `Message:clone`, …) that aren't in a stable
> release yet. Stable 2.5.6 doesn't have them. On older versions the plugin
> loads, but `/delay` only tells you to update. The nightly can run
> [side by side with your normal Chatterino](TESTING-WINDOWS.md#1-get-a-portable-nightly).

## Install

1. Get a [Chatterino nightly](https://github.com/Chatterino/chatterino2/releases/tag/nightly-build).
2. Download `chat-delay-vX.Y.Z.zip` from the
   [latest release](https://github.com/kastro5/chatterino-chat-delay/releases)
   and extract it into Chatterino's `Plugins` folder. You should end up with
   `Plugins\chat-delay\init.lua`.
   - Windows: `%APPDATA%\Chatterino2\Plugins\`, or `<chatterino folder>\Plugins\` in portable mode
   - Linux: `~/.local/share/chatterino/Plugins/`
   - macOS: `~/Library/Application Support/chatterino/Plugins/`
3. In Chatterino, open **Settings → Plugins**, tick **Enable plugins**, then press
   **Enable** on **Chat Delay**.

Check it works: type `/delay selftest` in any channel. It should report
`20 passed, 0 failed`.

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
are always shown right away. Other channels aren't affected.

## Known limitations

These come from the plugin API. Fixing them would need changes in Chatterino itself.

- **Sounds, notifications and mentions aren't delayed.** Highlight sounds,
  desktop notifications, the `/mentions` split, tab highlighting and logs all
  fire when a message arrives, not when it's shown.
- **Opening a new split for a delayed channel can leak a message.** Messages
  arriving in the ~0.5s after a split for that channel is (re)opened may show
  immediately.
- Messages being held when the plugin reloads or Chatterino closes are dropped
  from view.
- The "user timed out N times" counter may not stack for timeouts during the delay.

Found a bug? [Open an issue](https://github.com/kastro5/chatterino-chat-delay/issues).

## How it works

Each incoming message is swapped for an invisible, zero-height copy before
Chatterino draws it. Once the delay has passed, the real message is swapped
back in at the same spot. [FEASIBILITY.md](FEASIBILITY.md) covers the details
and why a plugin can do this at all.

## Development

- `plugin/init.lua`: version check, commands, the 100ms release tick, hooking open channels, and the context menu
- `plugin/delayer.lua`: hold/release (the placeholder swap)
- `plugin/config.lua`: per-channel delays, persistence, and duration parsing
- `plugin/selftest.lua`: `/delay selftest`
- `types/`: LuaLS definitions copied from chatterino2 `docs/lua-meta`. Note
  that `c2.ChannelType` keys are currently lowercase at runtime (`twitch`),
  unlike these definitions
  ([chatterino2#7127](https://github.com/Chatterino/chatterino2/issues/7127)).

[TESTING-WINDOWS.md](TESTING-WINDOWS.md) sets up a portable nightly with the
plugin linked from a git checkout, and has a manual test checklist.

**Release zip:** `python scripts/package.py` writes `dist/chat-delay-v<version>.zip`.
The version comes from `plugin/info.json`.

**Headless testing:** if `plugin/data/autotest` contains a channel name, the
self-test runs there once the channel has loaded. The results go to
`plugin/data/autotest-result.txt` and to the log (`SELFTEST ...` lines, with
`QT_LOGGING_RULES=chatterino.lua=true`).

## License

[MIT](LICENSE)
