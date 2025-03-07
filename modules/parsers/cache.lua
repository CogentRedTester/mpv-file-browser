local mp = require 'mp'
local msg = require 'mp.msg'

local o = require 'modules.options'
local fb = require 'file-browser'

---@type ParserConfig
local cacheParser = {
    name = 'cache',
    priority = 0,
    api_version = '1.8',
}

---@class CacheEntry
---@field list List
---@field opts Opts?
---@field timeout MPTimer

---@type table<string,CacheEntry>
local cache = {}

---@type table<string,(async fun(list: List?, opts: Opts?))[]>
local pending_parses = {}

---@param directories? string[]
local function clear_cache(directories)
    if directories then
        msg.debug('clearing cache', table.concat(directories, '\n'))
        for _, dir in ipairs(directories) do
            if cache[dir] then
            cache[dir].timeout:kill()
            cache[dir] = nil
            end
        end
    else
        msg.debug('clearing cache')
        for _, entry in pairs(cache) do
            entry.timeout:kill()
        end
        cache = {}
    end
end

---@type string
local prev_directory = ''

function cacheParser:can_parse(directory, parse_state)
    if not o.cache or directory == '' then return false end 

    -- clear the cache if reloading the current directory in the browser
    -- this means that fb.rescan() should maintain expected behaviour
    if parse_state.source == 'browser' then
        prev_directory = directory
        if prev_directory == directory then clear_cache({directory}) end
    end

    return true
end

---@async
function cacheParser:parse(directory)
    if cache[directory] then
        msg.verbose('fetching', directory, 'contents from cache')
        cache[directory].timeout:kill()
        cache[directory].timeout:resume()
        return cache[directory].list, cache[directory].opts
    end

    ---@type List?, Opts?
    local list, opts

    -- if another parse is already running on the same directory, then wait and use the same result
    if not pending_parses[directory] then
        pending_parses[directory] = {}
        list, opts = self:defer(directory)
    else
        msg.debug('parse for', directory, 'already running - waiting for other parse to finish...')
        table.insert(pending_parses[directory], fb.coroutine.callback())
        list, opts = coroutine.yield()
    end

    local pending = pending_parses[directory]
    if pending then
        -- need to clear the pending parses before resuming them or they will also attempt to resume the parses
        pending_parses[directory] = nil
        msg.debug('resuming', #pending,'pending parses for', directory)
        for _, cb in ipairs(pending) do
            cb(list, opts)
        end
    end

    if not list then return end

    -- pending will be truthy for the original parse and falsy for any parses that were pending
    if pending then
    msg.debug('storing', directory, 'contents in cache')
    cache[directory] = {
        list = list,
        opts = opts,
            timeout = mp.add_timeout(120, function() cache[directory] = nil end),
    }
    end

    return list, opts
end

if o.cache then
    cacheParser.keybinds = {
        {
            key = 'Ctrl+Shift+r',
            name = 'clear_cache',
            command = function() clear_cache() ; fb.rescan() end,
        }
    }
end

return cacheParser
