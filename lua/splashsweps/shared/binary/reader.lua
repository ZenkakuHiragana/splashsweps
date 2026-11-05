
-- Reads values and structures from binary files such as BSP and VTF.

---@class ss
local ss = SplashSWEPs
local BinaryStruct = ss.import "splashsweps/shared/binary/struct"

---@class ss.BinaryReaderModule
local BinaryReader = ss.module "splashsweps/shared/binary/reader"

---Reads little-endian values from a binary string, with methods named after those of File.
---Each read of File is costly however small it is,
---so binary data is read as one string by a single read of the file and decoded here in Lua.
---@class ss.BinaryReader.StringReader
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
---@param self ss.BinaryReader.StringReader
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

---Creates a reader at the beginning of the data, which BinaryReader.Read reads from.
---@param data string
---@return ss.BinaryReader.StringReader
function BinaryReader.NewStringReader(data)
    return setmetatable({ Data = data, Position = 0 }, StringReader)
end

---Reads a null-terminated string, padded to fixedLength bytes if given.
---@param binary      ss.BinaryReader.StringReader
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
---Arrays read a value for each element, so BinaryReader.Read looks up this table
---instead of joining "Read" and the type name every time, which LuaJIT 2.0 does not compile.
---@type table<string, fun(binary: ss.BinaryReader.StringReader): any>
local READERS = {
    Bool   = StringReader.ReadBool,
    Byte   = StringReader.ReadByte,
    Float  = StringReader.ReadFloat,
    Long   = StringReader.ReadLong,
    Short  = StringReader.ReadShort,
    ULong  = StringReader.ReadULong,
    UShort = StringReader.ReadUShort,
    SByte  = function(binary)
        local n = binary:ReadByte()
        return n - (n > 127 and 256 or 0)
    end,
    String = function(binary) return ReadString(binary) end,
}

---Reads a value of a field.
---@param binary ss.BinaryReader.StringReader
---@param field  ss.BinaryStruct.Field
---@param ...    any
---@return any
local function ReadField(binary, field, ...)
    local read = READERS[field.TypeName]
    if read then return read(binary) end
    return BinaryReader.Read(binary, field.TypeName, ...)
end

---Reads a structure by the fields of its definition.
---An array of no element is nil, and the values of a field without a key follow the previous ones by position.
---@param binary     ss.BinaryReader.StringReader
---@param definition ss.BinaryStruct.Definition
---@param ...        any
---@return table
local function ReadStructure(binary, definition, ...)
    local structure = {} ---@type table<string|integer, any>
    for _, field in ipairs(BinaryStruct.GetLayout(definition)) do
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

---Read a value or structure from given string reader.
---The offset should correctly be set before call by binary:Seek().
---arg should be one of the following:
---  - Number of bytes to read as a string, or a string of the number like `4`
---  - String for one of these:
---    - Built-in types: `Bool`, `Byte`, `SByte` (signed byte), `Short`, `UShort`, `Long`, `ULong`, and `Float`
---    - `String` for null-terminated string
---    - `String%d` for a null-terminated string but padded to `%d` bytes.
---    - Structure name defined by BinaryStruct.Define "T"
---  - Table representing a structure
---    Table containing a sequence of strings formatted as
---    `<type> <fieldname> <array amount (optional)>`
---    e.g. `Float dist`, `Byte fourCC 4`
---    Array amount can be a field name previously defined in the same structure.
---    e.g. `{ "Long edgeCount", "UShort edgeIndices edgeCount" }`
---@generic T : table
---@param binary ss.BinaryReader.StringReader
---@param arg ss.BinaryStruct.`T`
---@param ... any Any parameters passed to special function to read.
---@return ss.BinaryStruct.`T`
---@overload fun(binary: ss.BinaryReader.StringReader, arg: integer):  string
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "Bool"):   boolean
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "Byte"):   integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "Float"):  number
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "Long"):   integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "Short"):  integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "ULong"):  integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "UShort"): integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "SByte"):  integer
---@overload fun(binary: ss.BinaryReader.StringReader, arg: "String"): string
function BinaryReader.Read(binary, arg, ...)
    local read = READERS[arg]
    if read then return read(binary) end

    local argType = type(arg)
    if argType == "number" then ---@cast arg integer
        return binary:Read(arg)
    elseif argType == "table" then ---@cast arg ss.BinaryStruct.Definition
        if arg.Read then
            return arg:Read(binary, ...)
        end

        return ReadStructure(binary, arg, ...)
    elseif argType == "string" then ---@cast arg string
        if arg:StartsWith "String" then
            return ReadString(binary, tonumber(arg:sub(#"String" + 1)))
        elseif tonumber(arg) then
            return BinaryReader.Read(binary, tonumber(arg))
        elseif BinaryStruct.Find(arg) and (#BinaryStruct.Find(arg) > 0 or BinaryStruct.Find(arg).Read) then
            return BinaryReader.Read(binary, BinaryStruct.Find(arg), ...)
        end
    end

    ErrorNoHalt(string.format(
        "SplashSWEPs/BinaryReader: Need a correct structure name\n"
        .. "    Structure name given: %s\n", tostring(arg)))
    return {}
end

return BinaryReader
