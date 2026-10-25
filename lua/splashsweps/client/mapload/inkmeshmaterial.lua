
-- Creates the ink materials of the world ink meshes from the materials of the surfaces.

---@class ss
local ss = SplashSWEPs
local DetailAtlas   = ss.import "splashsweps/client/ink/detailatlas"
local InkMaterials  = ss.import "splashsweps/client/render/inkmaterials"
local Lightmaps     = ss.import "splashsweps/client/mapload/lightmaps"
local RenderTargets = ss.import "splashsweps/client/render/rendertargets"

---@class ss.InkMeshMaterialModule
local InkMeshMaterial = ss.module "splashsweps/client/mapload/inkmeshmaterial"

---Builds the shared key-values for dynamic inkmesh materials.
---@return table<string, string|number|Vector|VMatrix> baseParams Common Screenspace_General_8tex parameters.
local function buildBaseInkMeshMaterialParams()
    return {
        ["$vertexshader"]           = "splashsweps/inkmesh_vs30",
        ["$basetexture"]            = RenderTargets.InkMaps.InkMap:GetName(),
        ["$texture1"]               = DetailAtlas.GetRenderTarget():GetName(),
        ["$texture2"]               = RenderTargets.Frame.SceneAndFlashlight:GetName(),
        ["$texture7"]               = InkMaterials.DEFAULT_ENVMAP,
        ["$linearread_basetexture"] = "1",
        ["$linearread_texture1"]    = "1",
        ["$linearread_texture2"]    = "1",
        ["$linearread_texture3"]    = "0",
        ["$linearread_texture4"]    = "1",
        ["$linearread_texture5"]    = "1",
        ["$linearread_texture6"]    = render.GetHDREnabled() and "1" or "0",
        ["$linearread_texture7"]    = render.GetHDREnabled() and "1" or "0",
        ["$alpha_blend"]            = "0",
        ["$alphablend"]             = "0",
        ["$alphatested"]            = "0",
        ["$writealpha"]             = "1",
        ["$cull"]                   = "1",
        ["$depthtest"]              = "1",
        ["$vertexalpha"]            = "1",
        ["$vertexcolor"]            = "1",
        ["$vertexnormal"]           = "1",
        ["$tcsize0"]                = "4",
        ["$tcsize1"]                = "4",
        ["$tcsize2"]                = "4",
        ["$tcsize3"]                = "4",
        ["$tcsize4"]                = "4",
        ["$tcsize5"]                = "4",
        ["$tcsize6"]                = "4",
        ["$tcsize7"]                = "4",
        ["$c0_x"]                   = 0,     -- Sun direction x
        ["$c0_y"]                   = 0.3,   -- Sun direction y
        ["$c0_z"]                   = 0.954, -- Sun direction z
    }
end

---Packs Lightmapped_4WayBlend parameters into the layout the world ink shaders read from $invviewprojmat.
---@param m   VMatrix   Destination matrix.
---@param mat IMaterial Lightmapped_4WayBlend material.
local function set4WayBlendParams(m, mat)
    ---@param name string
    ---@return integer
    local function to8Bit(name)
        return math.Round(math.Clamp(mat:GetFloat(name), 0, 1) * 255)
    end

    ---@param format string Parameter name with %d for the layer number.
    ---@return integer
    local function packLayers(format)
        return to8Bit(format:format(2)) + to8Bit(format:format(3)) * 256 + to8Bit(format:format(4)) * 65536
    end

    -- $textureN_uvscale can be a float or a 2D vector; GetVector returns (v, v, v) for a float.
    local uvScale2 = mat:GetVector "$texture2_uvscale"
    local uvScale3 = mat:GetVector "$texture3_uvscale"
    local uvScale4 = mat:GetVector "$texture4_uvscale"
    m:SetUnpacked(
        packLayers "$texture%d_blendstart",
        packLayers "$texture%d_blendend",
        packLayers "$texture%d_lumstart",
        packLayers "$texture%d_lumend",
        packLayers "$lumblendfactor%d",
        packLayers "$texture%d_bumpblendfactor",
        packLayers "$detailblendfactor%d",
        to8Bit "$texture1_lumstart" + to8Bit "$texture1_lumend" * 256 + (mat:GetString "$bumpmap2" and 255 or 0) * 65536,
        uvScale2.x, uvScale3.x, uvScale4.x, mat:GetInt "$texture3_blendmode",
        uvScale2.y, uvScale3.y, uvScale4.y, mat:GetInt "$texture4_blendmode")
end

---Creates the ink material of the surfaces of a SortID, or gets the one created for the SortID before,
---and registers it to InkMaterials.
---@param lightmapLayout ss.Lightmaps.LightmapLayout SortID-indexed material and lightmap data.
---@param sortID         integer                     Lightmap/material group ID of the surfaces.
---@return IMaterial
function InkMeshMaterial.Create(lightmapLayout, sortID)
    local m = Matrix()
    local lightmapGroup         = lightmapLayout.Groups[sortID]
    local pageWidth, pageHeight = Lightmaps.GetPageSize(lightmapLayout, lightmapGroup)
    local materialInfo          = lightmapGroup.Material
    local cubemapInfo           = materialInfo.Cubemap
    local page                  = lightmapGroup.LightmapPage
    local lightmapTextureName   = page and string.format("\\[lightmap%d]", page) or "white"
    local materialParams        = buildBaseInkMeshMaterialParams()
    local hasDetail             = tobool(materialInfo.Detail)
    local detailBlendMode       = materialInfo.DetailBlendMode or 0
    local bmtstr                = materialInfo.Material:GetString "$blendmodulatetexture"
    -- Each kind of underlay has its own pixel shader.
    materialParams["$pixshader"] = materialInfo.HasBaseTexture3 and "splashsweps/inkmesh_4wayblend_ps30"
                                or materialInfo.HasBaseTexture2 and "splashsweps/inkmesh_wvt_ps30"
                                or "splashsweps/inkmesh_ps30"
    materialParams["$texture3"] = materialInfo.BaseTexture or "white"
    materialParams["$texture4"] = materialInfo.Bumpmap or "null-bumpmap"
    materialParams["$texture5"] = materialInfo.Detail or "white"
    materialParams["$texture6"] = lightmapTextureName
    materialParams["$texture7"] = cubemapInfo and cubemapInfo.Envmap or InkMaterials.DEFAULT_ENVMAP
    materialParams["$c0_w"]     = detailBlendMode
    materialParams["$c1_z"]     = 2 / RenderTargets.GetHammerUnitsToUV() -- InkMap region UV -> packed-surface HU.
    materialParams["$c1_y"]     = (materialInfo.NeedsBumpedLightmaps and 1 or 0)
                                + (bmtstr and 8 or 0)
    materialParams["$c2_x"]     = 1 / pageWidth
    materialParams["$c2_y"]     = 1 / pageHeight
    materialParams["$c2_z"]     = materialInfo.DetailScale and materialInfo.DetailScale.x or 4
    materialParams["$c2_w"]     = materialInfo.DetailScale and materialInfo.DetailScale.y or 4
    materialParams["$c3_x"]     = materialInfo.Color and materialInfo.Color.x or 1
    materialParams["$c3_y"]     = materialInfo.Color and materialInfo.Color.y or 1
    materialParams["$c3_z"]     = materialInfo.Color and materialInfo.Color.z or 1

    local mat = CreateMaterial(
        string.format("splashsweps_mesh_%d_%s", sortID, game.GetMap()),
        "Screenspace_General_8tex", materialParams)
    DetailAtlas.WriteLayout(mat)
    mat:SetFloat("$c1_z", 2 / RenderTargets.GetHammerUnitsToUV())
    m:SetUnpacked(
        materialInfo.BaseTextureTransform:GetField(1, 1),
        materialInfo.BaseTextureTransform:GetField(1, 2),
        materialInfo.BaseTextureTransform:GetField(1, 4),
        materialInfo.DetailTint and materialInfo.DetailTint.x or 1,
        materialInfo.BaseTextureTransform:GetField(2, 1),
        materialInfo.BaseTextureTransform:GetField(2, 2),
        materialInfo.BaseTextureTransform:GetField(2, 4),
        materialInfo.DetailTint and materialInfo.DetailTint.y or 1,
        materialInfo.BumpTextureTransform:GetField(1, 1),
        materialInfo.BumpTextureTransform:GetField(1, 2),
        materialInfo.BumpTextureTransform:GetField(1, 4),
        materialInfo.DetailTint and materialInfo.DetailTint.z or 1,
        materialInfo.BumpTextureTransform:GetField(2, 1),
        materialInfo.BumpTextureTransform:GetField(2, 2),
        materialInfo.BumpTextureTransform:GetField(2, 4),
        hasDetail and (materialInfo.DetailBlendFactor or 1) or 0)
    mat:SetMatrix("$viewprojmat", m)
    if materialInfo.HasBaseTexture3 then
        set4WayBlendParams(m, materialInfo.Material)
    else
        m:SetUnpacked(
            materialInfo.BlendMaskTransform:GetField(1, 1),
            materialInfo.BlendMaskTransform:GetField(1, 2),
            materialInfo.BlendMaskTransform:GetField(1, 4), 0,
            materialInfo.BlendMaskTransform:GetField(2, 1),
            materialInfo.BlendMaskTransform:GetField(2, 2),
            materialInfo.BlendMaskTransform:GetField(2, 4), 0,
            0, 0, 0, 0,
            0, 0, 0, 0)
    end
    mat:SetMatrix("$invviewprojmat", m)
    InkMaterials.AddWorld(mat, materialInfo.Material)
    return mat
end

---Writes the constants of the ink material drawing the world ink meshes in water reflections.
function InkMeshMaterial.SetupWater()
    local mat = Material "splashsweps/shaders/inkmesh"
    DetailAtlas.WriteLayout(mat)
    mat:SetFloat("$c1_z", 2 / RenderTargets.GetHammerUnitsToUV())
end

return InkMeshMaterial
