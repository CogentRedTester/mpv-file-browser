---@meta _

---@class Set<T>: {[T]: boolean}

---@class (exact) State
---@field list List
---@field selected number
---@field hidden boolean
---@field flag_update boolean
---@field keybinds KeybindTupleStrict[]?
---
---@field parser Parser?
---@field directory string?
---@field directory_label string?
---@field prev_directory string
---@field empty_text string
---@field co thread?
---
---@field multiselect_start number?
---@field initial_selection Set<number>?
---@field selection Set<number>?