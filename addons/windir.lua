--[[
    An addon for mpv-file-browser which uses the Windows dir command to parse native directories
    This behaves near identically to the native parser, but IO is done asynchronously.

    Available at: https://github.com/CogentRedTester/mpv-file-browser/tree/master/addons
]]--

local mp = require "mp"
local msg = require "mp.msg"
local fb = require "file-browser"

---@param bytes string
---@return fun(): number?, number?
local function byte_iterator(bytes)
    ---@async
    ---@return number?
    local function iter()
        for i = 1, #bytes do
            coroutine.yield(i, bytes:byte(i))
        end
        return nil
    end

    return coroutine.wrap(iter)
end

---@param iter fun(): number?, number?
---@return number
local function get_byte(iter)
    local _, byte = iter()
    if not byte then error('malformed utf16le string - expected byte but found end of string') end
    return byte
end

---@param bits number
---@param by number
---@return number
local function lshift(bits, by)
    return bits * 2^by
end

---@param bits number
---@param by number
---@return integer
local function rshift(bits, by)
    return math.floor(bits / 2^by)
end

---@param bits number
---@param i number
---@return number
local function bits_below(bits, i)
    -- local bitmask = lshift(rshift(bits, i), i)
    -- return bits - bitmask
    return bits % 2^i
end

---@param bits number
---@param i number exclusive
---@param j number inclusive
---@return integer
local function bits_between(bits, i, j)
    return rshift(bits_below(bits, j), i)
end

---@param bytes string
---@return number[]
local function utf16le_to_unicode(bytes)
    ---@type number[]
    local codepoints = {}

    local iter = byte_iterator(bytes)
    -- ---@type fun(): number?, number?
    -- local iter = ipairs({bytes:byte(1, #bytes)})

    local success, err = xpcall(function()
        while true do
            -- start of a char
            local success, little = pcall(get_byte, iter)
            if not success then break end

            local big = lshift(get_byte(iter), 8)
            local codepoint = big + little

            -- surrogate pairs
            if codepoint < 0xd800 or codepoint > 0xdfff then
                table.insert(codepoints, codepoint)
            else
                -- special surrogate handling
                -- grab the next two bytes to grab the low surrogate
                local high_pair = codepoint
                local low_pair = get_byte(iter) + lshift(get_byte(iter), 8)

                if high_pair >= 0xdc00 then error('malformed utf16le string - high surrogate pair is >= 0xdc00') end
                if low_pair < 0xdc00 then error('malformed utf16le string - low surrogate pair is < 0xdc00') end

                -- The last 10 bits of each surrogate are the two halves of the codepoint
                -- https://en.wikipedia.org/wiki/UTF-16#Code_points_from_U+010000_to_U+10FFFF
                local high_bits = bits_below(high_pair, 10)
                local low_bits = bits_below(low_pair, 10)

                table.insert(codepoints, (low_bits + lshift(high_bits, 10)) + 0x10000)
            end
        end
    end, debug.traceback)

    if not success then
        msg.error(err)
        msg.warn(table.concat(codepoints, ' '))
        msg.warn('read up to', (table.concat(codepoints, ' '):gsub('%d+', function(d) return string.format('0x%02X', d) end)))
    end

    return codepoints
end

---@param codepoints number[]
---@return string
local function unicode_to_utf8(codepoints)
    ---@type number[]
    local bytes = {}

    for _, codepoint in ipairs(codepoints) do
        if codepoint <= 0x7f then
            table.insert(bytes, codepoint)
        elseif codepoint <= 0x7ff then
            -- 5 most significant bits of the codepoint are in byte 1
            table.insert(bytes, 0xC0 + rshift(codepoint, 6))
            table.insert(bytes, 0x80 + bits_below(codepoint, 6))
        elseif codepoint <= 0xffff then
            table.insert(bytes, 0xE0 + rshift(codepoint, 12))
            table.insert(bytes, 0x80 + bits_between(codepoint, 6, 12))
            table.insert(bytes, 0x80 + bits_below(codepoint, 6))
        elseif codepoint <= 0x10ffff then
            table.insert(bytes, 0xF0 + rshift(codepoint, 18))
            table.insert(bytes, 0x80 + bits_between(codepoint, 12, 18))
            table.insert(bytes, 0x80 + bits_between(codepoint, 6, 12))
            table.insert(bytes, 0x80 + bits_below(codepoint, 6))
        end
    end

    return string.char(unpack(bytes))
end

local function utf8(text)
    return unicode_to_utf8(utf16le_to_unicode(text))
end

---@type ParserConfig
local dir = {
    priority = 109,
    api_version = "1.1.0",
    name = "cmd-dir",
    keybind_name = "file"
}

---@async
---@param args string[]
---@param parse_state ParseState
---@return string|nil
---@return string?
local function command(args, parse_state)
    ---@type boolean, MPVSubprocessResult
    local _, cmd = parse_state:yield(
        mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
            args = args,
        }, fb.coroutine.callback() )
    )
    cmd.stdout = utf8(cmd.stdout) or ''
    cmd.stderr = utf8(cmd.stderr) or ''

    --dir returns this exact error message if the directory is empty
    if cmd.status == 1 and cmd.stderr == "File Not Found\r\n" then cmd.status = 0 end

    return cmd.status == 0 and cmd.stdout or nil, cmd.stderr
end

function dir:can_parse(directory)
    if directory == "" then return false end
    return not fb.get_protocol(directory)
end

---@async
function dir:parse(directory, parse_state)
    local list = {}
    local files, dirs, err

    -- the dir command expects backslashes for our paths
    directory = string.gsub(directory, "/", "\\")

    dirs, err = command({ "cmd", "/U", "/c", "dir", "/b", "/ad", directory }, parse_state)
    if not dirs then return msg.error(err) end

    files, err = command({ "cmd", "/U", "/c", "dir", "/b", "/a-d", directory }, parse_state)
    if not files then return msg.error(err) end

    for name in dirs:gmatch("[^\n\r]+") do
        name = name.."/"
        if fb.valid_dir(name) then
            table.insert(list, { name = name, type = "dir" })
            msg.trace(name)
        end
    end

    for name in files:gmatch("[^\n\r]+") do
        if fb.valid_file(name) then
            table.insert(list, { name = name, type = "file" })
            msg.trace(name)
        end
    end

    return list, { filtered = true }
end

return dir
