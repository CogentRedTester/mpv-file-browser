--[[
    mpv-file-browser

    This script allows users to browse and open files and folders entirely from within mpv.
    The script uses nothing outside the mpv API, so should work identically on all platforms.
    The browser can move up and down directories, start playing files and folders, or add them to the queue.

    For full documentation see: https://github.com/CogentRedTester/mpv-file-browser
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local o = require 'modules.options'

if o.set_shared_script_properties then utils.shared_script_property_set('file_browser-open', 'no') end
if o.set_user_data then mp.set_property_bool('user-data/file_browser/open', false) end

package.path = mp.command_native({"expand-path", o.module_directory}).."/?.lua;"..package.path
local success, input = pcall(require, "user-input-module")
if not success then input = nil end



--------------------------------------------------------------------------------------------------------
-----------------------------------------Environment Setup----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--switch the main script to a different environment so that the
--executed lua code cannot access our global variales
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G }))
else
    _ENV = setmetatable({}, { __index = _G })
end

local API = require 'modules.utils'

--------------------------------------------------------------------------------------------------------
------------------------------------------Variable Setup------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local g = require 'modules.globals'

local state = g.state

local parsers = g.parsers
local parse_states = g.parse_states

local extensions = g.extensions
local sub_extensions = g.sub_extensions
local audio_extensions = g.audio_extensions
local parseable_extensions = g.parseable_extensions

local current_file = g.current_file

local root = g.root

local compatible_file_extensions = g.compatible_file_extensions

--------------------------------------------------------------------------------------------------------
--------------------------------------Cache Implementation----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local cache = require 'modules.cache'



--------------------------------------------------------------------------------------------------------
-----------------------------------------Utility Functions----------------------------------------------
---------------------------------------Part of the addon API--------------------------------------------
--------------------------------------------------------------------------------------------------------




--------------------------------------------------------------------------------------------------------
------------------------------------Parser Object Implementation----------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--parser object for the root
--not inserted to the parser list as it has special behaviour
--it does get get added to parsers under it's ID to prevent confusing duplicates
local root_parser = require 'modules.parsers.root'

--parser ofject for native filesystems
local file_parser = require 'modules.parsers.file'



--------------------------------------------------------------------------------------------------------
-----------------------------------------List Formatting------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local ass = require 'modules.ass'



--------------------------------------------------------------------------------------------------------
--------------------------------Scroll/Select Implementation--------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local cursor = require 'modules.navigation.cursor'



--------------------------------------------------------------------------------------------------------
-----------------------------------------Directory Movement---------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local scanning = require 'modules.navigation.scanning'
local movement = require 'modules.navigation.directory-movement'



------------------------------------------------------------------------------------------
------------------------------------Browser Controls--------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local controls = require 'modules.controls'



------------------------------------------------------------------------------------------
---------------------------------File/Playlist Opening------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local playlist = require 'modules.playlist'



------------------------------------------------------------------------------------------
----------------------------------Keybind Implementation----------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local keybinds = require 'modules.keybinds'



--------------------------------------------------------------------------------------------------------
-------------------------------------------API Functions------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local fb = require 'modules.apis.fb'
local parser_API = require 'modules.apis.parser'



--------------------------------------------------------------------------------------------------------
-----------------------------------------Setup Functions------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local addons = require 'modules.addons'
local setup = require 'modules.setup'

setup.root()

addons.setup_parser(file_parser, "file-browser.lua")
addons.setup_parser(root_parser, 'file-browser.lua')
if o.addons then
    --all of the API functions need to be defined before this point for the addons to be able to access them safely
    addons.setup_addons()
end

--these need to be below the addon setup in case any parsers add custom entries
setup.extensions_list()
keybinds.setup_keybinds()



------------------------------------------------------------------------------------------
------------------------------Other Script Compatability----------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local function scan_directory_json(directory, response_str)
    if not directory then msg.error("did not receive a directory string"); return end
    if not response_str then msg.error("did not receive a response string"); return end

    directory = mp.command_native({"expand-path", directory}, "")
    if directory ~= "" then directory = API.fix_path(directory, true) end
    msg.verbose(("recieved %q from 'get-directory-contents' script message - returning result to %q"):format(directory, response_str))

    local list, opts = scanning.scan_directory(directory, { source = "script-message" } )
    if opts then opts.API_VERSION = g.API_VERSION end

    local err
    list, err = API.format_json_safe(list)
    if not list then msg.error(err) end

    opts, err = API.format_json_safe(opts)
    if not opts then msg.error(err) end

    mp.commandv("script-message", response_str, list or "", opts or "")
end

if input then
    mp.add_key_binding("Alt+o", "browse-directory/get-user-input", function()
        input.get_user_input(controls.browse_directory, {request_text = "open directory:"})
    end)
end



------------------------------------------------------------------------------------------
----------------------------------Script Messages-----------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

--a helper script message for custom keybinds
--substitutes any '=>' arguments for 'script-message'
--makes chaining script-messages much easier
mp.register_script_message('=>', function(...)
    local command = table.pack('script-message', ...)
    for i, v in ipairs(command) do
        if v == '=>' then command[i] = 'script-message' end
    end
    mp.commandv(table.unpack(command))
end)

--a helper script message for custom keybinds
--sends a command after the specified delay
mp.register_script_message('delay-command', function(delay, ...)
    local command = table.pack(...)
    local success, err = pcall(mp.add_timeout, API.evaluate_string('return '..delay), function() mp.commandv(table.unpack(command)) end)
    if not success then return msg.error(err) end
end)

--a helper script message for custom keybinds
--sends a command only if the given expression returns true
mp.register_script_message('conditional-command', function(condition, ...)
    local command = table.pack(...)
    API.coroutine.run(function()
        if API.evaluate_string('return '..condition) == true then mp.commandv(table.unpack(command)) end
    end)
end)

--a helper script message for custom keybinds
--extracts lua expressions from the command and evaluates them
--expressions must be surrounded by !{}. Another ! before the { will escape the evaluation
mp.register_script_message('evaluate-expressions', function(...)
    local args = table.pack(...)
    API.coroutine.run(function()
        for i, arg in ipairs(args) do
            args[i] = arg:gsub('(!+)(%b{})', function(lead, expression)
                if #lead % 2 == 0 then return string.rep('!', #lead/2)..expression end

                local eval = API.evaluate_string('return '..expression:sub(2, -2))
                return type(eval) == "table" and utils.to_string(eval) or tostring(eval)
            end)
        end

        mp.commandv(table.unpack(args))
    end)
end)

--a helper function for custom-keybinds
--concatenates the command arguments with newlines and runs the
--string as a statement of code
mp.register_script_message('run-statement', function(...)
    local statement = table.concat(table.pack(...), '\n')
    API.coroutine.run(API.evaluate_string, statement)
end)

--allows keybinds/other scripts to auto-open specific directories
mp.register_script_message('browse-directory', controls.browse_directory)

--allows other scripts to request directory contents from file-browser
mp.register_script_message("get-directory-contents", function(directory, response_str)
    API.coroutine.run(scan_directory_json, directory, response_str)
end)



------------------------------------------------------------------------------------------
--------------------------------mpv API Callbacks-----------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local observers = require 'modules.observers'

--we don't want to add any overhead when the browser isn't open
mp.observe_property('path', 'string', observers.current_directory)

--updates the dvd_device
mp.observe_property('dvd-device', 'string', observers.dvd_device)

--declares the keybind to open the browser
mp.add_key_binding('MENU','browse-files', controls.toggle)
mp.add_key_binding('Ctrl+o','open-browser', controls.open)

