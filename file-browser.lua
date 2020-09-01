local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    --root directories
    root = "~/",

    --number of entries to show on the screen at once
    num_entries = 18,

    --ass tags
    ass_header = "{\\q2\\fs35\\c&00ccff&}",
    ass_body = "{\\q2\\fs25\\c&Hffffff&}",
    ass_selected = "{\\c&Hfce788&}",
    ass_playing = "{\\c&H33ff66&}",
    ass_footerheader = "{\\c&00ccff&\\b500\\fs16}"
}

opt.read_options(o, 'file_browser')

local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local list = {}
local cache = {}
local state = {
    directory = nil,
    selected = 1,
    multiple = false,
    root = false,
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
    {'HOME', 'pwd', function() goto_current_dir() end, {}},
    {'Shift+HOME', 'root', function() goto_root() end, {}}
}

--splits the string into a table on the semicolons
function setup_root()
    root = {}
    for str in string.gmatch(o.root, "([^;]+)") do
        path = mp.command_native({'expand-path', str})
        local last_char = path:sub(-1)
        if last_char ~= '\\' and last_char ~= '/' then path = path..'/' end

        root[#root+1] = {name = path, type = 'dir', label = str}
    end
end

function update_current_directory(_, filepath)
    local workingDirectory = mp.get_property('working-directory', '')
    if filepath == nil then filepath = "" end
    local exact_path = utils.join_path(workingDirectory, filepath)
    state.current_file.directory, state.current_file.name = utils.split_path(exact_path)
end

function goto_current_dir()
    --splits the directory and filename apart
    state.directory = state.current_file.directory
    state.selected = 1
    cache = {}
    update_list()
    update_ass()
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

    state.root = true
    state.directory = ""
    cache = {}
    update_ass()
end

function print_ass_header()
    ov.data = o.ass_header..state.directory..'\\N ---------------------------------------------------- \\N'
end

function update_ass()
    print_ass_header()
    ov.data = ov.data..o.ass_body

    --check for an empty directory
    if #list == 0 then
        ov.data = ov.data.."empty directory"
        ov:update()
        return
    end

    local start = 1
    local finish = start+o.num_entries
    local overflow = true

    --handling cursor positioning
    local mid = math.ceil(o.num_entries/2)
    if state.selected+mid > finish then
        local offset = state.selected - finish + mid

        --if we've overshot the end of the list then undo some of the offset
        if finish + offset > #list then
            offset = offset - ((finish+offset) - #list)
            overflow = false
        end

        start = start + offset
        finish = finish + offset
    else
        overflow = finish < #list
    end

    --making sure that we don't overstep the boundaries
    if start < 1 then start = 1 end
    if not overflow then finish = #list end

    --adding a header to show there are items above in the list
    if start > 1 then ov.data = ov.data..o.ass_footerheader..(start-1)..' items above\\N\\N' end

    local current_dir = state.directory == state.current_file.directory

    for i=start,finish do
        local v = list[i]
        local playing_file = current_dir and v.name == state.current_file.name
        ov.data = ov.data..o.ass_body
        if playing_file then ov.data = ov.data..o.ass_playing end
        if i == state.selected then ov.data = ov.data..o.ass_selected end

        if v.type == 'dir' then ov.data = ov.data..[[📁 ]] end

        if state.root then ov.data = ov.data..v.label.."\\N"
        else ov.data = ov.data..v.name.."\\N" end
    end

    if overflow then ov.data = ov.data..'\\N'..o.ass_footerheader..#list-finish..' items remaining' end
    ov:update()
end

function update_list(reload)
    msg.verbose('loading contents of ' .. state.directory)
    state.selected = 1

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if not reload and #cache > 0 then
        local cache = cache[#cache]
        if cache.directory == state.directory then
            msg.verbose('found directory in cache')
            list = cache.table
            state.selected = cache.cursor
            return
        end
    end

    local t = mp.get_time()
    list = utils.readdir(state.directory, 'dirs')

    --if we can't access the filesystem for the specified directory then we go to root page
    --this is cuased by either:
    --  a network file being streamed
    --  the user navigating above / on linux or the current drive root on windows
    if list == nil then
        goto_root()
        return
    end

    state.root = false
    for i,item in ipairs(list) do
        if (state.prev_directory == item) then
            state.selected = i
        end
        list[i] = {name = item..'/', type = 'dir'}
    end
    state.prev_directory = ""

    --array concatenation taken from https://stackoverflow.com/a/15278426
    local list2 = utils.readdir(state.directory, 'files')
    for i = 1,#list2 do
        list[#list+1] = {name = list2[i], type = 'file'}
    end
    msg.debug('load time: ' ..mp.get_time() - t)

    --saves the latest directory at the top of the stack
    cache[#cache+1] = {directory = state.directory, table = list}
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
    end
    update_ass()
end

function scroll_up()
    if state.selected > 1 then
        state.selected = state.selected - 1
    end
    update_ass()
end

function up_dir()
    local dir = state.directory:reverse()
    local index = dir:find("[/\\]")

    while index == 1 do
        dir = dir:sub(2)
        index = dir:find("[/\\]")
    end

    if index == nil then
        state.prev_directory = state.directory
        state.directory = ""
    else
        state.prev_directory = dir:sub(1, index-1):reverse()
        msg.debug('saving previous directory name ' .. state.prev_directory)
        state.directory = dir:sub(index):reverse()
    end

    cache[#cache] = nil
    update()
end

function down_dir()
    if list[state.selected].type ~= 'dir' then return end

    state.directory = state.directory..list[state.selected].name
    if #cache > 0 then cache[#cache].cursor = state.selected end
    update()
end

function open_browser()
    for _,v in ipairs(keybinds) do
        mp.add_forced_key_binding(v[1], 'dynamic/'..v[2], v[3], v[4])
    end

    if state.directory == nil then
        goto_current_dir()
    end
    ov.hidden = false
    ov:update()
end

function close_browser()
    for _,v in ipairs(keybinds) do
        mp.remove_key_binding('dynamic/'..v[2])
    end
    ov.hidden = true
    ov:update()
end

function open_file(flags)
    if state.selected > #list or state.selected < 1 then return end
    mp.commandv('loadfile', state.directory..list[state.selected].name, flags)
    if flags == 'replace' then
        close_browser()
    end
end

function toggle_browser()
    if ov.hidden then
        open_browser()
    else
        close_browser()
    end
end

mp.observe_property('path', 'string', function(_,path)
    update_current_directory(_,path)
    if not ov.hidden then update_ass() end
end)
mp.add_key_binding('MENU','browse-files', toggle_browser)
