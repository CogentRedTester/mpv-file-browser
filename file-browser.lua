local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    --root directories
    roots = "~/",

    ass_body = "{\\q2\\fs30}"
}

opt.read_options(o, 'file_browser')

local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local list = {}
local cache = {}
local cursor_pos = {}
local state = {
    directory = nil,
    selected = 1,
    multiple = false,
    root = false
}
local roots = nil
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
function setup_roots()
    roots = {}
    for str in string.gmatch(o.roots, "([^;]+)") do
        path = mp.command_native({'expand-path', str})
        roots[#roots+1] = {name = path, type = 'dir', label = str}
    end
    update_cursor()
end

function goto_current_dir()
    local workingDirectory = mp.get_property('working-directory', '')
    local filepath = mp.get_property('path', '')
    local exact_path = utils.join_path(workingDirectory, filepath)

    --splits the directory and filename apart
    state.directory = utils.split_path(exact_path)
    cache = {}
    cursor_pos[state.directory] = 1
    update_cursor()
    update_list()
    update_ass()
end

function goto_root()
    if roots == nil then setup_roots() end
    msg.verbose('loading roots')
    list = roots
    state.root = true
    state.directory = ""
    cache = {}
    update_cursor()
    update_ass()
end

function update_ass()
    ov.data = o.ass_body

    for i,v in ipairs(list) do
        if i == state.selected then
            ov.data = ov.data.."> "
        end
        if state.root then
            ov.data = ov.data..v.label.."\\N"
        else
            ov.data = ov.data..v.name.."\\N"
        end
    end
    ov:update()
end

function update_list(reload)
    msg.verbose('loading contents of ' .. state.directory)

    --loads the current directry from the cache to save loading time
    --there will be a way to forcibly reload the current directory at some point
    --the cache is in the form of a stack, items are taken off the stack when the dir moves up
    if not reload and #cache > 0 then
        if cache[#cache].directory == state.directory then
            msg.verbose('found directory in cache')
            list = cache[#cache].table
            return
        end
    end

    local t = mp.get_time()
    list = utils.readdir(state.directory, 'dirs')

    if list == nil then
        goto_root()
        if state.selected > #list then state.selected = 1 end
        return
    end

    state.root = false
    for i,item in ipairs(list) do
        list[i] = {name = item, type = 'dir'}
    end

    --array concatenation taken from https://stackoverflow.com/a/15278426
    local list2 = utils.readdir(state.directory, 'files')
    for i = 1,#list2 do
        list[#list+1] = {name = list2[i], type = 'file'}
    end

    if state.selected > #list then state.selected = 1 end
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

function update_cursor()
    local cursor = cursor_pos[state.directory]
    if cursor == nil then
        state.selected = 1
        cursor_pos[state.directory] = 1
        cursor = 1
    end
    state.selected = cursor
end

function up_dir()
    local dir = state.directory:reverse()
    local index = dir:find("[/\\]")

    while index == 1 do
        dir = dir:sub(2)
        index = dir:find("[/\\]")
    end

    cursor_pos[state.directory] = state.selected
    if index == nil then
        state.directory = ""
    else
        state.directory = dir:reverse():sub(1, 0-index)
    end

    cache[#cache] = nil
    update_cursor()
    update()
end

function down_dir()
    if list[state.selected].type ~= 'dir' then return end

    cursor_pos[state.directory] = state.selected
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

    update_cursor()
    update()
end

function open_browser()
    for _,v in ipairs(keybinds) do
        mp.add_forced_key_binding(v[1], v[2], v[3], v[4])
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
