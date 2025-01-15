
local g = require 'modules.globals'

--parser object for the root
--not inserted to the parser list as it has special behaviour
--it does get added to parsers under its ID to prevent confusing duplicates
local root_parser = {
    name = "root",
    priority = math.huge,
    api_version = '1.0.0',
}

function root_parser:can_parse(directory)
    return directory == ''
end

--we return the root directory exactly as setup
function root_parser:parse()
    return g.root, {
        sorted = true,
        filtered = true,
    }
end

return root_parser
