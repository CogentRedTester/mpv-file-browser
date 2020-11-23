--[[
    An addon for mpv-file-browser which adds support for apache http directory indexes
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

--https://stackoverflow.com/questions/132397/get-back-the-output-of-os-execute-in-lua
function os.capture(cmd)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    return s
  end

--decodes a URL address
--this piece of code was taken from: https://stackoverflow.com/questions/20405985/lua-decodeuri-luvit/20406960#20406960
local decodeURI
do
    local char, gsub, tonumber = string.char, string.gsub, tonumber
    local function _(hex) return char(tonumber(hex, 16)) end

    function decodeURI(s)
        msg.debug('decoding string: ' .. s)
        s = gsub(s, '%%(%x%x)', _)
        msg.debug('returning string: ' .. s)
        return s
    end
end

local function parse_http(directory)
    msg.verbose(directory)

    -- cmd.stdout = cmd.stdout:gsub("[\n\r]", ' ')
    msg.trace("curl -k -l "..string.format("%q", directory).. ' | grep "<tr>"')
    local html = os.capture("curl -k -l -s "..string.format("%q", directory).. ' | grep "href"' )

    -- print(html)
    if not html:find("%[PARENTDIR%]") then return end

    local list = {}
    for str in string.gmatch(html, "[^\r\n]+") do
        local link = str:match('href="(.-)"')
        local alt = str:match('alt="%[(.-)%]"')
        msg.trace(alt..": "..link)

        if not alt or not link then goto continue end
        if alt == "PARENTDIR" or alt == "ICO" then goto continue end
        if link:find("[:?<>|]") then goto continue end

        table.insert(list, { name = link, type = (alt == "DIR" and "dir" or "file"), label = decodeURI(link) })

        ::continue::
    end

    local json, _ = utils.format_json(list)
    return json
end

mp.register_script_message("browse-http", function(dir)
    local result = parse_http(dir)
    if not result then
        mp.commandv("script-message", "update-list-callback")
    else
        mp.commandv("script-message", "update-list-callback", result)
    end
end)