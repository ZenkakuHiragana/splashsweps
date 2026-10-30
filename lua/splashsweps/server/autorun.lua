
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

-- A net message sent here reaches the client before its InitPostEntity, where the client defines the same ink shapes and types.
hook.Add("PlayerInitialSpawn", "SplashSWEPs: Send ink definitions", function(ply)
    net.Start "SplashSWEPs: Ink definitions"
    InkShape.Write()
    InkType.Write()
    net.Send(ply)
end)

util.AddNetworkString "SplashSWEPs: Ink definitions"
util.AddNetworkString "SplashSWEPs: Clear all ink"
util.AddNetworkString "SplashSWEPs: Paint"
util.AddNetworkString "SplashSWEPs: Paint brush model"
