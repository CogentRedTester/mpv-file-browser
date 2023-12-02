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
package.loaded["file-browser"] = setmetatable({}, { __index = API })
local parser_API = setmetatable({}, { __index = package.loaded["file-browser"] })
local parse_state_API = {}

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

--these functions we'll provide as-is
API.redraw = ass.update_ass
API.rescan = scanning.rescan
API.browse_directory = controls.browse_directory

function API.clear_cache()
    cache:clear()
end

--a wrapper around scan_directory for addon API
function API.parse_directory(directory, parse_state)
    if not parse_state then parse_state = { source = "addon" }
    elseif not parse_state.source then parse_state.source = "addon" end
    return scanning.scan_directory(directory, parse_state)
end

--register file extensions which can be opened by the browser
function API.register_parseable_extension(ext)
    parseable_extensions[string.lower(ext)] = true
end
function API.remove_parseable_extension(ext)
    parseable_extensions[string.lower(ext)] = nil
end

--add a compatible extension to show through the filter, only applies if run during the setup() method
function API.add_default_extension(ext)
    table.insert(compatible_file_extensions, ext)
end

--add item to root at position pos
function API.insert_root_item(item, pos)
    msg.debug("adding item to root", item.label or item.name, pos)
    item.ass = item.ass or API.ass_escape(item.label or item.name)
    item.type = "dir"
    table.insert(root, pos or (#root + 1), item)
end

--a newer API for adding items to the root
--only adds the item if the same item does not already exist in the root
--the priority variable is a number that specifies the insertion location
--a lower priority is placed higher in the list and the default is 100
function API.register_root_item(item, priority)
    msg.verbose('registering root item:', utils.to_string(item))
    if type(item) == 'string' then
        item = {name = item}
    end

    -- if the item is already in the list then do nothing
    if API.list.some(root, function(r)
        return API.get_full_path(r, '') == API.get_full_path(item, '')
    end) then return false end

    item._priority = priority
    for i, v in ipairs(root) do
        if (v._priority or 100) > (priority or 100) then
            API.insert_root_item(item, i)
            return true
        end
    end
    API.insert_root_item(item)
    return true
end

--providing getter and setter functions so that addons can't modify things directly
function API.get_script_opts() return API.copy_table(o) end
function API.get_opt(key) return o[key] end
function API.get_extensions() return API.copy_table(extensions) end
function API.get_sub_extensions() return API.copy_table(sub_extensions) end
function API.get_audio_extensions() return API.copy_table(audio_extensions) end
function API.get_parseable_extensions() return API.copy_table(parseable_extensions) end
function API.get_state() return API.copy_table(state) end
function API.get_dvd_device() return g.dvd_device end
function API.get_parsers() return API.copy_table(parsers) end
function API.get_root() return API.copy_table(root) end
function API.get_directory() return state.directory end
function API.get_list() return API.copy_table(state.list) end
function API.get_current_file() return API.copy_table(current_file) end
function API.get_current_parser() return state.parser:get_id() end
function API.get_current_parser_keyname() return state.parser.keybind_name or state.parser.name end
function API.get_selected_index() return state.selected end
function API.get_selected_item() return API.copy_table(state.list[state.selected]) end
function API.get_open_status() return not state.hidden end
function API.get_parse_state(co) return parse_states[co or coroutine.running() or ""] end

function API.set_empty_text(str)
    state.empty_text = str
    API.redraw()
end

function API.set_selected_index(index)
    if type(index) ~= "number" then return false end
    if index < 1 then index = 1 end
    if index > #state.list then index = #state.list end
    state.selected = index
    API.redraw()
    return index
end

function parser_API:get_index() return parsers[self].index end
function parser_API:get_id() return parsers[self].id end

--a wrapper that passes the parsers priority value if none other is specified
function parser_API:register_root_item(item, priority)
    return API.register_root_item(item, priority or parsers[self:get_id()].priority)
end

--runs choose_and_parse starting from the next parser
function parser_API:defer(directory)
    msg.trace("deferring to other parsers...")
    local list, opts = scanning.choose_and_parse(directory, self:get_index() + 1)
    API.get_parse_state().already_deferred = true
    return list, opts
end



--------------------------------------------------------------------------------------------------------
-----------------------------------------Setup Functions------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local API_MAJOR, API_MINOR, API_PATCH = g.API_VERSION:match("(%d+)%.(%d+)%.(%d+)")

--checks if the given parser has a valid version number
local function check_api_version(parser)
    local version = parser.version or "1.0.0"

    local major, minor = version:match("(%d+)%.(%d+)")

    if not major or not minor then
        return msg.error("Invalid version number")
    elseif major ~= API_MAJOR then
        return msg.error("parser", parser.name, "has wrong major version number, expected", ("v%d.x.x"):format(API_MAJOR), "got", 'v'..version)
    elseif minor > API_MINOR then
        msg.warn("parser", parser.name, "has newer minor version number than API, expected", ("v%d.%d.x"):format(API_MAJOR, API_MINOR), "got", 'v'..version)
    end
    return true
end

--create a unique id for the given parser
local function set_parser_id(parser)
    local name = parser.name
    if parsers[name] then
        local n = 2
        name = parser.name.."_"..n
        while parsers[name] do
            n = n + 1
            name = parser.name.."_"..n
        end
    end

    parsers[name] = parser
    parsers[parser] = { id = name }
end

--loads an addon in a separate environment
local function load_addon(path)
    local name_sqbr = string.format("[%s]", path:match("/([^/]*)%.lua$"))
    local addon_environment = API.redirect_table(_G)
    addon_environment._G = addon_environment

    --gives each addon custom debug messages
    addon_environment.package = API.redirect_table(addon_environment.package)
    addon_environment.package.loaded = API.redirect_table(addon_environment.package.loaded)
    local msg_module = {
        log = function(level, ...) msg.log(level, name_sqbr, ...) end,
        fatal = function(...) return msg.fatal(name_sqbr, ...) end,
        error = function(...) return msg.error(name_sqbr, ...) end,
        warn = function(...) return msg.warn(name_sqbr, ...) end,
        info = function(...) return msg.info(name_sqbr, ...) end,
        verbose = function(...) return msg.verbose(name_sqbr, ...) end,
        debug = function(...) return msg.debug(name_sqbr, ...) end,
        trace = function(...) return msg.trace(name_sqbr, ...) end,
    }
    addon_environment.print = msg_module.info

    addon_environment.require = function(module)
        if module == "mp.msg" then return msg_module end
        return require(module)
    end

    local chunk, err
    if setfenv then
        --since I stupidly named a function loadfile I need to specify the global one
        --I've been using the name too long to want to change it now
        chunk, err = _G.loadfile(path)
        if not chunk then return msg.error(err) end
        setfenv(chunk, addon_environment)
    else
        chunk, err = _G.loadfile(path, "bt", addon_environment)
        if not chunk then return msg.error(err) end
    end

    local success, result = xpcall(chunk, API.traceback)
    return success and result or nil
end

--setup an internal or external parser
local function setup_parser(parser, file)
    parser = setmetatable(parser, { __index = parser_API })
    parser.name = parser.name or file:gsub("%-browser%.lua$", ""):gsub("%.lua$", "")

    set_parser_id(parser)
    if not check_api_version(parser) then return msg.error("aborting load of parser", parser:get_id(), "from", file) end

    msg.verbose("imported parser", parser:get_id(), "from", file)

    --sets missing functions
    if not parser.can_parse then
        if parser.parse then parser.can_parse = function() return true end
        else parser.can_parse = function() return false end end
    end

    if parser.priority == nil then parser.priority = 0 end
    if type(parser.priority) ~= "number" then return msg.error("parser", parser:get_id(), "needs a numeric priority") end

    --the root parser has special behaviour, so it should not be in the list of parsers
    if parser == root_parser then return end
    table.insert(parsers, parser)
end

--load an external addon
local function setup_addon(file, path)
    if file:sub(-4) ~= ".lua" then return msg.verbose(path, "is not a lua file - aborting addon setup") end

    local addon_parsers = load_addon(path)
    if not addon_parsers or type(addon_parsers) ~= "table" then return msg.error("addon", path, "did not return a table") end

    --if the table contains a priority key then we assume it isn't an array of parsers
    if not addon_parsers[1] then addon_parsers = {addon_parsers} end

    for _, parser in ipairs(addon_parsers) do
        setup_parser(parser, file)
    end
end

--loading external addons
local function setup_addons()
    local addon_dir = mp.command_native({"expand-path", o.addon_directory..'/'})
    local files = utils.readdir(addon_dir)
    if not files then error("could not read addon directory") end

    for _, file in ipairs(files) do
        setup_addon(file, addon_dir..file)
    end
    table.sort(parsers, function(a, b) return a.priority < b.priority end)

    --we want to store the indexes of the parsers
    for i = #parsers, 1, -1 do parsers[ parsers[i] ].index = i end

    --we want to run the setup functions for each addon
    for index, parser in ipairs(parsers) do
        if parser.setup then
            local success = xpcall(function() parser:setup() end, API.traceback)
            if not success then
                msg.error("parser", parser:get_id(), "threw an error in the setup method - removing from list of parsers")
                table.remove(parsers, index)
            end
        end
    end
end

--sets up the compatible extensions list
local function setup_extensions_list()
    --setting up subtitle extensions
    for ext in API.iterate_opt(o.subtitle_extensions:lower()) do
        sub_extensions[ext] = true
        extensions[ext] = true
    end

    --setting up audio extensions
    for ext in API.iterate_opt(o.audio_extensions:lower()) do
        audio_extensions[ext] = true
        extensions[ext] = true
    end

    --adding file extensions to the set
    for _, ext in ipairs(compatible_file_extensions) do
        extensions[ext] = true
    end

    --adding extra extensions on the whitelist
    for str in API.iterate_opt(o.extension_whitelist:lower()) do
        extensions[str] = true
    end

    --removing extensions that are in the blacklist
    for str in API.iterate_opt(o.extension_blacklist:lower()) do
        extensions[str] = nil
    end
end

--splits the string into a table on the semicolons
local function setup_root()
    for str in API.iterate_opt(o.root) do
        local path = mp.command_native({'expand-path', str})
        path = API.fix_path(path, true)

        local temp = {name = path, type = 'dir', label = str, ass = API.ass_escape(str, true)}

        root[#root+1] = temp
    end
end

setup_root()

setup_parser(file_parser, "file-browser.lua")
setup_parser(root_parser, 'file-browser.lua')
if o.addons then
    --all of the API functions need to be defined before this point for the addons to be able to access them safely
    setup_addons()
end

--these need to be below the addon setup in case any parsers add custom entries
setup_extensions_list()
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

