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
    --most useful on linux systems
    filter_dot_dirs = false,
    filter_dot_files = false,

    --when loading a directory from the browser use the scripts
    --parsing code to load the contents of the folder (using filters and sorting)
    --this means that files will be added to the playlist identically
    --to how they appear in the browser, rather than leaving it to mpv
    custom_dir_loading = false,

    --this option reverses the behaviour of the alt+ENTER keybind
    --when disabled the keybind is required to enable autoload for the file
    --when enabled the keybind disables autoload for the file
    autoload = false,

    --allows custom icons be set to fix incompatabilities with some fonts
    folder_icon = "🖿",
    cursor_icon = "➤",

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
list.cursor_style = o.ass_cursor

list.directory = nil
list.directory_label = nil
list.selection = {}
list.multiselect = nil
list.prev_directory = ""
list.dvd_device = nil
list.parser = "file"

local extensions = nil
local sub_extensions = {}

local current_file = {
    directory = nil,
    name = nil
}

local root = nil

local cache = {
    stack = {}
}
local meta = {
    __len = function(self)
        return #self.stack
    end
}
cache = setmetatable(cache, meta)

--push current settings onto the stack
function cache:push()
    table.insert(self.stack, {
        directory = list.directory,
        directory_label = list.directory_label,
        list = list.list,
        parser = list.parser,
        selected = list.selected
    })
end

--remove latest directory from the stack
function cache:pop()
    table.remove(self.stack)
end

--apply the settings in the cache
function cache:apply()
    for key, value in pairs(self.stack[#self.stack]) do
        list[key] = value
    end
end

--empty the cache
function cache:clear()
    self.stack = {}
end

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

--creating a set of subtitle extensions for custom subtitle loading behaviour
local subtitle_extensions = {
    "etf","etf8","utf-8","idx","sub","srt","rt","ssa","ass","mks","vtt","sup","scc","smi","lrc",'pgs'
}
for i = 1, #subtitle_extensions do
    sub_extensions[subtitle_extensions[i]] = true
end

--chooses which parser to use for the specific path
local function choose_parser(path)
    if o.dvd_browser and path == list.dvd_device then return "dvd"
    elseif o.http_browser and path:find("https?://") == 1 then return "http"
    elseif o.ftp_browser and path:sub(1, 6) == "ftp://" then return "ftp"
    else return "file" end
end

--get the full path for the current file
local function get_full_path(item, dir)
    if item.path then return item.path end
    return (dir or list.directory)..item.name
end

--detects whether or not to highlight the given entry as being played
local function highlight_entry(v)
    if v.type == "dir" then
        return current_file.directory:find(get_full_path(v), 1, true)
    else
        return current_file.directory == list.directory and current_file.name == v.name
    end
end

--creating the custom formatting function
function list:format_line(i, v)
    local playing_file = highlight_entry(v)
    self:append(o.ass_body)

    --handles custom styles for different entries
    if i == list.selected then self:append(list.cursor_style..o.cursor_icon.."\\h"..o.ass_body)
    else self:append([[\h\h\h\h]]) end

    --sets the selection colour scheme
    local multiselected = list.selection[i]
    if multiselected then self:append(o.ass_multiselect)
    elseif i == list.selected then self:append(o.ass_selected) end

    --prints the currently-playing icon and style
    if playing_file and multiselected then self:append(o.ass_playingselected)
    elseif playing_file then self:append(o.ass_playing) end

    --sets the folder icon
    if v.type == 'dir' then self:append(o.folder_icon.."\\h") end

    --adds the actual name of the item
    self:append(v.ass or v.label or v.name)
    self:newline()
end

--updates the header with the current directory
function list:format_header()
    local dir_name = list.directory_label or list.directory
    if dir_name == "" then dir_name = "ROOT" end
    self:append(list.header_style)
    self:append(list.ass_escape(dir_name)..'\\N ----------------------------------------------------')
    self:newline()
end

--standardises filepaths across systems
local function fix_path(str, is_directory)
    str = str:gsub([[\]],[[/]])
    str = str:gsub([[/./]], [[/]])
    if is_directory and str:sub(-1) ~= '/' then str = str..'/' end
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
    for i = 1, #subtitle_extensions do
        extensions[subtitle_extensions[i]] = true
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

--escapes ass characters - better to do it once then calculate it on the fly every time the list updates
local function escape_ass(t)
    for i = 1, #t do
        t[i].ass = t[i].ass or list.ass_escape(t[i].label or t[i].name)
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
    table.sort(t, function(a,b) return a.type:sub(1,1)..(a.label or a.name):lower():gsub("%d+",padnum) < b.type:sub(1,1)..(b.label or b.name):lower():gsub("%d+",padnum) end)
    return t
end

--returns the file extension of the given file
local function get_extension(filename)
    return filename:match("%.([^%.]+)$")
end

--removes items and folders from the list
--this is for addons which can't filter things during their normal processing
local function filter(t)
    local max = #t
    local top = 1
    for i = 1, max do
        local temp = t[i]
        t[i] = nil

        if  ( temp.type == "dir" and not ( o.filter_dot_dirs and temp.name:sub(1,1) == ".") ) or
            ( temp.type == "file"   and not ( o.filter_dot_files and (temp.name:sub(1,1) == ".") )
                                    and not ( o.filter_files and not extensions[ get_extension(temp.name) ] ) )
        then
            t[top] = temp
            top = top+1
        end
    end
end

--scans the list for which item to select by default
--chooses the folder that the script just moved out of
--or, otherwise, the item highlighted as currently playing
local function select_prev_directory()
    if list.prev_directory:find(list.directory, 1, true) == 1 then
        local i = 1
        while (list.list[i] and list.list[i].type == "dir") do
            if list.prev_directory:find(get_full_path(list.list[i]), 1, true) then
                list.selected = i
                return
            end
            i = i+1
        end
    end

    if current_file.directory:find(list.directory, 1, true) == 1 then
        for i,item in ipairs(list.list) do
            if highlight_entry(item) then
                list.selected = i
                return
            end
        end
    end
end

local function disable_select_mode()
    list.cursor_style = o.ass_cursor
    list.multiselect = nil
end

--splits the string into a table on the semicolons
local function setup_root()
    root = {}
    for str in string.gmatch(o.root, "([^"..o.root_seperators.."]+)") do
        local path = mp.command_native({'expand-path', str})
        path = fix_path(path, true)

        local temp = {name = path, type = 'dir', label = str, ass = list.ass_escape(str), parser = choose_parser(path)}

        root[#root+1] = temp
    end
end

--saves the directory and name of the currently playing file
local function update_current_directory(_, filepath)
    --if we're in idle mode then we want to open to the root
    if filepath == nil then 
        current_file.directory = ""
        return
    elseif filepath:find("dvd://") == 1 then
        filepath = list.dvd_device..filepath:match("dvd://(.+)")
    end

    local workingDirectory = mp.get_property('working-directory', '')
    local exact_path = filepath:find("^[^/\\]+://") and filepath or utils.join_path(workingDirectory, filepath)
    exact_path = fix_path(exact_path, false)
    current_file.directory, current_file.name = utils.split_path(exact_path)
end

--loads the root list
local function goto_root()
    if root == nil then setup_root() end
    msg.verbose('loading root')
    list.selected = 1
    list.list = root

    --if moving to root from one of the connected locations,
    --then select that location
    list.directory = ""
    select_prev_directory()

    list.parser = ""
    list.prev_directory = ""
    cache:clear()
    list.selection = {}
    disable_select_mode()
    list:update()
end

--scans the current directory and updates the directory table
local function scan_directory(directory)
    msg.verbose("scanning files in " .. directory)
    local new_list = {}
    local list1 = utils.readdir(directory, 'dirs')

    --if we can't access the filesystem for the specified directory then we go to root page
    --this is cuased by either:
    --  a network file being streamed
    --  the user navigating above / on linux or the current drive root on windows
    if list1 == nil then return nil end

    --sorts folders and formats them into the list of directories
    for i=1, #list1 do
        local item = list1[i]

        --filters hidden dot directories for linux
        if not (o.filter_dot_dirs and item:sub(1,1) == ".") then
            msg.debug(item..'/')
            table.insert(new_list, {name = item..'/', ass = list.ass_escape(item..'/'), type = 'dir'})
        end
    end

    --appends files to the list of directory items
    local list2 = utils.readdir(directory, 'files')
    for i=1, #list2 do
        local item = list2[i]

        --only adds whitelisted files to the browser
        if  not ( o.filter_files and not extensions[ get_extension(item) ] )
            and not (o.filter_dot_files and item:sub(1,1) == ".")
        then
            msg.debug(item)
            table.insert(new_list, {name = item, ass = list.ass_escape(item), type = 'file'})
        end
    end
    sort(new_list)
    return new_list
end

--sends update requests to the different parsers
local function update_list()
    msg.verbose('loading contents of ' .. list.directory)

    list.selected = 1
    list.selection = {}
    if extensions == nil then setup_extensions_list() end
    if list.directory == "" then return goto_root() end

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if #cache > 0 and cache.stack[#cache].directory == list.directory then
        msg.verbose('found directory in cache')
        cache:apply()

        list.prev_directory = list.directory
        list:update()
        return
    end

    list.parser = choose_parser(list.directory)

    if list.parser ~= "file" then
        mp.commandv("script-message", list.parser.."/browse-dir", list.directory, "callback/browse-dir")
    else
        list.list = scan_directory(list.directory)
        if not list.list then goto_root() end
        select_prev_directory()

        --saves previous directory information
        list.prev_directory = list.directory
        list:update()
    end
end

--rescans the folder and updates the list
local function update()
    list.empty_text = "~"
    list.list = {}
    list.directory_label = nil
    disable_select_mode()
    list:update()
    list.empty_text = "empty directory"
    update_list()
end

--switches to the directory of the currently playing file
local function goto_current_dir()
    --splits the directory and filename apart
    list.directory = current_file.directory
    cache:clear()
    list.selected = 1
    update()
end

--moves up a directory
local function up_dir()
    local dir = list.directory:reverse()
    local index = dir:find("[/\\]")

    while index == 1 do
        dir = dir:sub(2)
        index = dir:find("[/\\]")
    end

    if index == nil then list.directory = ""
    else list.directory = dir:sub(index):reverse() end

    update()
    cache:pop()
end

--moves down a directory
local function down_dir()
    if not list.list[list.selected] or list.list[list.selected].type ~= 'dir' then return end

    cache:push()
    list.directory = list.directory..list.list[list.selected].name
    update()
end

--calculates what drag behaviour is required for that specific movement
local function drag_select(direction)
    local setting = list.selection[list.multiselect]
    local below = (list.multiselect - list.selected) < 1

    if list.selected ~= list.multiselect and below == (direction == 1) then
        list.selection[list.selected] = setting
    elseif setting then
        list.selection[list.selected - direction] = nil
    end
    list:update()
end

--wrapper for list:scroll_down() which runs the multiselect drag behaviour when required
local function scroll_down()
    list:scroll_down()
    if list.multiselect then drag_select(1) end
end

--wrapper for list:scroll_up() which runs the multiselect drag behaviour when required
local function scroll_up()
    list:scroll_up()
    if list.multiselect then drag_select(-1) end
end

--toggles the selection
local function toggle_selection()
    if list.list[list.selected] then
        list.selection[list.selected] = not list.selection[list.selected] or nil
    end
    list:update()
end

--toggles select mode
local function toggle_select_mode()
    if list.multiselect == nil then
        list.multiselect = list.selected
        list.cursor_style = o.ass_multiselect
        toggle_selection()
    else
        disable_select_mode()
        list:update()
    end
end

--sortes a table into an array of its key values
local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    table.sort(keys)
    return keys
end

--an object for custom directory loading and parsing
--this is written specifically for handling asynchronous playback from add-ons
--I've bundled this into an object to make it clearer how everything works together
local directory_parser = {
    stack = {},
    parser = "file",
    flags = "",
    queue = {},

    --continue with the next directory in the queue/stack
    continue = function(self)
        if self.stack[1] then return self:open_directory()
        elseif self.queue[1] then
            local front = self.queue[1]
            self:setup_parse(front.directory, front.parser, front.flags)
            table.remove(self.queue, 1)
            return self:open_directory()
        end
    end,

    --queue an item to be opened
    queue_directory = function(self, item, flags)
        local dir = list.directory..item.name

        table.insert(self.queue, {
            directory = dir,
            parser = item.parser or list.parser,
            flags = flags
        })
        msg.trace("queuing " .. dir .. " for opening")
    end,

    --setup the variables to start opening from a specific directory
    setup_parse = function(self, directory, parser, flags)
        self.stack[1] = {
            pos = 0,
            directory = directory,
            files = nil
        }
        self.flags = flags
        self.parser = parser
    end,

    --parse the response from an add-on
    callback = function(self, response)
        local top = self.stack[#self.stack]
        response = utils.parse_json(response)
        local files = response.list

        if not files then
            msg.warn("could not open "..top.directory)
            self.stack[#self.stack] = nil
            return self:continue()
        end

        if response.filter ~= false and (o.filter_files or o.filter_dot_dirs or o.filter_dot_files) then
            filter(list.list)
        end
        if response.sort ~= false then sort(list.list) end
        top.files = files
        return self:open_directory()
    end,

    --scan for files in the specific directory
    scan_files = function(self)
        local top = self.stack[#self.stack]
        local parser = self.parser
        local directory = top.directory
        msg.debug("parsing files in '"..directory.."'")

        if parser ~= "file" then
            mp.commandv("script-message", parser.."/browse-dir", directory, "callback/custom-loadlist")
        else
            top.files = scan_directory(directory)
            return self:open_directory()
        end
    end,

    --open the files in a directory
    open_directory = function(self)
        local top = self.stack[#self.stack]
        local files = top.files
        local directory = top.directory
        msg.verbose("opening " .. directory)

        if not files then return self:scan_files()
        else msg.debug("loading '"..directory.."' into playlist") end

        --the position to iterate from is saved in case an asynchronous request needs to
        --be made to open a folder part way through
        for i = top.pos+1, #files do
            if not sub_extensions[ get_extension(files[i].name) ] then
                if files[i].type == "file" then
                    mp.commandv("loadfile", get_full_path(files[i], directory), self.flags)
                    self.flags = "append"
                else
                    top.pos = i
                    table.insert(self.stack, { pos = 0, directory = get_full_path(files[i], directory), files = nil})
                    return self:scan_files()
                end
            end
        end

        self.stack[#self.stack] = nil
        return self:continue()
    end
}

--filters and sorts the response from the addons
mp.register_script_message("callback/custom-loadlist", function(...) directory_parser:callback(...) end)

--loads lists or defers the command to add-ons
local function loadlist(item, flags)
    local parser = item.parser or list.parser
    if parser == "file" then
        mp.commandv('loadlist', get_full_path(item), flags == "append-play" and "append" or flags)
        if flags == "append-play" and mp.get_property_bool("core-idle") then mp.commandv("playlist-play-index", 0) end
    elseif parser ~= "" then
        mp.commandv("script-message", parser.."/open-dir", get_full_path(item), flags)
    end
end

--load playlist entries before and after the currently playing file
local function autoload_dir(path)
    local pos = 1
    local file_count = 0
    for _,item in ipairs(list.list) do
        if item.type == "file" then
            local p = get_full_path(item)
            if p == path then pos = file_count
            else mp.commandv("loadfile", p, "append") end
            file_count = file_count + 1
        end
    end
    mp.commandv("playlist-move", 0, pos+1)
end

--runs the loadfile or loadlist command
local function loadfile(item, flags, autoload)
    local path = get_full_path(item)
    if item.type == "dir" then 
        if o.custom_dir_loading then return directory_parser:queue_directory(item, flags)
        else return loadlist(item, flags) end
    end

    if sub_extensions[ get_extension(item.name) ] then mp.commandv("sub-add", path, flags == "replace" and "select" or "auto")
    else
        mp.commandv('loadfile', path, flags)
        if autoload then autoload_dir(path) end
    end
end

--opens the selelected file(s)
local function open_file(flags, autoload)
    if list.selected > #list.list or list.selected < 1 then return end
    if flags == 'replace' then list:close() end

    --handles multi-selection behaviour
    if next(list.selection) then
        local selection = sort_keys(list.selection)

        --the currently selected file will be loaded according to the flag
        --the remaining files will be appended
        loadfile(list.list[selection[1]], flags)

        for i=2, #selection do
            loadfile(list.list[selection[i]], "append")
        end

        --reset the selection after
        list.selection = {}
        disable_select_mode()
        list:update()

    elseif flags == 'replace' then
        loadfile(list.list[list.selected], flags, autoload ~= o.autoload)
        down_dir()
        list:close()
    else
        loadfile(list.list[list.selected], flags)
    end

    if o.custom_dir_loading then directory_parser:continue() end
end

--opens the browser
function list:open()
    self:add_keybinds()

    list.hidden = false
    if list.directory == nil then
        update_current_directory(nil, mp.get_property('path'))
        goto_current_dir()
        return
    end

    if list.flag_update then
        update_current_directory(nil, mp.get_property('path'))
    end
    list:open_list()
end

--run when the escape key is used
local function escape()
    --if multiple items are selection cancel the
    --selection instead of closing the browser
    if next(list.selection) or list.multiselect then
        list.selection = {}
        disable_select_mode()
        list:update()
        return
    end
    list:close()
end

--iterates through the command table and substitutes special
--character codes for the correct strings used for custom functions
local function format_command_table(t, index)
    local l = list.list
    local copy = {}
    for i = 1, #t do
        copy[i] = t[i]:gsub("%%.", {
            ["%%"] = "%",
            ["%f"] = l[index] and get_full_path(l[index]) or "",
            ["%F"] = string.format("%q", l[index] and get_full_path(l[index]) or ""),
            ["%n"] = l[index] and (l[index].label or l[index].name) or "",
            ["%N"] = string.format("%q", l[index] and (l[index].label or l[index].name) or ""),
            ["%p"] = list.directory or "",
            ["%P"] = string.format("%q", list.directory or ""),
            ["%d"] = (list.directory_label or list.directory):match("([^/]+)/$") or "",
            ["%D"] = string.format("%q", (list.directory_label or list.directory):match("([^/]+)/$") or "")
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
    if cmd.multiselect and next(list.selection) then
        local selection = sort_keys(list.selection)
        for i = 1, #selection do
            run_custom_command(cmd.command, selection[i])
        end
    else
        run_custom_command(cmd.command, list.selected)
    end
end

--dynamic keybinds to set while the browser is open
list.keybinds = {
    {'ENTER', 'open', function() open_file('replace', false) end, {}},
    {'Shift+ENTER', 'open_append', function() open_file('append-play', false) end, {}},
    {'Alt+ENTER', 'open_autoload', function() open_file('replace', true) end, {}},
    {'ESC', 'close', escape, {}},
    {'RIGHT', 'down_dir', down_dir, {}},
    {'LEFT', 'up_dir', up_dir, {}},
    {'DOWN', 'scroll_down', scroll_down, {repeatable = true}},
    {'UP', 'scroll_up', scroll_up, {repeatable = true}},
    {'HOME', 'goto_current', goto_current_dir, {}},
    {'Shift+HOME', 'goto_root', goto_root, {}},
    {'Ctrl+r', 'reload', function() cache:clear(); update() end, {}},
    {'s', 'select_mode', toggle_select_mode, {}},
    {'S', 'select', toggle_selection, {}}
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
    if not device or device == "" then device = "/dev/dvd/" end
    list.dvd_device = fix_path(device, true)
end)

--declares the keybind to open the browser
mp.add_key_binding('MENU','browse-files', function() list:toggle() end)

--allows keybinds/other scripts to auto-open specific directories
mp.register_script_message('browse-directory', function(directory)
    if directory ~= "" then directory = fix_path(directory, true) end
    msg.verbose('recieved directory from script message: '..directory)

    list.directory = directory
    cache:clear()
    update()
    list:open()
end)

--a callback function for addon scripts to return the results of their filesystem processing
mp.register_script_message('callback/browse-dir', function(response)
    msg.trace("callback response = "..response)
    response = utils.parse_json(response)
    local items = response.list
    if not items then goto_root(); return end
    list.list = items

    if response.filter ~= false and (o.filter_files or o.filter_dot_dirs or o.filter_dot_files) then
        filter(list.list)
    end

    if response.sort ~= false then sort(list.list) end
    if response.ass_escape ~= false then escape_ass(list.list) end

    --changes the display name of the directory
    list.directory_label = response.directory_label

    --changes the text displayed when the directory is empty
    if response.empty_text then list.empty_text = response.empty_text end

    --setting up the previous directory stuff
    select_prev_directory()
    list.prev_directory = list.directory
    list:update()
end)
