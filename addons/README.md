# How to Write an Addon

Addons provide ways for file-browser to parse non-native directory structures. This document describes how one can create their own custom addon. For examples see [ftp-browser](ftp-browser.lua) and [http-browser](http-browser.lua).

#### Terminology
For the purpose of this document addons refer to the scripts being loaded while parsers are the objects the scripts return. However, these terms are practically synonymous.
Additionally, `method` refer to functions called using the `object:funct()` syntax, and hence have access to the self object, whereas `function` is the standard `object.funct()` syntax.

## Overview

File-browser automatically loads any lua files from the `~~/script-modules/file-browser-addons` directory as modules. Each addon must return an object with the following three members:

| key       | type   | arguments | returns                          | description                                                                                                                 |
|-----------|--------|-----------|----------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| priority  | number | -         | -                                | a number to determine what order parsers are tested - 50 is a recommended neutral value                                     |
| can_parse | method | string    | boolean                          | returns whether or not the given path is compatible with the parser                                                         |
| parse     | method | string    | list_table, boolean, boolean     | returns an array of item_tables, and bools representing whether the list has already been filtered and sorted, respectively |

When a directory is loaded file-browser will iterate through the list of parsers from lowest to highest priority.
The first parser for which `can_parse` returns true will be selected as the parser for that directory.

The `parse` method will then be called on the selected parser, which is expected to return either a table of list items, or nil.
If nil is returned, then the browser will attempt to load the directory from the next parser for which `can_parse` return true, otherwise if an empty table is returned the browser will treat the directory as empty.
To be specific file-browser doesn't call parse directly, it calls the `parse_or_defer` method, as described in the [below](#utility-functions) table.

Additionally, parse can return two values after the list; these values will be evaluated into booleans, and will be used to determine if the output of the parser requires additional filtering and sorting, respectively.
This can be useful if you choose to filter or sort the script yourself, or if the directory does not conform to standard filesystem rules (such as dvd-browser).
Otherwise, the two extra return values can be excluded and file-browser will automatically filter and sort everything according to user preferences.

## The List Array

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
The API function `fix_path` (see next section) can be used to ensure that paths conform to file-browser rules.

## API Functions

All parsers are provided with a range of API functions to make addons more powerful.
These functions are added to the parser after being loaded via a metatable, so can be called through the self argument or the parser object.
These functions are only made available once file-browser has fully imported the parsers, so if a script wants to call them immediately on load they must do so in the `setup` method.

### Utility Functions

| key           | type     | arguments        | returns                 | description                                                                                                                                            |
|---------------|----------|------------------|-------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| setup         | method   | -                | -                       | a function that is automatically run once the parsers have been imported - this function is not set by default, and must instead be created by addons. |
| parse_or_defer| method   | string           | table, boolean, boolean | returns parse(string) or, if nil is returned, run again on the next valid parser - this is what file-browser uses to scan directories                  |
| fix_path      | function | string, boolean  | string                  | takes a path and an is_directory boolean and returns a corrected path                                                                                  |
| ass_escape    | function | string           | string                  | returns the string with escaped ass styling codes                                                                                                      |
| get_extension | function | string           | string                  | returns the file extension of the given file                                                                                                           |
| valid_file    | function | string           | boolean                 | tests if the given filename passes the user set filters (valid extensions and dot files)                                                               |
| valid_dir     | function | string           | boolean                 | tests if the given directory name passes the user set filters (dot directories)                                                                        |
| filter        | function | list_table       | list_table              | iterates through the given list and removes items that don't pass the filters - acts directly on the given list, it does not create a copy             |
| sort          | function | list_table       | list_table              | iterates through the given list and sorts the items using file-browsers sorting algorithm - acts directly on the given list, it does not create a copy |

### Getters and Setters
These functions allow addons to safely get information from file-browser, as well as set some useful values.
All tables returned by these functions are copies to ensure addons can't break things.

Note that the parse function is also run when appending directories to the playlist, so only set values when the requested directory is the one being loaded (use `get_directory()`).

| key                 | type     | arguments | returns | description                                                                                                           |
|---------------------|----------|-----------|---------|-----------------------------------------------------------------------------------------------------------------------|
| set_directory_label | function | string    | -       | set an alternative directory string to print to the header - useful to replace encoded paths                          |
| set_empty_text      | function | string    | -       | set alternative text to display when directory is empty - can also be used for error messages                         |
| set_selected_index  | function | number    | -       | set the current position of the cursor                                                                                |
| get_script_opts     | function | -         | table   | the table of script opts set by the user - this never gets changed during runtime                                     |
| get_extensions      | function | -         | table   | a set of valid extensions after applying the user's whitelist/blacklist - in the form {ext1 = true, ext2 = true, ...} |
| get_sub_extensions  | function | -         | table   | like above but with subtitle extensions - note that subtitles show up in the above list as well                       |
| get_parsers         | function | -         | table   | an array of the loaded parsers                                                                                        |
| get_dvd_device      | function | -         | string  | the current dvd-device - formatted to work with file-browser                                                          |
| get_directory       | function | -         | string  | the current directory open in the browser - formatted to work with file-browser                                       |
| get_current_file    | function | -         | table   | a table containing the path of the current open file - in the form {directory = "", name = ""}                        |
| get_current_parser  | function | -         | string  | the string name of the current parser - as used by custom keybinds                                                    |
| get_selected_index  | function | -         | number  | the current index of the cursor                                                                                       |
| get_state           | function | -         | table   | the current state values of the browser - this is probably useless                                                    |
