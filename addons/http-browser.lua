--[[
    An addon for mpv-file-browser which adds support for apache http directory indexes
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

--decodes a URL address
--this piece of code was taken from: https://stackoverflow.com/questions/20405985/lua-decodeuri-luvit/20406960#20406960
local decodeURI
do
    local char, gsub, tonumber = string.char, string.gsub, tonumber
    local function _(hex) return char(tonumber(hex, 16)) end

    function decodeURI(s)
        s = gsub(s, '%%(%x%x)', _)
        return s
    end
end

local function parse_http(directory)
    msg.verbose(directory)
    msg.trace("curl -k -l -m 5 "..string.format("%q", directory))

    local html = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"curl", "-k", "-l", "-m", "20", directory}
    })
    if html.status == 6 or html.status == 3 then return nil
    elseif html.status ~= 0 then return {}, "curl error: "..tostring(html.status)
    elseif not html.stdout:find("%[PARENTDIR%]") then return nil end

    html = html.stdout
    local list = {}
    for str in string.gmatch(html, "[^\r\n]+") do
        if str:sub(1,4) ~= "<tr>" then goto continue end

        local link = str:match('href="(.-)"')
        local alt = str:match('alt="%[(.-)%]"')

        if not alt or not link then goto continue end
        if alt == "PARENTDIR" or alt == "ICO" then goto continue end
        if link:find("[:?<>|]") then goto continue end

        msg.trace(alt..": "..link)
        table.insert(list, { name = link, type = (alt == "DIR" and "dir" or "file"), label = decodeURI(link) })

        ::continue::
    end

    return list
end

local flag = ""

--recursively opens the given directory
local function open_directory(path)
    local list = parse_http(path)
    if not list then return end
    for i = 1, #list do
        local item_path = path..list[i].name

        if list[i].type == "dir" then open_directory(item_path)
        else
            mp.commandv("loadfile", item_path, flag)
            flag = "append"
        end
    end
end

--custom parsing of directories
mp.register_script_message("http/browse-dir", function(dir, callback, ...)
    local response = {}
    response.list, response.empty_text = parse_http(dir)
    response.directory_label = decodeURI(dir)
    mp.commandv("script-message", callback, utils.format_json(response), ...)
end)

--custom handling for opening directories
mp.register_script_message("http/open-dir", function(path, flags)
    flag = flags
    open_directory(path)
end)
