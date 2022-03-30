# How to Write an Addon - API v1.0.0

Addons provide ways for file-browser to parse non-native directory structures. This document describes how one can create their own custom addon.

If you have an independent script but want to use file-browser's parsing capabilities, perhaps to make use of existing addons, then look [here](https://github.com/CogentRedTester/mpv-file-browser#get-directory-contents).

## Terminology

For the purpose of this document addons refer to the scripts being loaded while parsers are the objects the scripts return.
An addon can return multiple parsers, but when they only returns one the terms are almost synonymous.
Additionally, `method` refers to functions called using the `object:funct()` syntax, and hence have access to the self object, whereas `function` is the standard `object.funct()` syntax.

## API Version

The API version, shown in the title of this document, allows file-browser to ensure that addons are using the correct
version of the API. It follows [semantic versioning](https://semver.org/) conventions of `MAJOR.MINOR.PATCH`.
A parser sets its version string with the `version` field, as seen [below](#overview).

Any change that breaks backwards compatability will cause the major version number to increase.
A parser MUST have the same version number as the API, otherwise an error message will be printed and the parser will
not be loaded.

A minor version number denotes a change to the API that is backwards compatible. This includes additional API functions,
or extra fields in tables that were previously unused. It may also include additional arguments to existing functions that
add additional behaviour without changing the old behaviour.
If the parser's minor version number is greater than the API_VERSION, then a warning is printed to the console.

Patch numbers denote bug fixes, and are ignored when loading an addon.
For this reason addon authors are allowed to leave the patch number out of their version tag and just use `MAJOR.MINOR`.

## Overview

File-browser automatically loads any lua files from the `~~/script-modules/file-browser-addons` directory as modules.
Each addon must return either a single parser table, or an array of parser tables. Each parser object must contain the following three members:

| key       | type   | arguments | returns                    | description                                                                                                |
|-----------|--------|-----------|----------------------------|------------------------------------------------------------------------------------------------------------|
| priority  | number | -         | -                        | a number to determine what order parsers are tested - see [here](#priority-suggestions) for suggested values |
| version   | string | -         | -                        | the API version the parser is using - see [API Version](#api-version)                                        |
| can_parse | method | string    | boolean                    | returns whether or not the given path is compatible with the parser                                        |
| parse     | method | string, parser_state_table | list_table, opts_table | returns an array of item_tables, and a table of options to control how file_browser handles the list |

Additionally, each parser can optionally contain:

| key           | type   | arguments | returns | description                                                                                                                                                     |
|---------------|--------|-----------|---------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| name          | string | -         | -       | the name of the parser used for debug messages and to create a unique id - by default uses the filename with `.lua` or `-browser.lua` removed                   |
| keybind_name  | string | -         | -       | the name to use when setting custom keybind filters - uses the value of name by default but can be set manually so that the same keys work with multiple addons |
| setup         | method | -         | -       | if it exists this method is automatically run after all parsers are imported and API functions are made available                                               |
| keybinds      | table  | -         | -       | an array of keybind objects for the browser to set when loading - see [#keybinds]                                                                               |

All parsers are given a unique string ID based on their name. If there are collisions then numbers are appended to the end of the name until a free name is found.
These IDs are primarily used for debug messages, though they may gain additional functionality in the future.

Here is an extremely simple example of an addon creating a parser table and returning it to file-browser.

```lua
local parser = {
    priority = 100,
    name = "example"        -- this parser will have the id 'example' or 'example_#' if there are duplicates
}

function parser:can_parse(directory)
    return directory == "Example/"
end

function parser:parse(directory, state)
    local list, opts
    ------------------------------
    --- populate the list here ---
    ------------------------------
    return list, opts
end

return parser

```

## Parsing

When a directory is loaded file-browser will iterate through the list of parsers from lowest to highest priority.
The first parser for which `can_parse` returns true will be selected as the parser for that directory.

The `parse` method will then be called on the selected parser, which is expected to return either a table of list items, or nil.
If an empty table is returned then file-browser will treat the directory as empty, otherwise if the list_table is nil then file-browser will attempt to run `parse` on the next parser for which `can_parse` returns true.
This continues until a parser returns a list_table, or until there are no more parsers, after which the root is loaded instead.

The entire parse operation is run inside of a coroutine, this allows parsers to pause execution to handle asynchronous operations.
Please read [coroutines](#coroutines) for all the details.

### Parse State Table

The `parse` function is passed a state table as its second argument, this contains the following fields.

| key    | type   | description                                   |
|--------|--------|-----------------------------------------------|
| source | string | the source of the parse request               |
| directory | string | the directory of the parse request - for debugging purposes |
| yield  | method | a wrapper around `coroutine.yield()` - see [coroutines](#coroutines) |
| is_coroutine_current | method | returns if the browser is waiting on the current coroutine to populate the list |

Source can have the following values:

| source         | description                                                     |
|----------------|-----------------------------------------------------------------|
| browser        | triggered by the main browser window                            |
| loadlist       | the browser is scanning the directory to append to the playlist |
| script-message | triggered by the `get-directory-contents` script-message        |
| addon          | caused by an addon calling the `scan_directory` API function - note that addons can set a custom state |

Note that all calls to any `parse` function during a specific parse request will be given the same parse_state table.
This theoretically allows parsers to communicate with parsers of a lower priority (or modify how they see source information),
but no guarantees are made that specific keys will remain unused by the API.

#### Coroutines

Any calls to `parse()` (or `can_parse()`, but you should never be yielding inside there) are done in a [Lua coroutine](https://www.lua.org/manual/5.1/manual.html#2.11).
This means that you can arbitrarily pause the parse operation if you need to wait for some asynchronous operation to complete,
such as waiting for user input, or for a network request to complete.

Making these operations asynchronous has performance
advantages as well, for example recursively opening a network directory tree could cause the browser to freeze
for a long period of time. If the network query were asynchronous then the browser would only freeze during actual operations,
during network operations it would be free for the user interract with. The browser has even been designed so that
a loadfile/loadlist operation saves it's own copy of the current directory, so even if the user hops around like crazy the original
open operation will still occur in the correct order (though there's nothing stopping them starting a new operation which will cause
random ordering.)

However, there is one downside to this behaviour. If the parse operation is requested by the browser, then it is
possible for the user to change directories while the coroutine is yielded. If you were to resume the coroutine
in that situation, then any operations you do are wasted, and unexpected bahaviour could happen.
file-browser will automatically detect when it receives a list from an aborted coroutine, so there is no risk
of the current list being replaced, but any other logic in your script will continue until `parse` returns.

To fix this there are two methods available in the state table, the `yield()` method is a wrapper around `coroutine.yield()` that
detects when the browser has abandoned the parse, and automatically kills the coroutine by throwing an error.
The `is_coroutine_current()` method simply compares if the current coroutine (as returned by `coroutine.current()`) matches the
coroutine that the browser is waiting for. Remember this is only a problem when the browser is the source of the request,
if the request came from a script-message, or from a loadlist command there are no issues.

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

Here is an example of a static list table being returned by the `parse` method.
This would allow one to specify a custom list of items.

```lua
function parser:parse(directory, state)
    local list = {
        { name = "first/", type = "dir" },
        { name = "second/", type = "dir" },
        { name = "third/", type = "dir" },
        { name = "file%01", type = "file", label = "file1" },
        { name = "file2", type = "file", path = "https://youtube.com/video" },
    }

    return list
end
```

### The Opts Table

The options table allows scripts to better control how they are handled by file-browser.
None of these values are required, and the opts table can even left as nil when returning.

| key             | type    | description                                                                                                                               |
|-----------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------|
| filtered        | boolean | if true file-browser will not run the standard filter() function on the list                                                              |
| sorted          | boolean | if true file-browser will not sort the list                                                                                               |
| directory       | string  | **[deprecated]** - ges the browser directory to this - used for redirecting to other locations                                            |
| directory_label | string  | display this label in the header instead of the actual directory - useful to display encoded paths                                        |
| empty_text      | string  | display this text when the list is empty - can be used for error messages                                                                 |
| selected_index  | number  | the index of the item on the list to select by default - a.k.a. the cursor position                                                       |
| already_deferred| boolean | whether or not [defer](#Advanced-Functions) was used to create the list, if so then give up if list is nil - set automatically, but can be manually disabled |
| id              | number  | id of the parser that successfully returns a list - set automatically, but can be set manually to take ownership (see defer)              |

The previous static example, but modified so that file browser does not try to filter or re-order the list:

```lua
function parser:parse(directory, state)
    local list = {
        { name = "first/", type = "dir" },
        { name = "second/", type = "dir" },
        { name = "third/", type = "dir" },
        { name = "file%01", type = "file", label = "file1" },
        { name = "file2", type = "file", path = "https://youtube.com/video" },
    }

    return list, { sorted = true, filtered = true }
end
```

`already_deferred` is an optimisation. If a script uses defer and still returns nil, then that means that none of the remaining parsers will be able to parse the path.
Therefore, it is more efficient to just immediately jump to the root.
It is up to the addon author to manually disable this if their use of `defer` conflicts with this assumption.

`id` is used to declare ownership of a page. The name of the parser that has ownership is used for custom-keybinds parser filtering.
When using `defer` id will be the id of whichever parser first returned a list.
This is the only situation when a parser may want to set id manually.

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

## Keybinds

Addons have the ability to set custom keybinds using the `keybinds` field in the `parser` table. `keybinds` must be an array of tables, each of which may be in two forms.

Firstly, the keybind_table may be in the form
`{ "key", "name", [function], [flags] }`
where the table is an array whose four values corresond to the four arguments for the [mp.add_key_binding](https://mpv.io/manual/master/#lua-scripting-[,flags]]\)) API function.

```lua
local function main(keybind, state, co)
    -- deletes files
end

parser.keybinds = {
    { "Alt+DEL", "delete_files", main, {} },
}
```

Secondly, the keybind_table may use the same formatting as file-browser's [custom-keybinds](../custom-keybinds.md).
Using the array form is equivalent to setting `key`, `name`, `command`, and `flags` of the custom-keybind form, and leaving everything else on the defaults.

```lua
parser.keybinds = {
    {
        key = "Alt+DEL",
        name = "delete_files",
        command = {"run", "rm", "%F"},
        filter = "files"
    }
}
```

These keybinds are evaluated only once shortly after the addon is loaded, they cannot be modified dynamically during runtime.
Keybinds are applied after the default keybinds, but before the custom keybinds. This means that addons can overwrite the
default keybinds, but that users can ovewrite addon keybinds. Among addons, those with higher priority numbers have their keybinds loaded before those
with lower priority numbers.
Remember that a lower priority value is better, they will overwrite already loaded keybinds.
Keybind passthrough works the same way, though there is some custom behaviour when it comes to [raw functions](#keybind-functions).

### Keybind Names

In either form the naming of the function is different from custom keybinds. Instead of using the form `file_browser/dynamic/custom/[name]`
they use the form `file_browser/dynamic/[parser_ID]/[name]`, where `[parser_id]` is a unique string ID for the parser, which can be retrieved using the
`parser:get_id()` method.

### Native Functions vs Command Tables

There are two ways of specifying the behaviour of a keybind.
In the array form, the 3rd argument is a function to be executed, and in the custom-keybind form the `command` field is a table of mpv input commands to run.

These two ways of specifying commands are independant of how the overall keybind is defined.
What this means is that the command field of the custom-keybinds syntax can be an array, and the
3rd value in the array syntax can be a table of mpv commands.

```lua
local function main(keybind, state, co)
    -- deletes files
end

-- this is a valid keybind table
parser.keybinds = {
    { "Alt+DEL", "delete_files", {"run", "rm", "%F"}, {} },

    {
        key = "Alt+DEL",
        name = "delete_files",
        command = main,
        filter = "files"
    }
}
```

### Keybind Functions

This section details the use of keybind functions.

#### Function Call

If one uses the raw function then the functions are called directly in the form:

`fn(keybind, state, coroutine)`

Where `keybind` is the keybind_table of the key being run, `state` is a table of state values at the time of the key press, and `coroutine` is the coroutine object
that the keybind is being executed inside.

The `keybind` table uses the same fields as defined
in [custom-keybinds.md](../custom-keybinds.md). Any random extra fields placed in the original
`file-browser-keybinds.json` will likely show up as well (this is not guaranteed).
Note that even if the array form is used, the `keybind` table will still use the custom-keybind format.

The entire process of running a keybind is handled with a coroutine, so the addon can safely pause and resume the coroutine at will. The `state` table is provided to
allow addons to keep a record of important state values that may be changed during a paused coroutine.

#### State Table

The state table contains copies of the following values at the time of the key press.

| key             | description                                                                              |
|-----------------|------------------------------------------------------------------------------------------|
| directory       | the current directory                                                                    |
| directory_label | the current directory_label - can (and often will) be `nil`                              |
| list            | the current list_table                                                                   |
| selected        | index of the currently selected list item                                                |
| selection       | table of currently selected items (for multi-select) - in the form { index = true, ... } - always available even if the `multiselect` flag is not set |
| parser          | a copy of the parser object that provided the current directory                          |

The following example shows the implementation of the `delete_files` keybind using the state values:

```lua
local fb = require "file-browser"       -- see #api-functions and #utility-functions

local function main(keybind, state, co)
    for index, item in state.list do
        if state.selection[index] and item.type == "file" then
            os.remove( fb.get_full_path(item, state.directory) )
        end
    end
end

parser.keybinds = {
    { "Alt+DEL", "delete_files", main, {} },
}
```

#### Passthrough

If the `passthrough` field of the keybind_table is set to `true` or `false` then file-browser will
handle everything. However, if the passthrough field is not set (meaning the bahviour should be automatic)
then it is up to the addon to ensure that they are
correctly notifying when the operation failed and a passthrough should occur.
In order to tell the keybind handler to run the next priority command, the keybind function simply needs to return the value `false`,
any other value (including `nil`) will be treated as a successful operation.

The below example only allows removing files from the `/tmp/` directory and allows other
keybinds to run in different directories:

```lua
local fb = require "file-browser"       -- see #api-functions and #utility-functions

local function main(keybind, state, co)
    if state.directory ~= "/tmp/" then return false end

    for index, item in state.list do
        if state.selection[index] and item.type == "file" then
            os.remove( fb.get_full_path(item, state.directory) )
        end
    end
end

parser.keybinds = {
    { "Alt+DEL", "delete_files", main, {} },
}
```

## The API

The API is available through a module, which can be loaded with `require "file-browser"`.
The API provides a variety of different values and functions for an addon to use
in order to make them more powerful.

```lua
local fb = require "file-browser"

local parser = {
    priority = 100,
}

function parser:setup()
    fb.insert_root_item({ name = "Example/", type = "dir" })
end

return parser
```

### Parser API

In addition to the standard API there is also an extra parser API that provides
several parser specific methods,
labeled `method` below instead of `function`. This API is added to the parser
object after it is loaded by file-browser,
so if a script wants to call them immediately on load they must do so in the `setup` method.
All the standard API functions are also available in the parser API.

```lua
local parser = {
    priority = 100,
}

function parser:setup()
    -- same operations
    self.insert_root_item({ name = "Example/", type = "dir" })
    parser.insert_root_item({ name = "Example/", type = "dir" })
end

-- will not work since the API hasn't been added to the parser yet
parser.insert_root_item({ name = "Example/", type = "dir" })

return parser
```

### General Functions

| key                          | type     | arguments                    | returns | description                                                                                                              |
|------------------------------|----------|------------------------------|---------|--------------------------------------------------------------------------------------------------------------------------|
| API_VERSION                  | string   | -                            | -       | the current API version in use                                                                                           |
| register_parseable_extension | function | string                       | -       | register a file extension that the browser will attempt to open, like a directory - for addons which can parse files     |
| remove_parseable_extension   | function | string                       | -       | remove a file extension that the browser will attempt to open like a directory                                           |
| add_default_extension        | function | string                       | -       | adds the given extension to the default extension filter whitelist - can only be run inside setup()                      |
| insert_root_item             | function | item_table, number(optional) | -       | add an item_table (must be a directory) to the root list at the specified position - if number is nil then append to end |
| browse_directory             | function | string                       | -       | clears the cache and opens the given directory in the browser - if the browser is closed then open it                    |
| update_directory             | function |                              | -       | rescans the current directory - equivalent to Ctrl+r without the cache refresh for higher level directories              |
| clear_cache                  | function |                              | -       | clears the cache - use if modifying the contents of higher level directories                                             |
| scan_directory               | function | string, parser_state_table | list_table, opts_table       | starts a new scan for the given directory - note that all parsers are called as normal, so beware infinite recursion     |

Note that the `scan_directory()` function must be called from inside a [coroutine](#coroutines).

### Advanced Functions

| key           | type     | arguments        | returns                 | description                     |
|---------------|----------|------------------|-------------------------|---------------------------------|
| defer         | method   | string | list_table, opts_table  | forwards the given directory to the next valid parser - can be used to redirect the browser or to modify the results of lower priority parsers |

#### Using `defer`

The `defer` function is very powerful, and can be used by scripts to create virtual directories, or to modify the results of other parsers.
However, due to how much freedom Lua gives coders, it is impossible for file-browser to ensure that parsers are using defer correctly, which can cause unexpected results.
The following are a list of recommendations that will increase the compatability with other parsers:

* Always pass all arguments from `parse` into `defer`, using Lua's variable arguments `...` can be a good way to future proof this against any future API changes.
* Always return the opts table that is returned by defer, this can contain important values for file-browser, as described [above](#The-Opts-Table).
  * If required modify values in the existing opts table, don't create a new one.
* Respect the `sorted` and `filtered` values in the opts table. This may mean calling `sort` or `filter` manually.
* Think about how to handle the `directory_label` field, especially how it might interract with any virtual paths the parser may be maintaining.
* Think about what to do if the `directory` field is set. This field is deprecated, so you could probably get away with not handling this.
* Think if you want your parser to take full ownership of the results of `defer`, if so consider setting `opts.id = self:get_id()`.
  * Currently this only affects custom keybind filtering, though it may be changed in the future.

The [home-label](https://github.com/CogentRedTester/mpv-file-browser/blob/master/addons/home-label.lua)
addon provides a good simple example of the safe use of defer. It lets the normal file
parser load the home directory, then modifies the directory label.

```lua
local mp = require "mp"
local fb = require "file-browser"

local home = fb.fix_path(mp.command_native({"expand-path", "~/"}), true)

local home_label = {
    priority = 100
}

function home_label:can_parse(directory)
    return directory:sub(1, home:len()) == home
end

function home_label:parse(directory, ...)
    local list, opts = self:defer(directory, ...)

    if (not opts.directory or opts.directory == directory) and not opts.directory_label then
        opts.directory_label = "~/"..(directory:sub(home:len()+1) or "")
    end

    return list, opts
end

return home_label
```

### Utility Functions

| key           | type     | arguments        | returns    | description                                                                                                                                            |
|---------------|----------|------------------|------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| fix_path      | function | string, boolean  | string     | takes a path and an is_directory boolean and returns a file-browser compatible path                                                                    |
| join_path     | function | string, string   | string     | a wrapper for `mp.utils.join_path` which adds support for network protocols                                                                            |
| get_full_path | function | item_table, string | string   | returns the full path of a given item for a given directory - takes into account item.name/item.path, etc                                              |
| ass_escape    | function | string, string   | string     | returns the string with escaped ass styling codes - the 2nd argument allows optionally replacing newlines with the given string, or `\n` if set to `true`|
| pattern_escape| function | string           | string     | returns the string with special lua pattern characters escaped                                                                                         |
| get_extension | function | string, def      | string     | returns the file extension of the given file - returns def if file has no extension                                                                    |
| get_protocol  | function | string, def      | string     | returns the protocol scheme of the given url (https, ftp, etc) - returns def if path has no url scheme                                                 |
| valid_file    | function | string           | boolean    | tests if the given filename passes the user set filters (valid extensions and dot files)                                                               |
| valid_dir     | function | string           | boolean    | tests if the given directory name passes the user set filters (dot directories)                                                                        |
| filter        | function | list_table       | list_table | iterates through the given list and removes items that don't pass the filters - acts directly on the given list, it does not create a copy             |
| sort          | function | list_table       | list_table | iterates through the given list and sorts the items using file-browsers sorting algorithm - acts directly on the given list, it does not create a copy |
| copy_table    | function | table            | table      | recursively makes a deep copy of the given table and returns it, maintaining any cyclical references                                                   |

### Getters

These functions allow addons to safely get information from file-browser.
All tables returned by these functions are copies to ensure addons can't break things.

| key                        | type     | arguments | returns | description                                                                                                           |
|----------------------------|----------|-----------|---------|-----------------------------------------------------------------------------------------------------------------------|
| get_id                     | method   | -         | number  | the unique id of the parser - used internally to set ownership of list results for cutom-keybind filtering            |
| get_index                  | method   | -         | number  | the index of the parser in order of preference - `defer` uses this internally                                         |
| get_script_opts            | function | -         | table   | the table of script opts set by the user - this never gets changed during runtime                                     |
| get_root                   | function | -         | table   | the root table - an array of item_tables                                                                              |
| get_extensions             | function | -         | table   | a set of valid extensions after applying the user's whitelist/blacklist - in the form {ext1 = true, ext2 = true, ...} |
| get_sub_extensions         | function | -         | table   | like above but with subtitle extensions - note that subtitles show up in the above list as well                       |
| get_parseable_extensions   | function | -         | table   | shows parseable file extensions in the same format as the above functions                                             |
| get_parsers                | function | -         | table   | an array of the loaded parsers                                                                                        |
| get_dvd_device             | function | -         | string  | the current dvd-device - formatted to work with file-browser                                                          |
| get_directory              | function | -         | string  | the current directory open in the browser - formatted to work with file-browser                                       |
| get_list                   | function | -         | table   | the list_table for the currently open directory                                                                       |
| get_current_file           | function | -         | table   | a table containing the path of the current open file - in the form {directory = "", name = "", path = ""}             |
| get_current_parser         | function | -         | string  | the unique id of the parser used for the currently open directory                                                     |
| get_current_parser_keyname | function | -         | string  | the string name of the parser used for the currently open directory - as used by custom keybinds                      |
| get_selected_index         | function | -         | number  | the current index of the cursor - if the list is empty this should return 1                                           |
| get_selected_item          | function | -         | table   | returns the item_table of the currently selected item - returns nil if no item is selected (empty list)               |
| get_open_status            | function | -         | boolean | returns true if the browser is currently open and false if not                                                        |
| get_state                  | function | -         | table   | the current state values of the browser - not documented and subject to change at any time - adding a proper getter for anything is a valid request |

### Setters

| key                        | type     | arguments | returns | description                                                                                                           |
|----------------------------|----------|-----------|---------|-----------------------------------------------------------------------------------------------------------------------|
| set_selected_index         | function | -         | number or bool  | sets the cursor position - if the position is not a number return false, if the position is out of bounds move it in bounds, returns the new index |

## Examples

For standard addons that add support for non-native filesystems, but otherwise don't do anything fancy, see [ftp-browser](ftp-browser.lua) and [apache-browser](apache-browser.lua).

For more simple addons that make a few small modifications to how other parsers are displayed, see [home-label](home-label.lua).

For more complex addons that maintain their own virtual directory structure, see
[favourites](favourites.lua).
