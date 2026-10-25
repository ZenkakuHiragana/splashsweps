
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
        ---Various debug data goes here
        Debug = {},
        ---Contains information around render targets clientside.
        RenderTarget = {
            Resolutions = {
                4096,
                8192,
                16384,
            },
        },
    }
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/server/playerconnection.lua"
include "splashsweps/server/mapcache/cachebuilder.lua"
include "splashsweps/server/mapcache/lightmapbuilder.lua"
include "splashsweps/server/mapcache/surfacebuilder.lua"
include "splashsweps/server/mapcache/uvbuilder.lua"

---@class ss
local ss = SplashSWEPs

local InkFeature       = ss.import "splashsweps/shared/inkfeature"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"

local function LoadCache()
    local txtPath = string.format("splashsweps/%s.json", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local cache = PrecachedData.restore(util.JSONToTable(util.Decompress(file.Read(txtPath) or "") or "", true))
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    file.CreateDir "splashsweps"
    if not cache or cache.MapCRC ~= tonumber(mapCRC) or cache.CacheVersion ~= ss.CACHE_VERSION then
        cache = ss.BuildMapCache() or {}
        file.Write(txtPath, util.Compress(util.TableToJSON(cache)))
    end

    local ldr = PrecachedData.SurfaceInfo.restore(util.JSONToTable(util.Decompress(file.Read(ldrPath) or "") or "", true))
    if not ldr then return end

    ss.SurfaceHash = ldr.SurfaceHash
    ss.HashParameters = cache.HashParameters
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

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(PaintableSurface.Surfaces) do PaintableGrid.Clear(s) end
    net.Start "SplashSWEPs: Clear all ink"
    net.Broadcast()
end
