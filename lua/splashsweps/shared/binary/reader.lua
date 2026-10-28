
-- Reads values and structures from binary files such as BSP and VTF.

---@class ss
local ss = SplashSWEPs

---@class ss.BinaryReader
local Binary = ss.module "splashsweps/shared/binary/reader"

---Structure definition to read and write binary data in a File.
---@class ss.BinaryStructureDefinition
---@field [integer] string
---@field Read (fun(self: ss.BinaryStructureDefinition, binary: File|ss.BinaryStringReader, ...: any): table)? Special function to read this structure.
---@field Write (fun(self: ss.BinaryStructureDefinition, binary: File, value: table, ...: any))? Special function to write this structure.
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

---Reads little-endian values from a binary string with the methods of File that Binary.Read uses.
---Each read of File is costly however small it is,
---so large data is read as one string by a single File:Read and decoded here in Lua.
---@class ss.BinaryStringReader
---@field Data     string  The binary data.
---@field Position integer The position of the next byte to read, starting from 0 as File:Tell does.
local StringReader = {}
StringReader.__index = StringReader

local byte  = string.byte
local sub   = string.sub
local floor = math.floor
local ldexp = math.ldexp

---Moves the position by the size of a value and returns the position of the value.
---Reading past the end of the data is an error as there is no value to read.
---@param self ss.BinaryStringReader
---@param size integer
---@return integer
local function advance(self, size)
    local position = self.Position
    if position + size > #self.Data then
        error(string.format("SplashSWEPs/BinaryReader: reading %d bytes at %d past the end of %d bytes",
            size, position, #self.Data), 3)
    end

    self.Position = position + size
    return position
end

---@return integer
function StringReader:Tell()
    return self.Position
end

---@param position integer
function StringReader:Seek(position)
    self.Position = position
end

---@param amount integer
---@return integer amount
function StringReader:Skip(amount)
    self.Position = self.Position + amount
    return amount
end

---@return integer
function StringReader:Size()
    return #self.Data
end

---Reads the bytes as a string, or nil at the end of the data.
---@param length integer
---@return string?
function StringReader:Read(length)
    local position = self.Position
    if position >= #self.Data then return nil end
    self.Position = position + length
    return sub(self.Data, position + 1, position + length)
end

---@return integer
function StringReader:ReadByte()
    return byte(self.Data, advance(self, 1) + 1)
end

---@return boolean
function StringReader:ReadBool()
    return self:ReadByte() ~= 0
end

---@return integer
function StringReader:ReadUShort()
    local position = advance(self, 2)
    local b1, b2 = byte(self.Data, position + 1, position + 2)
    return b1 + b2 * 256
end

---@return integer
function StringReader:ReadShort()
    local n = self:ReadUShort()
    return n >= 32768 and n - 65536 or n
end

---@return integer
function StringReader:ReadULong()
    local position = advance(self, 4)
    local b1, b2, b3, b4 = byte(self.Data, position + 1, position + 4)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

---@return integer
function StringReader:ReadLong()
    local n = self:ReadULong()
    return n >= 2147483648 and n - 4294967296 or n
end

---Reads an IEEE 754 single precision number.
---The sign is the highest bit of the fourth byte, the exponent is the next 8 bits, and the mantissa is the other 23 bits.
---Lua numbers are doubles, so every single precision value is exact.
---@return number
function StringReader:ReadFloat()
    local position = advance(self, 4)
    local b1, b2, b3, b4 = byte(self.Data, position + 1, position + 4)
    local exponent = b4 % 128 * 2 + floor(b3 / 128)
    local mantissa = b3 % 128 * 65536 + b2 * 256 + b1
    local sign = b4 >= 128 and -1 or 1
    if exponent == 0 then
        return sign * ldexp(mantissa, -149) -- Zero and subnormal numbers
    elseif exponent == 255 then
        return mantissa == 0 and sign * math.huge or 0 / 0
    end

    return sign * ldexp(mantissa + 8388608, exponent - 150)
end

---Creates a reader at the beginning of the data, which Binary.Read accepts in place of File.
---@param data string
---@return ss.BinaryStringReader
function Binary.NewStringReader(data)
    return setmetatable({ Data = data, Position = 0 }, StringReader)
end

---Fields of each structure definition split into type, key, and array size.
---Reading and writing run for every element of an array, so the split is cached per definition.
local fieldsOf = setmetatable({}, { __mode = "k" }) ---@type table<ss.BinaryStructureDefinition, string[][]>

---Returns the fields of a structure definition, each split into type, key, and array size.
---@param definition ss.BinaryStructureDefinition
---@return string[][]
function Binary.GetFields(definition)
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

---Reads a null-terminated string, padded to fixedLength bytes if given.
---@param binary      File|ss.BinaryStringReader
---@param fixedLength integer?
---@return string
local function ReadString(binary, fixedLength)
    local str = ""
    local chr = binary:Read(1)
    local maxLength = fixedLength or 1024
    while chr and chr ~= "\x00" and #str < maxLength + 1 do
        str = str .. chr
        chr = binary:Read(1)
    end
    for _ = 1, (fixedLength or 0) - (#str + 1) do
        binary:Read(1)
    end
    return str
end

---Functions to read a value of the built-in types, looked up by the type name.
---Arrays read a value for each element, so Binary.Read looks up this table
---instead of joining "Read" and the type name every time, which LuaJIT 2.0 does not compile.
---Each function calls the method of the reader so that it works for both File and ss.BinaryStringReader.
---@type table<string, fun(binary: File|ss.BinaryStringReader): any>
local READERS = {
    Bool   = function(binary) return binary:ReadBool() end,
    Byte   = function(binary) return binary:ReadByte() end,
    Float  = function(binary) return binary:ReadFloat() end,
    Long   = function(binary) return binary:ReadLong() end,
    Short  = function(binary) return binary:ReadShort() end,
    ULong  = function(binary) return binary:ReadULong() end,
    UShort = function(binary) return binary:ReadUShort() end,
    SByte  = function(binary)
        local n = binary:ReadByte()
        return n - (n > 127 and 256 or 0)
    end,
    String = function(binary) return ReadString(binary) end,
}

---Returns the function to read a value of a type name that is not a structure:
---a built-in type, a string padded to a fixed length like `String128`, or bytes of a length like `4`.
---@param typename string
---@return (fun(binary: File|ss.BinaryStringReader): any)? # nil for a structure or a method of File only like `Double`.
local function ReaderOf(typename)
    if READERS[typename] then return READERS[typename] end
    local fixedLength = tonumber(typename:match "^String(%d+)$")
    if fixedLength then
        return function(binary) return ReadString(binary, fixedLength) end
    end

    local length = tonumber(typename)
    if length then
        return function(binary) return binary:Read(length) end
    end
end

---A field of a structure definition prepared for reading.
---@class ss.BinaryReader.Field
---@field TypeName   string
---@field Read       (fun(binary: File|ss.BinaryStringReader): any)? The function to read a value, or nil to read it by TypeName.
---@field Key        string?  The key of the field, or nil to put the values after the previous ones by position.
---@field Count      integer? The number of the elements of an array of a fixed size.
---@field CountField string?  The key of the previous field that has the number of the elements.

---Fields of each structure definition prepared for reading, which are the same for every element of an array.
local layoutOf = setmetatable({}, { __mode = "k" }) ---@type table<ss.BinaryStructureDefinition, ss.BinaryReader.Field[]>

---Returns the fields of a structure definition prepared for reading.
---@param definition ss.BinaryStructureDefinition
---@return ss.BinaryReader.Field[]
local function LayoutOf(definition)
    local layout = layoutOf[definition]
    if layout then return layout end

    layout = {}
    for i, field in ipairs(Binary.GetFields(definition)) do
        local typename, key, size = field[1], field[2], field[3]
        local entry = { TypeName = typename, Read = ReaderOf(typename) } ---@type ss.BinaryReader.Field
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

---Reads a value of a field.
---@param binary File|ss.BinaryStringReader
---@param field  ss.BinaryReader.Field
---@param ...    any
---@return any
local function ReadField(binary, field, ...)
    local read = field.Read
    if read then return read(binary) end
    return Binary.Read(binary, field.TypeName, ...)
end

---Reads a structure by the fields of its definition.
---An array of no element is nil, and the values of a field without a key follow the previous ones by position.
---@param binary     File|ss.BinaryStringReader
---@param definition ss.BinaryStructureDefinition
---@param ...        any
---@return table
local function ReadStructure(binary, definition, ...)
    local structure = {} ---@type table<string|integer, any>
    for _, field in ipairs(LayoutOf(definition)) do
        local count = field.Count
        if field.CountField then
            local n = structure[field.CountField]
            if not n then
                error(string.format("SplashSWEPs/BinaryReader: the number of %s is in %s, which is not read before",
                    field.Key or field.TypeName, field.CountField), 3)
            end

            count = tonumber(n) or 0
        end

        local key = field.Key
        if not count then
            structure[key or #structure + 1] = ReadField(binary, field, ...)
        elseif key then
            if count >= 1 then
                local array = structure[key] or {}
                structure[key] = array
                for i = 1, count do
                    array[i] = ReadField(binary, field, ...)
                end
            end
        else
            local first = #structure + 1
            for i = 0, count - 1 do
                structure[first + i] = ReadField(binary, field, ...)
            end
        end
    end

    return structure
end

---Read a value or structure from given binary file or string reader.
---The offset should correctly be set before call by binary:Seek().
---arg should be one of the following:
---  - Number for `File:Read(%d)`
---  - String for one of these:
---    - a call of `File:Read%s()`, e.g. `Long`, `Float`
---    - Additional built-in type: `SByte` (signed byte)
---    - `String` for null-terminated string
---    - `String%d` for a null-terminated string but padded to `%d` bytes.
---    - Structure name defined by Binary.struct "T"
---  - Table representing a structure
---    Table containing a sequence of strings formatted as
---    `<type> <fieldname> <array amount (optional)>`
---    e.g. `Float dist`, `Byte fourCC 4`
---    Array amount can be a field name previously defined in the same structure.
---    e.g. `{ "Long edgeCount", "UShort edgeIndices edgeCount" }`
---@generic T : table
---@param binary File|ss.BinaryStringReader
---@param arg ss.Binary.`T`
---@param ... any Any parameters passed to special function to read.
---@return ss.Binary.`T`
---@overload fun(binary: File|ss.BinaryStringReader, arg: integer):       string
---@overload fun(binary: File|ss.BinaryStringReader, arg: "Bool"):        boolean
---@overload fun(binary: File|ss.BinaryStringReader, arg: "Byte"):        integer
---@overload fun(binary: File,                       arg: "Double"):      number
---@overload fun(binary: File|ss.BinaryStringReader, arg: "Float"):       number
---@overload fun(binary: File,                       arg: "Line"):        string
---@overload fun(binary: File|ss.BinaryStringReader, arg: "Long"):        integer
---@overload fun(binary: File|ss.BinaryStringReader, arg: "Short"):       integer
---@overload fun(binary: File,                       arg: "UInt64"):      integer
---@overload fun(binary: File|ss.BinaryStringReader, arg: "ULong"):       integer
---@overload fun(binary: File|ss.BinaryStringReader, arg: "UShort"):      integer
---@overload fun(binary: File|ss.BinaryStringReader, arg: "SByte"):       integer
---@overload fun(binary: File|ss.BinaryStringReader, arg: "String"):      string
function Binary.Read(binary, arg, ...)
    local read = READERS[arg]
    if read then return read(binary) end

    local argType = type(arg)
    if argType == "number" then ---@cast arg integer
        return binary:Read(arg)
    elseif argType == "table" then ---@cast arg ss.BinaryStructureDefinition
        if arg.Read then
            return arg:Read(binary, ...)
        end

        return ReadStructure(binary, arg, ...)
    elseif argType == "string" then ---@cast arg string
        if arg:StartsWith "String" then
            return ReadString(binary, tonumber(arg:sub(#"String" + 1)))
        end

        local method = binary["Read" .. arg] ---@type fun(self: File|ss.BinaryStringReader): any
        if isfunction(method) then
            return method(binary)
        elseif tonumber(arg) then
            return Binary.Read(binary, tonumber(arg))
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
