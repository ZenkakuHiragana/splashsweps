
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
        ---Various debug data goes here
        Debug = {},
        ---Contains information around render targets clientside.
        RenderTarget = {
            Resolutions = {
                2048,
                4096,
                5792,
                8192,
                11586,
                16384,
            },
        },
    }
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/server/playerconnection.lua"
include "splashsweps/server/mapcache/bsploader.lua"
include "splashsweps/server/mapcache/cachebuilder.lua"
include "splashsweps/server/mapcache/lightmapbuilder.lua"
include "splashsweps/server/mapcache/surfacebuilder.lua"
include "splashsweps/server/mapcache/uvbuilder.lua"
include "splashsweps/server/packer/packer.lua"
include "splashsweps/server/packer/structures.lua"

---@class ss
local ss = SplashSWEPs
local function LoadCache()
    local txtPath = string.format("splashsweps/%s.json", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(util.Decompress(file.Read(txtPath) or "") or "", true)
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    setmetatable(cache or {}, getmetatable(ss.new "PrecachedData"))
    if not cache or cache.MapCRC ~= tonumber(mapCRC) then
        cache = ss.BuildMapCache() or {}
        file.Write(txtPath, util.Compress(util.TableToJSON(cache)))
    end

    ---@type ss.PrecachedData.SurfaceInfo?
    local ldr = util.JSONToTable(util.Decompress(file.Read(ldrPath) or "") or "", true)
    if not ldr then return end
    setmetatable(cache, getmetatable(ss.new "PrecachedData"))
    setmetatable(ldr, getmetatable(ss.new "PrecachedData.SurfaceInfo"))

    ss.SurfaceHash = ldr.SurfaceHash
    ss.HashParameters = setmetatable(cache.HashParameters, getmetatable(ss.new "PrecachedData.HashParameters"))
    ss.SetupSurfaces(ldr.Surfaces)
    ss.SetupSurfacesStaticProp(cache.StaticProps, cache.StaticPropLDR)
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
end

hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    LoadCache()
    collectgarbage "collect"
end)

util.AddNetworkString "SplashSWEPs: Clear all ink"
util.AddNetworkString "SplashSWEPs: Paint"

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(ss.SurfaceArray) do ss.ClearGrid(s) end
    net.Start "SplashSWEPs: Clear all ink"
    net.Broadcast()
end
