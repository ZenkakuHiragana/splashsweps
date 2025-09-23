
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
---@field LightmapUV          Vector  Absolute Lightmap UV values.
---@field LightmapSamplePoint Vector? Relative X-Y coordinates to calculate lightmap UV.
---@field DisplacementOrigin  Vector? The point that this displacement point was made from.
ss.struct "PrecachedData.Vertex" (setmetatable({
    Angle(),
    Vector(),
    Vector(),
    nil,
    nil,
}, {
    Angle               = 1,
    Translation         = 2,
    LightmapUV          = 3,
    LightmapSamplePoint = 4,
    DisplacementOrigin  = 5,
    __index             = indexer,
    __newindex          = newindexer,
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

---@class ss.PrecachedData.ModelInfo
---@field FaceIndices  integer[] Indices to the LUMP_FACE array that this model contains.
---@field NumTriangles integer   Total number of triangles to construct Mesh of this model.
ss.struct "PrecachedData.ModelInfo" (setmetatable({
    {},
    0,
}, {
    FaceIndices  = 1,
    NumTriangles = 2,
    __index      = indexer,
    __newindex   = newindexer,
}))

---Structure of UV coordinates for static props.
---```
---+------------------> v
---|
---|     (OffsetU, OffsetV)
---|   /^^^^^^^^^^^^^^^^^^^
---|  +---------+
---|  |         | Height
---|  +---------+
---v     Width
---u
---```
---@class ss.PrecachedData.StaticProp.UVInfo
---@field Offset Vector Offset (left and top position) in the UV space.
---@field Width  number Width in the UV space.
---@field Height number Height in the UV space.
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
---```
---+------------------> v
---|
---|     (OffsetU, OffsetV)
---|   /^^^^^^^^^^^^^^^^^^^
---|  +---------+
---|  |         | Height
---|  +---------+
---v     Width
---u
---```
---@class ss.PrecachedData.UVInfo
---@field Angle       Angle  Transforms world coordinates into UV space.
---@field Translation Vector Transforms world coordinates into UV space.
---@field OffsetU     number Left position in UV space.
---@field OffsetV     number Top position in UV space.
---@field Width       number The width of this surface in UV space.
---@field Height      number The height of this surface in UV space.
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
---@field Angles     Angle
---@field BoundsMax  Vector
---@field BoundsMin  Vector
---@field FadeMax    number  Fade-out distance which completely hides this model.
---@field FadeMin    number  Fade-out distance which starts fading.
---@field ModelIndex integer Index to array of paths to mdl.
---@field Position   Vector  The origin.
---@field Scale      number  The model scale of this prop.
ss.struct "PrecachedData.StaticProp" (setmetatable({
    Angle(),
    Vector(),
    Vector(),
    0,
    -1,
    0,
    Vector(),
    1,
}, {
    Angles     = 1,
    BoundsMax  = 2,
    BoundsMin  = 3,
    FadeMax    = 4,
    FadeMin    = 5,
    ModelIndex = 6,
    Position   = 7,
    Scale      = 8,
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
---@field LightmapHeight     number   The height of this surface in lightmap texture in luxels.
---@field LightmapWidth      number   The width of this surface in lightmap texture in luxels.
---@field MBBAngles          Angle    The angle of minimum (oriented) bounding box.
---@field MBBOrigin          Vector   The origin of minimum (oriented) bounding box.
---@field MBBSize            Vector   The size of minimum (oriented) bounding box in their local coordinates.
---@field PaintGridHeight    integer  The height of this surface in the serverside paint grid.
---@field PaintGridWidth     integer  The width of this surface in the serverside paint grid.
---Array of UV coordinates.
---One of them will be selected on mesh construction depending on the resolution of RenderTarget.
---@field UVInfo ss.PrecachedData.UVInfo[]
---Vertices in world coordinates (x0, y0, z0) which are directly fed into mesh triangles.
---@field Vertices ss.PrecachedData.Vertex[]
---Hash table to search triangles of displacement.   
---= `{ [hash] = { list of indices to Triangles }}`
---@field TriangleHash       table<integer, integer[]>?
---@field Triangles          ss.PrecachedData.DisplacementTriangle[]? Array of triangles of a displacement.
---@field FaceLumpIndex      integer? Index to face lump just used to calculate lightmap UV coordinates.
ss.struct "PrecachedData.Surface" (setmetatable({
    ss.vector_one * -math.huge,
    ss.vector_one * math.huge,
    ss.new "PrecachedData.MatrixTransform",
    0,
    0,
    Angle(),
    Vector(),
    Vector(),
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
    LightmapHeight     = 4,
    LightmapWidth      = 5,
    MBBAngles          = 6,
    MBBOrigin          = 7,
    MBBSize            = 8,
    PaintGridHeight    = 9,
    PaintGridWidth     = 10,
    UVInfo             = 11,
    Vertices           = 12,
    TriangleHash       = 13,
    Triangles          = 14,
    __index            = indexer,
    __newindex         = newindexer,
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
---@field Surfaces    ss.PrecachedData.Surface[]
---@field SurfaceHash table<integer, integer[]> = `ss.SurfaceHash`
---@field UVScales    number[] Render target size index -> Hammer units to UV multiplier
ss.struct "PrecachedData.SurfaceInfo" (setmetatable({
    {},
    {},
    {},
}, {
    Surfaces    = 1,
    SurfaceHash = 2,
    UVScales    = 3,
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
---@field MinimapBounds    ss.MinimapAreaBounds[]
---@field DirectionalLight ss.PrecachedData.DirectionalLight
---@field ModelsHDR        ss.PrecachedData.ModelInfo[]
---@field ModelsLDR        ss.PrecachedData.ModelInfo[]
---@field StaticProps      ss.PrecachedData.StaticProp[]
---@field StaticPropMDL    string[] List of path to models of static props.
---@field StaticPropHDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field StaticPropLDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field SurfacesWaterHDR ss.PrecachedData.Surface[]
---@field SurfacesWaterLDR ss.PrecachedData.Surface[]
---@field HashParameters   ss.HashParameters
ss.struct "PrecachedData" (setmetatable({
    -1,
    0,
    {},
    ss.new "PrecachedData.DirectionalLight",
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    {},
    ss.new "PrecachedData.HashParameters",
}, {
    CacheVersion     = 1,
    MapCRC           = 2,
    MinimapBounds    = 3,
    DirectionalLight = 4,
    ModelsHDR        = 5,
    ModelsLDR        = 6,
    StaticProps      = 7,
    StaticPropMDL    = 8,
    StaticPropHDR    = 9,
    StaticPropLDR    = 10,
    SurfacesWaterHDR = 11,
    SurfacesWaterLDR = 12,
    HashParameters   = 13,
    __index          = indexer,
    __newindex       = newindexer,
}))
