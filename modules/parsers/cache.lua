local mp = require 'mp'
local msg = require 'mp.msg'

local o = require 'modules.options'

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

    local list, opts = self:defer(directory)
    if not list then return end

    msg.debug('storing', directory, 'contents in cache')
    cache[directory] = {
        list = list,
        opts = opts,
        timeout = mp.add_timeout(60, function() print('clearing', directory) ; cache[directory] = nil end),
    }

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
