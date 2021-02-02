--[[
    An addon for mpv-file-browser which adds a Favourites path that can be loaded from the ROOT


    Designed to work with the following custom keybinds:
    {
        "key": "F",
        "command": ["script-message", "favourites/add_favourite", "%f"]
    },
    {
        "key": "F",
        "command": ["script-message", "favourites/remove_favourite", "%f"],
        "parser": "favourites"
    },
    {
        "key": "Ctrl+UP",
        "command": [
            ["script-binding", "file_browser/dynamic/scroll_up"],
            ["script-message", "favourites/move_up", "%f"]
        ],
        "parser": "favourites"
    },
    {
        "key": "Ctrl+DOWN",
        "command": [
            ["script-binding", "file_browser/dynamic/scroll_down"],
            ["script-message", "favourites/move_down", "%f"]
        ],
        "parser": "favourites"
    }
]]--

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"
local save_path = mp.command_native({"expand-path", "~~/script-opts/file_browser_favourites"})

local favourites = nil
local favs = {
    priority = 50,
    cursor = 1
}

local function create_favourite_object(str)
    return {
        type = str:sub(-1) == "/" and "dir" or "file",
        path = str,
        name = str:match("([^/]+/?)$")
    }
end

function favs:setup()
    favourites = {}

    local file = io.open(save_path, "r")
    if not file then return end

    for str in file:lines() do
        table.insert(favourites, create_favourite_object(str))
    end
    file:close()
end

function favs:can_parse(directory)
    return directory == "Favourites/"
end

function favs:parse()
    if self.cursor ~= 1 then self.set_selected_index(self.cursor) ; self.cursor = 1 end
    self.set_directory_label("Favourites")
    return favourites, true, true
end

local function get_favourite(path)
    for index, value in ipairs(favourites) do
        if value.path == path then return index, value end
    end
end

local function write_to_file()
    local file = io.open(save_path, "w+")
    for _, item in ipairs(favourites) do
        file:write(string.format("%s\n", item.path))
    end
    file:close()
    if favs.get_directory() == "Favourites/" then
        favs.cursor = favs.get_selected_index()
        mp.commandv("script-binding", "file_browser/dynamic/reload")
    end
end

local function add_favourite(path)
    if get_favourite(path) then return end
    favs:setup()
    table.insert(favourites, create_favourite_object(path))
    write_to_file()
end

local function remove_favourite(path)
    favs.setup()
    local index = get_favourite(path)
    if not index then return end
    table.remove(favourites, index)
    write_to_file()
end

local function move_favourite(path, direction)
    favs:setup()
    local index, item = get_favourite(path)
    if not index or not favourites[index + direction] then return end

    favourites[index] = favourites[index + direction]
    favourites[index + direction] = item
    write_to_file()
end

mp.register_script_message("favourites/add_favourite", add_favourite)
mp.register_script_message("favourites/remove_favourite", remove_favourite)
mp.register_script_message("favourites/move_up", function(path) move_favourite(path, -1) end)
mp.register_script_message("favourites/move_down", function(path) move_favourite(path, 1) end)

return favs