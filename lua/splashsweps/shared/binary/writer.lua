
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Write a value or structure to given binary file.
---The offset should correctly be set before call by binary:Seek().
---arg should be one of the following:
---  - Number of bytes to write a string using `File:Write(%s)`
---  - String for one of these:
---    - a call of `File:Write%s()`, e.g. `Long`, `Float`
---    - Additional built-in types: `Vector`, `ShortVector`, `LongVector`, `Angle`, or `SByte` (signed byte)
---    - `String` for null-terminated string
---    - `String%d` for a null-terminated string but padded to `%d` bytes.
---    - Structure name defined by ss.bstruct "T"
---  - Table representing a structure
---    Table containing a sequence of strings formatted as
---    `<type> <fieldname> <array amount (optional)>`
---    e.g. `Vector normal`, `Byte fourCC 4`
---    Array amount can be a field name previously defined in the same structure.
---    e.g. `{ "Long edgeCount", "UShort edgeIndices edgeCount" }`
--- value should be corresponding table if arg is structure.
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
function ss.WriteStructureToFile(binary, arg, value, ...)
    if value == nil then
        return
    elseif isnumber(arg) then
        ---@cast arg integer
        ---@cast value string
        binary:Write(value:sub(1, arg))
    elseif istable(arg) then ---@cast arg ss.BinaryStructureDefinition
        if arg.Write then
            arg:Write(binary, value, ...)
        else
            for _, varstring in ipairs(arg) do
                ---@type string, integer|string?, integer|string?
                local fieldType, fieldKey, arraySize = unpack(string.Explode(" +", varstring, true))
                if arraySize == nil or arraySize == "" then arraySize = 1 end
                if isstring(arraySize) and value[arraySize] or tonumber(arraySize) > 1 then
                    arraySize = tonumber(value[arraySize]) or tonumber(arraySize) or 0
                    for i = 1, arraySize do
                        ss.WriteStructureToFile(binary, fieldType, value[fieldKey][i], ...)
                        if isnumber(fieldKey) then ---@cast fieldKey integer
                            fieldKey = fieldKey + 1
                        end
                    end
                else
                    ss.WriteStructureToFile(binary, fieldType, value[fieldKey], ...)
                end
            end
        end
    elseif isstring(arg) then ---@cast arg string
        if arg == "Angle" then ---@cast value Angle
            binary:WriteFloat(value.pitch)
            binary:WriteFloat(value.yaw)
            binary:WriteFloat(value.roll)
        elseif arg == "SByte" then
            binary:WriteByte(math.Clamp(value < 0 and (256 - value) or value, -128, 127))
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
            binary["Write" .. arg](binary, value)
        elseif tonumber(arg) then ---@cast value string
            binary:Write(value:sub(1, tonumber(arg)))
        elseif #ss.bstruct(arg) > 0 or ss.bstruct(arg).Write then
            ss.WriteStructureToFile(binary, ss.bstruct(arg), value, ...)
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
