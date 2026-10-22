
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Utility constant number which represents really close to zero.
ss.eps = 1e-16

---Utility constant vector where all the elements are 1.0.
ss.vector_one = Vector(1, 1, 1)

---Perform dot product to make any color monotone
ss.GrayScaleFactor = Vector(0.2126, 0.7152, 0.0722)

---Assert but this states that the error was thrown by this addon.
---@generic T
---@param v? T
---@param message? any
---@param ... any
---@return T
---@return any ...
function ss.assert(v, message, ...)
    return assert(v, "[SplashSWEPs] " .. (message or "Assertion failed!"), ...)
end

---Iterates through files under given path that matches given pattern recursively.
---@param root     string The root path to search from.
---@param path     string Same as the second argument of file.Find.
---@param pattern? string Optional wildcard pattern.
---@return fun(): string
function ss.IterateFilesRecursive(root, path, pattern)
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
function ss.MinVector(a, b)
    return Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
end

---Compares each component and returns the larger one.
---@param a Vector Vector to compare
---@param b Vector Vector to compare
---@return Vector # Vector containing larger components
function ss.MaxVector(a, b)
    return Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

---Calculates AABB in another coordinate system containing given AABB.
---@param m    VMatrix Transformation to the target coordinate system.
---@param mins Vector  AABB minimum.
---@param maxs Vector  AABB maximum.
---@return Vector mins AABB minimum in the target coordinate system.
---@return Vector maxs AABB maximum in the target coordinate system.
function ss.TransformAABB(m, mins, maxs)
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
