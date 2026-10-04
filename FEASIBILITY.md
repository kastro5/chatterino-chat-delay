# Chat delay for Chatterino: plugin or fork?

Researched against chatterino2 `master` @ dda5be5f (2026-10-01) and tag `v2.5.5`.

## Verdict

**A plugin can do it, but only on nightly / the next release, and with caveats.**
A fork is the clean solution. Use it if the caveats below are deal-breakers.

## Why it's possible (master only)

The plugin API (Lua, `c2` global, enabled by default since 2.5.3) now has:

| Need | API | In 2.5.5? |
|---|---|---|
| See each incoming message | `Channel:on_message_appended(cb)` (sync, gets the real `Message`) | **No** (Unversioned) |
| Hide it immediately | `Channel:replace_message(msg, placeholder)` | Yes (#6650) |
| Show it later | `c2.later(cb, ms)` then `replace_message(placeholder, original)` | Yes |
| Find open channels | `c2.Channel.by_name`, `c2.windows` -> splits -> `split.channel` | Yes |
| UI to set the delay | `c2.register_command("/delay", ...)` | Yes |

### Mechanism ("placeholder swap")
1. `on_message_appended(msg)`: keep `msg`, then synchronously
   `channel:replace_message(msg, emptyPlaceholder)`.
2. `c2.later(D)`: `channel:replace_message(placeholder, msg)`.

Why it works:
- `Channel::addMessage` emits `messageAppended` synchronously, and pajlada
  signals call handlers **in connection order**
  (`lib/signals/.../signal.hpp` `invoke`).
- The ChannelView's proxy handler appends the message and only calls
  `queueLayout()`. Painting happens later in the event loop. If our handler
  runs after it, the replace comes in before the first paint, so the message
  is never seen.
- An empty message (no elements) lays out to **height 0**
  (`MessageLayoutContainer::beginLayout`/`endLayout`), so placeholders are invisible.
- Order is kept. Replacing in place keeps the alternating background.
- Deletes and timeouts set `Disabled` on the original object (flags stay
  mutable after freeze), so a message deleted during the delay should show
  as deleted when it appears (verified by `/delay selftest` on nightly 2.5.5-277).

## Caveats / leaks

1. **Handler order.** If a split connects to the channel *after* the plugin
   (you open a new split for that channel, or one gets re-set), that view's
   handler runs after ours. The original gets appended to the view's proxy
   channel after our replace. Our replace already ran and found nothing in
   that proxy, so **the message shows immediately**.
   Workaround: disconnect and re-register the handler often (for example,
   after each message) so it stays last. Worst case: one message leaks each
   time a split is opened.
2. **Side effects happen on arrival, not on display.** Highlight sounds,
   desktop notifications, the `/mentions` split, tab highlight, logs, the
   user card message list, and reply threads all see the real message right
   away. Highlight sounds and mentions are the real spoiler risk.
3. Placeholders count toward the message buffer limit and scrollbar.
   That's harmless.
4. Timeout stacking ("timed out 3 times") may break, because Chatterino
   looks for the previous timeout message and finds a placeholder.
5. Needs a nightly build until the next release (2.5.6 / 2.6).
6. Delay is in-memory. Messages waiting in the queue are dropped if the plugin
   reloads.

## Fork alternative

Small and clean: in `ChannelView::setChannel`, the proxy `messageAppended`
handler (`src/widgets/helper/ChannelView.cpp` ~L962) could hold messages for
D ms (QTimer / a queue drained by a timer) before
`this->channel_->addMessage(...)`. That fixes caveat 1. Caveat 2 can be
fixed by delaying in `TwitchIrcServer`/`TwitchChannel` before
`addMessage` instead. That delays highlights, sounds and mentions too. Put
the delay in a per-split or per-channel setting. Cost: keeping a fork up to
date. An upstream PR or feature request might be the better long-term route.

## Recommendation

Prototype as a plugin on a nightly build first. It's cheap, and the
placeholder swap is the only risky part. If leak 1 or 2 is unacceptable,
go to the fork or an upstream PR.
