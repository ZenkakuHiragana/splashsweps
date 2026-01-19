
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkMaterials then
    locals.InkMaterials = {}
end

---A set of drawing materials of the ink for the combination of ink type and ink shape.
---@type table<string, IMaterial>
local InkMaterials = locals.InkMaterials

---Returns the key of InkMaterials from ss.InkType and ss.InkShape.
---@param inktype ss.InkType
---@param shape ss.InkShape
---@return string
local function GetInkMaterialKey(inktype, shape)
    return shape.Identifier .. ":" .. inktype.Identifier
end

---Retrieves corresponding drawing material from ss.InkType and ss.InkShape
---@param inktype ss.InkType
---@param shape ss.InkShape
---@return IMaterial
function ss.GetInkMaterial(inktype, shape)
    return InkMaterials[GetInkMaterialKey(inktype, shape)]
end

---Constructs drawing materials using ss.InkTypes and ss.InkShapes
function ss.LoadInkMaterials()
    for _, shape in pairs(ss.InkShapes) do
        for _, inktype in pairs(ss.InkTypes) do
            local materialId = GetInkMaterialKey(inktype, shape)
            InkMaterials[materialId] = CreateMaterial(
                materialId,
                "Screenspace_General", {
                    ["$pixshader"]           = "splashsweps/drawink_ps30",
                    ["$vertexshader"]        = "splashsweps/drawink_vs30",
                    ["$alpha_blend"]         = "0",
                    ["$cull"]                = "1",
                    ["$depthtest"]           = "1",
                    ["$linearread_texture1"] = "1",
                    ["$linearread_texture2"] = "1",
                    ["$linearwrite"]         = "1",
                    ["$softwareskin"]        = "1",
                    ["$writealpha"]          = "1",
                    ["$vertexalpha"]         = "1",
                    ["$vertexcolor"]         = "1",
                    ["$basetexture"]         = inktype.BaseTexture,
                    ["$texture1"]            = inktype.Bumpmap,
                    ["$texture2"]            = inktype.PBRTexture,
                    ["$texture3"]            = shape.MaskTexture,
                    ["$fix_flags2"]          = "510",
                    Proxies = { -- Fixes the material flags
                        Equals = {
                            srcVar1   = "$fix_flags2",
                            resultVar = "$flags2",
                        },
                    },
                })
        end
    end
end
