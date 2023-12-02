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

state.keybinds = {
    {'ENTER',       'play',         function() playlist.add_files('replace', false) end},
    {'Shift+ENTER', 'play_append',  function() playlist.add_files('append-play', false) end},
    {'Alt+ENTER',   'play_autoload',function() playlist.add_files('replace', true) end},
    {'ESC',         'close',        controls.escape},
    {'RIGHT',       'down_dir',     movement.down_dir},
    {'LEFT',        'up_dir',       movement.up_dir},
    {'DOWN',        'scroll_down',  function() cursor.scroll(1, o.wrap) end,           {repeatable = true}},
    {'UP',          'scroll_up',    function() cursor.scroll(-1, o.wrap) end,          {repeatable = true}},
    {'PGDWN',       'page_down',    function() cursor.scroll(o.num_entries) end,       {repeatable = true}},
    {'PGUP',        'page_up',      function() cursor.scroll(-o.num_entries) end,      {repeatable = true}},
    {'Shift+PGDWN', 'list_bottom',  function() cursor.scroll(math.huge) end},
    {'Shift+PGUP',  'list_top',     function() cursor.scroll(-math.huge) end},
    {'HOME',        'goto_current', movement.goto_current_dir},
    {'Shift+HOME',  'goto_root',    movement.goto_root},
    {'Ctrl+r',      'reload',       function() cache:clear(); scanning.rescan() end},
    {'s',           'select_mode',  cursor.toggle_select_mode},
    {'S',           'select_item',  cursor.toggle_selection},
    {'Ctrl+a',      'select_all',   cursor.select_all}
}

--a map of key-keybinds - only saves the latest keybind if multiple have the same key code
local top_level_keys = {}

--format the item string for either single or multiple items
local function create_item_string(fn)
    local quoted_fn = function(...) return ("%q"):format(fn(...)) end
    return function(cmd, items, state, code)
        if not items[1] then return end
        local func = code == code:upper() and quoted_fn or fn

        local str = func(cmd, items[1], state, code)
        for i = 2, #items, 1 do
            str = str .. ( cmd["concat-string"] or " " ) .. func(cmd, items[i], state, code)
        end
        return str
    end
end

--functions to replace custom-keybind codes
local code_fns
code_fns = {
    ["%"] = "%",

    f = create_item_string(function(_, item, s) return item and API.get_full_path(item, s.directory) or "" end),
    n = create_item_string(function(_, item, _) return item and (item.label or item.name) or "" end),
    i = create_item_string(function(_, item, s) return API.list.indexOf(s.list, item) end),
    j = create_item_string(function(_, item, s) return math.abs(API.list.indexOf( API.sort_keys(s.selection) , item)) end),

    p = function(_, _, s) return s.directory or "" end,
    d = function(_, _, s) return (s.directory_label or s.directory):match("([^/]+)/?$") or "" end,
    r = function(_, _, s) return s.parser.keybind_name or s.parser.name or "" end,
}

--codes that are specific to individual items require custom encapsulation behaviour
--hence we need to manually specify the uppercase codes in the table
code_fns.F = code_fns.f
code_fns.N = code_fns.n
code_fns.I = code_fns.i
code_fns.J = code_fns.j

--programatically creates a pattern that matches any key code
--this will result in some duplicates but that shouldn't really matter
local CUSTOM_KEYBIND_CODES = ""
for key in pairs(code_fns) do CUSTOM_KEYBIND_CODES = CUSTOM_KEYBIND_CODES..key:lower()..key:upper() end
local KEYBIND_CODE_PATTERN = ('%%%%([%s])'):format(API.ass_escape(CUSTOM_KEYBIND_CODES))

--substitutes the key codes for the 
local function substitute_codes(str, cmd, items, state)
    return string.gsub(str, KEYBIND_CODE_PATTERN, function(code)
        if type(code_fns[code]) == "string" then return code_fns[code] end

        --encapsulates the string if using an uppercase code
        if not code_fns[code] then
            local lower = code_fns[code:lower()]
            if not lower then return end
            return string.format("%q", lower(cmd, items, state, code))
        end

        return code_fns[code](cmd, items, state, code)
    end)
end

--iterates through the command table and substitutes special
--character codes for the correct strings used for custom functions
local function format_command_table(cmd, items, state)
    local copy = {}
    for i = 1, #cmd.command do
        copy[i] = {}

        for j = 1, #cmd.command[i] do
            copy[i][j] = substitute_codes(cmd.command[i][j], cmd, items, state)
        end
    end
    return copy
end

--runs all of the commands in the command table
--key.command must be an array of command tables compatible with mp.command_native
--items must be an array of multiple items (when multi-type ~= concat the array will be 1 long)
local function run_custom_command(cmd, items, state)
    local custom_cmds = cmd.codes and format_command_table(cmd, items, state) or cmd.command

    for _, custom_cmd in ipairs(custom_cmds) do
        msg.debug("running command:", utils.to_string(custom_cmd))
        mp.command_native(custom_cmd)
    end
end

--returns true if the given code set has item specific codes (%f, %i, etc)
local function has_item_codes(codes)
    for code in pairs(codes) do
        if code_fns[code:upper()] then return true end
    end
    return false
end

--runs one of the custom commands
local function run_custom_keybind(cmd, state, co)
    --evaluates a condition and passes through the correct values
    local function evaluate_condition(condition, items)
        local cond = substitute_codes(condition, cmd, items, state)
        return API.evaluate_string('return '..cond) == true
    end

    -- evaluates the string condition to decide if the keybind should be run
    local do_item_condition
    if cmd.condition then
        if has_item_codes(cmd.condition_codes) then
            do_item_condition = true
        elseif not evaluate_condition(cmd.condition, {}) then
            return false
        end
    end

    if cmd.parser then
       local parser_str = ' '..cmd.parser..' '
       if not parser_str:find( '%W'..(state.parser.keybind_name or state.parser.name)..'%W' ) then return false end
    end

    --these are for the default keybinds, or from addons which use direct functions
    if type(cmd.command) == 'function' then return cmd.command(cmd, cmd.addon and API.copy_table(state) or state, co) end

    --the function terminates here if we are running the command on a single item
    if not (cmd.multiselect and next(state.selection)) then
        if cmd.filter then
            if not state.list[state.selected] then return false end
            if state.list[state.selected].type ~= cmd.filter then return false end
        end

        if cmd.codes then
            --if the directory is empty, and this command needs to work on an item, then abort and fallback to the next command
            if not state.list[state.selected] and has_item_codes(cmd.codes) then return false end
        end

        if do_item_condition and not evaluate_condition(cmd.condition, { state.list[state.selected] }) then
            return false
        end
        run_custom_command(cmd, { state.list[state.selected] }, state)
        return true
    end

    --runs the command on all multi-selected items
    local selection = API.sort_keys(state.selection, function(item)
        if do_item_condition and not evaluate_condition(cmd.condition, { item }) then return false end
        return not cmd.filter or item.type == cmd.filter
    end)
    if not next(selection) then return false end

    if cmd["multi-type"] == "concat" then
        run_custom_command(cmd, selection, state)

    elseif cmd["multi-type"] == "repeat" or cmd["multi-type"] == nil then
        for i,_ in ipairs(selection) do
            run_custom_command(cmd, {selection[i]}, state)

            if cmd.delay then
                mp.add_timeout(cmd.delay, function() API.coroutine.resume_err(co) end)
                coroutine.yield()
            end
        end
    end

    --we passthrough by default if the command is not run on every selected item
    if cmd.passthrough ~= nil then return end

    local num_selection = 0
    for _ in pairs(state.selection) do num_selection = num_selection+1 end
    return #selection == num_selection
end

--recursively runs the keybind functions, passing down through the chain
--of keybinds with the same key value
local function run_keybind_recursive(keybind, state, co)
    msg.trace("Attempting custom command:", utils.to_string(keybind))

    if keybind.passthrough ~= nil then
        run_custom_keybind(keybind, state, co)
        if keybind.passthrough == true and keybind.prev_key then
            run_keybind_recursive(keybind.prev_key, state, co)
        end
    else
        if run_custom_keybind(keybind, state, co) == false and keybind.prev_key then
            run_keybind_recursive(keybind.prev_key, state, co)
        end
    end
end

--a wrapper to run a custom keybind as a lua coroutine
local function run_keybind_coroutine(key)
    msg.debug("Received custom keybind "..key.key)
    local co = coroutine.create(run_keybind_recursive)

    local state_copy = {
        directory = state.directory,
        directory_label = state.directory_label,
        list = state.list,                      --the list should remain unchanged once it has been saved to the global state, new directories get new tables
        selected = state.selected,
        selection = API.copy_table(state.selection),
        parser = state.parser,
    }
    local success, err = coroutine.resume(co, key, state_copy, co)
    if not success then
        msg.error("error running keybind:", utils.to_string(key))
        API.traceback(err, co)
    end
end

--scans the given command table to identify if they contain any custom keybind codes
local function scan_for_codes(command_table, codes)
    if type(command_table) ~= "table" then return codes end
    for _, value in pairs(command_table) do
        local type = type(value)
        if type == "table" then
            scan_for_codes(value, codes)
        elseif type == "string" then
            value:gsub(KEYBIND_CODE_PATTERN, function(code) codes[code] = true end)
        end
    end
    return codes
end

--inserting the custom keybind into the keybind array for declaration when file-browser is opened
--custom keybinds with matching names will overwrite eachother
local function insert_custom_keybind(keybind)
    --we'll always save the keybinds as either an array of command arrays or a function
    if type(keybind.command) == "table" and type(keybind.command[1]) ~= "table" then
        keybind.command = {keybind.command}
    end

    keybind.codes = scan_for_codes(keybind.command, {})
    if not next(keybind.codes) then keybind.codes = nil end
    keybind.prev_key = top_level_keys[keybind.key]

    if keybind.condition then
        keybind.condition_codes = {}
        for code in string.gmatch(keybind.condition, KEYBIND_CODE_PATTERN) do keybind.condition_codes[code] = true end
    end

    table.insert(state.keybinds, {keybind.key, keybind.name, function() run_keybind_coroutine(keybind) end, keybind.flags or {}})
    top_level_keys[keybind.key] = keybind
end

--loading the custom keybinds
--can either load keybinds from the config file, from addons, or from both
local function setup_keybinds()
    if not o.custom_keybinds and not o.addons then return end

    --this is to make the default keybinds compatible with passthrough from custom keybinds
    for _, keybind in ipairs(state.keybinds) do
        top_level_keys[keybind[1]] = { key = keybind[1], name = keybind[2], command = keybind[3], flags = keybind[4] }
    end

    --this loads keybinds from addons
    if o.addons then
        for i = #parsers, 1, -1 do
            local parser = parsers[i]
            if parser.keybinds then
                for i, keybind in ipairs(parser.keybinds) do
                    --if addons use the native array command format, then we need to convert them over to the custom command format
                    if not keybind.key then keybind = { key = keybind[1], name = keybind[2], command = keybind[3], flags = keybind[4] }
                    else keybind = API.copy_table(keybind) end

                    keybind.name = parsers[parser].id.."/"..(keybind.name or tostring(i))
                    keybind.addon = true
                    insert_custom_keybind(keybind)
                end
            end
        end
    end

    --loads custom keybinds from file-browser-keybinds.json
    if o.custom_keybinds then
        local path = mp.command_native({"expand-path", "~~/script-opts"}).."/file-browser-keybinds.json"
        local custom_keybinds, err = io.open( path )
        if not custom_keybinds then return error(err) end

        local json = custom_keybinds:read("*a")
        custom_keybinds:close()

        json = utils.parse_json(json)
        if not json then return error("invalid json syntax for "..path) end

        for i, keybind in ipairs(json) do
            keybind.name = "custom/"..(keybind.name or tostring(i))
            insert_custom_keybind(keybind)
        end
    end
end



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
setup_keybinds()



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

