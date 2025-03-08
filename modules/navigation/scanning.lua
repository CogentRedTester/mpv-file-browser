local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local g = require 'modules.globals'
local fb_utils = require 'modules.utils'
local cursor = require 'modules.navigation.cursor'
local ass = require 'modules.ass'

local parse_state_API = require 'modules.apis.parse-state'

local function clear_non_adjacent_state()
    g.state.directory_label = nil
end

---parses the given directory or defers to the next parser if nil is returned
---@async
---@param directory string
---@param index number
---@return List?
---@return Opts?
local function choose_and_parse(directory, index)
    msg.debug(("finding parser for %q"):format(directory))
    ---@type Parser, List?, Opts?
    local parser, list, opts
    local parse_state = g.parse_states[coroutine.running() or ""]
    while list == nil and not parse_state.already_deferred and index <= #g.parsers do
        parser = g.parsers[index]
        if parser:can_parse(directory, parse_state) then
            msg.debug("attempting parser:", parser:get_id())
            list, opts = parser:parse(directory, parse_state)
        end
        index = index + 1
    end
    if not list then return nil, {} end

    msg.debug("list returned from:", parser:get_id())
    opts = opts or {}
    if list then opts.id = opts.id or parser:get_id() end
    return list, opts
end

---Sets up the parse_state table and runs the parse operation.
---@async
---@param directory string
---@param parse_state_template ParseStateTemplate
---@return List|nil
---@return Opts
local function run_parse(directory, parse_state_template)
    msg.verbose(("scanning files in %q"):format(directory))

    ---@type ParseStateFields
    local parse_state = {
        source = parse_state_template.source,
        directory = directory,
        properties = parse_state_template.properties or {}
    }

    local co = coroutine.running()
    g.parse_states[co] = fb_utils.set_prototype(parse_state, parse_state_API) --[[@as ParseState]]

    local list, opts = choose_and_parse(directory, 1)

    if list == nil then return msg.debug("no successful parsers found"), {} end
    opts = opts or {}
    opts.parser = g.parsers[opts.id]

    if not opts.filtered then fb_utils.filter(list) end
    if not opts.sorted then fb_utils.sort(list) end
    return list, opts
end

---Returns the contents of the given directory using the given parse state.
---If a coroutine has already been used for a parse then create a new coroutine so that
---the every parse operation has a unique thread ID.
---@async
---@param directory string
---@param parse_state ParseStateTemplate
---@return List|nil
---@return Opts
local function parse_directory(directory, parse_state)
    local co = fb_utils.coroutine.assert("scan_directory must be executed from within a coroutine - aborting scan "..utils.to_string(parse_state))
    if not g.parse_states[co] then return run_parse(directory, parse_state) end

    --if this coroutine is already is use by another parse operation then we create a new
    --one and hand execution over to that
    ---@async
    local new_co = coroutine.create(function()
        fb_utils.coroutine.resume_err(co, run_parse(directory, parse_state))
    end)

    --queue the new coroutine on the mpv event queue
    mp.add_timeout(0, function()
        local success, err = coroutine.resume(new_co)
        if not success then
            fb_utils.traceback(err, new_co)
            fb_utils.coroutine.resume_err(co)
        end
    end)
    return g.parse_states[co]:yield()
end

---Sends update requests to the different parsers.
---@async
---@param moving_adjacent? number|boolean
local function update_list(moving_adjacent)
    msg.verbose('opening directory: ' .. g.state.directory)

    g.state.selected = 1
    g.state.selection = {}

    local directory = g.state.directory
    local list, opts = parse_directory(g.state.directory, { source = "browser" })

    --if the running coroutine isn't the one stored in the state variable, then the user
    --changed directories while the coroutine was paused, and this operation should be aborted
    if coroutine.running() ~= g.state.co then
        msg.verbose(g.ABORT_ERROR.msg)
        msg.debug("expected:", g.state.directory, "received:", directory)
        return
    end

    --apply fallbacks if the scan failed
    if not list then
        --opens the root instead
        msg.warn("could not read directory", g.state.directory, "redirecting to root")
        list, opts = parse_directory("", { source = "browser" })

        if not list then error(('fatal error - failed to read the root directory')) end

        -- sets the directory redirect flag
        opts.directory = ''
    end

    g.state.list = list
    g.state.parser = opts.parser

    --setting custom options from parsers
    g.state.directory_label = opts.directory_label
    g.state.empty_text = opts.empty_text or g.state.empty_text

    --we assume that directory is only changed when redirecting to a different location
    --therefore we need to change the `moving_adjacent` flag and clear some state values
    if opts.directory then
        g.state.directory = opts.directory
        moving_adjacent = false
        clear_non_adjacent_state()
    end

    if opts.selected_index then
        g.state.selected = opts.selected_index or g.state.selected
        if g.state.selected > #g.state.list then g.state.selected = #g.state.list
        elseif g.state.selected < 1 then g.state.selected = 1 end
    end

    if moving_adjacent then cursor.select_prev_directory()
    else cursor.select_playing_item() end
    g.state.prev_directory = g.state.directory
end

---rescans the folder and updates the list.
---@param moving_adjacent? number|boolean
---@param cb? function
---@return thread # The coroutine for the triggered parse operation. May be aborted early if directory is in the cache.
local function rescan(moving_adjacent, cb)
    if moving_adjacent == nil then moving_adjacent = 0 end

    --we can only make assumptions about the directory label when moving from adjacent directories
    if not moving_adjacent then clear_non_adjacent_state() end

    g.state.empty_text = "~"
    g.state.list = {}
    cursor.disable_select_mode()
    ass.update_ass()

    --the directory is always handled within a coroutine to allow addons to
    --pause execution for asynchronous operations
    ---@async
    local co = fb_utils.coroutine.queue(function()
        update_list(moving_adjacent)
        if g.state.empty_text == "~" then g.state.empty_text = "empty directory" end

        ass.update_ass()
        if cb then fb_utils.coroutine.run(cb) end
    end)

    g.state.co = co
    return co
end

---@class scanning
return {
    rescan = rescan,
    scan_directory = parse_directory,
    choose_and_parse = choose_and_parse,
}
