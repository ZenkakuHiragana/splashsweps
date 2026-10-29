
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {}
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/server/playerconnection.lua"

---@class ss
local ss = SplashSWEPs

local CacheBuilder     = ss.import "splashsweps/shared/mapcache/cachebuilder"
local Hash             = ss.import "splashsweps/shared/hash"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local Paint            = ss.import "splashsweps/shared/paint/paint"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"

local function LoadCache()
    local cache = CacheBuilder.Load()
    if not cache then return end

    Hash.Setup(cache.SurfaceHash, cache.HashParameters)
    PaintableSurface.Setup(cache.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps)
    InkShape.Load()
    InkType.Load()
end

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    LoadCache()
    Paint.ClearAll()
    collectgarbage "collect"
end)

util.AddNetworkString "SplashSWEPs: Clear all ink"
util.AddNetworkString "SplashSWEPs: Paint"
util.AddNetworkString "SplashSWEPs: Paint brush model"
