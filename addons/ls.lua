--[[
    An addon for mpv-file-browser which uses the linux ls command to parse native directories

    This is mostly a proof of concept, I don't know of any cases when this would be needed.
]]--

local mp = require "mp"
local fb = require "file-browser"

local ls = {
    priority = 109,
    version = "1.0.0",
    name = "ls",
    keybind_name = "file"
}

local function command(args, parse_state)
    local co = coroutine.running()
    local cmd = nil
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args
    }, function(_, res)
        fb.coroutine.resume_err(co, res)
    end)
    if parse_state then cmd = parse_state:yield()
    else cmd = coroutine.yield() end

    return cmd.status == 0 and cmd.stdout or nil
end

function ls:can_parse(directory)
    return not self.get_protocol(directory)
end

function ls:parse(directory, parse_state)
    local list = {}
    local files = command({"ls", "-1", "-p", "-A", "-N", directory}, parse_state)

    if not files then return nil end

    for str in files:gmatch("[^\n\r]+") do
        local is_dir = str:sub(-1) == "/"

        if is_dir and self.valid_dir(str) then
            table.insert(list, {name = str, type = "dir"})
        elseif self.valid_file(str) then
            table.insert(list, {name = str, type = "file"})
        end
    end

    return list, {filtered = true}
end

return ls
