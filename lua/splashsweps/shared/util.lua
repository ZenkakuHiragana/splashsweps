
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

---Indicates the Z-offset direction of associated vertex of the ink mesh.
---@alias ss.LIFT_TYPE
---| `ss.LIFT_NONE`
---| `ss.LIFT_UP`
---| `ss.LIFT_DOWN`
ss.LIFT_DOWN = 0 ---@type ss.LIFT_TYPE Indicating the vertex has negative offset along the surface normal.
ss.LIFT_NONE = 1 ---@type ss.LIFT_TYPE Indicating the vertex has no offset along the surface normal.
ss.LIFT_UP   = 2 ---@type ss.LIFT_TYPE Indicating the vertex has positive offset along the surface normal.

---Type of triangle of the ink mesh.
---@alias ss.TRI_TYPE
---| `ss.TRI_CEIL`
---| `ss.TRI_DEPTH`
---| `ss.TRI_BASE`
---| `ss.TRI_SIDE_IN`
---| `ss.TRI_SIDE_OUT`
ss.TRI_CEIL     = 0 ---@type ss.TRI_TYPE Indicating the triangle acts like the ceiling of the mesh proxy.
ss.TRI_DEPTH    = 1 ---@type ss.TRI_TYPE Indicating the triangle is beneath the base surface to show curved shape on the sides.
ss.TRI_BASE     = 2 ---@type ss.TRI_TYPE Indicating the triangle is on the base surface.
ss.TRI_SIDE_IN  = 3 ---@type ss.TRI_TYPE Indicating the triangle is part of the side mesh facing inside the mesh.
ss.TRI_SIDE_OUT = 4 ---@type ss.TRI_TYPE Indicating the triangle is part of the side mesh facing outside the mesh.
ss.TRI_MAX      = 4 ---Maximum number of TRI_TYPE.

---Composes two numbers describing the triangle type of the mesh
---(base surface, side mesh, etc.) and
---indicator to lift up/down the vertices.
---@param triangleType ss.TRI_TYPE  The triangle type.
---@param liftType     ss.LIFT_TYPE The lift type.
---@return integer     composed     The composed number stored in the cache file.
function ss.ComposeMeshType(triangleType, liftType)
    return bit.bor(bit.lshift(triangleType, 2), liftType)
end

---Decomposes the parameter from cache file to obtain two values stored in it.
---@param param integer The parameter composed by `ss.ComposeMeshType`.
---@return ss.TRI_TYPE  triangleType
---@return ss.LIFT_TYPE liftType
function ss.DecomposeMeshType(param)
    local triangleType = bit.rshift(param, 2) ---@type ss.TRI_TYPE
    local liftType     = bit.band(param, 3) ---@type ss.LIFT_TYPE
    return triangleType, liftType
end
