# mpv-file-browser

![cover](screenshots/bunny.png)

This script allows users to browse and open files and folders entirely from within mpv. The script uses nothing outside the mpv API, so should work identically on all platforms. The browser can move up and down directories, start playing files and folders, or add them to the queue.

By default only file types compatible with mpv will be shown, but this can be changed in the config file.

This script requires [mpv-scroll-list](https://github.com/CogentRedTester/mpv-scroll-list) to work, simply place `scroll-list.lua` into the `~~/scripts` folder.

## Keybinds
The following keybind is set by default

    MENU            toggles the browser

The following keybinds are only set while the browser is open:

    ESC             closes the browser or clears the selection
    ENTER           plays the currently selected file or folder
    Shift+ENTER     appends the current file or folder to the playlist
    Alt+ENTER       loads playlist entries before and after the selected file (like autoload.lua)
    DOWN            move selector down the list
    UP              move selector up the list
    RIGHT           enter the currently selected directory
    LEFT            move to the parent directory
    HOME            move to the directory of the currently playing file
    Shift+HOME      move to the root directory
    Ctrl+r          reload directory and reset cache
    s               toggles multiselect mode
    S               toggles selection for the current item

When attempting to play or append a subtitle file the script will instead load the subtitle track into the existing video.

The behaviour of the autoload keybind can be reversed with the `autoload` script-opt.
By default the playlist will only be autoloaded if `Alt+ENTER` is used on a single file, however when the option is switched autoload will always be used on single files *unless* `Alt+ENTER` is used. Using autoload on a directory, or while appending an item, will not work.

## Root Directory
To accomodate for both windows and linux this script has its own virtual root directory where drives and file folders can be manually added. This can also be used to save favourite directories. The root directory can only contain folders.

The root directory is set using the `root` option, which is a comma separated list of directories. Entries are sent through mpv's `expand-path` command. By default the only root value is the user's home folder:

`root=~/`

It is highly recommended that this be customised for the computer being used; [file_browser.conf](file_browser.conf) contains commented out suggestions for generic linux and windows systems. For example, my windows root looks like:

`root=~/,C:/,D:/,E:/,Z:/`

## Multi-Select
By default file-browser only opens/appends the single item that the cursor has selected.
However, using the `s` keybinds specified above, it is possible to select multiple items to open all at once. Selected items are shown in a different colour to the cursor.
When in multiselect mode the cursor changes colour and scrolling up and down the list will drag the current selection. If the original item was unselected, then dragging will select items, if the original item was selected, then dragging will unselect items.

When multiple items are selected using the open or append commands will add all selected files to the playlist in the order they appear on the screen.
The currently selected (with the cursor) file will be ignored, instead the first multi-selected item in the folder will follow replace/append behaviour as normal, and following selected items will be appended to the playlist afterwards in the order that they appear on the screen.

## Custom Keybinds
File-browser also supports custom keybinds. These keybinds send normal input commands, but the script will substitute characters in the command strings for specific values depending on the currently open directory, and currently selected item.
This allows for a wide range of customised behaviour, such as loading additional audio tracks from the browser, or copying the path of the selected item to the clipboard.

The feature is disabled by default, but is enabled with the `custom_keybinds` script-opt.
Keybinds are declared in the `~~/script-opts/file-browser-keybinds.json` file, the config takes the form of an array of json objects, with the following keys:

    key             the key to bind the command to - same syntax as input.conf
    command         a json array of commands and arguments
    filter          optional - run the command on just a file or folder
    multiselect     optional - command is run on all commands selected (default true)

Example:
```
{
    "key": "KP1",
    "command": ["print-text", "example"],
    "filter": "file"
}
```

The command can also be an array of arrays, in order to send multiple commands at once:
```
{
    "key": "KP2",
    "command": [
        ["print-text", "example2"],
        ["show-text", "example2"]
    ],
    "multiselect": false
}
```

Filter should not be included unless one wants to limit what types of list entries the command should be run on.
To only run the command for directories use `dir`, to only run the command for files use `file`.

The script will scan every string in the command for the special substitution strings, they are:

    %f      filepath of the selected item
    %n      name of the selected item (what appears on the list)
    %p      currently open directory
    %d      name of the current directory (characters between the last two '/')
    %%      escape the previous codes

Additionally, using the uppercase forms of those codes will send the substituted string through the `string.format("%q", str)` function.
This adds double quotes around the string and automatically escapes any quotation marks within the string.
This is not necessary for most mpv commands, but can be very useful when sending commands to the console with the `run` command.

Example of a command to add an audio track:

```
{
    "key": "Alt+ENTER",
    "command": ["audio-add", "%f"],
    "filter": "file"
}
```

When multiple items are selected the command will be run on every item in the order they appear on the screen.
This can be controlled by the `multiselect` flag, which takes a boolean value.
When not set the flag defaults to `true`.

Examples can be found [here](/file-browser-keybinds.json).

## Add-ons
Add-ons are extra scripts that add parsing support for non-native filesystems.
They can be enabled by loading the add-on script normally and enabling the corresponding `script-opt`.

Browsing filesystems provided by add-ons should feel identical to the normal handling of the script,
but they may require extra commandline tools be installed.

### [http-browser](addons/http-browser.lua)
This add-on implements support for http/https file servers, specifically the directory indexes that apache servers dynamically generate.
I don't know if this will work on different types of servers.

Requires `curl` in the system PATH.

### [ftp-browser](addons/ftp-browser.lua)
Implements support for ftp file servers. Requires `curl` in the system path.

### [dvd-browser](https://github.com/CogentRedTester/mpv-dvd-browser)
This script implements support for DVD titles using the `lsdvd` commandline utility.
When playing a dvd, or when moving into the `--dvd-device` directory, the add-on loads up the DVD titles.

This add-on is a little different from the others; dvd-browser is actually standalone, and has a number of other dvd related features that don't
require the browser at all to make DVD playback more enjoyable, such as automatic playlist management.

It also has it's own, more limitted, browser, but overwriting the default keybind to open file-browser instead effectively disables it.
Both scripts use `MENU` as the default toggle command, so it will be necessary to explicitly specify which to use by putting `MENU script-binding browse-files` in input.conf.

Note that `lsdvd` is only available on linux, but the script has special support for WSL on windows 10.

## Configuration
See [file_browser.conf](file_browser.conf) for the full list of options and their default values.
