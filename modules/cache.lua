--------------------------------------------------------------------------------------------------------
--------------------------------------Cache Implementation----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local msg = require 'mp.msg'
local utils = require 'mp.utils'

local o = require 'modules.options'
local g = require 'modules.globals'
local fb_utils = require 'modules.utils'

local function get_keys(t)
    local keys = {}
    for key in pairs(t) do
        table.insert(keys, key)
    end
    return keys
end

local cache = {
    cache = setmetatable({}, {__mode = 'kv'}),
    traversal_stack = {},
    history = {},
    cached_values = {
        "directory", "directory_label", "list", "selected", "selection", "parser", "empty_text", "co"
    },
    dangling_refs = {},
}

function cache:print_debug_info()
    local cache_keys = get_keys(self.cache)
    msg.verbose('Printing cache debug info')
    msg.verbose('cache size:', #cache_keys)
    msg.debug(utils.to_string(cache_keys))
    msg.trace(utils.to_string(self.cache[cache_keys[#cache_keys]]))

    msg.verbose('traversal_stack size:', #self.traversal_stack)
    msg.debug(utils.to_string(fb_utils.list.map(self.traversal_stack, function(ref) return ref.directory end)))

    msg.verbose('history size:', #self.history)
    msg.debug(utils.to_string(fb_utils.list.map(self.history, function(ref) return ref.directory end)))
end

function cache:replace_dangling_refs(directory, ref)
    for _, v in ipairs(self.traversal_stack) do
        if v.directory == directory then
            v.ref = ref
            self.dangling_refs[directory] = nil
        end
    end
    for _, v in ipairs(self.history) do
        if v.directory == directory then
            v.ref = ref
            self.dangling_refs[directory] = nil
        end
    end
end

function cache:add_current_state()
    -- We won't actually store any cache details here if
    -- the option is not enabled.
    if not o.cache then return end

    local directory = g.state.directory
    if directory == nil then return end

    local t = self.cache[directory] or {}
    for _, value in ipairs(self.cached_values) do
        t[value] = g.state[value]
    end

    self.cache[directory] = t
    if self.dangling_refs[directory] then
        self:replace_dangling_refs(directory, t)
    end
end

-- Creates a reference to the cache of a particular directory to prevent it
-- from being garbage collected.
function cache:get_cache_ref(directory)
   return {
        directory = directory,
        ref = self.cache[directory],
   }
end

function cache:append_history()
    self:add_current_state()
    local history_size = #self.history

    -- We don't want to have the same directory in the history over and over again.
    if history_size > 0 and self.history[history_size].directory == g.state.directory then return end

    table.insert(self.history, self:get_cache_ref(g.state.directory))
    if (history_size + 1) > 100 then table.remove(self.history, 1) end
end

function cache:in_cache(directory)
    return self.cache[directory] ~= nil
end

function cache:apply(directory)
    directory = directory or g.state.directory
    local t = self.cache[directory]
    if not t then return false end

    msg.verbose('applying cache for', directory)

    for _, value in ipairs(self.cached_values) do
        msg.debug('setting', value, 'to', t[value])
        g.state[value] = t[value]
    end

    return true
end

function cache:push()
    local stack_size = #self.traversal_stack
    if stack_size > 0 and self.traversal_stack[stack_size].directory == g.state.directory then return end
    table.insert(self.traversal_stack, self:get_cache_ref(g.state.directory))
end

function cache:pop()
    table.remove(self.traversal_stack)
end

function cache:clear_traversal_stack()
    self.traversal_stack = {}
end

function cache:clear(directories)
    if directories then
        msg.verbose('clearing cache', utils.to_string(directories))
        for _, dir in ipairs(directories) do
            self.cache[dir] = nil
            for _, v in ipairs(self.traversal_stack) do
                if v.directory == dir then v.ref = nil end
            end
            for _, v in ipairs(self.history) do
                if v.directory == dir then v.ref = nil end
            end
            self.dangling_refs[dir] = nil
        end
        return
    end

    msg.verbose('clearing cache')
    self.cache = setmetatable({}, {__mode = 'kv'})
    for _, v in ipairs(self.traversal_stack) do
        v.ref = nil
        self.dangling_refs[v.directory] = true
    end
    for _, v in ipairs(self.history) do
        v.ref = nil
        self.dangling_refs[v.directory] = true
    end
end

return cache
