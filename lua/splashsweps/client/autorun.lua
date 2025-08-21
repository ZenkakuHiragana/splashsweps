
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
        ---Array of paintable surfaces.
        ---@type ss.PaintableSurface[]
        SurfaceArray = {},
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
        ---@type ss.InkType[]
        InkTypes = {},
        ---Conversion table from identifier string to internal index for ink type.
        ---@type table<string, integer>
        InkTypeIdentifierToIndex = {},

        ---A set of drawing materials of the ink for the combination of ink type and ink shape.
        ---@type table<string, IMaterial>
        InkMaterials = {},
        ---List of IMeshes to render the painted ink.
        ---@type { BrushEntity: Entity?, [integer]: IMesh }[]
        IMesh = {},
        ---@type IMaterial
        InkMeshMaterial = CreateMaterial(
            "splashsweps_inkmesh",
            "LightmappedGeneric", {
                ["$basetexture"]                 = "uvchecker",
                ["$bumpmap"]                     = "null-bumpmap",
                ["$vertexcolor"]                 = "1",
                ["$nolod"]                       = "1",
                -- ["$alpha"]                       = "0.99609375", -- = 255 / 256,
                -- ["$alphatest"]                   = "1",
                -- ["$alphatestreference"]          = "0.0625",
                -- ["$phong"]                       = "1",
                -- ["$phongexponent"]               = "128",
                -- ["$phongamount"]                 = "[1 1 1 1]",
                -- ["$phongmaskcontrastbrightness"] = "[2 .7]",
                -- ["$envmap"]                      = "shadertest/shadertest_env",
                -- ["$envmaptint"]                  = "[1 1 1]",
                -- ["$color"]                       = "[1 1 1]",
                -- ["$detail"]                      = rt.BaseTexture,
                -- ["$detailscale"]                 = 1,
                -- ["$detailblendmode"]             = 5,
                -- ["$detailblendfactor"]           = 1, -- Increase this for bright ink in night maps
            }
        ),
    }
end

include "splashsweps/shared/autorun.lua"
include "splashsweps/client/inkmaterial.lua"
include "splashsweps/client/inkrenderer.lua"
include "splashsweps/client/paintablesurface.lua"
include "splashsweps/client/surfacebuilder.lua"

---@class ss
local ss = SplashSWEPs
hook.Add("InitPostEntity", "SplashSWEPs: Initalize", function()
    ss.PrepareInkSurface()
    ss.SetupSurfaces()
    ss.GenerateHashTable()
    ss.LoadInkFeatures()
    ss.LoadInkShapes()
    ss.LoadInkTypes()
    ss.LoadInkMaterials()
end)
