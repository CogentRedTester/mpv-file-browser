local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    --root directories
    root = "~/",

    --characters to use as separators
    root_separators = ",;",

    --number of entries to show on the screen at once
    num_entries = 20,

    --wrap the cursor around the top and bottom of the list
    wrap = false,

    --only show files compatible with mpv
    filter_files = true,

    --experimental feature that recurses directories concurrently when
    --appending items to the playlist
    concurrent_recursion = false,

    --maximum number of recursions that can run concurrently
    max_concurrency = 16,

    --enable custom keybinds
    custom_keybinds = false,

    --blacklist compatible files, it's recommended to use this rather than to edit the
    --compatible list directly. A semicolon separated list of extensions without spaces
    extension_blacklist = "",

    --add extra file extensions
    extension_whitelist = "",

    --files with these extensions will be added as additional audio tracks for the current file instead of appended to the playlist
    audio_extensions = "mka,dts,dtshd,dts-hd,truehd,true-hd",

    --files with these extensions will be added as additional subtitle tracks instead of appended to the playlist
    subtitle_extensions = "etf,etf8,utf-8,idx,sub,srt,rt,ssa,ass,mks,vtt,sup,scc,smi,lrc,pgs",

    --filter dot directories like .config
    --most useful on linux systems
    filter_dot_dirs = false,
    filter_dot_files = false,

    --substitude forward slashes for backslashes when appending a local file to the playlist
    --potentially useful on windows systems
    substitute_backslash = false,

    --this option reverses the behaviour of the alt+ENTER keybind
    --when disabled the keybind is required to enable autoload for the file
    --when enabled the keybind disables autoload for the file
    autoload = false,

    --if autoload is triggered by selecting the currently playing file, then
    --the current file will have it's watch-later config saved before being closed
    --essentially the current file will not be restarted
    autoload_save_current = true,

    --when opening the browser in idle mode prefer the current working directory over the root
    --note that the working directory is set as the 'current' directory regardless, so `home` will
    --move the browser there even if this option is set to false
    default_to_working_directory = false,

    --allows custom icons be set to fix incompatabilities with some fonts
    --the `\h` character is a hard space to add padding between the symbol and the text
    folder_icon = "🖿",
    cursor_icon = "➤",
    indent_icon = [[\h\h\h]],

    --enable addons
    addons = false,
    addon_directory = "~~/script-modules/file-browser-addons",

    --directory to load external modules - currently just user-input-module
    module_directory = "~~/script-modules",

    --turn the OSC idle screen off and on when opening and closing the browser
    toggle_idlescreen = false,

    --Set the current open status of the browser in the `file_browser/open` field of the `user-data` property.
    --This property is only available in mpv v0.36+.
    set_user_data = true,

    --Set the current open status of the browser in the `file_browser-open` field of the `shared-script-properties` property.
    --This property is deprecated. When it is removed in mpv v0.37 file-browser will automatically ignore this option.
    set_shared_script_properties = true,

    --force file-browser to use a specific text alignment (default: top-left)
    --uses ass tag alignment numbers: https://aegi.vmoe.info/docs/3.0/ASS_Tags/#index23h3
    --set to 0 to use the default mpv osd-align options
    alignment = 7,

    --style settings
    font_bold_header = true,
    font_opacity_selection_marker = "99",

    font_size_header = 35,
    font_size_body = 25,
    font_size_wrappers = 16,

    font_name_header = "",
    font_name_body = "",
    font_name_wrappers = "",
    font_name_folder = "",
    font_name_cursor = "",

    font_colour_header = "00ccff",
    font_colour_body = "ffffff",
    font_colour_wrappers = "00ccff",
    font_colour_cursor = "00ccff",

    font_colour_multiselect = "fcad88",
    font_colour_selected = "fce788",
    font_colour_playing = "33ff66",
    font_colour_playing_multiselected = "22b547"

}

opt.read_options(o, 'file_browser')

o.set_shared_script_properties = o.set_shared_script_properties and utils.shared_script_property_set

return o
