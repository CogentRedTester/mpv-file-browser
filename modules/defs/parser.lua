---@meta ParserDefs

---A ParserConfig object returned by addons
---@class ParserConfig
---@field priority number
---@field api_version string    The minimum API version the string requires.
---@field version string?        The minimum API version the string requires. @deprecated.
---
---@field can_parse (fun(self: Parser, directory: string, parse_state: ParseState): boolean)?
---@field parse (fun(self: Parser, directory: string, parse_state: ParseState): List?, Opts?)?
---@field setup fun(self: Parser)?
---
---@field name string?
---@field keybind_name string?
---@field keybinds Keybind[]?


---The parser object used by file-browser once the parsers have been loaded and initialised.
---@class Parser: ParserConfig, ParserAPI
---@field name string
---@field can_parse fun(self: Parser, directory: string, parse_state: ParseState): boolean
---@field parse fun(self: Parser, directory: string, parse_state: ParseState): List?, Opts?


---The Parse State object passed to the can_parse and parse methods
---@class ParseState: ParseStateAPI
---@field source 'browser'|'loadlist'|'script-message'|'addon'|string
---@field directory string
---@field already_deferred boolean?
---@field yield fun(self: ParseState, ...:unknown): ...