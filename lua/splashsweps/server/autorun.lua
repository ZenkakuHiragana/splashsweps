
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
        ---Struct templates are stored here
        ---@type table<string, table>
        StructDefinitions = {},
        ---A hash table to represent grid separation of paintable surfaces
        --- `= { [hash] = { i1, i2, i3, ... }, ... }` where `i` is index of `ss.SurfaceArray`
        ---@type table<integer, integer[]>
        SurfaceHash = {},
        ---A set of event handlers with interactions to painted ink.
        ---@type table<string, ss.IInkFeature>
        InkFeatures = {},
        ---Map of ink shape category --> list of keys to actual definition
        ---@type table<string, string[]>
        InkShapeLists = {},
        ---Map of ink shape definition key (path to vmt file) --> InkShape object
        ---@type table<string, ss.InkShape>
        InkShapes = {},
        ---Definition of ink type (color and functionality)
        ---@type ss.InkType[]
        InkTypes = {},
        ---Conversion table from identifier string to internal index for ink type.
        ---@type table<string, integer>
        InkTypeIdentifierToIndex = {},

        ---Various debug data goes here
        Debug = {},

        RT_MARGIN_PIXELS = 4,
        InkGridSize = 12,
        NumRenderTargetOptions = -1,
        RenderTargetSize = {
            2048,
            4096,
            5792,
            8192,
            11586,
            16384,
        },
    }
    SplashSWEPs.NumRenderTargetOptions = #SplashSWEPs.RenderTargetSize
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/server/mapcache/bsploader.lua"
include "splashsweps/server/mapcache/cachebuilder.lua"
include "splashsweps/server/mapcache/lightmapbuilder.lua"
include "splashsweps/server/mapcache/surfacebuilder.lua"
include "splashsweps/server/mapcache/uvbuilder.lua"
include "splashsweps/server/packer/packer.lua"
include "splashsweps/server/packer/structures.lua"
include "splashsweps/server/paint/paint.lua"
include "splashsweps/server/paint/paintablesurface.lua"

local ss = SplashSWEPs
local txtPath = string.format("splashsweps/%s.json", game.GetMap())
hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(file.Read(txtPath) or "", true)
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    if not cache or cache.MapCRC ~= mapCRC then
        cache = ss.BuildMapCache() or {}
        file.Write(txtPath, util.TableToJSON(cache))
    end

    ss.SetupSurfaces()
    ss.GenerateHashTable()
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
end)
