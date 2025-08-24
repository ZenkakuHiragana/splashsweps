
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Ink type definition for the appearance and interactions.
---@class ss.InkType
---@field Index       integer  Internal index number used by networking.
---@field Identifier  string   The identifier of this type of ink as the key of ss.InkTypes.
---@field Features    string[] List of features this type of ink will have.
---@field BaseTexture string   The albedo texture to render this ink type.
---@field Bumpmap     string   The normal texture to render this ink type.
ss.struct "InkType" {
    Index = 0,
    Identifier = "",
    Features = {},
    BaseTexture = "",
    Bumpmap = "",
}

---JSON scheme for ink type definition.
---@class ss.InkType.JSON
---@field name?        string   The identifier.
---@field features?    string[] List of features this type of ink will have.
---@field basetexture? string   The albedo texture to render this ink type.
---@field bumpmap?     string   The normal texture to render this ink type.

---Converts ink type identifier (string) into internal index.
---@param identifier string
---@return integer?
function ss.FindInkTypeID(identifier)
    return ss.InkTypeIdentifierToIndex[identifier]
end

---Reads all JSON files and defines all ink types used in this addon.
function ss.LoadInkTypes()
    local inktypeCount = 0

    ---@param root string The path to search from.
    ---@param path string Same as the second argument of `file.Find`, e.g. "GAME", "DATA"
    local function load(root, path)
        for f in ss.IterateFilesRecursive(root, path, "*.json") do
            ---@type ss.InkType.JSON
            local json = util.JSONToTable(file.Read(f, path)) or {}
            local name = string.match(json.name or "", "^[A-Za-z0-9_]+$")
            if name then
                inktypeCount = inktypeCount + 1
                local inktype = ss.new "InkType"
                inktype.Index = inktypeCount
                inktype.Identifier = name
                inktype.Features = json.features or {}
                inktype.BaseTexture = json.basetexture or "debug/debugempty"
                inktype.Bumpmap = json.bumpmap or "null-bumpmap"
                ss.InkTypes[inktypeCount] = inktype
                ss.InkTypeIdentifierToIndex[name] = inktypeCount
            end
        end
    end

    load("data_static/splashsweps/inktypes", "GAME")
    load("splashsweps/inktypes", "DATA")

    ---Total number of defined ink types.
    ss.NumInkTypes = inktypeCount

    ---Required bits to transfer ink type as an unsigned integer.
    ss.MAX_INKTYPE_BITS = math.max(select(2, math.frexp(inktypeCount - 1)), 1)
end
