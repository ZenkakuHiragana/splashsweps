
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
--- +-------------+--> V              WorldToUVMatrix
--- |             ^                     :GetInverseTR()
--- |             |                     :GetTranslation()
--- |          OffsetU                        |
--- |             |    |<----UVHeight--->|    |
--- |             v    |                 |    |
--- +<----OffsetV-+--->+--------------<==@ <--+
--- |             ^    |                 $
--- v             |    |                 v
--- U          UVWidth |                 |
---               |    |                 |
---               v    |                 |
---              -+----+-----------------+
---```
---@class ss.PaintableSurface : ss.IHasMBB
---@field AABBMax                Vector           AABB maximum of this surface in world coordinates.
---@field AABBMin                Vector           AABB minimum of this surface in world coordinates.
---@field Normal                 Vector           Normal vector of this surface.
---@field Grid                   ss.PaintableGrid Represents serverside "canvas" for this surface to manage collision detection against painted ink.
---@field StaticPropUnwrapIndex  integer?         Determines how this static prop surfaces are unwrapped.
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
    StaticPropUnwrapIndex = nil,
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
---@field WorldToLocalRotation VMatrix Rotation matrix to convert world coordinates into local coordinates.
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
    WorldToLocalRotation = Matrix(),
}

---Returns barycentric coordinates (1 - u - v, u, v) from given triangle.
---@param triangle ss.DisplacementTriangle
---@param query Vector
---@return Vector barycentric The coordinates which may be outside of the triangle.
function ss.BarycentricCoordinates(triangle, query)
    local u = query:Dot(triangle.BarycentricDot1) + triangle.BarycentricAdd1
    local v = query:Dot(triangle.BarycentricDot2) + triangle.BarycentricAdd2
    return Vector(1 - u - v, u, v)
end

---Calculates cube-projected UV coordinates of a static prop.
---@param worldPos Vector
---@param worldNormal Vector
---@param worldToLocal VMatrix
---@param uvTransformMatrix VMatrix
---@param unwrapIndex integer
---@param boundingBoxSize Vector
---@return Vector
function ss.CalculateStaticPropUV(worldPos, worldNormal, worldToLocal, uvTransformMatrix, unwrapIndex, boundingBoxSize)
    local localPos = worldToLocal * worldPos
    local localNormal = worldToLocal * worldNormal - worldToLocal:GetTranslation()
    local absLocalNormal = Vector(math.abs(localNormal.x), math.abs(localNormal.y), math.abs(localNormal.z))
    local maxAbsComponent = math.max(absLocalNormal.x, absLocalNormal.y, absLocalNormal.z)

    local size = Vector()
    local uv = Vector()
    local faceIndex = 0
    if unwrapIndex == 1 then
        size:SetUnpacked(boundingBoxSize.x, boundingBoxSize.y, boundingBoxSize.z)
        if maxAbsComponent == absLocalNormal.x then
            uv.x = localPos.y
            uv.y = localPos.z
            faceIndex = (localNormal.x < 0) and 4 or 2
        elseif maxAbsComponent == absLocalNormal.y then
            uv.x = localPos.x
            uv.y = localPos.z
            faceIndex = (localNormal.y < 0) and 1 or 3
        else
            uv.x = localPos.y
            uv.y = localPos.x
            faceIndex = (localNormal.z < 0) and 5 or 6
        end
    elseif unwrapIndex == 2 then
        size:SetUnpacked(boundingBoxSize.y, boundingBoxSize.x, boundingBoxSize.z)
        if maxAbsComponent == absLocalNormal.x then
            uv.x = localPos.y
            uv.y = localPos.z
            faceIndex = (localNormal.x < 0) and 1 or 3
        elseif maxAbsComponent == absLocalNormal.y then
            uv.x = localPos.x
            uv.y = localPos.z
            faceIndex = (localNormal.y < 0) and 4 or 2
        else
            uv.x = localPos.x
            uv.y = localPos.y
            faceIndex = (localNormal.z < 0) and 5 or 6
        end
    else
        size:SetUnpacked(boundingBoxSize.z, boundingBoxSize.x, boundingBoxSize.y)
        if maxAbsComponent == absLocalNormal.x then
            uv.x = localPos.z
            uv.y = localPos.y
            faceIndex = (localNormal.x < 0) and 1 or 3
        elseif maxAbsComponent == absLocalNormal.y then
            uv.x = localPos.x
            uv.y = localPos.z
            faceIndex = (localNormal.y < 0) and 5 or 6
        else
            uv.x = localPos.x
            uv.y = localPos.y
            faceIndex = (localNormal.z < 0) and 4 or 2
        end
    end

    local offsetU = { 0, size.x, size.x + size.y, 2 * size.x + size.y, size.x, 2 * size.x + size.y }
    local offsetV = { 0, 0, 0, 0, size.z, size.z }
    if faceIndex == 2 or faceIndex == 3 or faceIndex == 5 then
        uv.x = size.x - uv.x
    end

    uv.x = uv.x + offsetU[faceIndex]
    uv.y = uv.y + offsetV[faceIndex]
    local uvTransformed = uvTransformMatrix * uv
    return Vector(uvTransformed.y, uvTransformed.x)
end

---Reads a surface list from a file and stores them for later use.
---@param surfaces ss.PrecachedData.Surface[]?
function ss.SetupSurfaces(surfaces)
    if not surfaces then return end
    local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
    local MatrixMeta = getmetatable(ss.new "PrecachedData.MatrixTransform")
    local TriangleMeta = getmetatable(ss.new "PrecachedData.DisplacementTriangle")
    local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
    local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
    for i, surf in ipairs(surfaces) do
        setmetatable(surf, SurfaceMeta)
        setmetatable(surf.TransformPaintGrid, MatrixMeta)
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
        ps.Triangles = surf.Triangles and {}
        for _, v in ipairs(surf.Vertices) do setmetatable(v, VertexMeta) end
        for j, t in ipairs(surf.Triangles or {}) do
            setmetatable(t, TriangleMeta)
            ps.Triangles[j] = ss.new "DisplacementTriangle"
            ps.Triangles[j][1] = surf.Vertices[t.Index].Translation
            ps.Triangles[j][2] = surf.Vertices[t.Index + 1].Translation
            ps.Triangles[j][3] = surf.Vertices[t.Index + 2].Translation
            ps.Triangles[j][4] = surf.Vertices[t.Index].DisplacementOrigin
            ps.Triangles[j][5] = surf.Vertices[t.Index + 1].DisplacementOrigin
            ps.Triangles[j][6] = surf.Vertices[t.Index + 2].DisplacementOrigin
            ps.Triangles[j].BarycentricDot1 = t.BarycentricDot1
            ps.Triangles[j].BarycentricDot2 = t.BarycentricDot2
            ps.Triangles[j].BarycentricAdd1 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot1)
            ps.Triangles[j].BarycentricAdd2 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot2)
            ps.Triangles[j].MBBAngles       = t.MBBAngles
            ps.Triangles[j].MBBOrigin       = t.MBBOrigin
            ps.Triangles[j].MBBSize         = t.MBBSize
            ps.Triangles[j].WorldToLocalRotation:SetAngles(t.WorldToLocalGridRotation)
        end
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvInfo = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
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

---Reads a list of static props and stores them for later use.
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function ss.SetupSurfacesStaticProp(staticPropInfo, uvInfo)
    local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
    local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
    local numSurfaces = #ss.SurfaceArray
    for i, prop in ipairs(staticPropInfo or {}) do
        setmetatable(prop, StaticPropMeta)
        local uv = setmetatable(uvInfo[i][#ss.RenderTarget.Resolutions], StaticPropUVMeta)
        local localToWorld = Matrix()
        localToWorld:SetAngles(prop.Angles)
        localToWorld:SetTranslation(prop.Position)
        localToWorld:SetTranslation(localToWorld * prop.BoundsMin)
        local worldToLocal = localToWorld:GetInverseTR()
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = localToWorld * prop.BoundsMax
        ps.AABBMin = localToWorld:GetTranslation()
        OrderVectors(ps.AABBMin, ps.AABBMax)
        ps.WorldToLocalGridMatrix:SetAngles(worldToLocal:GetAngles())
        ps.WorldToLocalGridMatrix:SetTranslation(worldToLocal:GetTranslation())
        ps.Normal = localToWorld:GetUp()
        ps.Grid.Width = math.ceil(uv.Width / ss.InkGridCellSize)
        ps.Grid.Height = math.ceil(uv.Height / ss.InkGridCellSize)
        ps.StaticPropUnwrapIndex = prop.UnwrapIndex
        ps.MBBAngles = prop.Angles
        ps.MBBOrigin = localToWorld:GetTranslation()
        ps.MBBSize = prop.BoundsMax - prop.BoundsMin
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvScale = ss.RenderTarget.HammerUnitsToUV
            local du ---@type number
            local u, v ---@type Vector, Vector
            if uv.Offset.z > 0 then
                du = uv.Offset.x + uv.Width
                u = Vector(0, 1, 0)
                v = Vector(-1, 0, 0)
            else
                du = uv.Offset.x
                u = Vector(1, 0, 0)
                v = Vector(0, 1, 0)
            end
            ps.WorldToUVMatrix:SetForward(u)
            ps.WorldToUVMatrix:SetRight(-v)
            ps.WorldToUVMatrix:SetScale(Vector(uvScale * rtSize, uvScale * rtSize, 1))
            ps.OffsetU  = math.max(du          * rtSize - ss.RT_MARGIN_PIXELS / 2, 0)
            ps.OffsetV  = math.max(uv.Offset.y * rtSize - ss.RT_MARGIN_PIXELS / 2, 0)
            ps.UVWidth  = uv.Width    * rtSize + ss.RT_MARGIN_PIXELS
            ps.UVHeight = uv.Height   * rtSize + ss.RT_MARGIN_PIXELS
        end
        ss.SurfaceArray[numSurfaces + i] = ps
    end
end
