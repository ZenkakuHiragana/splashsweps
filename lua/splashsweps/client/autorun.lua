
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
        ---Struct templates are stored here
        ---@type table<string, table>
        StructDefinitions = {},
        ---A hash table to represent grid separation of paintable surfaces
        --- `= { [hash] = { i1, i2, i3, ... }, ... }` where `i` is index of `ss.SurfaceArray`
        ---@type table<integer, integer[]>
        SurfaceHash = {},
        ---Array of paintable surfaces.
        ---@type ss.PaintableSurface[]
        SurfaceArray = {},
        ---A set of event handlers with interactions to painted ink.
        ---@type table<string, ss.IInkFeature>
        InkFeatures = {},
        ---Map of ink shape category --> list of indices to actual definition
        ---@type table<string, integer[]>
        InkShapeLists = {},
        ---Internal shape index --> ss.InkShape object
        ---@type ss.InkShape[]
        InkShapes = {},
        ---Definition of ink type (color and functionality)
        ---@type ss.InkType[]
        InkTypes = {},
        ---Conversion table from identifier string to internal index for ink type.
        ---@type table<string, integer>
        InkTypeIdentifierToIndex = {},
        ---Resolution of serverside canvas to maintain collision detection.
        InkGridCellSize = 12,
        ---Gap between surfaces in UV coordinates in pixels.
        RT_MARGIN_PIXELS = 4,
        ---Number of bits to transfer ink drop radius.
        MAX_INK_RADIUS_BITS = 8,

        ---A set of drawing materials of the ink for the combination of ink type and ink shape.
        ---@type table<string, IMaterial>
        InkMaterials = {},
        ---List of IMeshes to render the painted ink.
        ---@type { BrushEntity: Entity?, [integer]: IMesh }[]
        IMesh = {},
        ---Material to draw painted ink.
        ---@type IMaterial
        InkMeshMaterial = CreateMaterial(
            "splashsweps_inkmesh",
            "LightmappedGeneric", {
                ["$basetexture"]                 = "color",
                ["$bumpmap"]                     = "null-bumpmap",
                ["$vertexcolor"]                 = "1",
                ["$nolod"]                       = "1",
                ["$alpha"]                       = "0.99609375", -- = 255 / 256,
                ["$alphatest"]                   = "1",
                ["$alphatestreference"]          = "0.0625",
                -- ["$phong"]                       = "1",
                -- ["$phongexponent"]               = "128",
                -- ["$phongamount"]                 = "[1 1 1 1]",
                -- ["$phongmaskcontrastbrightness"] = "[2 .7]",
                -- ["$envmap"]                      = "shadertest/shadertest_env",
                -- ["$envmaptint"]                  = "[1 1 1]",
                -- ["$color"]                       = "[1 1 1]",
                -- ["$detail"]                      = "color",
                -- ["$detailscale"]                 = 1,
                -- ["$detailblendmode"]             = 5,
                -- ["$detailblendfactor"]           = 1, -- Increase this for bright ink in night maps
            }
        ),
    }
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/client/inkmaterial.lua"
include "splashsweps/client/inkrenderer.lua"
include "splashsweps/client/paintablesurface.lua"
include "splashsweps/client/rtbuilder.lua"
include "splashsweps/client/surfacebuilder.lua"

---@class ss
local ss = SplashSWEPs

local cachePath = string.format("splashsweps/%s.json", game.GetMap())
local pngldrPath = string.format("../data/splashsweps/%s_ldr.png", game.GetMap())
local pnghdrPath = string.format("../data/splashsweps/%s_hdr.png", game.GetMap())
local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
local hdrPath = string.format("splashsweps/%s_hdr.json", game.GetMap())
local pngldrExists = file.Exists(pngldrPath:sub(9), "DATA")
local pnghdrExists = file.Exists(pnghdrPath:sub(9), "DATA")
local ldrExists = file.Exists(ldrPath, "DATA")
local hdrExists = file.Exists(hdrPath, "DATA")

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    local cache = util.JSONToTable(file.Read(cachePath) or "", true) ---@type ss.PrecachedData?
    if not cache then return end

    local ishdr = false
    if render.GetHDREnabled() then
        ishdr = hdrExists and pnghdrExists
    else
        ishdr = not (ldrExists and pngldrExists)
    end

    local pngPath = ishdr and pnghdrPath or pngldrPath
    local surfacePath = ishdr and hdrPath or ldrPath
    local modelInfo = ishdr and cache.ModelsHDR or cache.ModelsLDR
    local waterSurfaces = ishdr and cache.SurfacesWaterHDR or cache.SurfacesWaterLDR

    ---@type ss.PrecachedData.SurfaceInfo
    local surfaces = util.JSONToTable(file.Read(surfacePath) or "", true) or {}

    ss.SURFACE_ID_BITS = select(2, math.frexp(#surfaces))
    ss.RenderTarget.HammerUnitsToUV = surfaces.UVScales[#ss.RenderTarget.Resolutions]

    ss.SetupHDRLighting(cache)
    ss.SetupModels(modelInfo, surfaces)
    ss.SetupSurfaces()
    ss.SetupRenderTargets()
    ss.SetupLightmap(pngPath)
    ss.GenerateHashTable()
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
    ss.LoadInkMaterials()
end)
