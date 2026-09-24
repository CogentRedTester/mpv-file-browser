local mp = require 'mp'

local o = require 'modules.options'
local g = require 'modules.globals'
local fb_utils = require 'modules.utils'
local fb = require 'modules.apis.fb'

--sets up the compatible extensions list
local function setup_extensions_list()
    --setting up subtitle extensions
    for ext in fb_utils.iterate_opt(o.subtitle_extensions:lower(), ',') do
        g.sub_extensions[ext] = true
        g.extensions[ext] = true
    end

    --setting up audio extensions
    for ext in fb_utils.iterate_opt(o.audio_extensions:lower(), ',') do
        g.audio_extensions[ext] = true
        g.extensions[ext] = true
    end

    --adding file extensions to the set
    for _, ext in ipairs(g.compatible_file_extensions) do
        g.extensions[ext] = true
    end

    --adding extra extensions on the whitelist
    for str in fb_utils.iterate_opt(o.extension_whitelist:lower(), ',') do
        g.extensions[str] = true
    end

    --removing extensions that are in the blacklist
    for str in fb_utils.iterate_opt(o.extension_blacklist:lower(), ',') do
        g.extensions[str] = nil
    end
end

--splits the string into a table on the separators
local function setup_root()
    for str in fb_utils.iterate_opt(o.root) do
        local path = mp.command_native({'expand-path', str}) --[[@as string]]
        path = fb_utils.fix_path(path, true)

        local temp = {name = path, type = 'dir', label = str, ass = fb_utils.ass_escape(str, true)}

        g.root[#g.root+1] = temp
    end

    if g.PLATFORM == 'windows' then
        fb.register_root_item('C:/')
    elseif g.PLATFORM ~= nil then
        fb.register_root_item('/')
    end
end

---@param hex string
---@return string
local function decode_uri_component(hex)
    local code = tonumber(hex, 16)
    return string.char(code)
end

--registers path substitutions for external paths
local function setup_substitutions()
    fb.register_path_substitution('^dvd://.*', function()
        return fb_utils.absolute_path(mp.get_property('dvd-device','/dev/dvd'))
    end)

    fb.register_path_substitution('^bd://.*', function()
        return fb_utils.absolute_path(mp.get_property('bd-device','/dev/bd'))
    end)

    fb.register_path_substitution('^cdda://.*', function()
        return fb_utils.absolute_path(mp.get_property('cdda-device','/dev/cdrom'))
    end)

    fb.register_path_substitution('^archive://(.*)|/.*$', function(archive_path)
        archive_path = string.gsub(archive_path, '%%(%x%x)', decode_uri_component)
        return fb_utils.absolute_path(archive_path)
    end)
end

---@class setup
return {
    extensions_list = setup_extensions_list,
    root = setup_root,
    substitutions = setup_substitutions
}
