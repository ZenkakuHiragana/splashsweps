
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Utility constant number which represents really close to zero.
ss.eps = 1e-16

---Utility constant vector where all the elements are 1.0.
ss.vector_one = Vector(1, 1, 1)

---Perform dot product to make any color monotone
ss.GrayScaleFactor = Vector(.298912, .586611, .114478)

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
    return coroutine.wrap(function()
        ---The iterator.
        ---@param name string Current path to search for.
        local function iterate(name)
            if not name:EndsWith("/") then name = name .. "/" end
            local files, directories = file.Find(name .. "*", path)
            for _, fileName in ipairs(files or {}) do
                if not pattern or fileName:find(pattern) then
                    coroutine.yield(name .. "/" .. fileName)
                end
            end

            for _, dirName in ipairs(directories or {}) do
                iterate(name .. "/" .. dirName)
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
