
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

---Compares each component and returns the smaller one.
---@param a Vector Vector to compare
---@param b Vector Vector to compare
---@return Vector # Vector containing smaller components
function Util.MinVector(a, b)
    return Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
end

---Compares each component and returns the larger one.
---@param a Vector Vector to compare
---@param b Vector Vector to compare
---@return Vector # Vector containing larger components
function Util.MaxVector(a, b)
    return Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

---Calculates AABB in another coordinate system containing given AABB.
---@param m    VMatrix Transformation to the target coordinate system.
---@param mins Vector  AABB minimum.
---@param maxs Vector  AABB maximum.
---@return Vector mins AABB minimum in the target coordinate system.
---@return Vector maxs AABB maximum in the target coordinate system.
function Util.TransformAABB(m, mins, maxs)
    local center = m * ((mins + maxs) / 2)
    local halfExtent = (maxs - mins) / 2
    local function extent(i)
        return halfExtent.x * math.abs(m:GetField(i, 1))
             + halfExtent.y * math.abs(m:GetField(i, 2))
             + halfExtent.z * math.abs(m:GetField(i, 3))
    end

    local transformedHalfExtent = Vector(extent(1), extent(2), extent(3))
    return center - transformedHalfExtent, center + transformedHalfExtent
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
