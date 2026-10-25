
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
    local txtPath = string.format("splashsweps/%s.json", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local cacheJSON = util.JSONToTable(util.Decompress(file.Read(txtPath) or "") or "", true)
    local cache = cacheJSON and PrecachedData.restore(cacheJSON)
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    file.CreateDir "splashsweps"
    if not cache or cache.MapCRC ~= tonumber(mapCRC) or cache.CacheVersion ~= ss.CACHE_VERSION then
        cache = CacheBuilder.Build() or {}
        file.Write(txtPath, util.Compress(util.TableToJSON(cache)))
    end

    local ldrJSON = util.JSONToTable(util.Decompress(file.Read(ldrPath) or "") or "", true)
    local ldr = ldrJSON and PrecachedData.SurfaceInfo.restore(ldrJSON)
    if not ldr then return end

    Hash.Setup(ldr.SurfaceHash, cache.HashParameters)
    PaintableSurface.Setup(ldr.Surfaces, cache.NumModels)
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
