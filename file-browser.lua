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

    --when opening the browser in idle mode prefer the current working directory over the root
    --note that the working directory is set as the 'current' directory regardless, so `home` will
    --move the browser there even if this option is set to false
    default_to_working_directory = false,

    --allows custom icons be set to fix incompatabilities with some fonts
    --the `\h` character is a hard space to add padding between the symbol and the text
    folder_icon = "🖿",
    cursor_icon = "➤",
    indent_icon = [[\h\h\h]],

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
local ass = mp.create_osd_overlay("ass-events")

local state = {
    list = {},
    selected = 1,
    hidden = true,
    flag_update = false,
    cursor_style = o.ass_cursor,

    directory = nil,
    directory_label = nil,
    prev_directory = "",
    parser = "file",

    multiselect_start = nil,
    selection = {}
}

local extensions = nil
local sub_extensions = {}

local dvd_device = nil
local current_file = {
    directory = nil,
    name = nil
}

local root = nil

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

--------------------------------------------------------------------------------------------------------
--------------------------------------Cache Implementation----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--metatable of methods to manage the cache 
local __cache = {
    push = function(self)
        table.insert(self, {
            directory = state.directory,
            directory_label = state.directory_label,
            list = state.list,
            parser = state.parser,
            selected = state.selected
        })
    end,

    pop = function(self) table.remove(self) end,

    apply = function(self)
        for key, value in pairs(self[#self]) do
            state[key] = value
        end
    end,

    clear = function(self)
        for i = 1, #self do
            self[i] = nil
        end
    end
}

local cache = setmetatable({}, { __index = __cache })



--------------------------------------------------------------------------------------------------------
-----------------------------------------Utility Functions----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--chooses which parser to use for the specific path
local function choose_parser(path)
    if o.dvd_browser and path == dvd_device then return "dvd"
    elseif o.http_browser and path:find("https?://") == 1 then return "http"
    elseif o.ftp_browser and path:sub(1, 6) == "ftp://" then return "ftp"
    else return "file" end
end

--get the full path for the current file
local function get_full_path(item, dir)
    if item.path then return item.path end
    return (dir or state.directory)..item.name
end

--formats strings for ass handling
--this function is taken from https://github.com/mpv-player/mpv/blob/master/player/lua/console.lua#L110
local function ass_escape(str)
    str = str:gsub('\\', '\\\239\187\191')
    str = str:gsub('{', '\\{')
    str = str:gsub('}', '\\}')
    -- Precede newlines with a ZWNBSP to prevent ASS's weird collapsing of
    -- consecutive newlines
    str = str:gsub('\n', '\239\187\191\\N')
    -- Turn leading spaces into hard spaces to prevent ASS from stripping them
    str = str:gsub('\\N ', '\\N\\h')
    str = str:gsub('^ ', '\\h')
    return str
end

--appends the entered text to the overlay
local function append(text)
        if text == nil then return end
        ass.data = ass.data .. text
    end

--appends a newline character to the osd
local function newline()
    ass.data = ass.data .. '\\N'
end

--detects whether or not to highlight the given entry as being played
local function highlight_entry(v)
    if current_file.name == nil then return false end
    if v.type == "dir" then
        return current_file.directory:find(get_full_path(v), 1, true)
    else
        return current_file.directory == state.directory and current_file.name == v.name
    end
end

--standardises filepaths across systems
local function fix_path(str, is_directory)
    str = str:gsub([[\]],[[/]])
    str = str:gsub([[/./]], [[/]])
    if is_directory and str:sub(-1) ~= '/' then str = str..'/' end
    return str
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

        if  ( temp.type == "dir"    and not ( o.filter_dot_dirs and temp.name:sub(1,1) == ".") ) or
            ( temp.type == "file"   and not ( o.filter_dot_files and (temp.name:sub(1,1) == ".") )
                                    and not ( o.filter_files and not extensions[ get_extension(temp.name) ] ) )
        then
            t[top] = temp
            top = top+1
        end
    end
end

--sorts a table into an array of selected items in the correct order
local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        local item = state.list[k]
        item.index = k
        keys[#keys+1] = item
    end

    table.sort(keys, function(a,b) return a.index < b.index end)
    return keys
end



--------------------------------------------------------------------------------------------------------
-----------------------------------------Setup Functions------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

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

--splits the string into a table on the semicolons
local function setup_root()
    root = {}
    for str in string.gmatch(o.root, "([^"..o.root_seperators.."]+)") do
        local path = mp.command_native({'expand-path', str})
        path = fix_path(path, true)

        local temp = {name = path, type = 'dir', label = str, ass = ass_escape(str), parser = choose_parser(path)}

        root[#root+1] = temp
    end
end



--------------------------------------------------------------------------------------------------------
-----------------------------------------List Formatting------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--scans the list for which item to select by default
--chooses the folder that the script just moved out of
--or, otherwise, the item highlighted as currently playing
local function select_prev_directory()
    if state.prev_directory:find(state.directory, 1, true) == 1 then
        local i = 1
        while (state.list[i] and state.list[i].type == "dir") do
            if state.prev_directory:find(get_full_path(state.list[i]), 1, true) then
                state.selected = i
                return
            end
            i = i+1
        end
    end

    if current_file.directory:find(state.directory, 1, true) == 1 then
        for i,item in ipairs(state.list) do
            if highlight_entry(item) then
                state.selected = i
                return
            end
        end
    end
end

local function disable_select_mode()
    state.cursor_style = o.ass_cursor
    state.multiselect_start = nil
end

--saves the directory and name of the currently playing file
local function update_current_directory(_, filepath)
    --if we're in idle mode then we want to open the working directory
    if filepath == nil then 
        current_file.directory = fix_path( mp.get_property("working-directory", ""), true)
        current_file.name = nil
        return
    elseif filepath:find("dvd://") == 1 then
        filepath = dvd_device..filepath:match("dvd://(.+)")
    end

    local workingDirectory = mp.get_property('working-directory', '')
    local exact_path = filepath:find("^[^/\\]+://") and filepath or utils.join_path(workingDirectory, filepath)
    exact_path = fix_path(exact_path, false)
    current_file.directory, current_file.name = utils.split_path(exact_path)
end

--refreshes the ass text using the contents of the list
local function update_ass()
    if state.hidden then state.flag_update = true ; return end

    ass.data = ""

    local dir_name = state.directory_label or state.directory
    if dir_name == "" then dir_name = "ROOT" end
    append(o.ass_header)
    append(ass_escape(dir_name)..'\\N ----------------------------------------------------')
    newline()

    if #state.list < 1 then
        append(state.empty_text)
        ass:update()
        return
    end

    local start = 1
    local finish = start+o.num_entries-1

    --handling cursor positioning
    local mid = math.ceil(o.num_entries/2)+1
    if state.selected+mid > finish then
        local offset = state.selected - finish + mid

        --if we've overshot the end of the list then undo some of the offset
        if finish + offset > #state.list then
            offset = offset - ((finish+offset) - #state.list)
        end

        start = start + offset
        finish = finish + offset
    end

    --making sure that we don't overstep the boundaries
    if start < 1 then start = 1 end
    local overflow = finish < #state.list
    --this is necessary when the number of items in the dir is less than the max
    if not overflow then finish = #state.list end

    --adding a header to show there are items above in the list
    if start > 1 then append(o.ass_footerheader..(start-1)..' item(s) above\\N\\N') end

    for i=start, finish do
        local v = state.list[i]
        local playing_file = highlight_entry(v)
        append(o.ass_body)

        --handles custom styles for different entries
        if i == state.selected then append(state.cursor_style..o.cursor_icon.."\\h"..o.ass_body)
        else append(o.indent_icon.."\\h") end

        --sets the selection colour scheme
        local multiselected = state.selection[i]
        if multiselected then append(o.ass_multiselect)
        elseif i == state.selected then append(o.ass_selected) end

        --prints the currently-playing icon and style
        if playing_file and multiselected then append(o.ass_playingselected)
        elseif playing_file then append(o.ass_playing) end

        --sets the folder icon
        if v.type == 'dir' then append(o.folder_icon.."\\h") end

        --adds the actual name of the item
        append(v.ass or v.label or v.name)
        newline()
    end

    if overflow then append('\\N'..o.ass_footerheader..#state.list-finish..' item(s) remaining') end
    ass:update()
end



--------------------------------------------------------------------------------------------------------
-----------------------------------------Directory Parsing----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--loads the root list
local function goto_root()
    if root == nil then setup_root() end
    msg.verbose('loading root')
    state.selected = 1
    state.list = root

    --if moving to root from one of the connected locations,
    --then select that location
    state.directory = ""
    select_prev_directory()

    state.parser = ""
    state.prev_directory = ""
    cache:clear()
    state.selection = {}
    disable_select_mode()
    update_ass()
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
            table.insert(new_list, {name = item..'/', ass = ass_escape(item..'/'), type = 'dir'})
        end
    end

    --appends files to the list of directory items
    local list2 = utils.readdir(directory, 'files')
    for i=1, #list2 do
        local item = list2[i]

        --only adds whitelisted files to the browser
        if  not ( o.filter_files and not extensions[ get_extension(item) ] ) and
            not (o.filter_dot_files and item:sub(1,1) == ".")
        then
            msg.debug(item)
            table.insert(new_list, {name = item, ass = ass_escape(item), type = 'file'})
        end
    end
    sort(new_list)
    return new_list
end

--sends update requests to the different parsers
local function update_list()
    msg.verbose('loading contents of ' .. state.directory)

    state.selected = 1
    state.selection = {}
    if extensions == nil then setup_extensions_list() end
    if state.directory == "" then return goto_root() end

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if #cache > 0 and cache[#cache].directory == state.directory then
        msg.verbose('found directory in cache')
        cache:apply()
        state.prev_directory = state.directory
        update_ass()
        return
    end

    state.parser = choose_parser(state.directory)

    if state.parser ~= "file" then
        mp.commandv("script-message", state.parser.."/browse-dir", state.directory, "callback/browse-dir")
    else
        state.list = scan_directory(state.directory)
        if not state.list then return goto_root() end
        select_prev_directory()

        --saves previous directory information
        state.prev_directory = state.directory
        update_ass()
    end
end

--rescans the folder and updates the list
local function update()
    state.empty_text = "~"
    state.list = {}
    state.directory_label = nil
    disable_select_mode()
    update_ass()
    state.empty_text = "empty directory"
    update_list()
end

--switches to the directory of the currently playing file
local function goto_current_dir()
    state.directory = current_file.directory
    cache:clear()
    state.selected = 1
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

    update()
    cache:pop()
end

--moves down a directory
local function down_dir()
    if not state.list[state.selected] or state.list[state.selected].type ~= 'dir' then return end

    cache:push()
    state.directory = state.directory..state.list[state.selected].name
    update()
end



--------------------------------------------------------------------------------------------------------
--------------------------------Scroll/Select Implementation--------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--calculates what drag behaviour is required for that specific movement
local function drag_select(direction)
    local setting = state.selection[state.multiselect_start]
    local below = (state.multiselect_start - state.selected) < 1

    if state.selected ~= state.multiselect_start and below == (direction == 1) then
        state.selection[state.selected] = setting
    elseif setting then
        state.selection[state.selected - direction] = nil
    end
    update_ass()
end

--moves the selector down the list
local function scroll_down()
    if state.selected < #state.list then
        state.selected = state.selected + 1
        update_ass()
    elseif state.wrap then
        state.selected = 1
        update_ass()
    end
    if state.multiselect_start then drag_select(1) end
end

--moves the selector up the list
local function scroll_up()
    if state.selected > 1 then
        state.selected = state.selected - 1
        update_ass()
    elseif state.wrap then
        state.selected = #state.list
        update_ass()
    end
    if state.multiselect_start then drag_select(-1) end
end

--toggles the selection
local function toggle_selection()
    if state.list[state.selected] then
        state.selection[state.selected] = not state.selection[state.selected] or nil
    end
    update_ass()
end

--select all items in the list
local function select_all()
    for i,_ in ipairs(state.list) do
        state.selection[i] = true
    end
    update_ass()
end

--toggles select mode
local function toggle_select_mode()
    if state.multiselect_start == nil then
        state.multiselect_start = state.selected
        state.cursor_style = o.ass_multiselect
        toggle_selection()
    else
        disable_select_mode()
        update_ass()
    end
end



------------------------------------------------------------------------------------------
---------------------------Custom Directory Loading---------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

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
        local dir = state.directory..item.name

        table.insert(self.queue, {
            directory = dir,
            parser = item.parser or state.parser,
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
            filter(files)
        end
        if response.sort ~= false then sort(files) end
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



------------------------------------------------------------------------------------------
---------------------------------File/Playlist Opening------------------------------------
------------------------------------Browser Controls--------------------------------------
------------------------------------------------------------------------------------------

--loads lists or defers the command to add-ons
local function loadlist(item, flags)
    local parser = item.parser or state.parser
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
    for _,item in ipairs(state.list) do
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

--opens the browser
local function open()
    for _,v in ipairs(state.keybinds) do
        mp.add_forced_key_binding(v[1], '__file-browser/'..v[2], v[3], v[4])
    end

    state.hidden = false
    if state.directory == nil then
        local path = mp.get_property('path')
        update_current_directory(nil, path)
        if path or o.default_to_working_directory then goto_current_dir() else goto_root() end
        return
    end

    if state.flag_update then update_current_directory(nil, mp.get_property('path')) end
    state.hidden = false
    if not state.flag_update then ass:update()
    else state.flag_update = false ; update_ass() end
end

--closes the list and sets the hidden flag
local function close()
    for _,v in ipairs(state.keybinds) do
        mp.remove_key_binding('__file-browser/'..v[2])
    end

    state.hidden = true
    ass:remove()
end

--toggles the list
local function toggle()
    if state.hidden then open()
    else close() end
end

--run when the escape key is used
local function escape()
    --if multiple items are selection cancel the
    --selection instead of closing the browser
    if next(state.selection) or state.multiselect_start then
        state.selection = {}
        disable_select_mode()
        update_ass()
        return
    end
    close()
end

--opens the selelected file(s)
local function open_file(flags, autoload)
    if not state.list[state.selected] then return end
    if flags == 'replace' then close() end

    --handles multi-selection behaviour
    if next(state.selection) then
        local selection = sort_keys(state.selection)

        --the currently selected file will be loaded according to the flag
        --the remaining files will be appended
        loadfile(selection[1], flags)

        for i=2, #selection do
            loadfile(selection[i], "append")
        end

        --reset the selection after
        state.selection = {}
        disable_select_mode()
        update_ass()

    elseif flags == 'replace' then
        loadfile(state.list[state.selected], flags, autoload ~= o.autoload)
        down_dir()
        close()
    else
        loadfile(state.list[state.selected], flags)
    end

    if o.custom_dir_loading then directory_parser:continue() end
end



------------------------------------------------------------------------------------------
----------------------------------Keybind Implementation----------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

--format the item string for either single or multiple items
local function create_item_string(cmd, items, funct)
    if not items[1] then return funct(items) end

    local str = funct(items[1])
    for i = 2, #items do
        str = str .. ( cmd["append-string"] or " " ) .. funct(items[i])
    end
    return str
end

--iterates through the command table and substitutes special
--character codes for the correct strings used for custom functions
local function format_command_table(t, cmd, items)
    local copy = {}
    for i = 1, #t do
        copy[i] = t[i]:gsub("%%.", {
            ["%%"] = "%",
            ["%f"] = create_item_string(cmd, items, function(item) return item and get_full_path(item, cmd.directory) or "" end),
            ["%F"] = create_item_string(cmd, items, function(item) return string.format("%q", item and get_full_path(item, cmd.directory) or "") end),
            ["%n"] = create_item_string(cmd, items, function(item) return item and (item.label or item.name) or "" end),
            ["%N"] = create_item_string(cmd, items, function(item) return string.format("%q", item and (item.label or item.name) or "") end),
            ["%p"] = cmd.directory or "",
            ["%P"] = string.format("%q", cmd.directory or ""),
            ["%d"] = (cmd.directory_label or cmd.directory):match("([^/]+)/$") or "",
            ["%D"] = string.format("%q", (cmd.directory_label or cmd.directory):match("([^/]+)/$") or "")
        })
    end
    return copy
end

--runs all of the commands in the command table
--recurses to handle nested tables of commands
local function run_custom_command(t, cmd, item)
    if type(t[1]) == "table" then
        for i = 1, #t do
            run_custom_command(t[i], cmd, item)
        end
    else
        local custom_cmd = format_command_table(t, cmd, item)
        msg.debug("running command: " .. utils.to_string(custom_cmd))
        mp.command_native(custom_cmd)
    end
end

--runs commands for multiple selected items
local function recursive_multi_command(cmd, i, length)
    if i > length then return end

    --filtering commands
    if cmd.filter and cmd.selection[i].type ~= cmd.filter then
        msg.verbose("skipping command for selection ")
    else
        run_custom_command(cmd.command, cmd, cmd.selection[i])
    end

    --delay running the next command if the delay option is set
    if not cmd.delay then return recursive_multi_command(cmd, i+1, length)
    else mp.add_timeout(cmd.delay, function() recursive_multi_command(cmd, i+1, length) end) end
end

--runs one of the custom commands
local function custom_command(cmd)
        cmd.directory = state.directory
        cmd.directory_label = state.directory_label

    --runs the command on all multi-selected items
    if cmd.multiselect and next(state.selection) then
        cmd.selection = sort_keys(state.selection)

        if not cmd["multi-type"] or cmd["multi-type"] == "repeat" then
            recursive_multi_command(cmd, 1, #cmd.selection)
        elseif cmd["multi-type"] == "append" then
            run_custom_command(cmd.command, cmd, cmd.selection)
        end
    else
        --filtering commands
        if cmd.filter and state.list[state.selected] and state.list[state.selected].type ~= cmd.filter then
            return msg.verbose("cancelling custom command") end
        run_custom_command(cmd.command, cmd, state.list[state.selected])
    end
end

--dynamic keybinds to set while the browser is open
state.keybinds = {
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
    {'S', 'select', toggle_selection, {}},
    {'Ctrl+a', 'select_all', select_all, {}}
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
            table.insert(state.keybinds, { json[i].key, "custom"..tostring(i), function() custom_command(json[i]) end, {} })
        end
    end
end



------------------------------------------------------------------------------------------
--------------------------------mpv API Callbacks-----------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

--we don't want to add any overhead when the browser isn't open
mp.observe_property('path', 'string', function(_,path)
    if not state.hidden then 
        update_current_directory(_,path)
        update_ass()
    else state.flag_update = true end
end)

--updates the dvd_device
mp.observe_property('dvd-device', 'string', function(_, device)
    if not device or device == "" then device = "/dev/dvd/" end
    dvd_device = fix_path(device, true)
end)

--declares the keybind to open the browser
mp.add_key_binding('MENU','browse-files', toggle)

--opens a specific directory
local function browse_directory(directory)
    if not directory then return end
    directory = mp.command_native({"expand-path", directory}, "")
    if directory ~= "" then directory = fix_path(directory, true) end
    msg.verbose('recieved directory from script message: '..directory)

    state.directory = directory
    cache:clear()
    open()
    update()
end

--allows keybinds/other scripts to auto-open specific directories
mp.register_script_message('browse-directory', browse_directory)

--a callback function for addon scripts to return the results of their filesystem processing
mp.register_script_message('callback/browse-dir', function(response)
    msg.trace("callback response = "..response)
    response = utils.parse_json(response)
    local items = response.list
    if not items then goto_root(); return end

    if response.filter ~= false and (o.filter_files or o.filter_dot_dirs or o.filter_dot_files) then
        filter(items)
    end

    if response.sort ~= false then sort(items) end
    if response.ass_escape ~= false then
        for i = 1, #items do
            items[i].ass = items[i].ass or ass_escape(items[i].label or items[i].name)
        end
    end

    state.list = items
    state.directory_label = response.directory_label

    --changes the text displayed when the directory is empty
    if response.empty_text then state.empty_text = response.empty_text end

    --setting up the previous directory stuff
    select_prev_directory()
    state.prev_directory = state.directory
    update_ass()
end)



------------------------------------------------------------------------------------------
----------------------------mpv-user-input Compatability----------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local counter = 1
local function get_user_input(funct, options)
    local name = mp.get_script_name()
    options = options or {}
    options.id = name .. '/' .. (options.id or "")
    options.text = options.text or (name.." is requesting user input:")

    local response_string = name.."/__user_input_request/"..counter
    options.response = response_string

    options = utils.format_json(options)
    if not options then error("table cannot be converted to json string") ; return end

    -- create a callback for user-input to respond to
    counter = counter + 1
    mp.register_script_message(response_string, function(response)
        mp.unregister_script_message(response_string)
        response = utils.parse_json(response)
        funct(response.input, response.err)
    end)

    mp.commandv("script-message-to", "user_input", "request-user-input", options)
end

mp.add_key_binding("Alt+o", "browse-directory/get-user-input", function()
    get_user_input(browse_directory, {text = "open directory:"})
end)
