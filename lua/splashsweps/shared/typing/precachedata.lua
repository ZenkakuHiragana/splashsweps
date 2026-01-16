
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Effectively removes keys from JSON string to avoid "not enough memory" crash!
---@generic K, V
---@param t table<K, V>
---@param k K
---@return V?
local function indexer(t, k)
    -- print("__index", t, k, getmetatable(t)[k], rawget(t, getmetatable(t)[k] or k))
    return rawget(t, getmetatable(t)[k] or k)
end

---Effectively removes keys from JSON string but allows using them in Lua.
---@generic K, V
---@param t table<K, V>
---@param k K
---@param v V
local function newindexer(t, k, v)
    -- print("__newindex", t, k, getmetatable(t)[k], rawget(t, getmetatable(t)[k] or k), v)
    rawset(t, getmetatable(t)[k] or k, v)
end

---Precached information of a vertex stored in a local file.
---@class ss.PrecachedData.Vertex
---@field Angle               Angle   Normal, tangent, and bitangent vector.
---@field Translation         Vector  The position.
---@field LightmapUV          Vector  Relative Lightmap UV values in luxels.
---@field BumpmapUV           Vector  Bumpmap UV coordinates of the original face.
---@field DisplacementOrigin  Vector? The point that this displacement point was made from.
ss.struct "PrecachedData.Vertex" (setmetatable({
    Angle(),
    Vector(),
    Vector(),
    Vector(),
    nil,
}, {
    Angle              = 1,
    Translation        = 2,
    LightmapUV         = 3,
    BumpmapUV          = 4,
    DisplacementOrigin = 5,
    __index            = indexer,
    __newindex         = newindexer,
}))

---Precached transformation matrix stored in a local file.
---util.TableToJSON doesn't convert VMatrix so I use this one instead.
---@class ss.PrecachedData.MatrixTransform
---@field Angle       Angle  The orientation corresponding to VMatrix:GetAngles9)
---@field Translation Vector The translation vector corresponding to VMatrix:GetTranslation()
ss.struct "PrecachedData.MatrixTransform" (setmetatable({
    Angle(),
    Vector(),
}, {
    Angle       = 1,
    Translation = 2,
    __index     = indexer,
    __newindex  = newindexer,
}))

---Table of lightmap info stored in external JSON file.
---@class ss.PrecachedData.DirectionalLight
---@field Color    Color  The LDR color of the directional light.
---@field ColorHDR Color  The HDR color of the directional light. -1 means the same as LDR.
---@field ScaleHDR number HDR scale.
ss.struct "PrecachedData.DirectionalLight" (setmetatable({
    Color(0, 0, 0),
    Color(0, 0, 0),
    0,
}, {
    Color    = 1,
    ColorHDR = 2,
    ScaleHDR = 3,
    __index    = indexer,
    __newindex = newindexer,
}))

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
---@field Width  number Width in the UV space in hammer units.
---@field Height number Height in the UV space in hammer units.
ss.struct "PrecachedData.StaticProp.UVInfo" (setmetatable({
    Vector(),
    0,
    0,
}, {
    Offset = 1,
    Width  = 2,
    Height = 3,
    __index    = indexer,
    __newindex = newindexer,
}))

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
ss.struct "PrecachedData.UVInfo" (setmetatable({
    Angle(),
    Vector(),
    0,
    0,
    0,
    0,
}, {
    Angle       = 1,
    Translation = 2,
    OffsetU     = 3,
    OffsetV     = 4,
    Width       = 5,
    Height      = 6,
    __index     = indexer,
    __newindex  = newindexer,
}))

---Fetched static prop information from the Game lump.
---@class ss.PrecachedData.StaticProp
---@field Angles      Angle   The angle of the prop.
---@field BoundsMax   Vector  OBB maximum.
---@field BoundsMin   Vector  OBB minimum.
---@field FadeMax     number  Fade-out distance which completely hides this model.
---@field FadeMin     number  Fade-out distance which starts fading.
---@field ModelIndex  integer Index to array of paths to mdl.
---@field Position    Vector  The origin.
---@field Scale       number  The model scale of this prop.
---@field UnwrapIndex integer Describes how the bounding box is unwrapped in UV space.  See GetStaticPropUVSize in cachebuilder.lua.
ss.struct "PrecachedData.StaticProp" (setmetatable({
    Angle(),
    Vector(),
    Vector(),
    0,
    -1,
    0,
    Vector(),
    1,
    1,
}, {
    Angles      = 1,
    BoundsMax   = 2,
    BoundsMin   = 3,
    FadeMax     = 4,
    FadeMin     = 5,
    ModelIndex  = 6,
    Position    = 7,
    Scale       = 8,
    UnwrapIndex = 9,
    __index    = indexer,
    __newindex = newindexer,
}))

---Vertices and some other info of a triangle in a displacement.
---@class ss.PrecachedData.DisplacementTriangle
---@field Index           integer Index to the vertices.
---@field BarycentricDot1 Vector  Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector  Parameter to calculate barycentric coordinates w.
---@field MBBAngles       Angle   The angle of minimum (oriented) bounding box.
---@field MBBOrigin       Vector  The origin of minimum (oriented) bounding box.
---@field MBBSize         Vector  The size of minimum (oriented) bounding box in their local coordinates.
---@field WorldToLocalGridRotation Angle Transforms world angles into local to map to serverside paint grid.
ss.struct "PrecachedData.DisplacementTriangle" (setmetatable({
    0,
    Vector(),
    Vector(),
    Angle(),
    Vector(),
    Vector(),
    Angle(),
}, {
    Index           = 1,
    BarycentricDot1 = 2,
    BarycentricDot2 = 3,
    MBBAngles       = 4,
    MBBOrigin       = 5,
    MBBSize         = 6,
    WorldToLocalGridRotation = 7,
    __index         = indexer,
    __newindex      = newindexer,
}))

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
ss.struct "PrecachedData.Surface" (setmetatable({
    ss.vector_one * -math.huge,
    ss.vector_one * math.huge,
    ss.new "PrecachedData.MatrixTransform",
    Angle(),
    Vector(),
    Vector(),
    0,
    0,
    0,
    {},
    {},
    nil,
    nil,
    nil,
}, {
    AABBMax            = 1,
    AABBMin            = 2,
    TransformPaintGrid = 3,
    MBBAngles          = 4,
    MBBOrigin          = 5,
    MBBSize            = 6,
    ModelIndex         = 7,
    PaintGridHeight    = 8,
    PaintGridWidth     = 9,
    UVInfo             = 10,
    Vertices           = 11,
    TriangleHash       = 12,
    Triangles          = 13,
    FaceLumpIndex      = 14,
    __index            = indexer,
    __newindex         = newindexer,
}))

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.PrecachedData.LightmapInfo
---@field MaterialIndex integer  Index to material names in ss.PrecachedData.MaterialNames
---@field HasLightmap   integer? nil = false, 1 = true, 2 = also has light styles
---@field Width         integer? Width of the lightmap in luxels.
---@field Height        integer? Height of the lightmap in luxels.
---@field FaceIndex     integer? Index to the PrecachedData.Surface array. nil if it does not correspond to paintable surface array.
ss.struct "PrecachedData.LightmapInfo" (setmetatable({
    0,
    nil,
    nil,
    nil,
    nil,
}, {
    MaterialIndex  = 1,
    HasLightmap    = 2,
    Width          = 3,
    Height         = 4,
    FaceIndex      = 5,
    __index        = indexer,
    __newindex     = newindexer,
}))

---Defines playable area in the map.
---@class ss.MinimapAreaBounds
---@field maxs Vector
---@field mins Vector
ss.struct "MinimapAreaBounds" (setmetatable({
    Vector(),
    Vector(),
}, {
    maxs       = 1,
    mins       = 2,
    __index    = indexer,
    __newindex = newindexer,
}))

---Array of paintable surfaces stored as JSON file.
---@class ss.PrecachedData.SurfaceInfo
---@field Lightmaps   ss.PrecachedData.LightmapInfo[] Array made from LUMP_FACES used to pack lightmaps.
---@field Surfaces    ss.PrecachedData.Surface[] Array of paintable surfaces.
---@field SurfaceHash table<integer, integer[]> = `ss.SurfaceHash`
---@field UVScales    number[]  Render target size index -> Hammer units to UV multiplier
ss.struct "PrecachedData.SurfaceInfo" (setmetatable({
    {},
    {},
    {},
    {},
}, {
    Lightmaps   = 1,
    Surfaces    = 2,
    SurfaceHash = 3,
    UVScales    = 4,
    __index     = indexer,
    __newindex  = newindexer,
}))

---@class ss.PrecachedData.HashParameters
---@field GridSizeSurface integer
---@field MinGridSizeDisplacement integer
---@field NumDivisionsDisplacement integer
ss.struct "PrecachedData.HashParameters" (setmetatable({
    128,
    32,
    8,
}, {
    GridSizeSurface          = 1,
    MinGridSizeDisplacement  = 2,
    NumDivisionsDisplacement = 3,
    __index                  = indexer,
    __newindex               = newindexer,
}))

---Precached results of the BSP which are directly saved to/loaded from external JSON file.
---@class ss.PrecachedData
---@field CacheVersion     number
---@field MapCRC           integer
---@field MaterialNames    string[] List of material names used in the map ordered by the same as TEXDATA_STRING_DATA lump.
---@field MinimapBounds    ss.MinimapAreaBounds[]
---@field NumModels        integer
---@field DirectionalLight ss.PrecachedData.DirectionalLight
---@field HashParameters   ss.HashParameters
---@field StaticProps      ss.PrecachedData.StaticProp[]
---@field StaticPropMDL    string[] List of paths to model of static props.
---@field StaticPropHDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field StaticPropLDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field SurfacesWaterHDR ss.PrecachedData.Surface[]
---@field SurfacesWaterLDR ss.PrecachedData.Surface[]
ss.struct "PrecachedData" (setmetatable({
    -1,
    0,
    {},
    {},
    0,
    ss.new "PrecachedData.DirectionalLight",
    ss.new "PrecachedData.HashParameters",
    {},
    {},
    {},
    {},
    {},
    {},
    {},
}, {
    CacheVersion     = 1,
    MapCRC           = 2,
    MaterialNames    = 3,
    MinimapBounds    = 4,
    NumModels        = 5,
    DirectionalLight = 6,
    HashParameters   = 7,
    StaticProps      = 8,
    StaticPropMDL    = 9,
    StaticPropHDR    = 10,
    StaticPropLDR    = 11,
    SurfacesWaterHDR = 12,
    SurfacesWaterLDR = 13,
    __index          = indexer,
    __newindex       = newindexer,
}))
