-- Per-channel delay settings, optional persistence and duration parsing.

local json = require("chatterino.json")

local M = {}

local SETTINGS_FILE = "settings.json"

M.MAX_DELAY_MS = 10 * 60 * 1000

---Whether delays are written to disk. Off by default (memory only).
M.persist = false

---@type table<string, integer> channel name -> delay in milliseconds
M.delays = {}

---@param ms number
---@return integer
local function clamp(ms)
    ms = math.floor(ms + 0.5)
    if ms < 0 then
        return 0
    end
    if ms > M.MAX_DELAY_MS then
        return M.MAX_DELAY_MS
    end
    return ms
end

---@return boolean ok
---@return string? err
function M.save()
    local data = { persist = M.persist }
    if M.persist then
        data.delays = M.delays
    end
    local ok, f, err = pcall(io.open, SETTINGS_FILE, "w")
    if not ok or not f then
        return false, tostring(f or err)
    end
    f:write(json.stringify(data))
    f:close()
    return true
end

function M.load()
    local ok, f = pcall(io.open, SETTINGS_FILE, "r")
    if not ok or not f then
        return
    end
    local text = f:read("a")
    f:close()

    local parsed_ok, data = pcall(json.parse, text)
    if not parsed_ok or type(data) ~= "table" or data.persist ~= true then
        return
    end

    M.persist = true
    if type(data.delays) == "table" then
        for name, ms in pairs(data.delays) do
            if type(name) == "string" and type(ms) == "number" and ms > 0 then
                M.delays[name] = clamp(ms)
            end
        end
    end
end

---@param name string
---@return integer
function M.get(name)
    return M.delays[name] or 0
end

---@param name string
---@param ms number
---@return integer applied The clamped delay that was stored.
function M.set(name, ms)
    ms = clamp(ms)
    if ms == 0 then
        M.delays[name] = nil
    else
        M.delays[name] = ms
    end
    if M.persist then
        M.save()
    end
    return ms
end

---@param enabled boolean
---@return boolean ok
---@return string? err
function M.set_persist(enabled)
    M.persist = enabled
    return M.save()
end

---Parses things like `30`, `2.5s`, `800ms`, `2m`, `1:30`, `+5`, `-1.5`, `off`.
---@param text string
---@return integer? ms Absolute delay, or the change if `relative`.
---@return boolean relative
function M.parse_duration(text)
    text = text:lower()
    if text == "off" then
        return 0, false
    end

    local sign = text:sub(1, 1)
    local relative = sign == "+" or sign == "-"
    local body = relative and text:sub(2) or text

    local ms
    local minutes, seconds = body:match("^(%d+):(%d+%.?%d*)$")
    if minutes then
        ms = (tonumber(minutes) * 60 + tonumber(seconds)) * 1000
    else
        local num, unit = body:match("^(%d*%.?%d+)(%a*)$")
        if not num then
            return nil, relative
        end
        num = tonumber(num)
        if unit == "" or unit == "s" then
            ms = num * 1000
        elseif unit == "ms" then
            ms = num
        elseif unit == "m" or unit == "min" then
            ms = num * 60 * 1000
        else
            return nil, relative
        end
    end

    ms = math.floor(ms + 0.5)
    if sign == "-" then
        ms = -ms
    end
    return ms, relative
end

---@param ms integer
---@return string
function M.format_duration(ms)
    if ms == 0 then
        return "off"
    end
    if ms % 1000 == 0 then
        return string.format("%ds", ms // 1000)
    end
    local s = string.format("%.2f", ms / 1000):gsub("0+$", "")
    return s .. "s"
end

return M
