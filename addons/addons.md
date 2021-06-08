# How to Write an Addon

Addons provide ways for file-browser to parse non-native directory structures. This document describes how one can create their own custom addon.

## Terminology

For the purpose of this document addons refer to the scripts being loaded while parsers are the objects the scripts return.
An addon can return multiple parsers, but when they only returns one the terms are almost synonymous.
Additionally, `method` refers to functions called using the `object:funct()` syntax, and hence have access to the self object, whereas `function` is the standard `object.funct()` syntax.

## Overview

File-browser automatically loads any lua files from the `~~/script-modules/file-browser-addons` directory as modules.
Each addon must return either a single parser table, or an array of parser tables.
Each parser object must contain the following three members:

| key       | type   | arguments | returns                    | description                                                                                                                 |
|-----------|--------|-----------|----------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| priority  | number | -         | -                          | a number to determine what order parsers are tested - see [here](#priority-suggestions) for suggested values                |
| can_parse | method | string    | boolean                    | returns whether or not the given path is compatible with the parser                                                         |
| parse     | method | string    | list_table, opts_table     | returns an array of item_tables, and a table of options to control how file_browser handles the list                        |

Additionally, each parser can optionally contain:

| key   | type   | arguments | returns | description                                                                                                                            |
|-------|--------|-----------|---------|----------------------------------------------------------------------------------------------------------------------------------------|
| name  | string | -         | -       | the name of the parser used for custom keybinds filters and codes - by default uses the filename with `.lua` or `-browser.lua` removed |
| setup | method | -         | -       | If it exists this method is automatically run after all parsers are imported and API functions are made available                      |

## Parsing

When a directory is loaded file-browser will iterate through the list of parsers from lowest to highest priority.
The first parser for which `can_parse` returns true will be selected as the parser for that directory.

The `parse` method will then be called on the selected parser, which is expected to return either a table of list items, or nil.
If an empty table is returned then file-browser will treat the directory as empty, otherwise if the list_table is nil then file-browser will attempt to run `parse` on the next parser for which `can_parse` returns true.
This continues until a parser returns a list_table, or until there are no more parsers, after which the root is loaded instead.

### The List Array

The list array must be made up of item_tables, which contain details about each item in the directory.
Each item has the following members:

| key   | type   | required | description                                                                               |
|-------|--------|----------|-------------------------------------------------------------------------------------------|
| name  | string | yes      | name of the item, and the string to append after the directory when opening a file/folder |
| type  | string | yes      | determines whether the item is a file ("file") or directory ("dir")                       |
| label | string | no       | an alternative string to print to the screen instead of name                              |
| ass   | string | no       | a string to print to the screen without escaping ass styling - overrides label and name   |
| path  | string | no       | opening the item uses this full path instead of appending directory and name              |

File-browser expects that `type` and `name` will be set for each item, so leaving these out will probably crash the script.
File-browser also assumes that all directories end in a `/` when appending name, and that there will be no backslashes.
The API function [`fix_path`](#Utility-Functions) can be used to ensure that paths conform to file-browser rules.

### The Opts Table

The options table allows scripts to better control how they are handled by file-browser.
None of these values are required, and the opts table can even left as nil when returning.

| key             | type    | description                                                                                                                               |
|-----------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------|
| filtered        | boolean | if true file-browser will not run the standard filter() function on the list                                                              |
| sorted          | boolean | if true file-browser will not sort the list                                                                                               |
| directory       | string  | changes the browser directory to this - used for redirecting to other locations                                                           |
| directory_label | string  | display this label in the header instead of the actual directory - useful to display encoded paths                                        |
| empty_text      | string  | display this text when the list is empty - can be used for error messages                                                                 |
| selected_index  | number  | the index of the item on the list to select by default - a.k.a. the cursor position                                                       |
| already_deferred| boolean | whether or not [defer](#Utility-Functions) was used to create the list, if so then give up if list is nil - set automatically, but can be manually disabled   |
| index           | number  | index of the parser that successfully returns a list - set automatically, but can be set manually to take ownership                       |

`already_deferred` is an optimisation. If a script uses defer and still returns nil, then that means that none of the remaining parsers will be able to parse the path.
Therefore, it is more efficient to just immediately jump to the root.
It is up to the addon author to manually disable this if their use of `defer` conflicts with this assumption.

`index` is used to declare ownership of a page. The name of the parser that has ownership is used for custom-keybinds parser filtering.
When using `defer` index will be the index of whichever parser first returned a list.
This is the only situation when a parser may want to set index manually.

## Priority Suggestions

Below is a table of suggested priority ranges:

| Range  | Suggested Use                                                                                                              | Example parsers                                |
|--------|----------------------------------------------------------------------------------------------------------------------------|------------------------------------------------|
| 0-20   | parsers that purely modify the results of other parsers                                                                    | [m3u-fixer](m3u-browser.lua)                   |
| 21-40  | virtual filesystems which need to link to the results of other parsers                                                     | [favourites](favourites.lua)                   |
| 41-50  | to support specific sites or systems which can be inferred from the path                                                   |                                                |
| 51-80  | limitted support for specific protocols which requires complex parsing to verify compatability                             | [apache](apache-browser.lua)                       |
| 81-90  | parsers that only need to modify the results of full parsers                                                               | [home-label](home-label.lua)                   |
| 91-100 | use for parsers which fully support a non-native protocol with absolutely no overlap                                       | [ftp](ftp-browser.lua), [m3u](m3u-browser.lua) |
| 101-109| replacements for the native file parser or fallbacks for the full parsers                                                  | [powershell](powershell.lua)                   |
| 110    | priority of the native file parser - don't use                                                                             |                                                |
| 111+   | fallbacks for native parser - potentially alternatives to the default root                                                 |                                                |

## API Functions

All parsers are provided with a range of API functions to make addons more powerful.
These functions are added to the parser after being loaded via a metatable, so can be called through the self argument or the parser object.
These functions are only made available once file-browser has fully imported the parsers, so if a script wants to call them immediately on load they must do so in the `setup` method.

| key                          | type     | arguments                    | returns | description                                                                                                              |
|------------------------------|----------|------------------------------|---------|--------------------------------------------------------------------------------------------------------------------------|
| register_parseable_extension | function | string                       | -       | register a file extension that the browser will attempt to open, like a directory - for addons which can parse files     |
| remove_parseable_extension   | function | string                       | -       | remove a file extension that the browser will attempt to open like a directory                                           |
| insert_root_item             | method   | item_table, number(optional) | -       | add an item_table (must be a directory) to the root list at the specified position - if number is nil then append to end |

### Advanced Functions

| key           | type     | arguments        | returns                 | description                                                                                                                                            |
|---------------|----------|------------------|-------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| defer         | method   | string           | list_table, opts_table  | forwards the given directory to the next valid parser - can be used to redirect the browser or to modify the results of lower priority parsers         |

### Utility Functions

| key           | type     | arguments        | returns                 | description                                                                                                                                            |
|---------------|----------|------------------|-------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| fix_path      | function | string, boolean  | string                  | takes a path and an is_directory boolean and returns a corrected path                                                                                  |
| join_path     | function | string, string   | string                  | a wrapper for mp.utils.join_path which adds support for network protocols                                                                              |
| ass_escape    | function | string           | string                  | returns the string with escaped ass styling codes                                                                                                      |
| get_extension | function | string           | string                  | returns the file extension of the given file - returns nil if file has no extension                                                                    |
| get_protocol  | function | string           | string                  | returns the protocol scheme of the given url (https, ftp, etc) - returns nil if path has no url scheme                                                 |
| valid_file    | function | string           | boolean                 | tests if the given filename passes the user set filters (valid extensions and dot files)                                                               |
| valid_dir     | function | string           | boolean                 | tests if the given directory name passes the user set filters (dot directories)                                                                        |
| filter        | function | list_table       | list_table              | iterates through the given list and removes items that don't pass the filters - acts directly on the given list, it does not create a copy             |
| sort          | function | list_table       | list_table              | iterates through the given list and sorts the items using file-browsers sorting algorithm - acts directly on the given list, it does not create a copy |

### Getters

These functions allow addons to safely get information from file-browser.
All tables returned by these functions are copies to ensure addons can't break things.

| key                 | type     | arguments | returns | description                                                                                                           |
|---------------------|----------|-----------|---------|-----------------------------------------------------------------------------------------------------------------------|
| get_index           | method   | -         | number  | the index of the parser in order of preference                                                                        |
| get_script_opts     | function | -         | table   | the table of script opts set by the user - this never gets changed during runtime                                     |
| get_root            | function | -         | table   | the root table - an array of item_tables                                                                              |
| get_extensions      | function | -         | table   | a set of valid extensions after applying the user's whitelist/blacklist - in the form {ext1 = true, ext2 = true, ...} |
| get_sub_extensions  | function | -         | table   | like above but with subtitle extensions - note that subtitles show up in the above list as well                       |
| get_parsers         | function | -         | table   | an array of the loaded parsers                                                                                        |
| get_dvd_device      | function | -         | string  | the current dvd-device - formatted to work with file-browser                                                          |
| get_directory       | function | -         | string  | the current directory open in the browser - formatted to work with file-browser                                       |
| get_current_file    | function | -         | table   | a table containing the path of the current open file - in the form {directory = "", name = ""}                        |
| get_current_parser  | function | -         | string  | the string name of the parser used for the currently open directory - as used by custom keybinds                      |
| get_selected_index  | function | -         | number  | the current index of the cursor - if the list is empty this should return 1                                           |
| get_selected_item   | function | -         | table   | returns the item_table of the currently selected item - returns nil if no item is selected (empty list)               |
| get_open_status     | function | -         | boolean | returns true if the browser is currently open and false if not                                                        |
| get_state           | function | -         | table   | the current state values of the browser - this is probably useless                                                    |

## Examples

For standard addons that add support for non-native filesystems, but otherwise don't do anything fancy, see [ftp-browser](ftp-browser.lua) and [apache-browser](apache-browser.lua).

For more simple addons that make a few small modifications to how other parsers are displayed, see [home-label](home-label.lua).

For more complex addons that maintain their own virtual directory structure, see
[favourites](favourites.lua).
