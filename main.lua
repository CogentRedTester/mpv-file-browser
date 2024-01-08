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

if input then
    mp.add_key_binding("Alt+o", "browse-directory/get-user-input", function()
        input.get_user_input(controls.browse_directory, {request_text = "open directory:"})
    end)
end



------------------------------------------------------------------------------------------
----------------------------------Script Messages-----------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local observers = require 'modules.observers'
local script_messages = require 'modules.script-messages'

--we don't want to add any overhead when the browser isn't open
mp.observe_property('path', 'string', observers.current_directory)

--updates the dvd_device
mp.observe_property('dvd-device', 'string', observers.dvd_device)

mp.register_script_message('=>', script_messages.chain)
mp.register_script_message('delay-command', script_messages.delay_command)
mp.register_script_message('conditional-command', script_messages.conditional_command)
mp.register_script_message('evaluate-expressions', script_messages.evaluate_expressions)
mp.register_script_message('run-statement', script_messages.run_statement)

mp.register_script_message('browse-directory', controls.browse_directory)
mp.register_script_message("get-directory-contents", script_messages.get_directory_contents)

--declares the keybind to open the browser
mp.add_key_binding('MENU','browse-files', controls.toggle)
mp.add_key_binding('Ctrl+o','open-browser', controls.open)

