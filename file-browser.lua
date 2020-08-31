local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    ass_body = "{\\q2\\fs30}"
}

local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local list = {}
local state = {
    directory = nil,
    selected = 1,
    multiple = false
}
local keybinds = {
    {'ENTER', 'open', function() open_file() end, {}},
    {'ESC', 'exit', function() close_browser() end, {}},
    {'RIGHT', 'down_dir', function() down_dir() end, {}},
    {'LEFT', 'up_dir', function() up_dir() end, {}},
    {'DOWN', 'scroll_down', function() scroll_down() end, {repeatable = true}},
    {'UP', 'scroll_up', function() scroll_up() end, {repeatable = true}}
}

function update_ass()
    ov.data = o.ass_body

    for i,v in ipairs(list) do
        if i == state.selected then
            ov.data = ov.data.."> "
        end
        ov.data = ov.data..v.name.."\\N"
    end
    ov:update()
end

function update_list()
    msg.verbose('loading contents of ' .. state.directory)
    local t = mp.get_time()
    list = utils.readdir(state.directory, 'dirs')

    for i,item in ipairs(list) do
        list[i] = {name = item, type = 'dir'}
    end

    --array concatenation taken from https://stackoverflow.com/a/15278426
    local list2 = utils.readdir(state.directory, 'files')
    for i = 1,#list2 do
        list[#list+1] = {name = list2[i], type = 'file'}
    end


    msg.debug('load time: ' ..mp.get_time() - t)
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

    state.directory = state.directory:sub(1, -1-index)
    state.selected = 1
    update()
end

function down_dir()
    if list[state.selected].type ~= 'dir' then return end

    state.directory = state.directory..'/'..list[state.selected].name
    state.selected = 1
    update()
end

function open_browser()
    for _,v in ipairs(keybinds) do
        mp.add_forced_key_binding(v[1], v[2], v[3], v[4])
    end

    if state.directory == nil then
        local workingDirectory = mp.get_property('working-directory')
        local filepath = mp.get_property('path')
        local exact_path = utils.join_path(workingDirectory, filepath)

        --splits the directory and filename apart
        state.directory = utils.split_path(exact_path)
        update_list()
        update_ass()
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

function open_file()
    mp.commandv('loadfile', state.directory..'/'..list[state.selected].name)
    close_browser()
end

mp.add_key_binding('MENU','browse-files', open_browser)
