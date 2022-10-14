--[[
    An addon that loads root items from a `~~/script-opts/file-browser-root.json` file.
    The contents of this file will override the root script-opt.

    The json file takes the form of a list array as defined by the addon API:
    https://github.com/CogentRedTester/mpv-file-browser/blob/master/addons/addons.md#the-list-array

    The main purpose of this addon is to allow for users to customise the appearance of their root items
    using the label or ass fields:

    [
        { "name": "Favourites/" },
        { "label": "~/", "name": "C:/Users/User/" },
        { "label": "1TB HDD", "name": "D:/" },
        { "ass": "{\\c&H007700&}Green Text", "name": "E:/" },
        { "label": "FTP Server", name: "ftp://user:password@server.com/" }
    ]

    Make sure local directories always end with `/`.
    `path` and `name` behave the same in the root but either name or label should have a value.
    ASS styling codes: https://aegi.vmoe.info/docs/3.0/ASS_Tags/
]]

local mp = require 'mp'
local utils = require 'mp.utils'
local fb = require 'file-browser'

-- loads the root json file
local json_path = mp.command_native({'expand-path', '~~/script-opts/file-browser-root.json'})
local f = assert(io.open(json_path, "r"), 'failed to open '..json_path)
local root, err = utils.parse_json(f:read("*a"))
if not root then error(err) end

-- deletes any root values set by the root script-opt
local original_root = getmetatable(fb.get_root()).__original
for i in ipairs(original_root) do
    original_root[i] = nil
end

local parser = {
    version = '1.4.0',
    priority = -math.huge
}

function parser:setup()
    for i, v in ipairs(root) do
        fb.register_root_item(v)
    end
end

return parser
