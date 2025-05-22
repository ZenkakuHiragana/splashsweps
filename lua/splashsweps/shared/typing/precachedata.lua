
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Precached information of a vertex stored in a local file.
---@class ss.PrecachedData.MatrixVertex
---@field Translation Vector The position.
---@field Angle Angle Normal, tangent, and bitangent vector.
---@field TextureUV Vector() Relative RenderTarget UV values (actual uv = offset + (u1 * width, v1 * height)).
---@field LightmapUV Vector() Absolute Lightmap UV values.
ss.struct "PrecachedData.MatrixVertex" {
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
---@field Scale Vector
ss.struct "PrecachedData.MatrixTransform" {
    Translation = Vector(),
    Angle = Angle(),
    Scale = Vector(1, 1, 1),
}

---Table of lightmap info stored in external JSON file.
---@class ss.PrecachedData.Lightmap
---@field DirectionalLightColor Color
---@field DirectionalLightColorHDR Color
---@field DirectionalLightScaleHDR number
ss.struct "PrecachedData.Lightmap" {
    DirectionalLightColor = Color(0, 0, 0),
    DirectionalLightColorHDR = Color(0, 0, 0),
    DirectionalLightScaleHDR = 0,
}

---@class ss.PrecachedData.ModelInfo
---@field FaceIndices integer[]
---@field NumTriangles integer
ss.struct "PrecachedData.ModelInfo" {
    FaceIndices = {},
    NumTriangles = 0,
}

---Structure of UV coordinates.
---@class ss.PrecachedData.UVInfo
---@field Transform ss.PrecachedData.MatrixTransform Transforms world coordinates into UV space.
---@field Width     number The width of this surface in UV space.
---@field Height    number The height of this surface in UV space.
ss.struct "PrecachedData.UVInfo" {
    Transform = ss.new "PrecachedData.MatrixTransform",
    Width = 0,
    Height = 0,
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
---@field Vertices ss.PrecachedData.MatrixVertex[]
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

---Precached results of the BSP which are directly saved to/loaded from external JSON file.
---@class ss.PrecachedData
---@field CacheVersion    number
---@field MapCRC          string
---@field MinimapBounds   ss.MinimapAreaBounds[]
---@field Lightmap        ss.PrecachedData.Lightmap
---@field ModelsHDR       ss.PrecachedData.ModelInfo[]
---@field ModelsLDR       ss.PrecachedData.ModelInfo[]
---@field SurfacesWaterHDR ss.PrecachedData.Surface[]
---@field SurfacesWaterLDR ss.PrecachedData.Surface[]
---@field NumTrianglesHDR integer[]
---@field NumTrianglesLDR integer[]
ss.struct "PrecachedData" {
    CacheVersion = -1,
    MapCRC = "",
    MinimapBounds = {},
    Lightmap = ss.new "PrecachedData.Lightmap",
    ModelsHDR = {},
    ModelsLDR = {},
    NumTrianglesHDR = {},
    NumTrianglesLDR = {},
    SurfacesWaterHDR = {},
    SurfacesWaterLDR = {},
}
