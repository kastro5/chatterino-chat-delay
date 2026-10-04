-- Holds incoming messages back by swapping them for an empty placeholder and
-- swaps the original back in once the channel's delay has passed.
--
-- Why this works: Channel::addMessage emits `messageAppended` synchronously and
-- handlers run in connection order. A split's ChannelView appends the message
-- and only queues a layout; our handler (connected after it) replaces the
-- message before anything is painted. An element-less message lays out with a
-- height of 0, so the placeholder is invisible.

local config = require("config")

local M = {}

local F = c2.MessageFlag

---@param names string[]
---@return integer
local function flag_mask(names)
    local mask = 0
    for _, name in ipairs(names) do
        if F[name] == nil then
            c2.log(c2.LogLevel.Warning, "unknown MessageFlag " .. name)
        else
            mask = mask | F[name]
        end
    end
    return mask
end

-- System messages without an author are normally client-side notices (command
-- output, connection status). These flags mark the ones that come from the
-- stream and should stay in sync with it.
local STREAM_NOTICE_FLAGS = flag_mask({
    "Timeout",
    "Untimeout",
    "ModerationAction",
    "ClearChat",
    "Subscription",
    "Announcement",
    "WatchStreak",
    "UncategorizedNotification",
    "RedeemedChannelPointReward",
    "CheerMessage",
    "AutoMod",
})

---@class PendingMessage
---@field original c2.Message
---@field placeholder c2.Message
---@field arrived integer Unix milliseconds

---@class ChannelState
---@field channel c2.Channel
---@field queue table<integer, PendingMessage>
---@field head integer
---@field tail integer
---@field appended? c2.ConnectionHandle
---@field cleared? c2.ConnectionHandle

---@type table<string, ChannelState>
local states = {}

local bypass_depth = 0

---@return integer
function M.now()
    return c2.DateTime.current_utc():to_unix_milliseconds()
end

---Runs `fn` with holding disabled, for messages the plugin adds itself.
---@param fn fun()
function M.with_bypass(fn)
    bypass_depth = bypass_depth + 1
    local ok, err = pcall(fn)
    bypass_depth = bypass_depth - 1
    if not ok then
        error(err, 0)
    end
end

---@param msg c2.Message
---@return boolean
local function should_hold(msg)
    if bypass_depth > 0 then
        return false
    end

    local login = msg.login_name
    if login ~= "" then
        local account = c2.current_account()
        if not account:is_anon() and login:lower() == account:login():lower() then
            return false
        end
    end

    local flags = msg.flags
    if flags & F.System ~= 0 and login == "" and flags & STREAM_NOTICE_FLAGS == 0 then
        return false
    end

    return true
end

---@param msg c2.Message
---@return c2.Message
local function make_placeholder(msg)
    -- A clone keeps id, author, badges and flags, so split filters judge the
    -- placeholder like the original and deletions by id land on it.
    local placeholder = msg:clone()
    local elements = placeholder:elements()
    while #elements > 0 do
        elements:erase(1)
    end
    return placeholder
end

---@param state ChannelState
local function reset_queue(state)
    state.queue = {}
    state.head = 1
    state.tail = 0
end

---@param name string
---@param state ChannelState
---@param msg c2.Message
local function hold(name, state, msg)
    if config.get(name) <= 0 or not should_hold(msg) then
        return
    end

    local placeholder = make_placeholder(msg)
    state.channel:replace_message(msg, placeholder)

    state.tail = state.tail + 1
    state.queue[state.tail] = {
        original = msg,
        placeholder = placeholder,
        arrived = M.now(),
    }
end

---@param state ChannelState
---@param item PendingMessage
local function release(state, item)
    -- Chatterino may have changed the placeholder's flags while we held it
    -- (e.g. Disabled after a deletion or timeout); carry them over.
    item.original.flags = item.placeholder.flags
    state.channel:replace_message(item.placeholder, item.original)
end

---@param state ChannelState
---@param due fun(item: PendingMessage): boolean
local function release_while(state, due)
    while state.head <= state.tail do
        local item = state.queue[state.head]
        if not due(item) then
            break
        end
        state.queue[state.head] = nil
        state.head = state.head + 1
        release(state, item)
    end
    if state.head > state.tail then
        reset_queue(state)
    end
end

---Attaches (or re-attaches) the hold handler to `channel`. Re-attaching moves
---our handler to the end of the signal's connection list so splits opened
---after the last hook still see the placeholder swap.
---@param channel c2.Channel
function M.hook(channel)
    local name = channel:get_name()
    local state = states[name]
    if state == nil then
        state = { channel = channel, queue = {}, head = 1, tail = 0 }
        states[name] = state
    end
    state.channel = channel

    if state.appended then
        state.appended:disconnect()
    end
    state.appended = channel:on_message_appended(function(msg)
        hold(name, state, msg)
    end)

    if not state.cleared then
        state.cleared = channel:on_messages_cleared(function()
            reset_queue(state)
        end)
    end
end

---@param state ChannelState
local function disconnect(state)
    if state.appended then
        state.appended:disconnect()
    end
    if state.cleared then
        state.cleared:disconnect()
    end
end

---Shows everything pending in `name` right away and stops holding messages.
---@param name string
function M.unhook(name)
    local state = states[name]
    if state == nil then
        return
    end
    disconnect(state)
    states[name] = nil
    if state.channel:is_valid() then
        release_while(state, function()
            return true
        end)
    end
end

---Releases every held message whose delay has passed.
function M.release_due()
    local now = M.now()
    for name, state in pairs(states) do
        if not state.channel:is_valid() then
            disconnect(state)
            states[name] = nil
        else
            local delay = config.get(name)
            release_while(state, function(item)
                return item.arrived + delay <= now
            end)
        end
    end
end

---@param name string
---@return integer
function M.pending_count(name)
    local state = states[name]
    if state == nil then
        return 0
    end
    return state.tail - state.head + 1
end

return M
