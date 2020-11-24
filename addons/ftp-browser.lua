--[[
    An addon for mpv-file-browser which adds support for ftp servers
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local function parse_ftp(directory)
    msg.verbose(directory)
    msg.debug("curl -k -g "..string.format("%q", directory))

    local ftp = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"curl", "-k", "-g", directory}
    })

    local entries = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"curl", "-k", "-g", "-l", directory}
    })

    if entries.status ~= 0 then
        msg.error(entries.stderr)
        return
    end

    local response = {}
    for str in string.gmatch(ftp.stdout, "[^\r\n]+") do
        table.insert(response, str)
    end

    local list = {}
    local i = 1
    for str in string.gmatch(entries.stdout, "[^\r\n]+") do
        msg.trace(str .. ' | ' .. response[i])

        if response[i]:sub(1,1) == "d" then
            table.insert(list, { name = str..'/', type = "dir" })
        else
            table.insert(list, { name = str, type = "file" })
        end

        i = i+1
    end

    return list
end

--recursively opens the given directory
local function open_directory(path, flags)
    local list = parse_ftp(path)
    if not list then return end
    for i = 1, #list do
        local item_path = path..list[i].name

        if list[i].type == "dir" then open_directory(item_path, flags)
        else mp.commandv("loadfile", item_path, flags) end
    end
end

--custom parsing of directories
mp.register_script_message("ftp/browse-dir", function(dir)
    local json = parse_ftp(dir)
    if json then json = utils.format_json(json) end
    mp.commandv("script-message", "update-list-callback", json or "")
end)

--custom handling for opening directories
mp.register_script_message("ftp/open-dir", function(path, flags)
    if flags == "replace" then mp.commandv("playlist-clear") end
    open_directory(path, "append")
    if flags == "replace" then mp.commandv("playlist-remove", "current") end
end)
