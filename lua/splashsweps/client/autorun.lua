
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
local InkMapLayout      = ss.import "splashsweps/client/mapload/inkmaplayout"
local InkShape          = ss.import "splashsweps/shared/inkshape"
local InkType           = ss.import "splashsweps/shared/inktype"
local PaintableSurface  = ss.import "splashsweps/shared/paint/paintablesurface"
local Players           = ss.import "splashsweps/shared/players"
local PrecachedData     = ss.import "splashsweps/shared/typing/precachedata"
local RenderTargets     = ss.import "splashsweps/client/render/rendertargets"
local StaticPropBuilder = ss.import "splashsweps/client/mapload/staticpropbuilder"
local Paint             = ss.import "splashsweps/shared/paint/paint"
local InkMesh           = ss.import "splashsweps/client/render/inkmesh"

local CVarDebugMeshData = CreateClientConVar("ss_debug_mesh_data", "0", false, false,
    "1 keeps the vertices of the ink meshes built at map load, for debugging. It takes as much memory as the meshes.")

local function LoadCache()
    local cachePath = string.format("splashsweps/%s.dat", game.GetMap())
    local surfacesPath = string.format("splashsweps/%s_surfaces.dat", game.GetMap())
    local cache = PrecachedData.ReadFile(cachePath, "PrecachedData") ---@type ss.PrecachedData?
    if not cache then return end

    local surfaces = PrecachedData.ReadFile(surfacesPath, "PrecachedData.SurfaceInfo") ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then return end

    -- The engine packs the HDR lightmaps if HDR is enabled, and the cache has them only if the faces match.
    local lightmaps = render.GetHDREnabled() and surfaces.LightmapsHDR or surfaces.LightmapsLDR or {}
    Hash.Setup(surfaces.SurfaceHash, cache.HashParameters)
    RenderTargets.Setup(surfaces.HammerUnitsToUV)
    InkShape.Load()
    InkType.Load()
    InkAtlases.Load()
    InkMap.Setup()
    PaintableSurface.Setup(surfaces.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps)
    InkMapLayout.Setup(surfaces.Surfaces, cache.StaticProps)
    InkMesh.Setup(surfaces, lightmaps, InkMapLayout.Placements, cache.NumModels, cache.MaterialNames,
        CVarDebugMeshData:GetBool())
    StaticPropBuilder.Setup(cache.StaticProps, cache.StaticPropMDL, surfaces.Cubemaps)
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
