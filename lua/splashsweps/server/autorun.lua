
if not SplashSWEPs then
    ---@class ss
    SplashSWEPs = {
        ---Struct templates are stored here
        ---@type table<string, table>
        StructDefinitions = {},
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
        ---@type table<string, ss.InkType>
        InkTypes = {},

        RT_MARGIN_PIXELS = 4,
        InkGridSize = 1,
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

local ss = SplashSWEPs
local txtPath = string.format("splashsweps/%s.txt", game.GetMap())
hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(util.Decompress(file.Read(txtPath) or "") or "", true)
    if not cache then
        cache = ss.BuildMapCache() or {}
        local json = util.TableToJSON(cache)
        local data = util.Compress(json)
        file.Write(txtPath, data)
    end
end)
