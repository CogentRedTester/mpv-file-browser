local utils = require 'mp.utils'

--------------------------------------------------------------------------------------------------------
-----------------------------------------Utility Functions----------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

--get the full path for the current file
local function get_full_path(item, dir)
    if item.path then return item.path end
    return (dir or state.directory)..item.name
end

local function concatenate_path(item, directory)
    if directory == "" then return item.name end
    if directory:sub(-1) == "/" then return directory..item.name end
    return directory.."/"..item.name
end

--returns the file extension of the given file
local function get_extension(filename, def)
    return filename:match("%.([^%./]+)$") or def
end

--returns the protocol scheme of the given url, or nil if there is none
local function get_protocol(filename, def)
    return filename:match("^(%a%w*)://") or def
end

--formats strings for ass handling
--this function is based on a similar function from https://github.com/mpv-player/mpv/blob/master/player/lua/console.lua#L110
local function ass_escape(str, replace_newline)
    if replace_newline == true then replace_newline = "\\\239\187\191n" end

    --escape the invalid single characters
    str = str:gsub('[\\{}\n]', {
        -- There is no escape for '\' in ASS (I think?) but '\' is used verbatim if
        -- it isn't followed by a recognised character, so add a zero-width
        -- non-breaking space
        ['\\'] = '\\\239\187\191',
        ['{'] = '\\{',
        ['}'] = '\\}',
        -- Precede newlines with a ZWNBSP to prevent ASS's weird collapsing of
        -- consecutive newlines
        ['\n'] = '\239\187\191\\N',
    })

    -- Turn leading spaces into hard spaces to prevent ASS from stripping them
    str = str:gsub('\\N ', '\\N\\h')
    str = str:gsub('^ ', '\\h')

    if replace_newline then
        str = str:gsub("\\N", replace_newline)
    end
    return str
end

--escape lua pattern characters
local function pattern_escape(str)
    return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-])", "%%%1")
end

--standardises filepaths across systems
local function fix_path(str, is_directory)
    str = str:gsub([[\]],[[/]])
    str = str:gsub([[/./]], [[/]])
    if is_directory and str:sub(-1) ~= '/' then str = str..'/' end
    return str
end

--wrapper for utils.join_path to handle protocols
local function join_path(working, relative)
    return get_protocol(relative) and relative or utils.join_path(working, relative)
end

--sorts the table lexicographically ignoring case and accounting for leading/non-leading zeroes
--the number format functionality was proposed by github user twophyro, and was presumably taken
--from here: http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
local function sort(t)
    local function padnum(d)
        local r = string.match(d, "0*(.+)")
        return ("%03d%s"):format(#r, r)
    end

    --appends the letter d or f to the start of the comparison to sort directories and folders as well
    table.sort(t, function(a,b) return a.type:sub(1,1)..(a.label or a.name):lower():gsub("%d+",padnum) < b.type:sub(1,1)..(b.label or b.name):lower():gsub("%d+",padnum) end)
    return t
end

local function valid_dir(dir)
    if o.filter_dot_dirs and dir:sub(1,1) == "." then return false end
    return true
end

local function valid_file(file)
    if o.filter_dot_files and (file:sub(1,1) == ".") then return false end
    if o.filter_files and not extensions[ get_extension(file, "") ] then return false end
    return true
end

--removes items and folders from the list
--this is for addons which can't filter things during their normal processing
local function filter(t)
    local max = #t
    local top = 1
    for i = 1, max do
        local temp = t[i]
        t[i] = nil

        if  ( temp.type == "dir" and valid_dir(temp.label or temp.name) ) or
            ( temp.type == "file" and valid_file(temp.label or temp.name) )
        then
            t[top] = temp
            top = top+1
        end
    end
    return t
end

--sorts a table into an array of selected items in the correct order
--if a predicate function is passed, then the item will only be added to
--the table if the function returns true
local function sort_keys(t, include_item)
    local keys = {}
    for k in pairs(t) do
        local item = state.list[k]
        if not include_item or include_item(item) then
            item.index = k
            keys[#keys+1] = item
        end
    end

    table.sort(keys, function(a,b) return a.index < b.index end)
    return keys
end

--copies a table without leaving any references to the original
--uses a structured clone algorithm to maintain cyclic references
local function copy_table_recursive(t, references)
    if not t then return nil end
    local copy = {}
    references[t] = copy

    for key, value in pairs(t) do
        if type(value) == "table" then
            if references[value] then copy[key] = references[value]
            else copy[key] = copy_table_recursive(value, references) end
        else
            copy[key] = value end
    end
    return copy
end

--a wrapper around copy_table to provide the reference table
local function copy_table(t)
    --this is to handle cyclic table references
    return copy_table_recursive(t, {})
end

return {
    ass_escape = ass_escape,
    concatenate_path = concatenate_path,
    copy_table = copy_table,
    filter = filter,
    fix_path = fix_path,
    get_extension = get_extension,
    get_full_path = get_full_path,
    get_protocol = get_protocol,
    join_path = join_path,
    pattern_escape = pattern_escape,
    sort = sort,
    sort_keys = sort_keys,
    valid_dir = valid_dir,
    valid_file = valid_file
}