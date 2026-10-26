
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {}
end

---@class ss
local ss = SplashSWEPs

include "splashsweps/shared/autorun.lua"
include "splashsweps/client/debug_mesh.lua"
include "splashsweps/client/render/inkpass.lua"

local Hash              = ss.import "splashsweps/shared/hash"
local InkAtlases        = ss.import "splashsweps/client/ink/atlases"
local InkMap            = ss.import "splashsweps/client/render/inkmap"
local InkShape          = ss.import "splashsweps/shared/inkshape"
local InkType           = ss.import "splashsweps/shared/inktype"
local PaintableSurface  = ss.import "splashsweps/shared/paint/paintablesurface"
local Players           = ss.import "splashsweps/shared/players"
local PrecachedData     = ss.import "splashsweps/shared/typing/precachedata"
local RenderTargets     = ss.import "splashsweps/client/render/rendertargets"
local StaticPropBuilder = ss.import "splashsweps/client/mapload/staticpropbuilder"
local Paint             = ss.import "splashsweps/shared/paint/paint"
local InkMesh           = ss.import "splashsweps/client/render/inkmesh"

local function LoadCache()
    local cachePath = string.format("splashsweps/%s.dat", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.dat", game.GetMap())
    local hdrPath = string.format("splashsweps/%s_hdr.dat", game.GetMap())
    local ldrExists = file.Exists(ldrPath, "DATA")
    local hdrExists = file.Exists(hdrPath, "DATA")
    local cache = PrecachedData.ReadFile(cachePath, "PrecachedData") ---@type ss.PrecachedData?
    if not cache then return end

    local ishdr = false
    if render.GetHDREnabled() then
        ishdr = hdrExists
    else
        ishdr = not ldrExists
    end

    local surfacePath = ishdr and hdrPath or ldrPath
    local staticPropUV = (ishdr and cache.StaticPropHDR or cache.StaticPropLDR) or {} -- nil without static props
    local waterSurfaces = ishdr and cache.SurfacesWaterHDR or cache.SurfacesWaterLDR
    local surfaces = PrecachedData.ReadFile(surfacePath, "PrecachedData.SurfaceInfo") ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then return end

    Hash.Setup(surfaces.SurfaceHash, cache.HashParameters)
    RenderTargets.Setup(surfaces.UVScales[#PrecachedData.InkMapResolutions])
    InkShape.Load()
    InkType.Load()
    InkAtlases.Load()
    InkMap.Setup()
    InkMesh.Setup(surfaces, cache.NumModels, cache.MaterialNames)
    PaintableSurface.Setup(surfaces.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps, {
        UVInfo = staticPropUV,
        HammerUnitsToUV = RenderTargets.GetHammerUnitsToUV(),
    })
    StaticPropBuilder.Setup(cache.StaticProps, cache.StaticPropMDL, staticPropUV, surfaces.Cubemaps)
    InkMap.ClearAll()
end

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    LoadCache()
    collectgarbage "collect"
    net.Start "SplashSWEPs: PlayerInitialSpawn"
    net.SendToServer()
end)

net.Receive("SplashSWEPs: Paint", function()
    Paint.PaintWorld(Paint.Read())
end)

net.Receive("SplashSWEPs: Paint brush model", function()
    local modelIndex = Paint.ReadModelIndex()
    Paint.PaintBrushModel(modelIndex, Paint.Read())
end)

net.Receive("SplashSWEPs: Clear all ink", function() InkMap.ClearAll() end)
net.Receive("SplashSWEPs: Refresh players table", function()
    Players.Replace(net.ReadTable(true))
end)
