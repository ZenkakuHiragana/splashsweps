
-- Module loader
--
-- A module file declares itself with `local M = ss.module "<its name>"` and ends with `return M`.
-- Its name is the slash-separated path under lua/ without the extension.
-- Nothing here checks these rules at runtime.

---@class ss
local ss = SplashSWEPs
if not ss then return end

if not ss.Loader then
    ---State of the module loader, kept across hot reloads.
    ---@class ss.Loader
    ---@field Exports table<string, table> Module name --> table the module file returned.
    ---@field Tables  table<string, table> Module name --> table given by ss.module, reused on hot reload.
    ---@field States  table<string, table> Module name --> table given by ss.state, reused on hot reload.
    ss.Loader = {
        Exports = {},
        Tables = {},
        States = {},
    }
end

local Loader = ss.Loader

---Loads a module and returns the table its file returned, which is `ss.module(name)`.
---The file `lua/<name>.lua` is executed only on the first import in this Lua state.
---
---LuaLS treats this function as `require` (see runtime.special in .luarc.*.json),
---so the returned value has the type of what the file returns.
---
---Do not copy fields of an imported module into locals when the file is loaded.
---Hot reload updates the module table in place, and copied locals would keep the old values.
---@param name string Module name such as "splashsweps/shared/util".
---@return table
function ss.import(name)
    local exports = Loader.Exports[name]
    if exports == nil then
        exports = include(name .. ".lua")
        Loader.Exports[name] = exports
    end

    return exports
end

---Returns the table a module file fills and returns.
---The same table is returned for the same name in this Lua state,
---so hot reloading the file updates the table that other files already hold.
---@param name string Module name of the calling file, same as the one passed to ss.import.
---@return table
function ss.module(name)
    local t = Loader.Tables[name]
    if not t then
        t = {}
        Loader.Tables[name] = t
    end

    return t
end

---Returns the table a module keeps its private state in, which survives hot reload.
---The given table becomes the state on the first call for the name in this Lua state.
---Later calls, such as the ones by hot reload, return that state and ignore the given table,
---so fields added to the given table take effect after the Lua state restarts, e.g. a map change.
---LuaLS types the state as the given table, so declare the class of the state right above the local
---to type its fields, e.g. `---@class ss.FooModule.State` and then `local state = ss.state(...)`,
---or annotate the local with `---@type` for a state that is not a class.
---@generic T: table
---@param name string Module name of the calling file, same as the one passed to ss.module.
---@param initial T The initial state.
---@return T
function ss.state(name, initial)
    local t = Loader.States[name]
    if not t then
        t = initial
        Loader.States[name] = t
    end

    return t
end
