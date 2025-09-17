
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

local ss = SplashSWEPs
local txtPath = string.format("splashsweps/%s.json", game.GetMap())
local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(file.Read(txtPath) or "", true)
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    if not cache or cache.MapCRC ~= mapCRC then
        cache = ss.BuildMapCache() or {}
        file.Write(txtPath, util.TableToJSON(cache))
    end

    ---@type ss.PrecachedData.SurfaceInfo?
    local ldr = util.JSONToTable(file.Read(ldrPath) or "", true)
    if not ldr then return end

    ss.SurfaceHash = ldr.SurfaceHash
    ss.HashParameters = cache.HashParameters
    ss.SetupSurfaces(ldr)
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
end)

util.AddNetworkString "SplashSWEPs: Paint"
