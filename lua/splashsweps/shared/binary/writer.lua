
---@class ss
local ss = SplashSWEPs
local BinaryStruct = ss.import "splashsweps/shared/binary/struct"

---@class ss.BinaryWriterModule
local BinaryWriter = ss.module "splashsweps/shared/binary/writer"

---The methods of File, which always exists in GMod.
local File = FindMetaTable "File" --[[@as File]]

---Writes a null-terminated string, padded to fixedLength bytes if given.
---@param binary      File
---@param value       string
---@param fixedLength integer?
local function WriteString(binary, value, fixedLength)
    fixedLength = fixedLength or #value + 1
    binary:Write(value:sub(1, fixedLength))
    binary:Write(string.rep("\x00", fixedLength - #value))
end

---Functions to write a value of the built-in types, looked up by the type name.
---@type table<string, fun(binary: File, value: any)>
local WRITERS = {
    Bool   = File.WriteBool,
    Byte   = File.WriteByte,
    Float  = File.WriteFloat,
    Long   = File.WriteLong,
    Short  = File.WriteShort,
    ULong  = File.WriteULong,
    UShort = File.WriteUShort,
    SByte  = function(binary, value) binary:WriteByte(value % 256) end,
    String = function(binary, value) WriteString(binary, value) end,
}

---Writes a value of a field.
---@param binary File
---@param field  ss.BinaryStruct.Field
---@param value  any
---@param ...    any
local function WriteField(binary, field, value, ...)
    local write = WRITERS[field.TypeName]
    if write then
        write(binary, value)
    else
        BinaryWriter.Write(binary, field.TypeName, value, ...)
    end
end

---Writes a structure by the fields of its definition.
---@param binary     File
---@param definition ss.BinaryStruct.Definition
---@param value      table
---@param ...        any
local function WriteStructure(binary, definition, value, ...)
    local position = 0 -- The last array index of the value written
    for _, field in ipairs(BinaryStruct.GetLayout(definition)) do
        local count = field.Count
        if field.CountField then
            local n = value[field.CountField]
            if not n then
                error(string.format("SplashSWEPs/BinaryWriter: the number of %s is in %s, which the value does not have",
                    field.Key or field.TypeName, field.CountField), 3)
            end

            count = tonumber(n) or 0
        end

        local key = field.Key
        if not count then
            if not key then position = position + 1 end
            WriteField(binary, field, value[key or position], ...)
        elseif key then
            local array = value[key]
            for i = 1, count do
                WriteField(binary, field, array[i], ...)
            end
        else
            for _ = 1, count do
                position = position + 1
                WriteField(binary, field, value[position], ...)
            end
        end
    end
end

---Write a value or structure to given binary file in the format BinaryReader.Read reads.
--- value should be corresponding table if arg is structure.
--- Every field of a structure is written, so the value must have all of them,
--- including the array amount that matches the length of the array.
---@generic T : table
---@param binary File
---@param arg ss.BinaryStruct.`T`
---@param value ss.BinaryStruct.`T`
---@param ... any Any parameters passed to special function to write.
---@overload fun(binary: File, arg: integer,  value: string)
---@overload fun(binary: File, arg: "Bool",   value: boolean)
---@overload fun(binary: File, arg: "Byte",   value: integer)
---@overload fun(binary: File, arg: "Float",  value: number)
---@overload fun(binary: File, arg: "Long",   value: integer)
---@overload fun(binary: File, arg: "Short",  value: integer)
---@overload fun(binary: File, arg: "ULong",  value: integer)
---@overload fun(binary: File, arg: "UShort", value: integer)
---@overload fun(binary: File, arg: "SByte",  value: integer)
---@overload fun(binary: File, arg: "String", value: string)
function BinaryWriter.Write(binary, arg, value, ...)
    local write = WRITERS[arg]
    if write then
        write(binary, value)
        return
    end

    local argType = type(arg)
    if argType == "number" then
        ---@cast arg integer
        ---@cast value string
        binary:Write(value:sub(1, arg))
    elseif argType == "table" then ---@cast arg ss.BinaryStruct.Definition
        if arg.Write then
            arg:Write(binary, value, ...)
        else
            WriteStructure(binary, arg, value, ...)
        end
    elseif argType == "string" then ---@cast arg string
        if arg:StartsWith "String" then ---@cast value string
            WriteString(binary, value, tonumber(arg:sub(#"String" + 1)))
        elseif tonumber(arg) then ---@cast value string
            binary:Write(value:sub(1, tonumber(arg)))
        elseif BinaryStruct.Find(arg) and (#BinaryStruct.Find(arg) > 0 or BinaryStruct.Find(arg).Write) then
            BinaryWriter.Write(binary, BinaryStruct.Find(arg), value, ...)
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
