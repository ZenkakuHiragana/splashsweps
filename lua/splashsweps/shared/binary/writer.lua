
---@class ss
local ss = SplashSWEPs
local Binary = ss.import "splashsweps/shared/binary/reader"

---@class ss.BinaryWriter
local BinaryWriter = ss.module "splashsweps/shared/binary/writer"

---Write a value or structure to given binary file in the format Binary.Read reads.
---The offset should correctly be set before call by binary:Seek().
---arg should be one of the following:
---  - Number of bytes to write a string using `File:Write(%s)`
---  - String for one of these:
---    - a call of `File:Write%s()`, e.g. `Long`, `Float`
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
---    The field name `nil` puts the value at the next array index of the structure.
--- value should be corresponding table if arg is structure.
--- Every field of a structure is written, so the value must have all of them,
--- including the array amount that matches the length of the array.
---@generic T : table
---@param binary File
---@param arg ss.Binary.`T`
---@param value ss.Binary.`T`
---@param ... any Any parameters passed to special function to write.
---@overload fun(binary: File, arg: integer,       value: string)
---@overload fun(binary: File, arg: "Bool",        value: boolean)
---@overload fun(binary: File, arg: "Byte",        value: integer)
---@overload fun(binary: File, arg: "Double",      value: number)
---@overload fun(binary: File, arg: "Float",       value: number)
---@overload fun(binary: File, arg: "Line",        value: string)
---@overload fun(binary: File, arg: "Long",        value: integer)
---@overload fun(binary: File, arg: "Short",       value: integer)
---@overload fun(binary: File, arg: "UInt64",      value: integer)
---@overload fun(binary: File, arg: "ULong",       value: integer)
---@overload fun(binary: File, arg: "UShort",      value: integer)
---@overload fun(binary: File, arg: "SByte",       value: integer)
---@overload fun(binary: File, arg: "Angle",       value: Angle)
---@overload fun(binary: File, arg: "Vector",      value: Vector)
---@overload fun(binary: File, arg: "ShortVector", value: Vector)
---@overload fun(binary: File, arg: "LongVector",  value: Vector)
---@overload fun(binary: File, arg: "String",      value: string)
function BinaryWriter.Write(binary, arg, value, ...)
    if isnumber(arg) then
        ---@cast arg integer
        ---@cast value string
        binary:Write(value:sub(1, arg))
    elseif istable(arg) then ---@cast arg ss.BinaryStructureDefinition
        if arg.Write then
            arg:Write(binary, value, ...)
        else
            local position = 0 -- The last array index of the structure written
            for _, field in ipairs(Binary.GetFields(arg)) do
                ---@type string, integer|string?, integer|string?
                local fieldType, fieldKey, arraySize = field[1], field[2], field[3]
                if fieldKey == nil or fieldKey == "" or fieldKey == "nil" then fieldKey = position + 1 end
                if arraySize == nil or arraySize == "" then arraySize = 1 end
                if isstring(arraySize) and value[arraySize] or tonumber(arraySize) > 1 then
                    arraySize = tonumber(value[arraySize]) or tonumber(arraySize) or 0
                    for i = 1, arraySize do
                        if isnumber(fieldKey) then ---@cast fieldKey integer
                            BinaryWriter.Write(binary, fieldType, value[fieldKey], ...)
                            position = fieldKey
                            fieldKey = fieldKey + 1
                        else
                            BinaryWriter.Write(binary, fieldType, value[fieldKey][i], ...)
                        end
                    end
                else
                    BinaryWriter.Write(binary, fieldType, value[fieldKey], ...)
                    if isnumber(fieldKey) then ---@cast fieldKey integer
                        position = fieldKey
                    end
                end
            end
        end
    elseif isstring(arg) then ---@cast arg string
        if arg == "Angle" then ---@cast value Angle
            binary:WriteFloat(value.pitch)
            binary:WriteFloat(value.yaw)
            binary:WriteFloat(value.roll)
        elseif arg == "SByte" then
            binary:WriteByte(value % 256)
        elseif arg == "ShortVector" then ---@cast value Vector
            binary:WriteShort(value.x)
            binary:WriteShort(value.y)
            binary:WriteShort(value.z)
        elseif arg == "LongVector" then ---@cast value Vector
            binary:WriteLong(value.x)
            binary:WriteLong(value.y)
            binary:WriteLong(value.z)
        elseif arg:StartsWith "String" then ---@cast value string
            local fixedLength = tonumber(arg:sub(#"String" + 1)) or (#value + 1)
            binary:Write(value:sub(1, fixedLength))
            binary:Write(string.rep("\x00", fixedLength - #value))
        elseif arg == "Vector" then ---@cast value Vector
            binary:WriteFloat(value.x)
            binary:WriteFloat(value.y)
            binary:WriteFloat(value.z)
        elseif isfunction(binary["Write" .. arg]) then
            local write = binary["Write" .. arg] ---@type fun(self: File, value: any)
            write(binary, value)
        elseif tonumber(arg) then ---@cast value string
            binary:Write(value:sub(1, tonumber(arg)))
        elseif Binary.Find(arg) and (#Binary.Find(arg) > 0 or Binary.Find(arg).Write) then
            BinaryWriter.Write(binary, Binary.Find(arg), value, ...)
        else
            ErrorNoHalt(string.format(
                "SplashSWEPs/BinaryWriter: Need a correct structure name\n"
                .. "    Structure name given: %s\n", arg))
        end
    else
        ErrorNoHalt(string.format(
            "SplashSWEPs/BinaryWriter: Need a correct structure name\n"
            .. "    Argument given: %s, %s\n", type(arg), tostring(arg)))
    end
end

return BinaryWriter
