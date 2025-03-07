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
        for _, dir in ipairs(directories) do
            cache[dir].timeout:kill()
            cache[dir] = nil
        end
    else

        for _, entry in pairs(cache) do
            entry.timeout:kill()
        end
        cache = {}
    end
end

function cacheParser:can_parse(directory)
    return o.cache and directory ~= ''
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
            key = 'Ctrl+r',
            name = 'reload',
            command = function() clear_cache() end,
            passthrough = true,
        }
    }
end

return cacheParser
