
-- Small utilities used everywhere.

---@class ss
local ss = SplashSWEPs

---@class ss.Util
local Util = ss.module "splashsweps/shared/util"

---Utility constant number which represents really close to zero.
Util.eps = 1e-16

---Utility constant vector where all the elements are 1.0.
Util.vector_one = Vector(1, 1, 1)

---Assert but this states that the error was thrown by this addon.
---@generic T
---@param v? T
---@param message? any
---@param ... any
---@return T
---@return any ...
function Util.assert(v, message, ...)
    return assert(v, "[SplashSWEPs] " .. (message or "Assertion failed!"), ...)
end

---Iterates through files under given path that matches given pattern recursively.
---@param root     string The root path to search from.
---@param path     string Same as the second argument of file.Find.
---@param pattern? string Optional wildcard pattern.
---@return fun(): string
function Util.IterateFilesRecursive(root, path, pattern)
    pattern = pattern and pattern:gsub("%*", ".*")
    return coroutine.wrap(function()
        ---The iterator.
        ---@param name string Current path to search for.
        local function iterate(name)
            if not name:EndsWith("/") then name = name .. "/" end
            local files, directories = file.Find(name .. "*", path)
            for _, fileName in ipairs(files or {}) do
                if not pattern or fileName:match(pattern) then
                    coroutine.yield(name .. fileName)
                end
            end

            for _, dirName in ipairs(directories or {}) do
                iterate(name .. dirName)
            end
        end

        iterate(root)
    end)
end

---Performs a deep copy for given table.
---Metatable will not be deep-copied.
---@generic T: table<any, any>
---@param t T|table<any, any>?
---@param lookup table<any, any>?
---@return T?
function Util.deepcopy(t, lookup)
    if t == nil then return nil end

    ---@type table<any, any>
    local copy = setmetatable({}, getmetatable(t))
    for k, v in pairs(t) do
        if istable(v) then
            lookup = lookup or {}
            lookup[t] = copy
            if lookup[v] then
                copy[k] = lookup[v]
            else
                copy[k] = Util.deepcopy(v, lookup)
            end
        elseif isvector(v) then
            copy[k] = Vector(v)
        elseif isangle(v) then
            copy[k] = Angle(v)
        elseif ismatrix(v) then
            copy[k] = Matrix(v)
        else
            copy[k] = v
        end
    end

    return copy
end

return Util
