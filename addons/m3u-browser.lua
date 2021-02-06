--[[
    An addon for mpv-file-browser which adds support for m3u playlists
]]--

local utils = require "mp.utils"

local m3u = {
    priority = 10
}

local exts = {
    m3u = true,
    m3u8 = true
}

local full_paths = {}

function m3u:can_parse()
    return true
end

function m3u:parse(directory)
    --convert .m3u files into directories
    local ext = self.get_extension(directory:gsub("/$", ""))
    if not exts[ext] then
        local list, opts = self:defer(directory)
        if not list then return nil end
        for _, item in ipairs(list) do
            if exts[ self.get_extension(item.name) ] then
                local path = (opts.directory or directory)..item.name

                --only declare the playlist file if it is local
                if utils.file_info(item.path or path) then
                    item.type = "dir"
                    full_paths[ path ] = item.path or path
                end
            end
        end
        return list, opts
    end

    directory = directory:gsub("/$", "")
    local list = {}

    local path = full_paths[ directory ] or directory
    local playlist = io.open( path )

    --if we can't read the path then stop here
    if not playlist then return {}, {sorted = true, filtered = true, empty_text = "Could not read filepath"} end

    local parent = self.fix_path(path:match("^(.+/[^/]+)/"), true)

    local lines = playlist:read("*a")

    --for some reason there seems to be an invisible unicode character at the start of the playlist sometimes, so for now I'm removing it
    if lines:byte() > 127 then lines = lines:gsub("^[%z\1-\127\194-\244][\128-\191]*", "") end
    for item in lines:gmatch("[^%c]+") do
        item = self.fix_path(item)
        table.insert(list, {name = item, path = self.join_path(parent, item), type = "file"})
    end
    return list, {filtered = true, sorted = true}
end

return m3u
