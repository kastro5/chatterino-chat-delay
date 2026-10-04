-- Chat Delay: holds chat messages back per channel so chat lines up with a
-- delayed stream. See README.md for usage and known limitations.

local config = require("config")
local delayer = require("delayer")
local selftest = require("selftest")

local TICK_MS = 100
-- Re-attach handlers every N ticks so we stay last in the signal's handler
-- order even after new splits connect to a delayed channel.
local REHOOK_EVERY = 5

config.load()

---@param channel c2.Channel
---@param text string
local function reply(channel, text)
    delayer.with_bypass(function()
        channel:add_system_message("[chat-delay] " .. text)
    end)
end

-- The docs/type defs say `Twitch`, but the enum is exposed with its serialized
-- name (`twitch`) in current nightlies.
local TWITCH_CHANNEL_TYPE = c2.ChannelType.Twitch or c2.ChannelType.twitch

---@param channel c2.Channel
---@return boolean
local function is_delayable(channel)
    return channel:is_valid() and channel:get_type() == TWITCH_CHANNEL_TYPE
end

---@param channel c2.Channel
---@param ms integer
---@return integer applied
local function set_delay(channel, ms)
    local name = channel:get_name()
    local applied = config.set(name, ms)
    if applied > 0 then
        delayer.hook(channel)
    else
        delayer.unhook(name)
    end
    return applied
end

---@param cb fun(channel: c2.Channel)
local function each_open_channel(cb)
    local seen = {}
    for _, window in ipairs(c2.windows:all()) do
        local notebook = window.notebook
        for i = 0, notebook.page_count - 1 do
            local page = notebook:page_at(i)
            if page then
                for _, split in ipairs(page:splits()) do
                    local channel = split.channel
                    if is_delayable(channel) then
                        local name = channel:get_name()
                        if not seen[name] then
                            seen[name] = true
                            cb(channel)
                        end
                    end
                end
            end
        end
    end
end

local function rehook()
    each_open_channel(function(channel)
        if config.get(channel:get_name()) > 0 then
            delayer.hook(channel)
        end
    end)
end

local tick_count = 0
local function tick()
    local ok, err = pcall(function()
        tick_count = tick_count + 1
        if tick_count % REHOOK_EVERY == 0 then
            rehook()
        end
        delayer.release_due()
    end)
    if not ok then
        c2.log(c2.LogLevel.Warning, "tick failed: " .. tostring(err))
    end
    c2.later(tick, TICK_MS)
end

---@param channel c2.Channel
local function describe(channel)
    local name = channel:get_name()
    return string.format(
        "Delay for #%s: %s (%d pending, saving %s).",
        name,
        config.format_duration(config.get(name)),
        delayer.pending_count(name),
        config.persist and "on" or "off"
    )
end

local USAGE = "Usage: /delay <30 | 2.5s | 800ms | 1:30 | +5 | -1 | off> · /delay persist <on|off> · /delay selftest"

---@param channel c2.Channel
local function run_selftest(channel, on_done)
    reply(channel, "Running selftest (takes ~3s)...")
    selftest.run(channel, set_delay, function(report)
        local summary = string.format("Selftest: %d passed, %d failed.", report.passed, report.failed)
        c2.log(c2.LogLevel.Info, "SELFTEST DONE " .. summary)
        reply(channel, summary)
        for _, line in ipairs(report.lines) do
            reply(channel, line)
        end
        if on_done then
            on_done(report)
        end
    end)
end

---@param ctx CommandContext
local function delay_command(ctx)
    local channel = ctx.channel
    if not is_delayable(channel) then
        reply(channel, "Delays only work in Twitch channel splits.")
        return
    end
    local name = channel:get_name()
    local arg = ctx.words[2]

    if arg == nil then
        reply(channel, describe(channel) .. " " .. USAGE)
        return
    end
    arg = arg:lower()

    if arg == "persist" then
        local value = ctx.words[3] and ctx.words[3]:lower()
        if value == "on" or value == "off" then
            local ok, err = config.set_persist(value == "on")
            if not ok then
                reply(channel, "Couldn't write settings: " .. tostring(err))
                return
            end
        elseif value ~= nil then
            reply(channel, "Usage: /delay persist <on|off>")
            return
        end
        reply(channel, "Saving delays across restarts is " .. (config.persist and "on." or "off."))
        return
    end

    if arg == "selftest" then
        run_selftest(channel)
        return
    end

    local ms, relative = config.parse_duration(arg)
    if ms == nil then
        reply(channel, "Couldn't understand '" .. arg .. "'. " .. USAGE)
        return
    end
    if relative then
        ms = config.get(name) + ms
    end
    set_delay(channel, ms)
    reply(channel, describe(channel))
end

c2.register_command("/delay", delay_command)

local NUDGES = { -5000, -1000, 1000, 5000 }

c2.windows:on_channelview_context_menu_requested(function(ev)
    -- Only real splits: usercards and search popups show virtual channels.
    if ev.split == nil then
        return
    end
    local channel = ev.split.channel
    if not is_delayable(channel) then
        return
    end
    local name = channel:get_name()

    local menu = ev.menu:add_menu("Chat delay (" .. config.format_duration(config.get(name)) .. ")")
    for _, step in ipairs(NUDGES) do
        local label = (step > 0 and "+" or "-") .. config.format_duration(math.abs(step))
        menu:add_action(label, function()
            if channel:is_valid() then
                set_delay(channel, config.get(name) + step)
                reply(channel, describe(channel))
            end
        end)
    end
    menu:add_action("Off", function()
        if channel:is_valid() then
            set_delay(channel, 0)
            reply(channel, describe(channel))
        end
    end)
end)

-- Hook channels restored from saved delays once the windows exist.
c2.later(tick, TICK_MS)

-- Headless testing aid: if data/autotest contains a channel name, run the
-- selftest there once the channel is joined and write data/autotest-result.txt.
local function autotest()
    local ok, f = pcall(io.open, "autotest", "r")
    if not ok or not f then
        return
    end
    local name = (f:read("l") or ""):match("^%s*(%S+)")
    f:close()
    if not name then
        return
    end

    local attempts = 0
    local function try()
        attempts = attempts + 1
        local channel = c2.Channel.by_name(name)
        if channel == nil or not channel:has_messages() then
            if attempts < 60 then
                c2.later(try, 1000)
            else
                c2.log(c2.LogLevel.Warning, "SELFTEST DONE autotest: channel #" .. name .. " never opened")
            end
            return
        end
        run_selftest(channel, function(report)
            local out = io.open("autotest-result.txt", "w")
            if out then
                out:write(string.format("passed=%d failed=%d\n", report.passed, report.failed))
                for _, line in ipairs(report.lines) do
                    out:write(line, "\n")
                end
                out:close()
            end
        end)
    end
    c2.later(try, 1000)
end
autotest()
