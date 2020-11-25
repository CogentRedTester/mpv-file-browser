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
local opt = require 'mp.options'

local o = {
    --root directories
    root = "~/",

    --characters to use as seperators
    root_seperators = ",;",

    --number of entries to show on the screen at once
    num_entries = 20,

    --only show files compatible with mpv
    filter_files = true,

    --enable custom keybinds
    custom_keybinds = false,

    --blacklist compatible files, it's recommended to use this rather than to edit the
    --compatible list directly. A semicolon separated list of extensions without spaces
    extension_blacklist = "",

    --add extra file extensions
    extension_whitelist = "",

    --filter dot directories like .config
    --only usefu on linux systems
    filter_dot_dirs = false,

    --enable addons
    dvd_browser = false,
    http_browser = false,
    ftp_browser = false,

    --ass tags
    ass_header = "{\\q2\\fs35\\c&00ccff&}",
    ass_body = "{\\q2\\fs25\\c&Hffffff&}",
    ass_selected = "{\\c&Hfce788&}",
    ass_multiselect = "{\\c&Hfcad88&}",
    ass_playing = "{\\c&H33ff66&}",
    ass_playingselected = [[{\c&H22b547&}]],
    ass_footerheader = "{\\c&00ccff&\\fs16}",
    ass_cursor = "{\\c&00ccff&}"
}

opt.read_options(o, 'file_browser')

package.path = mp.command_native( {"expand-path", (mp.get_opt("scroll_list-directory") or "~~/scripts") } ) .. "/?.lua;" .. package.path
local list = require "scroll-list"

--setting ass styles for the list
list.num_entries = o.num_entries
list.header_style = o.ass_header

local cache = {}
local extensions = nil
local state = {
    directory = nil,
    selection = {},
    prev_directory = "",
    current_file = {
        directory = nil,
        name = nil
    },
    dvd_device = nil,
    parser = "file-browser"
}
local root = nil
local open_dvd_browser

--default list of compatible file extensions
--adding an item to this list is a valid request on github
local compatible_file_extensions = {
    "264","265","3g2","3ga","3ga2","3gp","3gp2","3gpp","3iv","a52","aac","adt","adts","ahn","aif","aifc","aiff","amr","ape","asf","au","avc","avi","awb","ay",
    "bmp","cue","divx","dts","dtshd","dts-hd","dv","dvr","dvr-ms","eac3","evo","evob","f4a","flac","flc","fli","flic","flv","gbs","gif","gxf","gym",
    "h264","h265","hdmov","hdv","hes","hevc","jpeg","jpg","kss","lpcm","m1a","m1v","m2a","m2t","m2ts","m2v","m3u","m3u8","m4a","m4v","mid","mk3d","mka","mkv",
    "mlp","mod","mov","mp1","mp2","mp2v","mp3","mp4","mp4v","mp4v","mpa","mpe","mpeg","mpeg2","mpeg4","mpg","mpg4","mpv","mpv2","mts","mtv","mxf","nsf",
    "nsfe","nsv","nut","oga","ogg","ogm","ogv","ogx","opus","pcm","pls","png","qt","ra","ram","rm","rmvb","sap","snd","spc","spx","svg","thd","thd+ac3",
    "tif","tiff","tod","trp","truehd","true-hd","ts","tsa","tsv","tta","tts","vfw","vgm","vgz","vob","vro","wav","weba","webm","webp","wm","wma","wmv","wtv",
    "wv","x264","x265","xvid","y4m","yuv"
}

--detects whether or not to highlight the given entry as being played
local function highlight_entry(v)
    if v.type == "dir" then
        return state.current_file.directory:find(state.directory .. v.name, 1, true)
    else
        return state.current_file.directory == state.directory and state.current_file.name == v.name
    end
end

--creating the custom formatting function
list.format_line = function(this, i, v)
    local playing_file = highlight_entry(v)
    -- if not playing_file then print(utils.to_string(state.current_file)) ; print(state.directory) end
    this:append(o.ass_body)

    --handles custom styles for different entries
    if i == list.selected then this:append(o.ass_cursor..[[➤\h]]..o.ass_body)
    else this:append([[\h\h\h\h]]) end

    --sets the selection colour scheme
    local multiselected = state.selection[i]
    if multiselected then this:append(o.ass_multiselect)
    elseif i == list.selected then this:append(o.ass_selected) end

    --prints the currently-playing icon and style
    if playing_file and multiselected then this:append(o.ass_playingselected)
    elseif playing_file then this:append(o.ass_playing) end

    --sets the folder icon
    if v.type == 'dir' then this:append([[🖿\h]]) end

    --adds the actual name of the item
    if v.label then this:append(v.label.."\\N")
    else this:append(v.name.."\\N") end
end

--standardises filepaths across systems
local function fix_path(str, directory)
    str = str:gsub([[\]],[[/]])
    str = str:gsub([[/./]], [[/]])
    if directory and str:sub(-1) ~= '/' then str = str..'/' end
    return str
end

--sets up the compatible extensions list
local function setup_extensions_list()
    extensions = {}
    if not o.filter_files then return end

    --adding file extensions to the set
    for i=1, #compatible_file_extensions do
        extensions[compatible_file_extensions[i]] = true
    end

    --adding extra extensions on the whitelist
    for str in string.gmatch(o.extension_whitelist, "([^"..o.root_seperators.."]+)") do
        extensions[str] = true
    end

    --removing extensions that are in the blacklist
    for str in string.gmatch(o.extension_blacklist, "([^"..o.root_seperators.."]+)") do
        extensions[str] = nil
    end
end

--sorts the table lexicographically ignoring case and accounting for leading/non-leading zeroes
--the number format functionality was proposed by github user twophyro, and was presumably taken
--from here: http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
local function sort(t)
    local function padnum(d)
        local r = string.match(d, "0*(.+)")
        return ("%03d%s"):format(#r, r)
    end

    --appends the letter d or f to the start of the comparison to sort directories and folders as well
    table.sort(t, function(a,b) return a.type:sub(1,1)..a.name:lower():gsub("%d+",padnum) < b.type:sub(1,1)..b.name:lower():gsub("%d+",padnum) end)
    return t
end

--checks if the name has a valid extension
local function is_valid(name)
    local index = name:find([[.[^.]*$]])
    if not index then return false end
    local fileext = name:sub(index + 1)
    return extensions[fileext]
end

--removes items and folders from the list
--this is for addons which can't filter things during their normal processing
local function filter(t)
    local max = #t
    local top = 1
    for i = 1, max do
        local temp = t[i]
        t[i] = nil
        if  ( temp.type == "dir" and (not o.filter_dot_dirs or (temp.name:find('%.') ~= 1)) )
            or ( temp.type == "file" and o.filter_files and is_valid(temp.name) )
        then
            t[top] = temp
            top = top+1
        end
    end
end

--scans the list for the folder that the script just moved out of
--must be run after the sort
local function select_prev_directory()
    if state.prev_directory:find(state.directory, 1, true) ~= 1 then return end

    local i = 1
    while (list.list[i] and list.list[i].type == "dir") do
        if state.prev_directory:find(state.directory..list.list[i].name, 1, true) then
            list.selected = i
            break
        end
        i = i+1
    end
end

--splits the string into a table on the semicolons
local function setup_root()
    root = {}
    for str in string.gmatch(o.root, "([^"..o.root_seperators.."]+)") do
        local path = mp.command_native({'expand-path', str})
        path = fix_path(path, true)

        local temp = {name = path, type = 'dir', label = str}

        --setting up the addon handlers
        if o.http_browser and path:find("https://") == 1 then temp.parser = "http"
        elseif o.ftp_browser and path:sub(1,6) == "ftp://" then temp.parser = "ftp"
        else temp.parser = "file" end

        root[#root+1] = temp
    end
end

--saves the directory and name of the currently playing file
local function update_current_directory(_, filepath)
    --if we're in idle mode then we want to open to the root
    if filepath == nil then 
        state.current_file.directory = ""
        return
    elseif filepath:find("dvd://") == 1 then
        filepath = state.dvd_device
    end

    local workingDirectory = mp.get_property('working-directory', '')
    local exact_path = filepath:find(":") and filepath or utils.join_path(workingDirectory, filepath)
    exact_path = fix_path(exact_path, false)
    state.current_file.directory, state.current_file.name = utils.split_path(exact_path)
end

--updates the header with the current directory
local function update_header()
    local dir_name = state.directory
    if dir_name == "" then dir_name = "ROOT" end
    list.header = dir_name..'\\N ----------------------------------------------------'
end

--loads the root list
local function goto_root()
    if root == nil then setup_root() end
    msg.verbose('loading root')
    list.selected = 1
    list.list = root

    --if moving to root from one of the connected locations,
    --then select that location
    state.directory = ""
    select_prev_directory()

    state.parser = ""
    state.prev_directory = ""
    cache = {}
    state.selection = {}
    update_header()
    list:update()
end

--scans the current directory and updates the directory table
local function update_local_list()
    local list1 = utils.readdir(state.directory, 'dirs')

    --if we can't access the filesystem for the specified directory then we go to root page
    --this is cuased by either:
    --  a network file being streamed
    --  the user navigating above / on linux or the current drive root on windows
    if list1 == nil then
        goto_root()
        return
    end

    --sorts folders and formats them into the list of directories
    for i=1, #list1 do
        local item = list1[i]

        --filters hidden dot directories for linux
        if o.filter_dot_dirs and item:find('%.') == 1 then goto continue end

        msg.debug(item..'/')
        table.insert(list.list, {name = item..'/', type = 'dir'})

        ::continue::
    end

    --appends files to the list of directory items
    local list2 = utils.readdir(state.directory, 'files')
    for i=1, #list2 do
        local item = list2[i]

        --only adds whitelisted files to the browser
        if o.filter_files then
            if not is_valid(item) then goto continue end
        end

        msg.debug(item)
        table.insert(list.list, {name = item, type = 'file'})

        ::continue::
    end
    sort(list.list)
    select_prev_directory()

    --saves the latest directory at the top of the stack
    cache[#cache+1] = {directory = state.directory, table = list.list}

    --once the directory has been successfully loaded we set it as the 'prev' directory for next time
    --this is for highlighting the previous folder when moving up a directory
    state.prev_directory = state.directory
end

--sends update requests to the different parsers
local function update_list()
    msg.verbose('loading contents of ' .. state.directory)

    list.selected = 1
    state.selection = {}
    if extensions == nil then setup_extensions_list() end

    --dvd browser has special behaviour, so it is called seperately from the other add-ons
    if o.dvd_browser then
        if state.directory == state.dvd_device then
            state.parser = "dvd"
            open_dvd_browser()
            return
        end
    end

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if #cache > 0 then
        local cache = cache[#cache]
        if cache.directory == state.directory then
            msg.verbose('found directory in cache')
            list.list = cache.table

            --sets the cursor to the previously opened file and resets the prev_directory in
            --case we move above the cache source
            list.selected = cache.cursor
            state.prev_directory = state.directory
            list:update()
            return
        end
    end

    if state.directory == "" then
        goto_root()
    elseif o.http_browser and state.directory:find("https?://") == 1 then
        state.parser = "http"
        mp.commandv("script-message", "http/browse-dir", state.directory)
    elseif o.ftp_browser and state.directory:sub(1, 6) == "ftp://" then
        state.parser = "ftp"
        mp.commandv("script-message", "ftp/browse-dir", state.directory)
    else
        state.parser = "file"
        update_local_list()
        list:update()
    end
end

--rescans the folder and updates the list
local function update()
    update_header()
    list.empty_text = "~"
    list.list = {}
    list:update()
    list.empty_text = "empty directory"
    update_list()
end

--switches to the directory of the currently playing file
local function goto_current_dir()
    --splits the directory and filename apart
    state.directory = state.current_file.directory
    list.selected = 1
    update()
end

--moves up a directory
local function up_dir()
    local dir = state.directory:reverse()
    local index = dir:find("[/\\]")

    while index == 1 do
        dir = dir:sub(2)
        index = dir:find("[/\\]")
    end

    if index == nil then state.directory = ""
    else state.directory = dir:sub(index):reverse() end

    cache[#cache] = nil
    update()
end

--moves down a directory
local function down_dir()
    if not list.list[list.selected] or list.list[list.selected].type ~= 'dir' then return end

    state.directory = state.directory..list.list[list.selected].name
    if #cache > 0 then cache[#cache].cursor = list.selected end
    update()
end

--toggles the selection
local function toggle_selection()
    if list.list[list.selected] then
        if state.selection[list.selected] then
            state.selection[list.selected] = nil
        else
            state.selection[list.selected] = true
        end
    end
    list:update()
end

--drags the selection down
local function drag_down()
    state.selection[list.selected] = true
    list:scroll_down()
    state.selection[list.selected] = true
    list:update()
end

--drags the selection up
local function drag_up()
    state.selection[list.selected] = true
    list:scroll_up()
    state.selection[list.selected] = true
    list:update()
end

--sortes a table into an array of its key values
local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    table.sort(keys)
    return keys
end

--loads lists or defers the command to add-ons
local function loadlist(item, path, flags)
    local parser = item.parser or state.parser
    if parser == "file" or parser == "dvd" then mp.commandv('loadlist', path, flags)
    elseif parser ~= "" then mp.commandv("script-message", parser.."/open-dir", path, flags)
    end
end

--runs the loadfile or loadlist command
local function loadfile(item, flags)
    local path = state.directory..item.name
    if (path == state.dvd_device) then path = "dvd://"
    elseif item.type == "dir" then return loadlist(item, path, flags) end
    return mp.commandv('loadfile', path, flags)
end

--opens the selelected file(s)
local function open_file(flags)
    if list.selected > #list.list or list.selected < 1 then return end

    loadfile(list.list[list.selected], flags)
    state.selection[list.selected] = nil

    --handles multi-selection behaviour
    if next(state.selection) then
        local selection = sort_keys(state.selection)

        --the currently selected file will be loaded according to the flag
        --the remaining files will be appended
        for i=1, #selection do
            loadfile(list.list[selection[i]], "append-play")
        end

        --reset the selection after
        state.selection = {}
        if flags == 'replace' then list:close()
        else list:update() end
        return

    elseif flags == 'replace' then
        down_dir()
        list:close()
    end
end

--opens the browser
list.open = function(this)
    this:add_keybinds()

    list.hidden = false
    if state.directory == nil then
        update_current_directory(nil, mp.get_property('path'))
        goto_current_dir()
        return
    end

    if list.flag_update then
        update_current_directory(nil, mp.get_property('path'))
    end
    list:open_list()
end

--intercepts toggles when in an addons domain
--otherwise passes the request to the lists toggle function
local function toggle_browser()
    --if we're in the dvd-device then pass the request on to dvd-browser
    if o.dvd_browser and state.directory == state.dvd_device then
        mp.commandv('script-message-to', 'dvd_browser', 'dvd-browser')
    else
        list:toggle()
    end
end

--run when the escape key is used
local function escape()
    --if multiple items are selection cancel the
    --selection instead of closing the browser
    if next(state.selection) then
        state.selection = {}
        list:update()
        return
    end
    list:close()
end

--isolates just the name of the current directory
local function get_dir_name()
    local find = state.directory:reverse():match("/(.-)/")
    if find then return find:reverse()
    else return state.directory:match("(.-)/") end
end

--iterates through the command table and substitutes special
--character codes for the correct strings used for custom functions
local function format_command_table(t, index)
    local l = list.list
    local copy = {}
    for i = 1, #t do
        copy[i] = t[i]:gsub("%%.", {
            ["%%"] = "%",
            ["%f"] = l[index] and state.directory..l[index].name or "",
            ["%F"] = string.format("%q", l[index] and state.directory..l[index].name or ""),
            ["%n"] = l[index] and (l[index].label or l[index].name) or "",
            ["%N"] = string.format("%q", l[index] and (l[index].label or l[index].name) or ""),
            ["%p"] = state.directory or "",
            ["%P"] = string.format("%q", state.directory or ""),
            ["%d"] = get_dir_name() or "",
            ["%D"] = string.format("q", get_dir_name() or "")
        })
    end
    return copy
end

--runs all of the commands in the command table
--recurses to handle nested tables of commands
local function run_custom_command(t, index)
    if type(t[1]) == "table" then
        for i = 1, #t do
            run_custom_command(t[i], index)
        end
    else
        local custom_cmd = format_command_table(t, index)
        msg.debug("running command: " .. utils.to_string(custom_cmd))
        mp.command_native(custom_cmd)
    end
end

--runs one of the custom commands
local function custom_command(cmd)
    --filtering commands
    if cmd.filter then
        if list.list[list.selected] and list.list[list.selected].type ~= cmd.filter then
            msg.verbose("cancelling custom command")
            return
        end
    end

    --runs the command on all multi-selected items
    if cmd.multiselect and next(state.selection) then
        local selection = sort_keys(state.selection)
        for i = 1, #selection do
            run_custom_command(cmd.command, selection[i])
        end
    else
        run_custom_command(cmd.command, list.selected)
    end
end

--passes control to DVD browser
open_dvd_browser = function()
    state.prev_directory = state.dvd_device
    list:close()
    mp.commandv('script-message', 'browse-dvd')
end

--dynamic keybinds to set while the browser is open
list.keybinds = {
    {'ENTER', 'open', function() open_file('replace') end, {}},
    {'Shift+ENTER', 'append_playlist', function() open_file('append-play') end, {}},
    {'ESC', 'exit', function() escape() end, {}},
    {'RIGHT', 'down_dir', function() down_dir() end, {}},
    {'LEFT', 'up_dir', function() up_dir() end, {}},
    {'DOWN', 'scroll_down', function() list:scroll_down() end, {repeatable = true}},
    {'UP', 'scroll_up', function() list:scroll_up() end, {repeatable = true}},
    {'HOME', 'pwd', function() cache = {}; goto_current_dir() end, {}},
    {'Shift+HOME', 'root', function() goto_root() end, {}},
    {'Ctrl+r', 'reload', function() cache={}; update() end, {}},
    {'Ctrl+ENTER', 'select', function() toggle_selection() end, {}},
    {'Ctrl+DOWN', 'select_down', function() drag_down() end, {repeatable = true}},
    {'Ctrl+UP', 'select_up', function() drag_up() end, {repeatable = true}},
    {'Ctrl+RIGHT', 'select_yes', function() state.selection[list.selected] = true ; list:update() end, {}},
    {'Ctrl+LEFT', 'select_no', function() state.selection[list.selected] = nil ; list:update() end, {}}
}

--loading the custom keybinds
if o.custom_keybinds then
    local path = mp.command_native({"expand-path", "~~/script-opts"}).."/file-browser-keybinds.json"
    local custom_keybinds, err = assert(io.open( path ))
    if custom_keybinds then
        local json = custom_keybinds:read("*a")
        custom_keybinds:close()

        json = utils.parse_json(json)
        if not json then error("invalid json syntax for "..path) end

        for i = 1, #json do
            if json[i].multiselect == nil then json[i].multiselect = true end
            table.insert(list.keybinds, { json[i].key, "custom"..tostring(i), function() custom_command(json[i]) end, {} })
        end
    end
end

--we don't want to add any overhead when the browser isn't open
mp.observe_property('path', 'string', function(_,path)
    if not list.hidden then 
        update_current_directory(_,path)
        list:update()
    else list.flag_update = true end
end)

--updates the dvd_device
mp.observe_property('dvd-device', 'string', function(_, device)
    if device == "" then device = "/dev/dvd/" end
    state.dvd_device = fix_path(device, true)
end)

--declares the keybind to open the browser
mp.add_key_binding('MENU','browse-files', toggle_browser)

--opens the root directory
mp.register_script_message('goto-root-directory',function()
    goto_root()
    list:open()
end)

--opens the directory of the currently playing file
mp.register_script_message('goto-current-directory', function()
    goto_current_dir()
    list:open()
end)

--allows keybinds/other scripts to auto-open specific directories
mp.register_script_message('browse-directory', function(directory)
    msg.verbose('recieved directory from script message: '..directory)

    state.directory = directory
    cache = {}
    update()
    list:open()
end)

--a callback function for addon scripts to return the results of their filesystem processing
mp.register_script_message('update-list-callback', function(json)
    if not json or json == "" then goto_root(); return end
    list.list = utils.parse_json(json)
    if o.filter_files or o.filter_dot_dirs then filter(list.list) end
    sort(list.list)
    select_prev_directory()

    --setting up the cache stuff
    cache[#cache+1] = {directory = state.directory, table = list.list}
    state.prev_directory = state.directory
    list:update()
end)
