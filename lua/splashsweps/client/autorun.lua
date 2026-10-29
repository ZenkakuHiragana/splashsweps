
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {}
end

---@class ss
local ss = SplashSWEPs

include "splashsweps/shared/autorun.lua"
include "splashsweps/client/debug_mesh.lua"
include "splashsweps/client/render/inkpass.lua"

local CacheBuilder      = ss.import "splashsweps/shared/mapcache/cachebuilder"
local Hash              = ss.import "splashsweps/shared/hash"
local InkAtlases        = ss.import "splashsweps/client/ink/atlases"
local InkMap            = ss.import "splashsweps/client/render/inkmap"
local InkMapLayout      = ss.import "splashsweps/client/mapload/inkmaplayout"
local InkShape          = ss.import "splashsweps/shared/inkshape"
local InkType           = ss.import "splashsweps/shared/inktype"
local PaintableSurface  = ss.import "splashsweps/shared/paint/paintablesurface"
local Players           = ss.import "splashsweps/shared/players"
local RenderTargets     = ss.import "splashsweps/client/render/rendertargets"
local StaticPropBuilder = ss.import "splashsweps/client/mapload/staticpropbuilder"
local Paint             = ss.import "splashsweps/shared/paint/paint"
local InkMesh           = ss.import "splashsweps/client/render/inkmesh"

local CVarDebugMeshData = CreateClientConVar("ss_debug_mesh_data", "0", false, false,
    "1 keeps the vertices of the ink meshes built at map load, for debugging. It takes as much memory as the meshes.")

local function LoadCache()
    local cache = CacheBuilder.Load()
    if not cache then return end

    -- The engine packs the HDR lightmaps if HDR is enabled, and the cache has them only if the faces match.
    local lightmaps = render.GetHDREnabled() and cache.LightmapsHDR or cache.LightmapsLDR or {}
    Hash.Setup(cache.SurfaceHash, cache.HashParameters)
    RenderTargets.Setup(cache.HammerUnitsToUV)
    InkShape.Load()
    InkType.Load()
    InkAtlases.Load()
    InkMap.Setup()
    PaintableSurface.Setup(cache.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps)
    InkMapLayout.Setup(cache.Surfaces, cache.StaticProps)
    InkMesh.Setup(cache, lightmaps, InkMapLayout.Placements, CVarDebugMeshData:GetBool())
    StaticPropBuilder.Setup(cache.StaticProps, cache.StaticPropMDL, cache.Cubemaps)
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
