
local g = require 'modules.globals'
local fb_utils = require 'modules.utils'
local directory_movement = require 'modules.navigation.directory-movement'

local observers ={}

--saves the directory and name of the currently playing file
function observers.current_directory(_, filepath)
    directory_movement.set_current_file(filepath)
end

function observers.dvd_device(_, device)
    if not device or device == "" then device = "/dev/dvd/" end
    g.dvd_device = fb_utils.fix_path(device, true)
end

return observers
