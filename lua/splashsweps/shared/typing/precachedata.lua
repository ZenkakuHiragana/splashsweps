
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Precached information of a vertex stored in a local file.
---@class ss.PrecachedData.Vertex
---@field Translation Vector The position.
---@field Angle Angle Normal, tangent, and bitangent vector.
---@field TextureUV Vector() Relative RenderTarget UV values (actual uv = offset + (u1 * width, v1 * height)).
---@field LightmapUV Vector() Absolute Lightmap UV values.
ss.struct "PrecachedData.Vertex" {
    Angle = Angle(),
    LightmapUV = Vector(),
    TextureUV = Vector(),
    Translation = Vector(),
}

---Precached transformation matrix stored in a local file.
---util.TableToJSON doesn't convert VMatrix so I use this one instead.
---@class ss.PrecachedData.MatrixTransform
---@field Translation Vector
---@field Angle Angle
ss.struct "PrecachedData.MatrixTransform" {
    Translation = Vector(),
    Angle = Angle(),
}

---Table of lightmap info stored in external JSON file.
---@class ss.PrecachedData.DirectionalLight
---@field Color Color
---@field ColorHDR Color
---@field ScaleHDR number
ss.struct "PrecachedData.DirectionalLight" {
    Color = Color(0, 0, 0),
    ColorHDR = Color(0, 0, 0),
    ScaleHDR = 0,
}

---@class ss.PrecachedData.ModelInfo
---@field FaceIndices integer[]
---@field NumTriangles integer
ss.struct "PrecachedData.ModelInfo" {
    FaceIndices = {},
    NumTriangles = 0,
}

---Structure of UV coordinates for static props.
---@class ss.PrecachedData.StaticProp.UVInfo
---@field Offset Vector()
---@field Width number
---@field Height number
ss.struct "PrecachedData.StaticProp.UVInfo" {
    Offset = Vector(),
    Width = 0,
    Height = 0,
}

---Structure of UV coordinates.
---@class ss.PrecachedData.UVInfo
---@field Angle       Angle  Transforms world coordinates into UV space.
---@field Translation Vector Transforms world coordinates into UV space.
---@field Width       number The width of this surface in UV space.
---@field Height      number The height of this surface in UV space.
ss.struct "PrecachedData.UVInfo" {
    Angle = Angle(),
    Translation = Vector(),
    Width = 0,
    Height = 0,
}

---@class ss.PrecachedData.StaticProp
---@field Angles    Angle
---@field BoundsMax Vector
---@field BoundsMin Vector
---@field FadeMax   number
---@field FadeMin   number
---@field ModelName string
---@field Position  Vector
---@field Scale     number The model scale of this prop.
ss.struct "PrecachedData.StaticProp" {
    Angles = Angle(),
    BoundsMax = Vector(),
    BoundsMin = Vector(),
    FadeMax = 0,
    FadeMin = -1,
    ModelName = "",
    Position = Vector(),
    Scale = 1,
}

---Per-surface precached data to construct paintable surface.
---@class ss.PrecachedData.Surface
---@field AABBMax            Vector Maximum component of all vertices in world coordinates.
---@field AABBMin            Vector Minimum component of all vertices in world coordinates.
---@field TransformPaintGrid ss.PrecachedData.MatrixTransform Transforms world coordinates into the serverside paint grid coordinates.
---@field LightmapHeight     number  The height of this surface in lightmap texture in luxels.
---@field LightmapWidth      number  The width of this surface in lightmap texture in luxels.
---@field PaintGridHeight    integer The height of this surface in the serverside paint grid.
---@field PaintGridWidth     integer The width of this surface in the serverside paint grid.
---Array of UV coordinates.
---One of them will be selected on mesh construction depending on the resolution of RenderTarget.
---@field UVInfo ss.PrecachedData.UVInfo[]
---Vertices in world coordinates (x0, y0, z0) which are directly fed into mesh triangles.
---@field Vertices ss.PrecachedData.Vertex[]
ss.struct "PrecachedData.Surface" {
    AABBMax = ss.vector_one * -math.huge,
    AABBMin = ss.vector_one * math.huge,
    TransformPaintGrid = ss.new "PrecachedData.MatrixTransform",
    LightmapHeight = 0,
    LightmapWidth = 0,
    PaintGridHeight = 0,
    PaintGridWidth = 0,
    UVInfo = {},
    Vertices = {},
}

---Defines playable area in the map.
---@class ss.MinimapAreaBounds
---@field maxs Vector
---@field mins Vector
ss.struct "MinimapAreaBounds" {
    maxs = Vector(),
    mins = Vector(),
}

---@class ss.PrecachedData.SurfaceInfo
---@field [integer] ss.PrecachedData.Surface
---@field UVScales number[] Render target size index -> Hammer units to UV multiplier
ss.struct "PrecachedData.SurfaceInfo" {
    UVScales = {},
}

---Precached results of the BSP which are directly saved to/loaded from external JSON file.
---@class ss.PrecachedData
---@field CacheVersion     number
---@field MapCRC           string
---@field MinimapBounds    ss.MinimapAreaBounds[]
---@field DirectionalLight ss.PrecachedData.DirectionalLight
---@field ModelsHDR        ss.PrecachedData.ModelInfo[]
---@field ModelsLDR        ss.PrecachedData.ModelInfo[]
---@field StaticProps      ss.PrecachedData.StaticProp[]
---@field StaticPropHDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field StaticPropLDR    ss.PrecachedData.StaticProp.UVInfo[][]
---@field SurfacesWaterHDR ss.PrecachedData.Surface[]
---@field SurfacesWaterLDR ss.PrecachedData.Surface[]
ss.struct "PrecachedData" {
    CacheVersion = -1,
    MapCRC = "",
    MinimapBounds = {},
    DirectionalLight = ss.new "PrecachedData.DirectionalLight",
    ModelsHDR = {},
    ModelsLDR = {},
    StaticProps = {},
    StaticPropHDR = {},
    StaticPropLDR = {},
    SurfacesWaterHDR = {},
    SurfacesWaterLDR = {},
}
