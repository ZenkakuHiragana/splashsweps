
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
local InkFeature       = ss.import "splashsweps/shared/inkfeature"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"

local function LoadCache()
    local txtPath = string.format("splashsweps/%s.json", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local cache = PrecachedData.restore(util.JSONToTable(util.Decompress(file.Read(txtPath) or "") or "", true))
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    file.CreateDir "splashsweps"
    if not cache or cache.MapCRC ~= tonumber(mapCRC) or cache.CacheVersion ~= ss.CACHE_VERSION then
        cache = CacheBuilder.Build() or {}
        file.Write(txtPath, util.Compress(util.TableToJSON(cache)))
    end

    local ldr = PrecachedData.SurfaceInfo.restore(util.JSONToTable(util.Decompress(file.Read(ldrPath) or "") or "", true))
    if not ldr then return end

    Hash.Setup(ldr.SurfaceHash, cache.HashParameters)
    PaintableSurface.Setup(ldr.Surfaces, cache.NumModels)
    PaintableSurface.SetupStaticProps(cache.StaticProps, cache.StaticPropLDR)
    InkFeature.Load()
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
