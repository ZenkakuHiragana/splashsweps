
-- Encodes the parameters of ink types into the ink data: texels of the ink detail atlas the shaders read,
-- one column per ink type and one texel per parameter slot.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"
local VTF  = ss.import "splashsweps/shared/vtf/reader"

---@class ss.InkDataModule
local InkData = ss.module "splashsweps/client/ink/inkdata"

---@class ss.InkDataModule.State
---@field AverageHeights table<string, number> Mean alpha of each texture's smallest stored mipmap
local state = ss.state("splashsweps/client/ink/inkdata", { AverageHeights = {} }) ---@type ss.InkDataModule.State

---Averages the smallest stored mipmap, including levels the engine may omit without ALL_MIPS.
---@param path string
---@return number
local function GetAverageHeight(path)
    if state.AverageHeights[path] then return state.AverageHeights[path] end
    local vtf = VTF.Read(path)
    Util.assert(vtf, "Automatic height baseline has invalid texture (" .. path .. ")") ---@cast vtf -?
    local level = #vtf.Images
    local image = vtf.Images[level]
    local alpha = 0
    for y = 0, image.Height - 1 do
        for x = 0, image.Width - 1 do
            alpha = alpha + VTF.ReadPixel(vtf, x, y, level).a
        end
    end
    local average = alpha / (255 * image.Width * image.Height)
    state.AverageHeights[path] = average
    return average
end

---Reads the ink material and encodes its ink data.
---Lua index j corresponds to the parameter slot ID j - 1 of the shaders; image cell numbers are 1-based here.
---@param mat             IMaterial The ink material
---@param detailSlot      integer?  Grid cell of the detail image, nil if the ink type has none
---@param baseTextureName string    Source of the automatic height baseline
---@return number[][] inkData Texels of four components each, indexed by parameter slot
function InkData.Encode(mat, detailSlot, baseTextureName)
    local heightbaseline = mat:GetFloat "$heightbaseline" or -1
    if heightbaseline < 0 then heightbaseline = GetAverageHeight(baseTextureName) end
    local detailtexturetransform = mat:GetMatrix "$detailtexturetransform" or Matrix()
    local detailtransformscale   = detailtexturetransform:GetScale()
    local detailTranslationUV    = detailtexturetransform:GetTranslation()
    local detailRotationCosSin   = detailtexturetransform:GetForward():GetNormalized() -- (cos, sin, 0)
    local detailPeriodHU         = mat:GetFloat "$detailperiod" or 512
    local detailblendscale       = { mat:GetVector4D "$detailblendscale" }
    local detailheightsource     = math.Clamp(mat:GetInt "$detailheightsource" or 0, 0, 3)
    local detailheightinvert     = math.Clamp(mat:GetInt "$detailheightinvert" or 0, 0, 1)
    local heightLimitHU          = math.Clamp(mat:GetFloat "$detailheightmax" or 24, 0, 24)
    local heightLimitSqrtCode5   = math.Clamp(math.Round(math.sqrt(heightLimitHU / 24) * 32) - 1, 0, 31)
    local color                  = mat:GetVector "$color"     or Util.vector_one
    local tintcolor              = mat:GetVector "$tintcolor" or Util.vector_one
    local alpha                  = mat:GetFloat "$alpha" or 1
    local maxheight              = mat:GetFloat "$maxheight" or 1
    local normalBlendThicknessHU = mat:GetFloat "$bumpblendheight" or maxheight * 24
    return {
        { color.x,     color.y,     color.z,     alpha },
        { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
        {
            (mat:GetInt "$maxlayers" or 1) / 255,
            maxheight,
            math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
            heightbaseline,
        }, {
            mat:GetFloat "$erase"           or 0,
            mat:GetFloat "$flatten"         or 0,
            math.Clamp(normalBlendThicknessHU / 24, 0, 1),
            ((mat:GetInt "$nodig"      or 0) * 128 +
            (mat:GetInt  "$heightonly" or 0) * 64 +
            (mat:GetInt "$detaillocal" or 0) * 32) / 255,
        }, {
            mat:GetFloat "$metallic"        or 0,
            mat:GetFloat "$roughness"       or 0,
            mat:GetFloat "$specularscale"   or 1,
            1 - 1 / (mat:GetFloat "$refractiveindex" or 1.33), -- Refraction strength for the shader
        },
        {
            0, 0, 0, -- Unused
            mat:GetFloat "$viscosity" or 1,
        },
        {
            -- 127 / 255 represents 1
            (detailblendscale[1] or 1) * 127 / 255,
            (detailblendscale[2] or 1) * 127 / 255,
            (detailblendscale[3] or 1) * 127 / 255,
            (detailblendscale[4] or 1) * 127 / 255,
        }, {
            detailTranslationUV.x % 1,
            detailTranslationUV.y % 1,
            -- 127 / 255 represents zero
            (detailRotationCosSin.x + 1) * 127 / 255,
            (detailRotationCosSin.y + 1) * 127 / 255,
        }, {
            -- Image repeats per Hammer unit, log2 with 24 steps per octave from 2^-13
            (math.log(detailtransformscale.x / detailPeriodHU, 2) + 13) * 24 / 255,
            (math.log(detailtransformscale.y / detailPeriodHU, 2) + 13) * 24 / 255,
            ((detailSlot or 1) - 1) / 255, -- Grid index of the detail image
            -- bit 0: invert; bits 1..2: source (0 = off, 1 = thickness, 2 = height, 3 = depth).
            -- bits 3..7: sqrt-encode the height limit to give small limits finer steps within five bits.
            -- The 32 decoded levels stay above zero to avoid division by zero in the shader's height weight.
            (heightLimitSqrtCode5 * 8 + detailheightsource * 2 + detailheightinvert) / 255,
        },
    }
end

return InkData
