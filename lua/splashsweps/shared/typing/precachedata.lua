
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Table of lightmap info stored in external JSON file.
---@class ss.PrecachedData.Lightmap
---@field DirectionalLightColor Color
---@field DirectionalLightColorHDR Color
---@field DirectionalLightScaleHDR number
---@field PNGHDR string
---@field PNGLDR string
ss.struct "PrecachedData.Lightmap" {
    DirectionalLightColor = Color(0, 0, 0),
    DirectionalLightColorHDR = Color(0, 0, 0),
    DirectionalLightScaleHDR = 0,
    PNGHDR = "",
    PNGLDR = "",
}

---Structure of UV coordinates.
---@class ss.PrecachedData.UVInfo
---@field Transform   VMatrix  Transforms world coordinates into UV space.
---@field Width       number   The width of this surface in UV space.
---@field Height      number   The height of this surface in UV space.
ss.struct "PrecachedData.UVInfo" {
    Transform = Matrix(),
    Width = 0,
    Height = 0,
}

---Per-surface precached data to construct paintable surface.
---@class ss.PrecachedData.Surface
---@field AABBMax            Vector Maximum component of all vertices in world coordinates.
---@field AABBMin            Vector Minimum component of all vertices in world coordinates.
---@field TransformPaintGrid VMatrix Transforms world coordinates into the serverside paint grid coordinates.
---@field LightmapHeight     number  The height of this surface in lightmap texture in luxels.
---@field LightmapWidth      number  The width of this surface in lightmap texture in luxels.
---@field PaintGridHeight    integer The height of this surface in the serverside paint grid.
---@field PaintGridWidth     integer The width of this surface in the serverside paint grid.
---Array of UV coordinates.
---One of them will be selected on mesh construction depending on the resolution of RenderTarget.
---@field UVInfo ss.PrecachedData.UVInfo[]
---Vertices in world coordinates (x0, y0, z0) which are directly fed into mesh triangles.
---This array includes normal (nx, ny, nz), tangent (tx, ty, tz), and bitangent (bx, by, bz) of the vertices.
---
---The forth row is used to store UV coordinates of the vertex.  
---The first two column is for RenderTarget UV (u1, v1), the rest is lightmap UV (u2, v2).  
---The RenderTarget UV values are relative (actual uv = offset + (u1 * width, v1 * height)).  
---The Lightmap UV values are absolute (no such calculation like u1v1 is performed).
---```
---[ tx bx nx | x0 ]
---[ ty by ny | y0 ]
---[ tz bz nz | z0 ]
---[ ---------+--- ]
---[ u1 v1 u2 | v2 ]
---```
---@field Vertices VMatrix[]
ss.struct "PrecachedData.Surface" {
    AABBMax = ss.vector_one * -math.huge,
    AABBMin = ss.vector_one * math.huge,
    TransformPaintGrid = Matrix(),
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
---@field SurfacesHDR     ss.PrecachedData.Surface[]
---@field SurfacesLDR     ss.PrecachedData.Surface[]
---@field SurfacesWater   ss.PrecachedData.Surface[]
---@field NumTrianglesHDR integer
---@field NumTrianglesLDR integer
ss.struct "PrecachedData" {
    CacheVersion = -1,
    MapCRC = "",
    MinimapBounds = {},
    Lightmap = ss.new "PrecachedData.Lightmap",
    NumTrianglesHDR = 0,
    NumTrianglesLDR = 0,
    SurfacesHDR = {},
    SurfacesLDR = {},
    SurfacesWater = {},
}
