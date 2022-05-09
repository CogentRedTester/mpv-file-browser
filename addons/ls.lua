--[[
    An addon for mpv-file-browser which uses the Linux ls command to parse native directories
    This behaves near identically to the native parser, but IO is done asynchronously.

    Available at: https://github.com/CogentRedTester/mpv-file-browser/tree/master/addons
]]--

local mp = require "mp"
local fb = require "file-browser"

local ls = {
    priority = 109,
    version = "1.1.0",
    name = "ls",
    keybind_name = "file"
}

local function command(args, parse_state)
    local _, cmd = parse_state:yield(
        mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
            args = args
        }, fb.coroutine.callback())
    )

    return cmd.status == 0 and cmd.stdout or nil
end

function ls:can_parse(directory)
    return not fb.get_protocol(directory)
end

function ls:parse(directory, parse_state)
    local list = {}
    local files = command({"ls", "-1", "-p", "-A", "-N", directory}, parse_state)

    if not files then return nil end

    for str in files:gmatch("[^\n\r]+") do
        local is_dir = str:sub(-1) == "/"

        if is_dir and fb.valid_dir(str) then
            table.insert(list, {name = str, type = "dir"})
        elseif fb.valid_file(str) then
            table.insert(list, {name = str, type = "file"})
        end
    end

    return list, {filtered = true}
end

return ls
