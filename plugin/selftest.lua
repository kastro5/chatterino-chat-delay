-- `/delay selftest`: pushes synthetic messages through the real hold/release
-- path of a channel and checks the result. Results are shown in the channel
-- and written to the Chatterino log (prefixed with "SELFTEST").

local config = require("config")
local delayer = require("delayer")

local M = {}

local TEST_DELAY_MS = 2000
local CHECK_AFTER_MS = 2600
local COUNT = 3

---@param msg c2.Message?
---@return integer?
local function element_count(msg)
    if msg == nil then
        return nil
    end
    return #msg:elements()
end

---@class SelfTestReport
---@field passed integer
---@field failed integer
---@field lines string[]

---@return SelfTestReport
local function new_report()
    return { passed = 0, failed = 0, lines = {} }
end

---@param report SelfTestReport
---@param ok boolean
---@param what string
local function check(report, ok, what)
    if ok then
        report.passed = report.passed + 1
    else
        report.failed = report.failed + 1
        table.insert(report.lines, "FAIL " .. what)
    end
    c2.log(c2.LogLevel.Info, "SELFTEST " .. (ok and "PASS " or "FAIL ") .. what)
end

---@param report SelfTestReport
local function check_parsing(report)
    local cases = {
        { "30", 30000, false },
        { "2.5s", 2500, false },
        { "800ms", 800, false },
        { "2m", 120000, false },
        { "1:30", 90000, false },
        { "+5", 5000, true },
        { "-1.5", -1500, true },
        { "off", 0, false },
    }
    for _, case in ipairs(cases) do
        local ms, relative = config.parse_duration(case[1])
        check(
            report,
            ms == case[2] and relative == case[3],
            string.format("parse %q -> %s %s", case[1], tostring(ms), tostring(relative))
        )
    end
    check(report, config.parse_duration("abc") == nil, "parse rejects garbage")
end

---Checks that `ids` appear in the channel (oldest first) in the given order.
---@param channel c2.Channel
---@param ids string[]
---@return boolean
local function in_order(channel, ids)
    local snapshot = channel:message_snapshot(200)
    local position = {}
    for i = 1, #snapshot do
        position[snapshot[i].id] = i
    end
    local last = 0
    for _, id in ipairs(ids) do
        local p = position[id]
        if p == nil or p <= last then
            return false
        end
        last = p
    end
    return true
end

---@param channel c2.Channel
---@param set_delay fun(channel: c2.Channel, ms: integer)
---@param done fun(report: SelfTestReport)
function M.run(channel, set_delay, done)
    local report = new_report()
    check_parsing(report)

    local name = channel:get_name()
    local previous = config.get(name)
    local persist = config.persist
    config.persist = false -- don't write the temporary delay to disk
    set_delay(channel, TEST_DELAY_MS)

    local tag = "chat-delay-selftest-" .. tostring(delayer.now())
    local ids = {}
    for i = 1, COUNT do
        local id = tag .. "-" .. i
        ids[i] = id
        channel:add_message(c2.Message.new({
            id = id,
            login_name = "chatdelayselftest",
            display_name = "selftest",
            message_text = "selftest message " .. i,
            elements = {
                { type = "text", text = "[chat-delay selftest] message " .. i .. " of " .. COUNT },
            },
        }))
    end

    for i, id in ipairs(ids) do
        check(report, element_count(channel:find_message_by_id(id)) == 0, "message " .. i .. " is hidden on arrival")
    end
    check(report, delayer.pending_count(name) == COUNT, "pending count is " .. COUNT)
    check(report, in_order(channel, ids), "placeholders are in order")

    -- Simulate a moderator deleting message 2 while it is held.
    local held = channel:find_message_by_id(ids[2])
    if held then
        held.flags = held.flags | c2.MessageFlag.Disabled
    end

    c2.later(function()
        for i, id in ipairs(ids) do
            check(report, element_count(channel:find_message_by_id(id)) == 1, "message " .. i .. " is shown after the delay")
        end
        check(report, in_order(channel, ids), "released messages are in order")

        local deleted = channel:find_message_by_id(ids[2])
        check(
            report,
            deleted ~= nil and deleted.flags & c2.MessageFlag.Disabled ~= 0,
            "deletion during the delay carries over"
        )

        set_delay(channel, previous)
        if previous == 0 then
            -- Live chat may still be held at this point; turning the delay
            -- off must show all of it.
            check(report, delayer.pending_count(name) == 0, "turning the delay off releases everything")
        end
        config.persist = persist
        done(report)
    end, CHECK_AFTER_MS)
end

return M
