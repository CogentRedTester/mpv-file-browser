local g = require 'modules.globals'
local directory_movement = require 'modules.navigation.directory-movement'
local fb = require 'modules.apis.fb'
local fb_utils = require 'modules.utils'
local ass = require 'modules.ass'

---@class observers
local observers ={}

---saves the directory and name of the currently playing file
---@param _ string
---@param filepath string
function observers.current_directory(_, filepath)
    directory_movement.set_current_file(filepath)
end

---@param property string
---@param alignment string
function observers.osd_align(property, alignment)
    if property == 'osd-align-x' then g.ALIGN_X = alignment
    elseif property == 'osd-align-y' then g.ALIGN_Y = alignment end

    g.style.global = ([[{\an%d}]]):format(g.ASS_ALIGNMENT_MATRIX[g.ALIGN_Y][g.ALIGN_X])
    ass.update_ass()
end

return observers
