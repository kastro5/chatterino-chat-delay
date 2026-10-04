# Testing on Windows

This guide sets up a separate, portable Chatterino nightly next to your normal
install. Your main Chatterino settings, accounts and tabs are not touched.

Everything should take about 15 minutes.

## 1. Get a portable nightly

1. Download `chatterino-windows-x86-64-Qt-6.8.3.zip` from the
   [nightly-build release](https://github.com/Chatterino/chatterino2/releases/tag/nightly-build).
   (The Qt version in the name may change; grab the Windows `.zip`.)
2. Extract it somewhere of its own, e.g. `C:\Tools\Chatterino-nightly\`.
   You should end up with `C:\Tools\Chatterino-nightly\Chatterino2\chatterino.exe`.
3. **Make it portable.** In that `Chatterino2` folder, create a file named
   `modes` (no extension) whose only line is `portable`:

   ```powershell
   Set-Content -Path C:\Tools\Chatterino-nightly\Chatterino2\modes -Value portable -NoNewline
   ```

   Without this, the nightly would use `%APPDATA%\Chatterino2`, which is the
   same settings folder as your main install. With it, settings, logs and
   plugins live inside `C:\Tools\Chatterino-nightly\Chatterino2\`.

4. Run `chatterino.exe` once, then close it. This creates the `Plugins`
   folder. If Windows SmartScreen complains, choose *More info → Run anyway*
   (nightlies aren't signed).

## 2. Get the plugin

Clone the repo anywhere, e.g. `C:\Code`:

```powershell
cd C:\Code
git clone https://github.com/kastro5/chat-delay.git
```

Link the repo's `plugin` folder into the nightly's `Plugins` folder. A
**junction** works without admin rights or Developer Mode, and `git pull`
updates the plugin in place:

```powershell
New-Item -ItemType Junction `
  -Path   C:\Tools\Chatterino-nightly\Chatterino2\Plugins\chat-delay `
  -Target C:\Code\chat-delay\plugin
```

The folder name must be exactly `chat-delay`. Chatterino uses it as the
plugin's ID.

(If you'd rather not link, copy the *contents* of `plugin\` into
`Plugins\chat-delay\` instead, and re-copy after each update.)

## 3. Enable it

1. Start `chatterino.exe`.
2. Optionally, log in (the account button, top left). This is needed to test
   that your own messages aren't delayed. The portable copy has its own
   accounts, separate from your main install.
3. Open **Settings → Plugins**.
4. Tick **Enable plugins**.
5. Find **Chat Delay** in the list. It declares FilesystemRead/Write, which
   only cover its own `data` folder. Press **Enable**.
6. Press **Open REPL** next to the plugin. This window shows the plugin's
   log output and any Lua errors, so keep it open while testing.

After pulling changes from git, press **Reload** on the plugin, or restart
Chatterino.

## 4. Smoke test

Open a split for a busy channel and type:

```
/delay selftest
```

After about 3 seconds you should see `[chat-delay] Selftest: 20 passed, 0 failed.`
Any failures are listed underneath and in the REPL window.

## 5. What to check

These are the parts that couldn't be tested headless. Tick them off as you go.

**Basics**
- [ ] `/delay 10`: chat goes quiet for about 10s, then flows again,
      consistently 10s late. Compare against the same channel open in your
      main Chatterino, or on twitch.tv.
- [ ] No blank gaps or stray lines in the chat while messages are held.
      Also try it with **Settings → General → Messages → Separate with lines** turned on.
- [ ] The chat stays pinned to the bottom. Scroll up, wait, scroll back down:
      it should resume normally.
- [ ] `/delay +2` and `/delay -1` change the delay smoothly, and `/delay`
      shows the new value.
- [ ] `/delay off` instantly shows everything that was held.

**Behaviour**
- [ ] While logged in, **your own messages appear instantly** while others
      stay delayed.
- [ ] Right-click a chat message: there's a **Chat delay (10s)** submenu, and
      its ±1s / ±5s / Off items work.
- [ ] A typo like `/delay abc` shows a help message instantly (not 10s late).
- [ ] Two channels in different splits: delaying one doesn't affect the other.
- [ ] A split with a filter (split menu → *Set filters*) still respects the
      filter under a delay.
- [ ] If you're a mod somewhere (or with a friend): a message deleted during
      the delay shows up greyed out as deleted. The selftest only simulates this.

**Known leak, to gauge how bad it is**
- [ ] With a delay active, open a *second* split of the same channel. A few
      messages arriving in the first ~0.5s may show undelayed. Note whether
      it's noticeable.

**Persistence**
- [ ] With saving off (the default), restart Chatterino and run `/delay`.
      It should say `off`.
- [ ] `/delay persist on`, `/delay 15`, restart, then run `/delay`. It should
      say `15s`. Run `/delay persist off` afterwards if you don't want that.

**Real use**
- [ ] Watch an actual delayed stream. Pick a moment chat clearly reacts to
      (a goal, a kill), and tune with `/delay +n` / `-n` until it lines up.
      Note the delay you ended up with.

## Debug output (if something breaks)

The REPL window usually has what you need. For full Chatterino logs, start
it from a terminal with the verbose flag:

```powershell
$env:QT_LOGGING_RULES = "chatterino.lua=true"
C:\Tools\Chatterino-nightly\Chatterino2\chatterino.exe -v
```

Lines from the plugin start with `[chat-delay:Chat Delay]`.

The plugin's saved settings are in
`C:\Code\chat-delay\plugin\data\settings.json` (through the junction).
Git ignores that folder.

## Cleaning up

Delete `C:\Tools\Chatterino-nightly\`. Nothing outside it was changed, apart
from the cloned repo.
