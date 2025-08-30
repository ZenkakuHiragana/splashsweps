
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.StructDefinitions then
    locals.StructDefinitions = {}
end

---Struct templates are stored here
---@type table<string, table>
local StructDefinitions = locals.StructDefinitions
local getmetatable = getmetatable
local isangle = isangle
local ismatrix = ismatrix
local istable = istable
local isvector = isvector
local pairs = pairs
local setmetatable = setmetatable
local Vector = Vector
local Angle = Angle
local Matrix = Matrix

---Performs a deep copy for given table.
---@generic T: table<any, any>
---@param t T|table<any, any>?
---@param lookup table<any, any>?
---@return T?
local function deepcopy(t, lookup)
    if t == nil then return nil end

    ---@type table<any, any>
    local copy = setmetatable({}, deepcopy(getmetatable(t)))
    for k, v in pairs(t) do
        if istable(v) then
            lookup = lookup or {}
            lookup[t] = copy
            if lookup[v] then
                copy[k] = lookup[v]
            else
                copy[k] = deepcopy(v, lookup)
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

ss.deepcopy = deepcopy

---Binds a constructor for struct typename
---@generic T
---@param typename ss.`T`
---@return fun(ctor: fun(this: T, ...))
function ss.ctor(typename)
    local meta = getmetatable(StructDefinitions[typename]) or {}
    ---Registers the constructor for struct typename
    ---@generic T
    ---@param ctor fun(this: T, ...)
    return function(ctor)
        meta.__call = function(this, ...)
            ctor(this, ...)
            return this
        end
        setmetatable(StructDefinitions[typename], meta)
    end
end

---Returns a new instance of struct typename.
---@generic T
---@param typename ss.`T`
---@return T
function ss.new(typename)
    return deepcopy(StructDefinitions[typename])
end

---Defines structure template.
---@generic T
---@param typename ss.`T` The name of structure
---@return fun(definition: T)
function ss.struct(typename)
    return function(definition)
        StructDefinitions[typename] = definition
    end
end
