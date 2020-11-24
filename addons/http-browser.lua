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

    msg.trace("curl -k -l -s "..string.format("%q", directory))

    local html = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {"curl", "-k", "-l", directory}
    })
    html = html.stdout
    if not html:find("%[PARENTDIR%]") then return end

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

    local json, _ = utils.format_json(list)
    return json
end

mp.register_script_message("browse-http", function(dir)
    mp.commandv("script-message", "update-list-callback", parse_http(dir) or "")
end)