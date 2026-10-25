
-- Records of the map cache saved as JSON files.
-- <map>.json is PrecachedData itself, and <map>_hdr.json and <map>_ldr.json are PrecachedData.SurfaceInfo.
-- A record stores its fields at array positions to keep the JSON small,
-- and Lua code accesses them by name through its metatable.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.PrecachedDataModule
---@field new     fun(): ss.PrecachedData Creates <map>.json with the defaults.
---@field restore fun(t: table): ss.PrecachedData Sets metatables to a table decoded from <map>.json.
local PrecachedData = ss.module "splashsweps/shared/typing/precachedata"

---Resolutions of the ink map, which the UV arrays of the cache are indexed by.
---The client uses the last one.
PrecachedData.InkMapResolutions = { 4096, 8192, 16384 }

---A field of a record: `{ name, default, of = type of the elements if the field is an array }`.
---The default is used as follows so that instances do not share mutable values:
---a record is created by its new(), a function is called, a table is deep-copied, and others are used as is.
---@class ss.PrecachedData.Field
---@field [1] string
---@field [2] any
---@field of  { restore: fun(t: table): table }?

---Record types, to tell a nested record from a table default.
local records = {} ---@type table<table, true>

---@param default any
---@return any
local function newDefault(default)
    if records[default] then return default.new() end
    if isfunction(default) then return default() end
    if istable(default) then return Util.deepcopy(default) end
    return default
end

---Defines a record type.
---@param fields ss.PrecachedData.Field[]
---@param R table? The table to define the record in, or a new one.
---@return table
local function record(fields, R)
    R = R or {}
    records[R] = true
    local positions = {} ---@type table<string, integer>
    for i, field in ipairs(fields) do positions[field[1]] = i end

    local meta = {
        __index    = function(t, k) return rawget(t, positions[k] or k) end,
        __newindex = function(t, k, v) rawset(t, positions[k] or k, v) end,
    }

    function R.new()
        local t = setmetatable({}, meta)
        for i, field in ipairs(fields) do rawset(t, i, newDefault(field[2])) end
        return t
    end

    function R.restore(t)
        setmetatable(t, meta)
        for i, field in ipairs(fields) do
            local value = rawget(t, i)
            if value ~= nil then
                if field.of then
                    for _, element in pairs(value) do field.of.restore(element) end
                elseif records[field[2]] then
                    field[2].restore(value)
                end
            end
        end

        return t
    end

    return R
end

---Describes an array of the given type, for the elements of an array of arrays.
---@param element { restore: fun(t: table): table }
---@return { restore: fun(t: table): table }
local function arrayOf(element)
    return {
        restore = function(t)
            for _, v in pairs(t) do element.restore(v) end
            return t
        end,
    }
end

local function blackColor() return Color(0, 0, 0) end

---Precached information of a vertex stored in a local file.
---@class ss.PrecachedData.Vertex
---@field Translation       Vector  The position.
---@field Normal            Vector
---@field Tangent           Vector
---@field Binormal          Vector
---@field LightmapTangent   Vector
---@field LightmapBinormal  Vector
---@field LightmapUV        Vector  Relative Lightmap UV values in luxels.
---@field BumpmapUV         Vector  Bumpmap UV coordinates of the original face in texels.
---                                 Z = blend factors toward $basetexture2, 3, and 4 as b2 + b3 * 256 + b4 * 65536.
---@field DispPaintOrigin   Vector? Displacement-only world-space reference point used to compute paint/ink UV.

---@type { new: (fun(): ss.PrecachedData.Vertex), restore: (fun(t: table): ss.PrecachedData.Vertex) }
PrecachedData.Vertex = record {
    { "Translation",      Vector },
    { "Normal",           Vector },
    { "Tangent",          Vector },
    { "Binormal",         Vector },
    { "LightmapTangent",  Vector },
    { "LightmapBinormal", Vector },
    { "LightmapUV",       Vector },
    { "BumpmapUV",        Vector },
    { "DispPaintOrigin" },
}

---Precached transformation matrix stored in a local file.
---util.TableToJSON doesn't convert VMatrix so I use this one instead.
---@class ss.PrecachedData.MatrixTransform
---@field Angle       Angle  The orientation corresponding to VMatrix:GetAngles9)
---@field Translation Vector The translation vector corresponding to VMatrix:GetTranslation()

---@type { new: (fun(): ss.PrecachedData.MatrixTransform), restore: (fun(t: table): ss.PrecachedData.MatrixTransform) }
PrecachedData.MatrixTransform = record {
    { "Angle",       Angle },
    { "Translation", Vector },
}

---Table of lightmap info stored in external JSON file.
---@class ss.PrecachedData.DirectionalLight
---@field Color    Color  The LDR color of the directional light.
---@field ColorHDR Color  The HDR color of the directional light. -1 means the same as LDR.
---@field ScaleHDR number HDR scale.

---@type { new: (fun(): ss.PrecachedData.DirectionalLight), restore: (fun(t: table): ss.PrecachedData.DirectionalLight) }
PrecachedData.DirectionalLight = record {
    { "Color",    blackColor },
    { "ColorHDR", blackColor },
    { "ScaleHDR", 0 },
}

---Structure of UV coordinates for static props.
---```text
---. +-----------------------------> v
---. |
---. |            (OffsetU, OffsetV)
---. |          /^^^^^^^^^^^^^^^^^^^
---. |         /
---. |        / Height              Width
---. |       +---------+          +-------+
---. | Width |         |          |       |
---. |       +---------+   Height |       |
---. |                            |       |
---. |                            +-------+
---. |        (OffsetU, OffsetV) /
---. |        ^^^^^^^^^^^^^^^^^^^
---. V      (not rotated)         (rotated)
---. u
---```
---@class ss.PrecachedData.StaticProp.UVInfo
---Offset (left and top position) in the UV space in hammer units.
---Z indicates if this rectangle is rotated.
---@field Offset Vector
---@field Width  number Width in the UV space in hammer units, including the margins of each face.
---@field Height number Height in the UV space in hammer units, including the margins of each face.

---@type { new: (fun(): ss.PrecachedData.StaticProp.UVInfo), restore: (fun(t: table): ss.PrecachedData.StaticProp.UVInfo) }
PrecachedData.StaticPropUVInfo = record {
    { "Offset", Vector },
    { "Width",  0 },
    { "Height", 0 },
}

---Structure of UV coordinates.
---```text
---. +-----------------------------> v
---. |
---. |            (OffsetU, OffsetV)
---. |          /^^^^^^^^^^^^^^^^^^^
---. |         /
---. |        / Height              Width
---. |       +---------+          +-------+
---. | Width |         |          |       |
---. |       +---------+   Height |       |
---. |                            |       |
---. |                            +-------+
---. |        (OffsetU, OffsetV) /
---. |        ^^^^^^^^^^^^^^^^^^^
---. V      (not rotated)         (rotated)
---. u
---```
---@class ss.PrecachedData.UVInfo
---@field Angle       Angle  Transforms world coordinates into UV space.
---@field Translation Vector Transforms world coordinates into UV space.
---@field OffsetU     number Left position in UV space ranging from 0 to 1.
---@field OffsetV     number Top position in UV space ranging from 0 to 1.
---@field Width       number The width of this surface in UV space ranging from 0 to 1.
---@field Height      number The height of this surface in UV space ranging from 0 to 1.

---@type { new: (fun(): ss.PrecachedData.UVInfo), restore: (fun(t: table): ss.PrecachedData.UVInfo) }
PrecachedData.UVInfo = record {
    { "Angle",       Angle },
    { "Translation", Vector },
    { "OffsetU",     0 },
    { "OffsetV",     0 },
    { "Width",       0 },
    { "Height",      0 },
}

---Fetched static prop information from the Game lump.
---@class ss.PrecachedData.StaticProp
---@field Angles       Angle   The angle of the prop.
---@field BoundsMax    Vector  OBB maximum.
---@field BoundsMin    Vector  OBB minimum.
---@field FadeMax      number  Fade-out distance which completely hides this model.
---@field FadeMin      number  Fade-out distance which starts fading.
---@field ModelIndex   integer Index to array of paths to mdl.
---@field Position     Vector  The origin.
---@field Scale        number  The model scale of this prop.
---@field Skin         integer The skin of this prop.
---@field UnwrapIndex  integer Describes how the bounding box is unwrapped in UV space.  See GetStaticPropUVSize.
---@field CubemapIndex integer Index to ss.PrecachedData.SurfaceInfo.Cubemaps of the cubemap the engine uses, or 0 if none.

---@type { new: (fun(): ss.PrecachedData.StaticProp), restore: (fun(t: table): ss.PrecachedData.StaticProp) }
PrecachedData.StaticProp = record {
    { "Angles",       Angle },
    { "BoundsMax",    Vector },
    { "BoundsMin",    Vector },
    { "FadeMax",      0 },
    { "FadeMin",      -1 },
    { "ModelIndex",   0 },
    { "Position",     Vector },
    { "Scale",        1 },
    { "UnwrapIndex",  1 },
    { "Skin",         0 },
    { "CubemapIndex", 0 },
}

---Vertices and some other info of a triangle in a displacement.
---@class ss.PrecachedData.DisplacementTriangle
---@field Index           integer Index to the vertices.
---@field BarycentricDot1 Vector  Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector  Parameter to calculate barycentric coordinates w.
---@field MBBAngles       Angle   The angle of minimum (oriented) bounding box.
---@field MBBOrigin       Vector  The origin of minimum (oriented) bounding box.
---@field MBBSize         Vector  The size of minimum (oriented) bounding box in their local coordinates.
---@field WorldToLocalGridRotation Angle Transforms world angles into local to map to serverside paint grid.

---@type { new: (fun(): ss.PrecachedData.DisplacementTriangle), restore: (fun(t: table): ss.PrecachedData.DisplacementTriangle) }
PrecachedData.DisplacementTriangle = record {
    { "Index",                    0 },
    { "BarycentricDot1",          Vector },
    { "BarycentricDot2",          Vector },
    { "MBBAngles",                Angle },
    { "MBBOrigin",                Vector },
    { "MBBSize",                  Vector },
    { "WorldToLocalGridRotation", Angle },
}

---Per-surface precached data to construct paintable surface.
---@class ss.PrecachedData.Surface
---@field AABBMax            Vector   Maximum component of all vertices in world coordinates.
---@field AABBMin            Vector   Minimum component of all vertices in world coordinates.
---@field TransformPaintGrid ss.PrecachedData.MatrixTransform Transforms world coordinates into the serverside paint grid coordinates.
---@field MBBAngles          Angle    The angle of minimum (oriented) bounding box.
---@field MBBOrigin          Vector   The origin of minimum (oriented) bounding box.
---@field MBBSize            Vector   The size of minimum (oriented) bounding box in their local coordinates.
---@field ModelIndex         integer  Index to model lump entry.
---@field PaintGridHeight    integer  The height of this surface in the serverside paint grid.
---@field PaintGridWidth     integer  The width of this surface in the serverside paint grid.
---Array of UV coordinates.
---One of them will be selected on mesh construction depending on the resolution of RenderTarget.
---@field UVInfo ss.PrecachedData.UVInfo[]
---Vertices in world coordinates (x0, y0, z0) which are directly fed into mesh triangles.
---@field Vertices ss.PrecachedData.Vertex[]
---Hash table to search triangles of displacement.
---= `{ [hash] = { list of indices to Triangles }}`
---@field TriangleHash  table<integer, integer[]>?
---@field Triangles     ss.PrecachedData.DisplacementTriangle[]? Array of triangles of a displacement.
---@field FaceLumpIndex integer? Index to face lump just used to calculate lightmap UV coordinates.

---@type { new: (fun(): ss.PrecachedData.Surface), restore: (fun(t: table): ss.PrecachedData.Surface) }
PrecachedData.Surface = record {
    { "AABBMax",            function() return Util.vector_one * -math.huge end },
    { "AABBMin",            function() return Util.vector_one * math.huge end },
    { "TransformPaintGrid", PrecachedData.MatrixTransform },
    { "MBBAngles",          Angle },
    { "MBBOrigin",          Vector },
    { "MBBSize",            Vector },
    { "ModelIndex",         0 },
    { "PaintGridHeight",    0 },
    { "PaintGridWidth",     0 },
    { "UVInfo",             {}, of = PrecachedData.UVInfo },
    { "Vertices",           {}, of = PrecachedData.Vertex },
    { "TriangleHash" },
    { "Triangles",          nil, of = PrecachedData.DisplacementTriangle },
    { "FaceLumpIndex" },
}

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.PrecachedData.LightmapInfo
---@field MaterialIndex integer  Index to material names in ss.PrecachedData.MaterialNames
---@field HasLightmap   integer? nil = false, 1 = true, 2 = also has light styles
---@field Width         integer? Width of the lightmap in luxels.
---@field Height        integer? Height of the lightmap in luxels.
---@field FaceIndex     integer? Index to the PrecachedData.Surface array. nil if it does not correspond to paintable surface array.

---@type { new: (fun(): ss.PrecachedData.LightmapInfo), restore: (fun(t: table): ss.PrecachedData.LightmapInfo) }
PrecachedData.LightmapInfo = record {
    { "MaterialIndex", 0 },
    { "HasLightmap" },
    { "Width" },
    { "Height" },
    { "FaceIndex" },
}

---Cubemap sample and the paintable face bounds that use it.
---@class ss.PrecachedData.CubemapInfo
---@field Envmap    string  Resolved cubemap texture name, e.g. `maps/<map>/cX_Y_Z`.
---@field Origin    Vector  Cubemap sample origin in world coordinates.
---@field BoxMin    Vector  Minimum corner of paintable face bounds using this cubemap.
---@field BoxMax    Vector  Maximum corner of paintable face bounds using this cubemap.
---@field FaceCount integer Number of paintable faces accumulated into this box.
---@field Blend     number  Parallax correction blend ratio. 0 disables correction.

---@type { new: (fun(): ss.PrecachedData.CubemapInfo), restore: (fun(t: table): ss.PrecachedData.CubemapInfo) }
PrecachedData.CubemapInfo = record {
    { "Envmap",    "" },
    { "Origin",    Vector },
    { "BoxMin",    Vector },
    { "BoxMax",    Vector },
    { "FaceCount", 0 },
    { "Blend",     0 },
}

---Array of paintable surfaces stored as JSON file.
---@class ss.PrecachedData.SurfaceInfo
---@field Lightmaps   ss.PrecachedData.LightmapInfo[] Array made from LUMP_FACES used to pack lightmaps.
---@field Surfaces    ss.PrecachedData.Surface[] Array of paintable surfaces.
---@field SurfaceHash table<integer, integer[]> Spatial hash given to Hash.Setup.
---@field UVScales    number[]  Render target size index -> Hammer units to UV multiplier
---@field Cubemaps    ss.PrecachedData.CubemapInfo[] Cubemap samples and paintable face bounds using them.

---@type { new: (fun(): ss.PrecachedData.SurfaceInfo), restore: (fun(t: table): ss.PrecachedData.SurfaceInfo) }
PrecachedData.SurfaceInfo = record {
    { "Lightmaps",   {}, of = PrecachedData.LightmapInfo },
    { "Surfaces",    {}, of = PrecachedData.Surface },
    { "SurfaceHash", {} },
    { "UVScales",    {} },
    { "Cubemaps",    {}, of = PrecachedData.CubemapInfo },
}

---@class ss.PrecachedData.HashParameters
---@field GridSizeSurface integer
---@field MinGridSizeDisplacement integer
---@field NumDivisionsDisplacement integer

---@type { new: (fun(): ss.PrecachedData.HashParameters), restore: (fun(t: table): ss.PrecachedData.HashParameters) }
PrecachedData.HashParameters = record {
    { "GridSizeSurface",          128 },
    { "MinGridSizeDisplacement",  32 },
    { "NumDivisionsDisplacement", 8 },
}

---Defines playable area in the map, stored as a plain table (not a record) in PrecachedData.MinimapBounds.
---@class ss.MinimapAreaBounds
---@field maxs Vector
---@field mins Vector

---Precached results of the BSP which are directly saved to/loaded from external JSON file.
---@class ss.PrecachedData
---@field CacheVersion     number
---@field MapCRC           integer
---@field MaterialNames    string[] List of material names used in the map ordered by the same as TEXDATA_STRING_DATA lump.
---@field MinimapBounds    ss.MinimapAreaBounds[]
---@field NumModels        integer
---@field DirectionalLight ss.PrecachedData.DirectionalLight
---@field HashParameters   ss.PrecachedData.HashParameters
---@field StaticProps      ss.PrecachedData.StaticProp[]
---@field StaticPropMDL    string[] List of paths to model of static props.
---@field StaticPropHDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field StaticPropLDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field SurfacesWaterHDR ss.PrecachedData.Surface[]
---@field SurfacesWaterLDR ss.PrecachedData.Surface[]
record({
    { "CacheVersion",     -1 },
    { "MapCRC",           0 },
    { "MaterialNames",    {} },
    { "MinimapBounds",    {} },
    { "NumModels",        0 },
    { "DirectionalLight", PrecachedData.DirectionalLight },
    { "HashParameters",   PrecachedData.HashParameters },
    { "StaticProps",      {}, of = PrecachedData.StaticProp },
    { "StaticPropMDL",    {} },
    { "StaticPropHDR",    {}, of = arrayOf(PrecachedData.StaticPropUVInfo) },
    { "StaticPropLDR",    {}, of = arrayOf(PrecachedData.StaticPropUVInfo) },
    { "SurfacesWaterHDR", {}, of = PrecachedData.Surface },
    { "SurfacesWaterLDR", {}, of = PrecachedData.Surface },
}, PrecachedData)

return PrecachedData
