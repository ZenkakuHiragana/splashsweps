
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {}
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/server/playerconnection.lua"

---@class ss
local ss = SplashSWEPs

local CacheBuilder     = ss.import "splashsweps/server/mapcache/cachebuilder"
local Hash             = ss.import "splashsweps/shared/hash"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"

local function LoadCache()
    local cachePath = string.format("splashsweps/%s.dat", game.GetMap())
    local surfacesPath = string.format("splashsweps/%s_surfaces.dat", game.GetMap())
    local cache = PrecachedData.ReadFile(cachePath, "PrecachedData") ---@type ss.PrecachedData?
    file.CreateDir "splashsweps"
    if not cache or cache.Revision ~= game.GetMapVersion() then
        cache = CacheBuilder.Build()
        if not cache then return end
        PrecachedData.WriteFile(cachePath, "PrecachedData", cache)
        PrecachedData.CompressFile(cachePath)
    end

    local surfaces = PrecachedData.ReadFile(surfacesPath, "PrecachedData.SurfaceInfo") ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then return end

    Hash.Setup(surfaces.SurfaceHash, cache.HashParameters)
    PaintableSurface.Setup(surfaces.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps)
    InkShape.Load()
    InkType.Load()
end

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    LoadCache()
    collectgarbage "collect"
end)

util.AddNetworkString "SplashSWEPs: Clear all ink"
util.AddNetworkString "SplashSWEPs: Paint"
util.AddNetworkString "SplashSWEPs: Paint brush model"
