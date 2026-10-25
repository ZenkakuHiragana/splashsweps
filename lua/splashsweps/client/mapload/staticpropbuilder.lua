
-- Creates the models of static props that draw their paint, and their ink sprp materials.

---@class ss
local ss = SplashSWEPs
local InkDetailAtlas     = ss.import "splashsweps/client/ink/inkdetailatlas"
local PrecachedData      = ss.import "splashsweps/shared/typing/precachedata"
local RenderTargets      = ss.import "splashsweps/client/render/rendertargets"
local StaticPropRenderer = ss.import "splashsweps/client/render/staticproprenderer"
local UnderlaySync       = ss.import "splashsweps/client/render/underlaysync"
local Util               = ss.import "splashsweps/shared/util"

---@class ss.StaticPropBuilderModule
local StaticPropBuilder = ss.module "splashsweps/client/mapload/staticpropbuilder"

-- MaterialVarFlags_t in imaterial.h of Source
local MATERIAL_VAR_SELFILLUM = 64
local MATERIAL_VAR_ALPHATEST = 256
local MATERIAL_VAR_NOCULL = 8192
local MATERIAL_VAR_BASEALPHAENVMAPMASK = 1048576
local MATERIAL_VAR_NORMALMAPALPHAENVMAPMASK = 4194304

---Whether $envmap of a model material names a texture.
---Otherwise (env_cubemap or none), the cubemap nearest to the prop is used.
---@param envmap string?
---@return boolean
local function isEnvmapTexture(envmap)
    if not envmap or envmap == "" then return false end
    return envmap:lower():gsub("%.vtf$", ""):gsub("%.hdr$", "") ~= "env_cubemap"
end

---Returns the $basetexture alpha below which the alpha test of a VertexLitGeneric material discards pixels,
---or 0 if the test does not read it. $alpha is not taken into account.
---
---  $alphatest   alpha of $basetexture used for                      returns
---  ----------   -------------------------------------------------   ---------
---  no           -                                                   0
---  yes          $selfillum, $basealphaenvmapmask (the engine        0
---               clears $alphatest), or $blendtintbybasealpha
---  yes          none of them                                        reference
---
---$normalmapalphaenvmapmask with $bumpmap or $lightwarptexture takes the mask from $bumpmap instead.
---See InitParamsVertexLitGeneric_DX9 in vertexlitgeneric_dx9_helper.cpp of Source.
---@param mat IMaterial
---@return number
local function getAlphaTestReference(mat)
    local flags = mat:GetInt "$flags" or 0
    local hasTangentSpace = mat:GetString "$bumpmap" or mat:GetString "$lightwarptexture"
    local usesNormalMapAlpha = hasTangentSpace and bit.band(flags, MATERIAL_VAR_NORMALMAPALPHAENVMAPMASK) ~= 0
    if bit.band(flags, MATERIAL_VAR_ALPHATEST) == 0
    or bit.band(flags, MATERIAL_VAR_SELFILLUM) ~= 0
    or bit.band(flags, MATERIAL_VAR_BASEALPHAENVMAPMASK) ~= 0 and not usesNormalMapAlpha
    or (mat:GetInt "$blendtintbybasealpha" or 0) ~= 0 then
        return 0
    end

    -- The engine uses 0.7 unless $alphatestreference is positive, and compares 8-bit alpha with it.
    local reference = mat:GetFloat "$alphatestreference" or 0
    return math.floor((reference > 0 and reference or 0.7) * 255) / 255
end

---Creates the models and the ink sprp materials of static props.
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param modelNames     string[]
---@param uvInfo         ss.PrecachedData.StaticProp.UVInfo[][]
---@param cubemaps       ss.PrecachedData.CubemapInfo[]
function StaticPropBuilder.Setup(staticPropInfo, modelNames, uvInfo, cubemaps)
    local templateMaterial = Material "splashsweps/shaders/staticprop"
    local materialCache = {} ---@type table<string, IMaterial>
    local watchedMaterials = {} ---@type { Material: IMaterial }[]
    local identity = Matrix()
    local matKeyValues = templateMaterial:GetKeyValues() ---@type table<string, string|number>
    local transforms = Matrix()
    matKeyValues["$flags"] = nil
    matKeyValues["$flags2"] = nil
    matKeyValues["$flags_defined"] = nil
    matKeyValues["$flags_defined2"] = nil
    matKeyValues["$basetexture"] = RenderTargets.InkMaps.InkMap:GetName()
    matKeyValues["$texture1"] = InkDetailAtlas.GetRenderTarget():GetName()
    matKeyValues["$texture2"] = RenderTargets.Frame.SceneAndFlashlight:GetName()
    matKeyValues["$texture5"] = RenderTargets.Frame.StaticPropFlashlight:GetName()
    matKeyValues["$linearread_texture7"] = render.GetHDREnabled() and "1" or "0"
    matKeyValues["$c0_x"] = ss.RT_BILINEAR_GUARD_PIXELS
    matKeyValues["$c1_z"] = 2 / RenderTargets.GetHammerUnitsToUV() -- InkMap region UV -> packed-surface HU.

    -- Matrix(X, Y, Z) * xyzTyzx = (Y, Z, X)
    local xyzTyzx = Matrix {
        { 0, 0, 1, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 0, 1 },
    }
    -- xyzTzxy = xyzTyzx * xyzTyzx
    -- xyzTzxy * Vector(X, Y, Z) = (Y, Z, X)
    local xyzTzxy = xyzTyzx:GetTransposed()
    for i, prop in ipairs(staticPropInfo or {}) do
        local uv = uvInfo[i][#PrecachedData.InkMapResolutions]
        local modelName = modelNames[prop.ModelIndex]
        if modelName then
            ---@class ss.PaintableCSEnt : CSEnt
            ---@field QueuedFlags Enum.STUDIO? Flags the engine drew this prop with in the current view.
            local mdl = ClientsideModel(modelName)
            if mdl then
                mdl:SetPos(prop.Position or Vector())
                mdl:SetAngles(prop.Angles or Angle())
                mdl:SetKeyValue("fademindist", prop.FadeMin or -1)
                mdl:SetKeyValue("fademaxdist", prop.FadeMax or 0)
                mdl:SetModelScale(prop.Scale or 1)
                mdl:SetSkin(prop.Skin or 0)
                mdl.RenderOverride = StaticPropRenderer.Queue
                local fadeMax = prop.FadeMax and prop.FadeMax > 0 and prop.FadeMax or false
                local mins, maxs = mdl:GetModelBounds()
                mdl.FadeMaxSqr = fadeMax and (fadeMax * fadeMax)
                mdl.ModelLengthSqr = mins:DistToSqr(maxs)
                local size = prop.BoundsMax - prop.BoundsMin
                local localTworld = mdl:GetWorldTransformMatrix()
                localTworld:SetTranslation(localTworld * prop.BoundsMin)
                if prop.UnwrapIndex == 2 then
                    -- (X, Y, Z) * xyzTyzx = (Y, Z, X)
                    localTworld:Mul(xyzTyzx)
                    size:Mul(xyzTzxy)
                elseif prop.UnwrapIndex == 3 then
                    -- (X, Y, Z) * xyzTzxy = (Z, X, Y)
                    localTworld:Mul(xyzTzxy)
                    size:Mul(xyzTyzx)
                end
                localTworld:InvertTR()

                -- $invviewprojmat = c15..c18 of the static prop ink shader:
                --   rows 1-3  world -> bounding box (origin at the minimum corner, axes permuted)
                --   row 4     size.x  size.y  size.z  margin
                localTworld:SetField(4, 1, size.x)
                localTworld:SetField(4, 2, size.y)
                localTworld:SetField(4, 3, size.z)
                localTworld:SetField(4, 4, ss.MARGIN_HAMMER_UNITS)

                -- The cache has the cubemap names without ".hdr"
                local cubemap = cubemaps[prop.CubemapIndex]
                local nearestEnvmap = cubemap and cubemap.Envmap .. (render.GetHDREnabled() and ".hdr" or "") or UnderlaySync.DEFAULT_ENVMAP
                local params = table.Merge(matKeyValues, {
                    ["$c1_y"] = uv.Offset.z > 0 and uv.Width or 0,
                    ["$c2_x"] = uv.Offset.x,
                    ["$c2_y"] = uv.Offset.y,
                })
                for j, name in ipairs(mdl:GetMaterials()) do
                    local mdlmat = materialCache[name]
                    if not mdlmat then
                        mdlmat = Material(name)
                        materialCache[name] = mdlmat
                        watchedMaterials[#watchedMaterials + 1] = { Material = mdlmat }
                    end

                    local baseTextureTransform = mdlmat:GetMatrix "$basetexturetransform" or identity
                    local bumpTransform = mdlmat:GetMatrix "$bumptransform" or identity
                    local color = (mdlmat:GetVector "$color" or Util.vector_one)
                                * (mdlmat:GetVector "$color2" or Util.vector_one)
                    params["$texture3"] = mdlmat:GetString "$basetexture" or "white"
                    params["$texture4"] = mdlmat:GetString "$bumpmap" or "null-bumpmap"
                    -- $envmap        $texture7
                    -- -------------  ------------------------------
                    -- a texture      the texture
                    -- env_cubemap    the cubemap of the prop
                    -- none           the cubemap of the prop
                    local envmap = mdlmat:GetString "$envmap"
                    params["$texture7"] = isEnvmapTexture(envmap) and envmap or nearestEnvmap
                    params["$c1_w"] = getAlphaTestReference(mdlmat)
                    params["$cull"] = bit.band(mdlmat:GetInt "$flags" or 0, MATERIAL_VAR_NOCULL) ~= 0 and 0 or 1
                    params["$c3_x"] = color.x
                    params["$c3_y"] = color.y
                    params["$c3_z"] = color.z
                    -- CreateMaterial reuses the material of the same name and ignores params,
                    -- so the values that can change on reloading the same map are set again.
                    local mat = CreateMaterial(
                        string.format("splashsweps_sprp_%d_%d_%s", i, j, game.GetMap()),
                        "Screenspace_General_8tex", params)
                    mat:SetTexture("$texture5", RenderTargets.Frame.StaticPropFlashlight)
                    InkDetailAtlas.WriteLayout(mat)
                    mat:SetFloat("$c1_z", 2 / RenderTargets.GetHammerUnitsToUV())
                    transforms:SetUnpacked(
                        baseTextureTransform:GetField(1, 1),
                        baseTextureTransform:GetField(1, 2),
                        baseTextureTransform:GetField(1, 4), 0,
                        baseTextureTransform:GetField(2, 1),
                        baseTextureTransform:GetField(2, 2),
                        baseTextureTransform:GetField(2, 4), 0,
                        bumpTransform:GetField(1, 1),
                        bumpTransform:GetField(1, 2),
                        bumpTransform:GetField(1, 4), 0,
                        bumpTransform:GetField(2, 1),
                        bumpTransform:GetField(2, 2),
                        bumpTransform:GetField(2, 4), 0)
                    mat:SetMatrix("$viewprojmat", transforms)
                    mat:SetMatrix("$invviewprojmat", localTworld)
                    mdl:SetSubMaterial(j - 1, "!" .. mat:GetName())
                    UnderlaySync.AddInkSprp(mat, mdlmat)
                end
            end
        end
    end

    UnderlaySync.WatchUnderlays(watchedMaterials)
end

return StaticPropBuilder
