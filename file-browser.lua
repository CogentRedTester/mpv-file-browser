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

    --number of entries to show on the screen at once
    num_entries = 18,

    --only show files compatible with mpv
    filter_files = true,

    --blacklist compatible files, it's recommended to use this rather than to edit the
    --compatible list directly. A semicolon separated list of extensions without spaces
    extension_blacklist = "",

    --add extra file extensions
    extension_whitelist = "",

    --full list of compatible file extensions
    compatible_files = "264;265;3g2;3ga;3ga2;3gp;3gp2;3gpp;3iv;a52;aac;adt;adts;aif;aifc;aiff;amr;ape;asf;au;avc;avi;awb;ay;bmp;cue;divx;dts;dtshd;dts-hd;dv;dvr;dvr-ms;eac3;evo;evob;f4a;flac;flc;fli;flic;flv;gbs;gif;gxf;gym;h264;h265;hdmov;hdv;hes;hevc;jpeg;jpg;kss;lpcm;m1a;m1v;m2a;m2t;m2ts;m2v;m3u;m3u8;m4a;m4v;mk3d;mka;mkv;mlp;mod;mov;mp1;mp2;mp2v;mp3;mp4;mp4v;mp4v;mpa;mpe;mpeg;mpeg2;mpeg4;mpg;mpg4;mpv;mpv2;mts;mtv;mxf;nsf;nsfe;nsv;nut;oga;ogg;ogm;ogv;ogx;opus;pcm;pls;png;qt;ra;ram;rm;rmvb;sap;svg;ahn;snd;spc;spx;thd;thd+ac3;tif;tiff;tod;trp;truehd;true-hd;ts;tsa;tsv;tta;tts;vfw;vgm;vgz;vob;vro;wav;weba;webm;webp;wm;wma;wmv;wtv;wv;x264;x265;xvid;y4m;yuv",

    --filter dot directories like .config
    --only usefu on linux systems
    filter_dot_dirs = false,

    --ass tags
    ass_header = "{\\q2\\fs35\\c&00ccff&}",
    ass_body = "{\\q2\\fs25\\c&Hffffff&}",
    ass_selected = "{\\c&Hfce788&}",
    ass_multiselect = "{\\c&Hfcad88&}",
    ass_playing = "{\\c&H33ff66&}",
    ass_footerheader = "{\\c&00ccff&\\fs16}",
    ass_cursor = "{\\c&00ccff&}"
}

opt.read_options(o, 'file_browser')

local ov = mp.create_osd_overlay('ass-events')
local list = {}
local cache = {}
local extensions = nil
local state = {
    hidden = true,
    flag_update = false,
    directory = nil,
    selected = 1,
    selection = {},
    prev_directory = nil,
    current_file = {
        directory = nil,
        name = nil
    }
}
local root = nil
local keybinds = {
    {'ENTER', 'open', function() open_file('replace') end, {}},
    {'Shift+ENTER', 'append_playlist', function() open_file('append') end, {}},
    {'ESC', 'exit', function() close_browser() end, {}},
    {'RIGHT', 'down_dir', function() down_dir() end, {}},
    {'LEFT', 'up_dir', function() up_dir() end, {}},
    {'DOWN', 'scroll_down', function() scroll_down() end, {repeatable = true}},
    {'UP', 'scroll_up', function() scroll_up() end, {repeatable = true}},
    {'HOME', 'pwd', function() cache = {}; goto_current_dir() end, {}},
    {'Shift+HOME', 'root', function() goto_root() end, {}},
    {'Ctrl+r', 'reload', function() cache={}; update() end, {}},
    {'Ctrl+ENTER', 'select', function() toggle_selection() end, {}},
    {'Ctrl+DOWN', 'select_down', function() drag_down() end, {repeatable = true}},
    {'Ctrl+UP', 'select_up', function() drag_up() end, {repeatable = true}},
    {'Ctrl+RIGHT', 'select_yes', function() state.selection[state.selected] = true ; update_ass() end, {}},
    {'Ctrl+LEFT', 'select_no', function() state.selection[state.selected] = nil ; update_ass() end, {}}
}

--sets up the compatible extensions list
local function setup_extensions_list()
    extensions = {}
    if not o.filter_files then return end

    local blacklist = {}

    --creating the blacklist
    for str in string.gmatch(o.extension_blacklist, "([^;]+)") do
        blacklist[str] = true
    end

    --adding file extensions not on the blacklist
    for str in string.gmatch(o.compatible_files, "([^;]+)") do
        if not blacklist[str] then
            extensions[str] = true
        end
    end

    --adding extra extensions on the whitelist
    for str in string.gmatch(o.extension_whitelist, "([^;]+)") do
        extensions[str] = true
    end
end

local function sort(t)
    table.sort(t, function(a,b) return a:lower() < b:lower() end)
end

--splits the string into a table on the semicolons
local function setup_root()
    root = {}
    for str in string.gmatch(o.root, "([^;]+)") do
        local path = mp.command_native({'expand-path', str})
        path = path:gsub([[\]], [[/]])
        local last_char = path:sub(-1)
        if last_char ~= '/' then path = path..'/' end

        root[#root+1] = {name = path, type = 'dir', label = str}
    end
end

function update_current_directory(_, filepath)
    --if we're in idle mode then we want to open to the root
    if filepath == nil then 
        state.current_file.directory = ""
        return
    end

    local workingDirectory = mp.get_property('working-directory', '')
    local exact_path = utils.join_path(workingDirectory, filepath)
    exact_path = exact_path:gsub([[\]],[[/]])
    exact_path = exact_path:gsub([[/./]], [[/]])
    state.current_file.directory, state.current_file.name = utils.split_path(exact_path)
end

function goto_current_dir()
    --splits the directory and filename apart
    state.directory = state.current_file.directory
    state.selected = 1
    update()
end

function goto_root()
    if root == nil then setup_root() end
    msg.verbose('loading root')
    state.selected = 1
    list = root

    --if moving to root from one of the connected locations,
    --then select that location
    for i,item in ipairs(list) do
        if (state.prev_directory == item.name) then
            state.selected = i
            break
        end
    end
    state.prev_directory = ""
    state.directory = ""
    cache = {}
    state.selection = {}
    update_ass()
end

--prints the persistent header
function print_ass_header()
    local dir_name = state.directory
    if dir_name == "" then dir_name = "ROOT" end
    ov.data = o.ass_header..dir_name..'\\N ---------------------------------------------------- \\N'
end

--loops through the directory table and creates the ass string to generate the browser page
function update_ass()
    print_ass_header()
    --check for an empty directory
    if #list == 0 then
        ov.data = ov.data.."empty directory"
        ov:update()
        return
    end

    ov.data = ov.data..o.ass_body
    local start = 1
    local finish = start+o.num_entries

    --handling cursor positioning
    local mid = math.ceil(o.num_entries/2)+1
    if state.selected+mid > finish then
        local offset = state.selected - finish + mid

        --if we've overshot the end of the list then undo some of the offset
        if finish + offset > #list then
            offset = offset - ((finish+offset) - #list)
        end

        start = start + offset
        finish = finish + offset
    end

    --making sure that we don't overstep the boundaries
    if start < 1 then start = 1 end
    local overflow = finish < #list
    --this is necessary when the number of items in the dir is less than the max
    if not overflow then finish = #list end

    --adding a header to show there are items above in the list
    if start > 1 then ov.data = ov.data..o.ass_footerheader..(start-1)..' items above\\N\\N' end

    local current_dir = state.directory == state.current_file.directory

    for i=start,finish do
        local v = list[i]
        local playing_file = current_dir and v.name == state.current_file.name
        ov.data = ov.data..o.ass_body

        --handles custom styles for different entries
        --the below text contains unicode whitespace characters
        if i == state.selected then ov.data = ov.data..o.ass_cursor..[[➤  ]]..o.ass_body
        else ov.data = ov.data..[[   ]] end

        --prints the currently-playing icon and style
        if playing_file then ov.data = ov.data..o.ass_playing..[[▶ ]] end

        --sets the selection colour scheme
        if state.selection[i] then ov.data = ov.data..o.ass_multiselect
        elseif i == state.selected then ov.data = ov.data..o.ass_selected end

        --sets the folder icon
        if v.type == 'dir' then ov.data = ov.data..[[🖿 ]] end

        --adds the actual name of the item
        if state.directory == "" then ov.data = ov.data..v.label.."\\N"
        else ov.data = ov.data..v.name.."\\N" end
    end

    if overflow then ov.data = ov.data..'\\N'..o.ass_footerheader..#list-finish..' items remaining' end
    ov:update()
end

--scans the current directory and updates the directory table
function update_list()
    msg.verbose('loading contents of ' .. state.directory)
    state.selected = 1
    state.selection = {}

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if #cache > 0 then
        local cache = cache[#cache]
        if cache.directory == state.directory then
            msg.verbose('found directory in cache')
            list = cache.table

            --sets the cursor to the previously opened file and resets the prev_directory in
            --case we move above the cache source
            state.selected = cache.cursor
            state.prev_directory = state.directory
            return
        end
    end

    local t = mp.get_time()
    list = {}
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
    sort(list1)
    for i=1, #list1 do
        local item = list1[i]
        if (state.prev_directory == state.directory..item..'/') then state.selected = i end

        --filters hidden dot directories for linux
        if o.filter_dot_dirs and item:find('%.') == 1 then goto continue end

        msg.debug(item..'/')
        list[#list+1] = {name = item..'/', type = 'dir'}

        ::continue::
    end

    --appends files to the list of directory items
    local list2 = utils.readdir(state.directory, 'files')
    sort(list2)
    for i=1, #list2 do
        local item = list2[i]

        --only adds whitelisted files to the browser
        if o.filter_files then
            local index = item:find([[.[^.]*$]])
            if not index then goto continue end
            local fileext = item:sub(index + 1)
            if not extensions[fileext] then goto continue end
        end

        msg.debug(item)
        list[#list+1] = {name = item, type = 'file'}

        ::continue::
    end
    msg.debug('load time: ' ..mp.get_time() - t)

    --saves the latest directory at the top of the stack
    cache[#cache+1] = {directory = state.directory, table = list}

    --once the directory has been successfully loaded we set it as the 'prev' directory for next time
    --this is for highlighting the previous folder when moving up a directory
    state.prev_directory = state.directory
end

function update()
    print_ass_header()
    ov:update()
    update_list()
    update_ass()
end

function scroll_down()
    if state.selected < #list then
        state.selected = state.selected + 1
        update_ass()
    end
end

function scroll_up()
    if state.selected > 1 then
        state.selected = state.selected - 1
        update_ass()
    end
end

function up_dir()
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

function down_dir()
    if not list[state.selected] or list[state.selected].type ~= 'dir' then return end

    state.directory = state.directory..list[state.selected].name
    if #cache > 0 then cache[#cache].cursor = state.selected end
    update()
end

function toggle_selection()
    if list[state.selected] then
        if state.selection[state.selected] then
            state.selection[state.selected] = nil
        else
            state.selection[state.selected] = true
        end
    end
    update_ass()
end

function drag_down()
    state.selection[state.selected] = true
    scroll_down()
    state.selection[state.selected] = true
    update_ass()
end

function drag_up()
    state.selection[state.selected] = true
    scroll_up()
    state.selection[state.selected] = true
    update_ass()
end

function open_browser()
    for _,v in ipairs(keybinds) do
        mp.add_forced_key_binding(v[1], 'dynamic/'..v[2], v[3], v[4])
    end

    if extensions == nil then setup_extensions_list() end
    if state.directory == nil then
        update_current_directory(nil, mp.get_property('path'))
        goto_current_dir()
    end

    state.hidden = false
    if state.flag_update then
        update_current_directory(nil, mp.get_property('path'))
        update_ass()
    else ov:update() end
end

--sortes a table into an array of its key values
local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    table.sort(keys)
    return keys
end

function close_browser()
    --if multiple items are selection cancel the
    --selection instead of closing the browser
    if next(state.selection) then
        state.selection = {}
        update_ass()
        return
    end

    for _,v in ipairs(keybinds) do
        mp.remove_key_binding('dynamic/'..v[2])
    end
    state.hidden = true
    ov:remove()
end

function open_file(flags)
    if state.selected > #list or state.selected < 1 then return end

    mp.commandv('loadfile', state.directory..list[state.selected].name, flags)
    state.selection[state.selected] = nil

    --handles multi-selection behaviour
    if next(state.selection) then
        local selection = sort_keys(state.selection)

        --the currently selected file will be loaded according to the flag
        --the remaining files will be appended
        for i=1, #selection do
            mp.commandv('loadfile', state.directory..list[selection[i]].name, 'append')
        end

        --reset the selection after
        state.selection = {}
        if flags == 'replace' then close_browser()
        else update_ass() end
        return

    elseif flags == 'replace' then
        down_dir()
        close_browser()
    end
end

function toggle_browser()
    if state.hidden then
        open_browser()
    else
        close_browser()
    end
end

--we don't want to add any overhead when the browser isn't open
mp.observe_property('path', 'string', function(_,path)
    if not state.hidden then 
        update_current_directory(_,path)
        update_ass()
    else state.flag_update = true end
end)
mp.add_key_binding('MENU','browse-files', toggle_browser)
