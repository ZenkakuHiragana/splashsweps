
-- Reads values and structures from binary files such as BSP and VTF.

---@class ss
local ss = SplashSWEPs

---@class ss.BinaryReader
local Binary = ss.module "splashsweps/shared/binary/reader"

---Structure definition to read binary data in a File.
---@class ss.BinaryStructureDefinition
---@field [integer] string
---@field Read (fun(self: ss.BinaryStructureDefinition, binary: File, ...: any): table)? Special function to read this structure.
---@field Size integer? The total size of this structure.

---Defined binary structures, filled when the defining files are loaded.
local definitions = ss.state("splashsweps/shared/binary/reader", {}) ---@type table<string, ss.BinaryStructureDefinition>

---Defines a binary structure, which Binary.Read reads by its name.
---```lua
---Binary.struct "BSP.EDGES" { "UShort nil 2", Size = 2 + 2 }
---```
---@param typename string The name of binary structure
---@return fun(definition: ss.BinaryStructureDefinition)
function Binary.struct(typename)
    return function(definition)
        definitions[typename] = definition
    end
end

---Returns the binary structure defined with the name.
---@generic T
---@param typename ss.Binary.`T` The name of binary structure
---@return ss.BinaryStructureDefinition?
function Binary.Find(typename)
    return definitions[typename]
end

---Fields of each structure definition split into type, key, and array size.
---Read runs for every element of a lump, so the split is cached per definition.
local fieldsOf = setmetatable({}, { __mode = "k" }) ---@type table<ss.BinaryStructureDefinition, string[][]>

---Returns the fields of a structure definition, each split into type, key, and array size.
---@param definition ss.BinaryStructureDefinition
---@return string[][]
local function getFields(definition)
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

---Read a value or structure from given binary file.
---The offset should correctly be set before call by binary:Seek().
---arg should be one of the following:
---  - Number for `File:Read(%d)`
---  - String for one of these:
---    - a call of `File:Read%s()`, e.g. `Long`, `Float`
---    - Additional built-in types: `Vector`, `ShortVector`, `LongVector`, `Angle`, or `SByte` (signed byte)
---    - `String` for null-terminated string
---    - `String%d` for a null-terminated string but padded to `%d` bytes.
---    - Structure name defined by Binary.struct "T"
---  - Table representing a structure
---    Table containing a sequence of strings formatted as
---    `<type> <fieldname> <array amount (optional)>`
---    e.g. `Vector normal`, `Byte fourCC 4`
---    Array amount can be a field name previously defined in the same structure.
---    e.g. `{ "Long edgeCount", "UShort edgeIndices edgeCount" }`
---@generic T : table
---@param binary File
---@param arg ss.Binary.`T`
---@param ... any Any parameters passed to special function to read.
---@return ss.Binary.`T`
---@overload fun(binary: File, arg: integer):       string
---@overload fun(binary: File, arg: "Bool"):        boolean
---@overload fun(binary: File, arg: "Byte"):        integer
---@overload fun(binary: File, arg: "Double"):      number
---@overload fun(binary: File, arg: "Float"):       number
---@overload fun(binary: File, arg: "Line"):        string
---@overload fun(binary: File, arg: "Long"):        integer
---@overload fun(binary: File, arg: "Short"):       integer
---@overload fun(binary: File, arg: "UInt64"):      integer
---@overload fun(binary: File, arg: "ULong"):       integer
---@overload fun(binary: File, arg: "UShort"):      integer
---@overload fun(binary: File, arg: "SByte"):       integer
---@overload fun(binary: File, arg: "Angle"):       Angle
---@overload fun(binary: File, arg: "Vector"):      Vector
---@overload fun(binary: File, arg: "ShortVector"): Vector
---@overload fun(binary: File, arg: "LongVector"):  Vector
---@overload fun(binary: File, arg: "String"):      string
function Binary.Read(binary, arg, ...)
    if isnumber(arg) then ---@cast arg integer
        return binary:Read(arg)
    elseif istable(arg) then ---@cast arg ss.BinaryStructureDefinition
        if arg.Read then
            return arg:Read(binary, ...)
        end

        ---@type table<string|integer, boolean|number|string|table|Angle|Vector?>
        local structure = {}
        for _, field in ipairs(getFields(arg)) do
            ---@type string, integer|string?, integer|string?
            local fieldType, fieldKey, arraySize = field[1], field[2], field[3]
            if fieldKey == nil or fieldKey == "" or fieldKey == "nil" then fieldKey = #structure + 1 end
            if arraySize == nil or arraySize == "" then arraySize = 1 end
            if isstring(arraySize) and structure[arraySize] or tonumber(arraySize) > 1 then
                arraySize = tonumber(structure[arraySize]) or tonumber(arraySize) or 0
                for i = 1, arraySize do
                    if isstring(fieldKey) then
                        ---@cast fieldKey string
                        ---@cast structure table<string, table[]>
                        structure[fieldKey] = structure[fieldKey] or {}
                        structure[fieldKey][i] = Binary.Read(binary, fieldType, ...)
                    else
                        ---@cast fieldKey integer
                        structure[fieldKey] = Binary.Read(binary, fieldType, ...)
                        fieldKey = fieldKey + 1
                    end
                end
            else
                structure[fieldKey] = Binary.Read(binary, fieldType, ...)
            end
        end
        return structure
    elseif isstring(arg) then ---@cast arg string
        if arg == "Angle" then
            local pitch = binary:ReadFloat()
            local yaw   = binary:ReadFloat()
            local roll  = binary:ReadFloat()
            return Angle(pitch, yaw, roll)
        elseif arg == "SByte" then
            local n = binary:ReadByte()
            return n - (n > 127 and 256 or 0)
        elseif arg == "ShortVector" then
            local x = binary:ReadShort()
            local y = binary:ReadShort()
            local z = binary:ReadShort()
            return Vector(x, y, z)
        elseif arg == "LongVector" then
            local x = binary:ReadLong()
            local y = binary:ReadLong()
            local z = binary:ReadLong()
            return Vector(x, y, z)
        elseif arg:StartsWith "String" then
            local str = ""
            local chr = Binary.Read(binary, 1)
            local fixedLength = tonumber(arg:sub(#"String" + 1))
            local MAX_STRING_LENGTH = fixedLength or 1024
            while chr and chr ~= "\x00" and #str < MAX_STRING_LENGTH + 1 do
                str = str .. chr
                chr = Binary.Read(binary, 1)
            end
            for _ = 1, (fixedLength or 0) - (#str + 1) do
                Binary.Read(binary, 1)
            end
            return str
        elseif arg == "Vector" then
            local x = binary:ReadFloat()
            local y = binary:ReadFloat()
            local z = binary:ReadFloat()
            return Vector(x, y, z)
        elseif isfunction(binary["Read" .. arg]) then
            return binary["Read" .. arg](binary)
        elseif tonumber(arg) then
            return binary:Read(tonumber(arg))
        elseif definitions[arg] and (#definitions[arg] > 0 or definitions[arg].Read) then
            return Binary.Read(binary, definitions[arg], ...)
        end
    end

    ErrorNoHalt(string.format(
        "SplashSWEPs/BinaryReader: Need a correct structure name\n"
        .. "    Structure name given: %s\n", tostring(arg)))
    return {}
end

return Binary
