
local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local o = require 'modules.options'
local g = require 'modules.globals'
local ass = require 'modules.ass'
local scanning = require 'modules.navigation.scanning'
local fb_utils = require 'modules.utils'

---@class directory_movement
local directory_movement = {}

---Clears directories from the history
---@param from? number All entries >= this index are cleared.
---@return string[]
function directory_movement.clear_history(from)
    ---@type string[]
    local cleared = {}

    from = from or 1
    for i = g.history.size, from, -1 do
        table.insert(cleared, g.history.list[i])
        g.history.list[i] = nil
        g.history.size = g.history.size - 1

        if g.history.position >= i then
            g.history.position = g.history.position - 1
        end
    end

    return cleared
end

---Append a directory to the history
---If we have navigated backward in the history,
---then clear any history beyond the current point.
---@param directory string
function directory_movement.append_history(directory)
    if g.history.list[g.history.position] == directory then
        msg.debug('reloading same directory - history unchanged:', directory)
        return
    end

    msg.debug('appending to history:', directory)
    if g.history.position < g.history.size then
        directory_movement.clear_history(g.history.position + 1)
    end

    table.insert(g.history.list, directory)
    g.history.size = g.history.size + 1
    g.history.position = g.history.position + 1

    if g.history.size > 100 then
        table.remove(g.history.list, 1)
        g.history.size = g.history.size - 1
    end
end

---@param filepath string
function directory_movement.set_current_file(filepath)
    --if we're in idle mode then we want to open the working directory
    if filepath == nil then
        g.current_file.directory = fb_utils.fix_path( mp.get_property("working-directory", ""), true)
        g.current_file.name = nil
        g.current_file.path = nil
        return
    end

    local absolute_path = fb_utils.absolute_path(filepath)
    local resolved_path = fb_utils.resolve_directory_mapping(absolute_path)

    g.current_file.directory, g.current_file.name = utils.split_path(resolved_path)
    g.current_file.original_path = absolute_path
    g.current_file.path = resolved_path

    if not g.state.hidden then ass.update_ass()
    else g.state.flag_update = true end
end

--the base function for moving to a directory
---@param directory string
---@param moving_adjacent? number|false
---@param store_history? boolean default `true`
---@return thread
function directory_movement.goto_directory(directory, moving_adjacent, store_history)
    local current = g.state.list[g.state.selected]
    g.state.directory = directory

    if g.state.directory_label then
        if moving_adjacent == 1 then
            g.state.directory_label = g.state.directory_label..(current.label or current.name)
        elseif moving_adjacent == -1 then
            g.state.directory_label = string.match(g.state.directory_label, "^(.-/+)[^/]+/*$")
        end
    end

    if store_history == nil or store_history then
        directory_movement.append_history(directory)
    end
    return scanning.rescan(moving_adjacent or false)
end

--loads the root list
function directory_movement.goto_root()
    msg.verbose('jumping to root')
    return directory_movement.goto_directory("")
end

--switches to the directory of the currently playing file
function directory_movement.goto_current_dir()
    msg.verbose('jumping to current directory')
    return directory_movement.goto_directory(g.current_file.directory)
end

--moves up a directory
function directory_movement.up_dir()
    local parent_dir = g.state.directory:match("^(.-/+)[^/]+/*$") or ""

    if o.skip_protocol_schemes and parent_dir:find("^(%a[%w+-.]*)://$") then
        return directory_movement.goto_root()
    end

    return directory_movement.goto_directory(parent_dir, -1)
end

--moves down a directory
function directory_movement.down_dir()
    local current = g.state.list[g.state.selected]
    if not current or not fb_utils.parseable_item(current) then return end

    local directory, redirected = fb_utils.get_new_directory(current, g.state.directory)
    return directory_movement.goto_directory(directory, not redirected and 1)
end

--moves backwards through the directory history
function directory_movement.back_history()
    msg.debug('moving backwards in history to', g.history.list[g.history.position-1])
    if g.history.position == 1 then return end
    g.history.position = g.history.position - 1
    directory_movement.goto_directory(g.history.list[g.history.position])
end

--moves forward through the history
function directory_movement.forwards_history()
    msg.debug('moving forwards in history to', g.history.list[g.history.position+1])
    if g.history.position == g.history.size then return end
    g.history.position = g.history.position + 1
    directory_movement.goto_directory(g.history.list[g.history.position])
end

return directory_movement
