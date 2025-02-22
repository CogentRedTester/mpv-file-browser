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
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local fb = require 'file-browser'

-- loads the root json file
local config_path = mp.command_native({'expand-path', '~~/script-opts/file-browser-root.json'}) --[[@as string]]

local file = io.open(config_path, 'r')
if not file then
    msg.error('failed to read file', config_path)
    return
end

---@class RootConfigItem: Item
---@field priority number?

local root_config = utils.parse_json(file:read("*a")) --[=[@as RootConfigItem[]]=]
if not root_config then
    msg.error('failed to parse contents of', config_path, '- Check the syntax is correct.')
    return
end

local function setup()
    for i, item in ipairs(root_config) do
        local priority = item.priority
        item.priority = nil
        fb.register_root_item(item, priority)
    end
end

---@type ParserConfig
return {
    api_version = '1.4.0',
    setup = setup,
    priority = -1000,
}
