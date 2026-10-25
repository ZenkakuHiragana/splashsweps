
-- Materials of the map surfaces, enumerated in the order the engine allocates their lightmaps.

---@class ss
local ss = SplashSWEPs
local PrecachedData = ss.import "splashsweps/shared/typing/precachedata"
local Session       = ss.import "splashsweps/client/session"
local Util          = ss.import "splashsweps/shared/util"

---@class ss.MapMaterialsModule
local MapMaterials = ss.module "splashsweps/client/mapload/materials"

---Material metadata needed to reproduce world surface shading in inkmesh.
---@class ss.MapMaterials.MaterialInfo
---@field Material             IMaterial The source material.
---@field ArrayIndex           integer   Index to material name array which is usually game.GetMap():GetMaterials().
---@field NeedsBumpedLightmaps boolean   Whether the material uses 3 directional lightmaps plus the base lightmap.
---@field HasBaseTexture2      boolean   Indicates if the material has $basetexture2.
---@field HasBaseTexture3      boolean   Indicates if the material has $basetexture3.
---@field BaseTexture          string?   Value of $basetexture.
---@field Bumpmap              string?   Value of $bumpmap.
---@field Detail               string?   Value of $detail.
---@field BumpTextureTransform VMatrix?  Value of $bumptransform.
---@field BaseTextureTransform VMatrix?  Value of $basetexturetransform.
---@field BlendMaskTransform   VMatrix?  Value of $blendmasktransform.
---@field DetailBlendFactor    number?   Value of $detailblendfactor.
---@field DetailBlendMode      integer?  Value of $detailblendmode.
---@field DetailScale          Vector?   Value of $detailscale.
---@field DetailTint           Vector?   Value of $detailtint.
---@field Color                Vector?   Value of $color.
---@field Cubemap              ss.PrecachedData.CubemapInfo? Resolved $envmap plus cubemap sample correction data.

---@param name string?
---@return string?
local function normalizeEnvmapName(name)
    if not name or name == "" then return end
    local normalized = name:lower():gsub("\\", "/"):gsub("%.vtf$", ""):gsub("%.hdr$", "")
    return normalized
end

---@param cubemaps ss.PrecachedData.CubemapInfo[]?
---@return table<string, ss.PrecachedData.CubemapInfo>
local function buildCubemapLookup(cubemaps)
    local lookup = {} ---@type table<string, ss.PrecachedData.CubemapInfo>
    for _, cubemap in ipairs(cubemaps or {}) do
        local name = normalizeEnvmapName(cubemap.Envmap)
        if name then lookup[name] = cubemap end
    end
    return lookup
end

---@param envmap string?
---@param cubemapLookup table<string, ss.PrecachedData.CubemapInfo>
---@return ss.PrecachedData.CubemapInfo?
local function resolveMaterialCubemap(envmap, cubemapLookup)
    local name = normalizeEnvmapName(envmap)
    if not name then return end ---@cast envmap -?

    local cached = cubemapLookup[name]
    local cubemap = PrecachedData.CubemapInfo.new()
    cubemap.Envmap = envmap
    if cached then
        cubemap.Origin:Set(cached.Origin)
        cubemap.BoxMin:Set(cached.BoxMin)
        cubemap.BoxMax:Set(cached.BoxMax)
        cubemap.FaceCount = cached.FaceCount
        cubemap.Blend = cached.Blend
    end

    return cubemap
end

---Assigns enumeration ID to materials in the map,
---considering the global string table in the engine.
---@param materialsInMap string[]
---@param cubemapLookup table<string, ss.PrecachedData.CubemapInfo>
---@return table<integer, ss.MapMaterials.MaterialInfo> materialInfo Sparse enumeration-ID-indexed materials.
local function enumerateMaterials(materialsInMap, cubemapLookup)
    local materialNames = materialsInMap
    local enumerationIDToArrayIndex = {} ---@type integer[]
    if not Session.IsFirstRun() then
        materialNames = util.JSONToTable( ---@type string[]
            file.Read("splashsweps/material-names.json", "DATA") or "") or {}
        local materialNameAsKey = table.Flip(materialNames)
        for _, str in ipairs(materialsInMap) do
            if not materialNameAsKey[str] then
                materialNames[#materialNames + 1] = str
            end
        end
    end

    file.Write("splashsweps/material-names.json", util.TableToJSON(materialNames))
    local materialsInMapFlip = table.Flip(materialsInMap)
    for enumerationID, str in ipairs(materialNames) do
        enumerationIDToArrayIndex[enumerationID] = materialsInMapFlip[str]
    end

    ---Enumeration ID --> material information
    local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)
    local IdentityMatrix = Matrix()
    local materialInfo = {} ---@type table<integer, ss.MapMaterials.MaterialInfo>
    for enumerationID, name in ipairs(materialNames) do
        if enumerationIDToArrayIndex[enumerationID] then
            local mat = Material(name)
            if mat and not mat:IsError() then
                local baseTexture2 = mat:GetString "$basetexture2"
                local baseTexture3 = mat:GetString "$basetexture3"
                local envmap       = mat:GetString "$envmap"
                materialInfo[enumerationID] = {
                    Material             = mat,
                    ArrayIndex           = enumerationIDToArrayIndex[enumerationID],
                    NeedsBumpedLightmaps = bit.band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0,
                    HasBaseTexture2      = tobool(baseTexture2),
                    HasBaseTexture3      = tobool(baseTexture3),
                    BaseTexture          = mat:GetString "$basetexture",
                    Bumpmap              = mat:GetString "$bumpmap",
                    Detail               = baseTexture2 or mat:GetString "$detail",
                    BaseTextureTransform = mat:GetMatrix "$basetexturetransform",
                    BumpTextureTransform = mat:GetMatrix "$bumptransform",
                    BlendMaskTransform   = mat:GetMatrix "$blendmasktransform" or IdentityMatrix,
                    DetailBlendFactor    = mat:GetFloat  "$detailblendfactor",
                    DetailBlendMode      = mat:GetInt    "$detailblendmode",
                    DetailScale          = mat:GetVector "$detailscale",
                    DetailTint           = baseTexture2 and Util.vector_one or mat:GetVector "$detailtint",
                    Cubemap              = resolveMaterialCubemap(envmap, cubemapLookup),
                    Color = (mat:GetVector "$color" or Util.vector_one)
                          * (mat:GetVector "$color2" or Util.vector_one),
                }
            end
        end
    end

    return materialInfo
end

---Assigns enumeration ID to materials in the map and reads what the ink meshes need from them.
---@param materialNames string[] Materials in the map, usually game.GetMap():GetMaterials() saved in the map cache.
---@param cubemaps ss.PrecachedData.CubemapInfo[]? Cubemaps in the map.
---@return table<integer, ss.MapMaterials.MaterialInfo> materialInfo Sparse enumeration-ID-indexed materials.
function MapMaterials.Enumerate(materialNames, cubemaps)
    return enumerateMaterials(materialNames, buildCubemapLookup(cubemaps))
end

return MapMaterials
