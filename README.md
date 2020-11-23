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
    DOWN            move selector down the list
    UP              move selector up the list
    RIGHT           enter the currently selected directory
    LEFT            move to the parent directory
    HOME            move to the directory of the currently playing file
    Shift+HOME      move to the root directory
    Ctrl+r          reload directory and reset cache
    Ctrl+ENTER      toggle selection for the current item
    Ctrl+RIGHT      select current item
    Ctrl+LEFT       deselect current item
    Ctrl+DOWN       drag selection down
    Ctrl+UP         drag selection up

## Root Directory
To accomodate for both windows and linux this script has its own virtual root directory where drives and file folders can be manually added. This can also be used to save favourite directories. The root directory can only contain folders.

The root directory is set using the `root` option, which is a semicolon separated list of directories. Entries are sent through mpv's `expand-path` command. By default the only root value is the user's home folder:

`root=~/`

It is highly recommended that this be customised for the computer being used; [file_browser.conf](file_browser.conf) contains commented out suggestions for generic linux and windows systems. For example, my windows root looks like:

`root=~/;C:/;D:/;E:/;Z:/`

## Multi-Select
By default file-browser only opens/appends the single item that the cursor has selected. However, using the `Ctrl` keybinds specified above, it is possible to select multiple items to open all at once. Selected items are shown in a different colour to the cursor. When multiple items are selected, they will be appended after the currently selected file when using the ENTER commands. The currently selected (with the cursor) file will always be added first, regardless of if it is part of the multi-selection, and will follow replace/append behaviour as normal. Selected items will be appended to the playlist afterwards in the order that they appear on the screen.

## Add-ons
Add-ons are extra scripts that add parsing support for non-native filesystems.
They can be enabled by loading the add-on script normally and enabling the corresponding `script-opt`.

Browsing filesystems provided by add-ons should feel identical to the normal handling of the script.

### http-browser
This add-on implements support for http/https file servers, specifically the directory indexes that apache servers dynamically generate.
I don't know if this will work on different types of servers.

Requires `curl` in the system PATH.

### ftp-browser
Planned

### [DVD Browser](https://github.com/CogentRedTester/mpv-dvd-browser)
This add-on is a little different from the others. dvd-browser is actually standalone, and has a number of other dvd related features that don't
require the browser at all. However, there is a compatability mode that makes it act a lot like a normal addon.

The script uses the `lsdvd` commandline utility to read and display the titles of DVDs in an interractive browser extremely similar to this one.
The script also has numerous options to make DVD playback more enjoyable, such as automatic playlist management.

To enable compatability mode enable the option `dvd_browser` in `file_browser.conf`, and the associated `file_browser` option in `dvd_browser.conf`.
When both scripts are active attempting to enter the `--dvd-device` directory will automatically pass control to dvd-browser.
Similarly, moving up a directory from dvd-browser will pass control back to file-browser.
It is also important to always use the file-browser activation keybind. Both scripts use `MENU` as the default toggle command, so it will be necessary to explicitly specify which to use by putting `MENU script-binding browse-files` in input.conf.



With the exception of the multi-select behaviour all file-browser keybinds should work from within dvd-browser, and with identical behaviour. 

Note: unlike file-browser, dvd-browser only works on Linux or WSL

## Configuration
See [file_browser.conf](file_browser.conf) for the full list of options and their default values.
