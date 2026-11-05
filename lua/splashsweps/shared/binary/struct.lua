
-- Definitions of binary structures, which BinaryReader reads and BinaryWriter writes by their names.

---@class ss
local ss = SplashSWEPs

---@class ss.BinaryStructModule
local BinaryStruct = ss.module "splashsweps/shared/binary/struct"

---Structure definition to read binary data from a string reader and write it to a File.
---@class ss.BinaryStruct.Definition
---@field [integer] string
---@field Read (fun(self: ss.BinaryStruct.Definition, binary: ss.BinaryReader.StringReader, ...: any): table)? Special function to read this structure.
---@field Write (fun(self: ss.BinaryStruct.Definition, binary: File, value: table, ...: any))? Special function to write this structure.
---@field Size integer? The total size of this structure.

---Defined binary structures, filled when the defining files are loaded.
local definitions = ss.state("splashsweps/shared/binary/struct", {}) ---@type table<string, ss.BinaryStruct.Definition>

---Defines a binary structure, which BinaryReader.Read reads and BinaryWriter.Write writes by its name.
---```lua
---BinaryStruct.Define "BSP.EDGES" { "UShort nil 2", Size = 2 + 2 }
---```
---@param typename string The name of binary structure
---@return fun(definition: ss.BinaryStruct.Definition)
function BinaryStruct.Define(typename)
    return function(definition)
        definitions[typename] = definition
    end
end

---Returns the binary structure defined with the name.
---@generic T
---@param typename ss.BinaryStruct.`T` The name of binary structure
---@return ss.BinaryStruct.Definition?
function BinaryStruct.Find(typename)
    return definitions[typename]
end

---Fields of each structure definition split into type, key, and array size.
---Reading and writing run for every element of an array, so the split is cached per definition.
local fieldsOf = setmetatable({}, { __mode = "k" }) ---@type table<ss.BinaryStruct.Definition, string[][]>

---Returns the fields of a structure definition, each split into type, key, and array size.
---@param definition ss.BinaryStruct.Definition
---@return string[][]
function BinaryStruct.GetFields(definition)
    local fields = fieldsOf[definition]
    if not fields then
        fields = {}
        for i, varstring in ipairs(definition) do
            fields[i] = string.Explode(" +", varstring, true)
        end
        fieldsOf[definition] = fields
    end

    return fields
end


---A field of a structure definition, with its key and its array size interpreted.
---@class ss.BinaryStruct.Field
---@field TypeName   string
---@field Key        string?  The key of the field, or nil to put the values after the previous ones by position.
---@field Count      integer? The number of the elements of an array of a fixed size.
---@field CountField string?  The key of the previous field that has the number of the elements.

---Fields of each structure definition interpreted, which are the same for every element of an array.
local layoutOf = setmetatable({}, { __mode = "k" }) ---@type table<ss.BinaryStruct.Definition, ss.BinaryStruct.Field[]>

---Returns the fields of a structure definition with their keys and their array sizes interpreted,
---which BinaryReader.Read and BinaryWriter.Write follow.
---A field is an array if it has Count or CountField, and a single value otherwise.
---@param definition ss.BinaryStruct.Definition
---@return ss.BinaryStruct.Field[]
function BinaryStruct.GetLayout(definition)
    local layout = layoutOf[definition]
    if layout then return layout end

    layout = {}
    for i, field in ipairs(BinaryStruct.GetFields(definition)) do
        local typename, key, size = field[1], field[2], field[3]
        local entry = { TypeName = typename } ---@type ss.BinaryStruct.Field
        if key ~= nil and key ~= "" and key ~= "nil" then
            entry.Key = key
        end

        if size ~= nil and size ~= "" then
            local count = tonumber(size)
            if not count then
                entry.CountField = size
            elseif count > 1 then
                entry.Count = count
            end
        end

        layout[i] = entry
    end

    layoutOf[definition] = layout
    return layout
end
return BinaryStruct
