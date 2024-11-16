--------------------------------------------------------------------------------------------------------
--------------------------------Scroll/Select Implementation--------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local o = require 'modules.options'
local g = require 'modules.globals'
local fb_utils = require 'modules.utils'
local ass = require 'modules.ass'

local cursor = {}

--disables multiselect
function cursor.disable_select_mode()
    g.state.multiselect_start = nil
    g.state.initial_selection = nil
end

--enables multiselect
function cursor.enable_select_mode()
    g.state.multiselect_start = g.state.selected
    g.state.initial_selection = fb_utils.copy_table(g.state.selection)
end

--calculates what drag behaviour is required for that specific movement
local function drag_select(original_pos, new_pos)
    if original_pos == new_pos then return end

    local setting = g.state.selection[g.state.multiselect_start]
    for i = original_pos, new_pos, (new_pos > original_pos and 1 or -1) do
        --if we're moving the cursor away from the starting point then set the selection
        --otherwise restore the original selection
        if i > g.state.multiselect_start then
            if new_pos > original_pos then
                g.state.selection[i] = setting
            elseif i ~= new_pos then
                g.state.selection[i] = g.state.initial_selection[i]
            end
        elseif i < g.state.multiselect_start then
            if new_pos < original_pos then
                g.state.selection[i] = setting
            elseif i ~= new_pos then
                g.state.selection[i] = g.state.initial_selection[i]
            end
        end
    end
end

--moves the selector up and down the list by the entered amount
function cursor.scroll(n, wrap)
    local num_items = #g.state.list
    if num_items == 0 then return end

    local original_pos = g.state.selected

    if original_pos + n > num_items then
        g.state.selected = wrap and 1 or num_items
    elseif original_pos + n < 1 then
        g.state.selected = wrap and num_items or 1
    else
        g.state.selected = original_pos + n
    end

    if g.state.multiselect_start then drag_select(original_pos, g.state.selected) end

    --moves the scroll window down so that the selected item is in the middle of the screen
    g.state.scroll_offset = g.state.selected - (math.ceil(o.num_entries/2)-1)
    if g.state.scroll_offset < 0 then
        g.state.scroll_offset = 0
    end
    ass.update_ass()
end

--selects the first item in the list which is highlighted as playing
function cursor.select_playing_item()
    for i,item in ipairs(g.state.list) do
        if ass.highlight_entry(item) then
            g.state.selected = i
            return
        end
    end
end

--scans the list for which item to select by default
--chooses the folder that the script just moved out of
--or, otherwise, the item highlighted as currently playing
function cursor.select_prev_directory()
    if g.state.prev_directory:find(g.state.directory, 1, true) == 1 then
        local i = 1
        while (g.state.list[i] and fb_utils.parseable_item(g.state.list[i])) do
            if g.state.prev_directory:find(fb_utils.get_full_path(g.state.list[i]), 1, true) then
                g.state.selected = i
                return
            end
            i = i+1
        end
    end

    cursor.select_playing_item()
end

--toggles the selection
function cursor.toggle_selection()
    if not g.state.list[g.state.selected] then return end
    g.state.selection[g.state.selected] = not g.state.selection[g.state.selected] or nil
    ass.update_ass()
end

--select all items in the list
function cursor.select_all()
    for i,_ in ipairs(g.state.list) do
        g.state.selection[i] = true
    end
    ass.update_ass()
end

--toggles select mode
function cursor.toggle_select_mode()
    if g.state.multiselect_start == nil then
        cursor.enable_select_mode()
        cursor.toggle_selection()
    else
        cursor.disable_select_mode()
        ass.update_ass()
    end
end

--update the selected item based on the mouse position
function cursor.update_mouse_pos(_, mouse_pos)
    if not o.mouse_mode or g.state.hidden or #g.state.list == 0 then return end

    if not mouse_pos then mouse_pos = mp.get_property_native("mouse-pos", {}) end
    if not mouse_pos.hover then return end
    msg.trace('received mouse pos:', utils.to_string(mouse_pos))

    local scale = mp.get_property_number("osd-height", 0) / g.ass.res_y
    local osd_offset = scale * mp.get_property("osd-margin-y", 22)

    local font_size_body = g.BASE_FONT_SIZE
    local font_size_header = g.BASE_FONT_SIZE * o.scaling_factor_header
    local font_size_wrappers = g.BASE_FONT_SIZE * o.scaling_factor_wrappers

    msg.trace('calculating mouse pos for', g.state.osd_alignment, 'alignment')

    --calculate position when browser is aligned to the top of the screen
    if g.state.osd_alignment == "top" then
        local header_offset = osd_offset + (2 * scale * font_size_header) + (g.state.scroll_offset > 0 and (scale * font_size_wrappers) or 0)
        msg.trace('calculated header offset', header_offset)

        g.state.selected = math.ceil((mouse_pos.y-header_offset) / (scale * font_size_body)) + g.state.scroll_offset

    --calculate position when browser is aligned to the bottom of the screen
    --this calculation is slightly off when a bottom wrapper exists,
    --I do not know what causes this.
    elseif g.state.osd_alignment == "bottom" then
        mouse_pos.y = (mp.get_property_number("osd-height", 0)) - mouse_pos.y

        local bottom = math.min(#g.state.list, g.state.scroll_offset + o.num_entries)
        local footer_offset = (2 * scale * font_size_wrappers) + osd_offset
        msg.trace('calculated footer offset', footer_offset)

        g.state.selected = bottom - math.floor((mouse_pos.y - footer_offset) / (scale * font_size_body))
    end

    ass.update_ass()
end

-- scrolls the view window when using mouse mode
function cursor.wheel(direction)
    g.state.scroll_offset = g.state.scroll_offset + direction
    if (g.state.scroll_offset + o.num_entries) > #g.state.list then
        g.state.scroll_offset = #g.state.list - o.num_entries
    end
    if g.state.scroll_offset < 0 then
        g.state.scroll_offset = 0
    end
    cursor.update_mouse_pos()
end

return cursor
