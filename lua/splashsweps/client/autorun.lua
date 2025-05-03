
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
        ---Map of ink shape definition key (path to vmt file) --> ss.InkShape object
        ---@type table<string, ss.InkShape>
        InkShapes = {},
        ---Definition of ink type (color and functionality)
        ---@type table<string, ss.InkType>
        InkTypes = {},

        ---A set of drawing materials of the ink for the combination of ink type and ink shape.
        ---@type table<string, IMaterial>
        InkMaterials = {},
        ---List of IMeshes to render the painted ink.
        ---@type IMesh[]
        IMesh = {},
    }
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/client/inkmaterial.lua"
include "splashsweps/client/inkrenderer.lua"
include "splashsweps/client/surfacebuilder.lua"

---@class ss
local ss = SplashSWEPs
hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    -- ss.PrepareInkSurface()
end)
