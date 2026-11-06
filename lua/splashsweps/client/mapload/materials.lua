
-- Materials of the map surfaces, enumerated in the order the engine allocates their lightmaps.

---@class ss
local ss = SplashSWEPs
local Session = ss.import "splashsweps/client/session"
local Util    = ss.import "splashsweps/shared/util"

---@class ss.MapMaterialsModule
local MapMaterials = ss.module "splashsweps/client/mapload/materials"

---Material metadata needed to reproduce world surface shading in inkmesh.
---@class ss.MapMaterials.MaterialInfo
---@field Material             IMaterial The source material.
---Indices to the material names of the map,
---of the materials of this enumeration ID. Several materials have the same one if they are missing.
---@field ArrayIndices         integer[]
---@field NeedsBumpedLightmaps boolean   Whether the material uses 3 directional lightmaps plus the base lightmap.
---@field HasBaseTexture2      boolean   Indicates if the material has $basetexture2.
---@field HasBaseTexture3      boolean   Indicates if the material has $basetexture3.
---@field BaseTexture          string?   Value of $basetexture.
---@field Bumpmap              string?   Value of $bumpmap.
---@field Detail               string?   Value of $detail.
---@field UnderlayBlendAtlas   string?   Name of the render target UnderlayBlendAtlas.Build packs the blended textures into, nil if the material has no $basetexture2.
---@field BumpTextureTransform VMatrix   Value of $bumptransform, or the identity if the material has none.
---@field BaseTextureTransform VMatrix?  Value of $basetexturetransform.
---@field BlendMaskTransform   VMatrix?  Value of $blendmasktransform.
---@field DetailBlendFactor    number?   Value of $detailblendfactor.
---@field DetailBlendMode      integer?  Value of $detailblendmode.
---@field DetailScale          Vector?   Value of $detailscale.
---@field DetailTint           Vector?   Value of $detailtint.
---@field Color                Vector?   Value of $color.
---@field Envmap               string?   Value of $envmap, nil if the material has none.

---Assigns enumeration ID to materials in the map,
---considering the global string table in the engine.
---@param materialsInMap string[]
---@return table<integer, ss.MapMaterials.MaterialInfo> materialInfo
local function enumerateMaterials(materialsInMap)
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

    ---The engine replaces missing materials with the error material, which is made by CreateMaterial.
    ---The material dictionary sorts such materials before those from files (CMaterialDict::MaterialLessFunc),
    ---so the error material has the enumeration ID before all materials of the map.
    local ERROR_MATERIAL_ENUMERATION_ID = 0
    local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)
    local IdentityMatrix = Matrix()
    local materialInfo = {} ---@type table<integer, ss.MapMaterials.MaterialInfo>
    for enumerationID, name in ipairs(materialNames) do
        local arrayIndex = enumerationIDToArrayIndex[enumerationID]
        if arrayIndex then
            local mat = Material(name)
            if mat:IsError() then enumerationID = ERROR_MATERIAL_ENUMERATION_ID end
            if not materialInfo[enumerationID] then
                local baseTexture2 = mat:GetString "$basetexture2"
                local baseTexture3 = mat:GetString "$basetexture3"
                local envmap       = mat:GetString "$envmap"
                materialInfo[enumerationID] = {
                    Material             = mat,
                    ArrayIndices         = {},
                    NeedsBumpedLightmaps = bit.band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0,
                    HasBaseTexture2      = tobool(baseTexture2),
                    HasBaseTexture3      = tobool(baseTexture3),
                    BaseTexture          = mat:GetString "$basetexture",
                    Bumpmap              = mat:GetString "$bumpmap",
                    Detail               = mat:GetString "$detail",
                    BaseTextureTransform = mat:GetMatrix "$basetexturetransform",
                    BumpTextureTransform = mat:GetMatrix "$bumptransform" or IdentityMatrix, -- None for the error material
                    BlendMaskTransform   = mat:GetMatrix "$blendmasktransform" or IdentityMatrix,
                    DetailBlendFactor    = mat:GetFloat  "$detailblendfactor",
                    DetailBlendMode      = mat:GetInt    "$detailblendmode",
                    DetailScale          = mat:GetVector "$detailscale",
                    DetailTint           = baseTexture2 and Util.vector_one or mat:GetVector "$detailtint",
                    Envmap               = envmap ~= "" and envmap or nil,
                    Color = (mat:GetVector "$color" or Util.vector_one)
                          * (mat:GetVector "$color2" or Util.vector_one),
                }
            end

            local arrayIndices = materialInfo[enumerationID].ArrayIndices
            arrayIndices[#arrayIndices + 1] = arrayIndex
        end
    end

    return materialInfo
end

---Reads what the ink meshes need from the materials in the map.
---@param materialNames string[] Materials in the map, usually game.GetMap():GetMaterials() saved in the map cache.
---@return table<integer, ss.MapMaterials.MaterialInfo> materialInfo Sparse enumeration-ID-indexed materials.
function MapMaterials.Enumerate(materialNames)
    return enumerateMaterials(materialNames)
end

return MapMaterials
