local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    --root directories
    root = "~/",

    num_entries = 20,

    --ass tags
    ass_body = "{\\q2\\fs30}",
    ass_folder = "{\\c&Hfce788>&}",
    ass_file = "{\\c&Hffffff>&}"
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
    prev_directory = nil
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
        root[#root+1] = {name = path, type = 'dir', label = str}
    end
end

function goto_current_dir()
    local workingDirectory = mp.get_property('working-directory', '')
    local filepath = mp.get_property('path', '')
    local exact_path = utils.join_path(workingDirectory, filepath)

    --splits the directory and filename apart
    state.directory = utils.split_path(exact_path)
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
    state.root = true
    state.directory = ""
    cache = {}
    update_ass()
end

function update_ass()
    ov.data = o.ass_body

    for i,v in ipairs(list) do
        if i == state.selected then
            ov.data = ov.data.."> "
        end
        if v.type == 'dir' then
            ov.data = ov.data..o.ass_folder
        end

        if state.root then
            ov.data = ov.data..v.label.."\\N"
        else
            ov.data = ov.data..v.name.."\\N"
        end

        if v.type == "dir" then ov.data=ov.data..o.ass_file end
    end
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
        list[i] = {name = item, type = 'dir'}
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

    local last_char = state.directory:sub(-1)
    if state.root or last_char == '\\' or last_char == '/' then
        state.directory = state.directory..list[state.selected].name
    else
        state.directory = state.directory..'/'..list[state.selected].name
    end

    last_char = state.directory:sub(-1)
    if last_char ~= '\\' and last_char ~= '/' then
        state.directory = state.directory..'/'
    end

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
        mp.remove_key_binding(v[2])
    end
    ov.hidden = true
    ov:update()
end

function open_file(flags)
    if state.selected > #list or state.selected < 1 then return end
    mp.commandv('loadfile', state.directory..'/'..list[state.selected].name, flags)
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

mp.add_key_binding('MENU','browse-files', toggle_browser)
