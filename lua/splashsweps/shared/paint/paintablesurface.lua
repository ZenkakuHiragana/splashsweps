
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Classes containing the oriented minimum bounding box.
---@class ss.IHasMBB
---@field MBBAngles Angle  The angle of minimum (oriented) bounding box.
---@field MBBOrigin Vector The origin of minimum (oriented) bounding box.
---@field MBBSize   Vector The size of minimum (oriented) bounding box in their local coordinates.
ss.struct "IHasMBB" {
    MBBAngles = Angle(),
    MBBOrigin = Vector(),
    MBBSize   = Vector(),
}

---This class holds information around serverside paintings and conversion to UV coordinates.
---```text
---World origin
---  +--> x
---  |
---  v   WorldToLocalGridMatrix:GetInverseTR():GetTranslation()
---  y      +--> X
---         |
---         v   * (Xi, Yi) = WorldToLocalGridMatrix * (xi, yi)
---         Y
---```
---
---The surface is placed in UV coordinates like this:
---
---```text
---UV origin
--- +--------------+--> U             WorldToUVMatrix
--- |              ^                    :GetInverseTR()
--- |              |                    :GetTranslation()
--- |           OffsetV                       |
--- |              |   |<----UVWidth---->|    |
--- |              v   |                 |    |
--- +<----OffsetU--+-->+--------------<==@ <--+
--- |              ^   |                 $
--- v              |   |                 V
--- V         UVHeight |                 |
---                |   |                 |
---                v   |                 |
---              --+---+-----------------+
---```
---@class ss.PaintableSurface : ss.IHasMBB
---@field AABBMax                Vector  AABB maximum of this surface in world coordinates.
---@field AABBMin                Vector  AABB minimum of this surface in world coordinates.
---@field Normal                 Vector  Normal vector of this surface.
---@field Grid                   ss.PaintableGrid Represents serverside "canvas" for this surface to manage collision detection against painted ink.
---@field TriangleHash           table<integer, integer[]>? Hash table to lookup triangles of a displacement.
---@field Triangles              ss.DisplacementTriangle[]? Array of triangles of a displacement.
---@field WorldToLocalGridMatrix VMatrix The transformation matrix to convert world coordinates into local coordinates. This does not modify scales.
---@field WorldToUVMatrix        VMatrix The transformation matrix to convert world coordinates into UV coordinates. This does not modify scales.
---@field OffsetU                number  The u-coordinate of left-top corner of this surface in UV space in pixels.
---@field OffsetV                number  The v-coordinate of left-top corner of this surface in UV space in pixels.
---@field UVWidth                number  The width of this surface in UV space in pixels.
---@field UVHeight               number  The height of this surface in UV space in pixels.
ss.struct "PaintableSurface" "IHasMBB" {
    AABBMax = Vector(),
    AABBMin = Vector(),
    Normal = Vector(),
    Grid = ss.new "PaintableGrid",
    TriangleHash = nil,
    Triangles = nil,
    WorldToLocalGridMatrix = Matrix(),
    WorldToUVMatrix = Matrix(),
    OffsetU = 0,
    OffsetV = 0,
    UVWidth = 0,
    UVHeight = 0,
}

---Vertices and some other info of a triangle in a displacement.
---@class ss.DisplacementTriangle : ss.IHasMBB
---@field [1]       Vector The positions of this triangle.
---@field [2]       Vector The positions of this triangle.
---@field [3]       Vector The positions of this triangle.
---@field [4]       Vector The position that the corresponding vertex originally was located at.
---@field [5]       Vector The position that the corresponding vertex originally was located at.
---@field [6]       Vector The position that the corresponding vertex originally was located at.
---@field BarycentricDot1 Vector Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector Parameter to calculate barycentric coordinates w.
---@field BarycentricAdd1 number Parameter to calculate barycentric coordinates v.
---@field BarycentricAdd2 number Parameter to calculate barycentric coordinates w.
ss.struct "DisplacementTriangle" "IHasMBB" {
    [1] = Vector(),
    [2] = Vector(),
    [3] = Vector(),
    [4] = Vector(),
    [5] = Vector(),
    [6] = Vector(),
    BarycentricDot1 = Vector(),
    BarycentricDot2 = Vector(),
    BarycentricAdd1 = 0,
    BarycentricAdd2 = 0,
}

---Reads a surface list from a file and stores them for later use.
---@param surfaces ss.PrecachedData.SurfaceInfo?
function ss.SetupSurfaces(surfaces)
    if not surfaces then return end
    for i, surf in ipairs(surfaces) do
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToLocalGridMatrix:SetAngles(surf.TransformPaintGrid.Angle)
        ps.WorldToLocalGridMatrix:SetTranslation(surf.TransformPaintGrid.Translation)
        ps.Normal = ps.WorldToLocalGridMatrix:GetInverseTR():GetUp()
        ps.Grid.Width = surf.PaintGridWidth
        ps.Grid.Height = surf.PaintGridHeight
        ps.MBBAngles = surf.MBBAngles
        ps.MBBOrigin = surf.MBBOrigin
        ps.MBBSize = surf.MBBSize
        ps.TriangleHash = surf.TriangleHash
        ps.Triangles = surf.Triangles
        for j, t in ipairs(surf.Triangles or {}) do
            ps.Triangles[j][1] = surf.Vertices[t.Index].Translation
            ps.Triangles[j][2] = surf.Vertices[t.Index + 1].Translation
            ps.Triangles[j][3] = surf.Vertices[t.Index + 2].Translation
            ps.Triangles[j][4] = surf.Vertices[t.Index].DisplacementOrigin
            ps.Triangles[j][5] = surf.Vertices[t.Index + 1].DisplacementOrigin
            ps.Triangles[j][6] = surf.Vertices[t.Index + 2].DisplacementOrigin
            ps.Triangles[j].BarycentricAdd1 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot1)
            ps.Triangles[j].BarycentricAdd2 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot2)
        end
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvInfo = surf.UVInfo[rtIndex]
            ps.WorldToUVMatrix:SetAngles(uvInfo.Angle)
            ps.WorldToUVMatrix:SetTranslation(uvInfo.Translation)
            ps.OffsetU = math.max(uvInfo.OffsetU * rtSize - ss.RT_MARGIN_PIXELS / 2, 0)
            ps.OffsetV = math.max(uvInfo.OffsetV * rtSize - ss.RT_MARGIN_PIXELS / 2, 0)
            ps.UVWidth = uvInfo.Width * rtSize + ss.RT_MARGIN_PIXELS
            ps.UVHeight = uvInfo.Height * rtSize + ss.RT_MARGIN_PIXELS
        end
        ss.SurfaceArray[i] = ps
    end
end

---Returns barycentric coordinates (1 - u - v, u, v) from given triangle.
---@param triangle ss.DisplacementTriangle
---@param query Vector
---@return Vector barycentric The coordinates which may be outside of the triangle.
function ss.BarycentricCoordinates(triangle, query)
    local u = query:Dot(triangle.BarycentricDot1) + triangle.BarycentricAdd1
    local v = query:Dot(triangle.BarycentricDot2) + triangle.BarycentricAdd2
    return Vector(1 - u - v, u, v)
end
