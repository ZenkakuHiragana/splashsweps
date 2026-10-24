
-- Module loader
--
-- A module file declares itself with `local M = ss.module "<its name>"` and ends with `return M`.
-- Its name is the slash-separated path under lua/ without the extension.
-- Nothing here checks these rules at runtime.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local locals = ss.Locals ---@class ss.Locals
if not locals.Import then
    ---State of the module loader, kept across hot reloads.
    ---@class ss.Locals.Import
    ---@field Exports table<string, table> Module name --> table the module file returned.
    ---@field Tables  table<string, table> Module name --> table given by ss.module, reused on hot reload.
    ---@field States  table<string, table> Module name --> table given by ss.state, reused on hot reload.
    locals.Import = {
        Exports = {},
        Tables = {},
        States = {},
    }
end

local Import = locals.Import

---Loads a module and returns the table its file returned, which is `ss.module(name)`.
---The file `lua/<name>.lua` is executed only on the first import in this Lua state.
---
---LuaLS treats this function as `require` (see runtime.special in .luarc.*.json),
---so the returned value has the type of what the file returns.
---
---Do not copy fields of an imported module into locals when the file is loaded.
---Hot reload updates the module table in place, and copied locals would keep the old values.
---@param name string Module name such as "splashsweps/shared/struct".
---@return table
function ss.import(name)
    local exports = Import.Exports[name]
    if exports == nil then
        exports = include(name .. ".lua")
        Import.Exports[name] = exports
    end

    return exports
end

---Returns the table a module file fills and returns.
---The same table is returned for the same name in this Lua state,
---so hot reloading the file updates the table that other files already hold.
---@param name string Module name of the calling file, same as the one passed to ss.import.
---@return table
function ss.module(name)
    local t = Import.Tables[name]
    if not t then
        t = {}
        Import.Tables[name] = t
    end

    return t
end

---Returns the table a module keeps its private state in, which survives hot reload.
---The given table becomes the state on the first call for the name in this Lua state.
---Later calls, such as the ones by hot reload, return that state and ignore the given table,
---so fields added to the given table take effect after the Lua state restarts, e.g. a map change.
---@generic T: table
---@param name string Module name of the calling file, same as the one passed to ss.module.
---@param initial T The initial state.
---@return T
function ss.state(name, initial)
    local t = Import.States[name]
    if not t then
        t = initial
        Import.States[name] = t
    end

    return t
end
