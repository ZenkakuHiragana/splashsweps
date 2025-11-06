
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
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
local function LoadCache()
    local cachePath = string.format("splashsweps/%s.json", game.GetMap())
    local pngldrPath = string.format("../data/splashsweps/%s_ldr.vtf", game.GetMap())
    local pnghdrPath = string.format("../data/splashsweps/%s_hdr.vtf", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local hdrPath = string.format("splashsweps/%s_hdr.json", game.GetMap())
    local pngldrExists = file.Exists(pngldrPath:sub(9), "DATA")
    local pnghdrExists = file.Exists(pnghdrPath:sub(9), "DATA")
    local ldrExists = file.Exists(ldrPath, "DATA")
    local hdrExists = file.Exists(hdrPath, "DATA")
    local cache = util.JSONToTable(util.Decompress(file.Read(cachePath) or "") or "", true) ---@type ss.PrecachedData?
    if not cache then return end
    setmetatable(cache, getmetatable(ss.new "PrecachedData"))

    local ishdr = false
    if render.GetHDREnabled() then
        ishdr = hdrExists and pnghdrExists
    else
        ishdr = not (ldrExists and pngldrExists)
    end

    local pngPath = ishdr and pnghdrPath or pngldrPath
    local surfacePath = ishdr and hdrPath or ldrPath
    local modelInfo = ishdr and cache.ModelsHDR or cache.ModelsLDR
    local staticPropUV = ishdr and cache.StaticPropHDR or cache.StaticPropLDR
    local waterSurfaces = ishdr and cache.SurfacesWaterHDR or cache.SurfacesWaterLDR

    ---@type ss.PrecachedData.SurfaceInfo
    local surfaces = util.JSONToTable(util.Decompress(file.Read(surfacePath) or "") or "", true) or {}
    setmetatable(surfaces, getmetatable(ss.new "PrecachedData.SurfaceInfo"))

    ss.SURFACE_ID_BITS = select(2, math.frexp(#surfaces.Surfaces))
    ss.RenderTarget.HammerUnitsToUV = surfaces.UVScales[#ss.RenderTarget.Resolutions]
    ss.SurfaceHash = surfaces.SurfaceHash
    ss.HashParameters = setmetatable(cache.HashParameters, getmetatable(ss.new "PrecachedData.HashParameters"))

    ss.SetupRenderTargets()
    ss.SetupHDRLighting(cache)
    ss.SetupModels(modelInfo, surfaces)
    ss.SetupSurfaces(surfaces.Surfaces)
    ss.SetupSurfacesStaticProp(cache.StaticProps, staticPropUV)
    ss.SetupStaticProps(cache.StaticProps, cache.StaticPropMDL, staticPropUV)
    ss.SetupLightmap(pngPath)
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
    ss.LoadInkMaterials()
end

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    LoadCache()
    collectgarbage "collect"
    net.Start "SplashSWEPs: PlayerInitialSpawn"
    net.SendToServer()
end)

net.Receive("SplashSWEPs: Refresh players table", function()
    local playersReady = net.ReadTable()
    table.Empty(ss.PlayersReady)
    table.Empty(ss.PlayerIndices)
    table.Merge(ss.PlayersReady, playersReady)
    table.Merge(ss.PlayerIndices, table.Flip(playersReady))
end)
