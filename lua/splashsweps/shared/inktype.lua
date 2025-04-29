
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Ink type definition for the appearance and interactions.
---@class ss.InkType
---@field Identifier  string   The identifier of this type of ink as the key of ss.InkTypes.
---@field Features    string[] List of features this type of ink will have.
---@field BaseTexture string   The albedo texture to render this ink type.
---@field Bumpmap     string   The normal texture to render this ink type.
ss.struct "InkType" {
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

---Reads all JSON files and defines all ink types used in this addon.
function ss.LoadInkTypes()
    for f in ss.IterateFilesRecursive("splashsweps/inktypes", "DATA", "*.json") do
        ---@type ss.InkType.JSON
        local json = util.JSONToTable(file.Read(f, "DATA")) or {}
        local name = string.match(json.name or "", "^[A-Za-z0-9_]+$")
        if name then
            local inktype = ss.new "InkType"
            inktype.Identifier = name
            inktype.Features = json.features or {}
            inktype.BaseTexture = json.basetexture or "debug/debugempty"
            inktype.Bumpmap = json.bumpmap or "null-bumpmap"
            ss.InkTypes[name] = inktype
        end
    end
end
