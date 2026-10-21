-- This file is an internal file-browser addon.
-- It should not be imported like a normal module.

local mp = require 'mp'
local msg = require 'mp.msg'
local fb = require 'file-browser'

---@type ParserConfig
local archive = {
    name = 'archive',
    priority = 105,
    api_version = '1.9.0',
}

---@type table<string, boolean>
local archive_extensions = {}

local default_extensions = {
    '7z', '7z.001', 'ace', 'ar', 'arj', 'bz2', 'cab', 'cpio', 'deb', 'gz',
    'iso', 'lha', 'lz', 'lzh', 'lzma', 'lzo', 'rar', 'rpm', 'tar',
    'taz', 'tbz', 'tbz2', 'tgz', 'tlz', 'txz', 'war', 'xar', 'xz', 'zip',
    'zipx', 'zst',
}

local function add_extension(extension)
    extension = string.lower(string.gsub(extension, '^%.', ''))
    if extension == '' then return end

    archive_extensions[extension] = true
    archive.register_parseable_extension(extension:match('([^%.]+)$'))
end

function archive:setup()
    local extensions = mp.get_property_native('options/archive-exts')
    if type(extensions) == 'table' then
        ---@cast extensions string[]
        for _, extension in ipairs(extensions) do add_extension(extension) end
    elseif type(extensions) == 'string' then
        ---@cast extensions string
        for extension in extensions:gmatch('[^,]+') do add_extension(extension) end
    else
        for _, extension in ipairs(default_extensions) do add_extension(extension) end
    end

    for extension in pairs(archive_extensions) do
        self.add_default_extension(extension:match('([^%.]+)$'))
    end
end

---@param path string
---@return string?, string?
local function split_archive_path(path)
    path = path:gsub('/+$', '')

    for index = 1, #path + 1 do
        if index == #path + 1 or path:sub(index, index) == '/' then
            local candidate = path:sub(1, index - 1)
            local basename = candidate:match('([^/]+)$') or candidate

            for extension in pairs(archive_extensions) do
                if basename:lower():sub(-#extension - 1) == '.' .. extension then
                    return candidate, path:sub(index + 1)
                end
            end
        end
    end
end

function archive:can_parse(directory)
    if not fb.get_opt('archive_parser') then return false end
    return split_archive_path(directory) ~= nil
end

---@async
---@param path string
---@param parse_state ParseState
---@return string?
local function list_archive(path, parse_state)
    local async = mp.command_native_async({
        name = 'subprocess',
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = { 'bsdtar', '-tf', path },
    }, fb.coroutine.callback(30))

    ---@type boolean, boolean, MPVSubprocessResult
    local completed, _, result = parse_state:yield()
    if not completed then
        msg.warn('timed out listing archive:', path)
        mp.abort_async_command(async)
        return nil
    end
    if result.status ~= 0 then
        msg.warn('could not list archive:', path, result.stderr)
        return nil
    end

    return result.stdout or ''
end

---@param entry string
---@return string?, boolean?
local function clean_entry(entry)
    local is_directory = entry:sub(-1) == '/'
    entry = fb.fix_path(entry):gsub('^%./', ''):gsub('/+$', '')
    if entry == '' or entry:sub(1, 1) == '/' or entry:match('^%a:/') then return nil end

    for component in entry:gmatch('[^/]+') do
        if component == '..' then return nil end
    end

    return entry, is_directory
end

---@async
---@param directory string
---@param parse_state ParseState
---@return List?, Opts?
function archive:parse(directory, parse_state)
    local archive_path, member_path = split_archive_path(directory)
    if not archive_path then return nil end

    archive_path = self.absolute_path(archive_path)
    member_path = (member_path or ''):gsub('/+$', '')

    local output = list_archive(archive_path, parse_state)
    if output == nil then return nil end

    ---@type table<string, boolean>
    local directories = {}
    ---@type table<string, string>
    local files = {}
    local prefix = member_path ~= '' and member_path .. '/' or ''

    for entry in output:gmatch('[^\r\n]+') do
        local cleaned, is_directory = clean_entry(entry)
        if cleaned then
            if prefix == '' or cleaned:sub(1, #prefix) == prefix then
                local relative = prefix == '' and cleaned or cleaned:sub(#prefix + 1)
                if relative ~= '' then
                    local child, remainder = relative:match('^([^/]+)/?(.*)$')
                    if child then
                        if remainder ~= '' or is_directory then
                            directories[child] = true
                        else
                            files[child] = cleaned
                        end
                    end
                end
            end
        end
    end

    local escaped_archive_path = archive_path:gsub('%%', '%%25'):gsub('|', '%%7C')
    local list = {}
    for name in pairs(directories) do
        table.insert(list, { name = name .. '/', type = 'dir' })
    end
    for name, member in pairs(files) do
        if not directories[name] then
            table.insert(list, {
                name = name,
                path = 'archive://' .. escaped_archive_path .. '|' .. member,
                type = 'file',
            })
        end
    end

    return list
end

return archive