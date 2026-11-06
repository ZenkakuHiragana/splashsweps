
-- Builds the paintable surfaces and static props of the map cache from the BSP.

---@class ss
local ss = SplashSWEPs
local Geometry           = ss.import "splashsweps/shared/geometry"
local MapCache           = ss.import "splashsweps/shared/mapcache/mapcache"
local MinimumBoundingBox = ss.import "splashsweps/shared/mapcache/minimumboundingbox"
local PaintableGrid      = ss.import "splashsweps/shared/paint/paintablegrid"
local Util               = ss.import "splashsweps/shared/util"

---@class ss.SurfaceBuilderModule
local SurfaceBuilder = ss.module "splashsweps/shared/mapcache/surfacebuilder"

local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local huge = math.huge
local max = math.max
local min = math.min
local round = math.Round
local MaterialCache = {} ---@type table<string, IMaterial>
local GRID_ROUNDING_TOLERANCE = 1e-6 -- In cells
local TextureFilterBits = bit.bor(
    SURF_SKY, SURF_NOPORTAL, SURF_TRIGGER,
    SURF_NODRAW, SURF_HINT, SURF_SKIP)

---Index to SURFEDGES array -> actual vertex index
---@param bsp   ss.BSP.Lumps
---@param index integer
---@return integer
local function SurfEdgeToVertexIndex(bsp, index)
    local surfedge  = bsp.SURFEDGES[index]
    local edge      = bsp.EDGES[abs(surfedge) + 1]
    return edge[surfedge < 0 and 2 or 1]
end

---Index to SURFEDGES array -> actual vertex
---@param bsp   ss.BSP.Lumps
---@param index integer
---@return ss.BinaryStruct.BSP.VERTEXES
local function SurfEdgeToVertex(bsp, index)
    return bsp.VERTEXES[SurfEdgeToVertexIndex(bsp, index) + 1]
end

---@param name string
---@return IMaterial
local function GetMaterial(name)
    if not MaterialCache[name] then
        MaterialCache[name] = Material(name)
    end
    return MaterialCache[name]
end

---Returns the orientation of a face of which the up is the normal,
---the same as normal:Angle() rotated by -90 degrees around its right:
---the forward is the negated up of normal:Angle(), and the left is its negated right.
---@param normalX number
---@param normalY number
---@param normalZ number
---@return number[] # A transform of ss.GeometryModule with no translation.
local function FaceOrientation(normalX, normalY, normalZ)
    local length = Geometry.Length(normalX, normalY, normalZ)
    local xyLength = Geometry.Length(normalX, normalY, 0)
    local sinPitch, cosPitch, sinYaw, cosYaw ---@type number, number, number, number
    if normalX == 0 and normalY == 0 then -- normal:Angle() has the pitch 270 or 90, and the yaw 0.
        sinPitch, cosPitch, sinYaw, cosYaw = normalZ > 0 and -1 or 1, 0, 0, 1
    else
        sinPitch, cosPitch = -normalZ / length, xyLength / length
        sinYaw, cosYaw = normalY / xyLength, normalX / xyLength
    end

    return {
        -sinPitch * cosYaw, -sinYaw, normalX / length, 0,
        -sinPitch * sinYaw,  cosYaw, normalY / length, 0,
        -cosPitch,           0,      normalZ / length, 0,
    }
end

---Bakes the transform into the paintable grid, and sets the sizes of the paintable grid and of its rectangle in the ink map.
---@param surf      ss.MapCache.Surface
---@param mbr       number[] The minimum bounding rectangle from MinimumBoundingBox.FindMBR.
---@param mbrSizeX  number
---@param mbrSizeY  number
local function SetTransformRelatedValues(surf, mbr, mbrSizeX, mbrSizeY)
    local g, worldToLocal = surf.ToGrid, Geometry.InvertRotationTranslation(mbr)
    for i = 1, 12 do g[i] = worldToLocal[i] end
    -- A size of exactly a multiple of the cell can be larger by rounding errors, which should not add a cell.
    surf.PaintableGridWidth  = ceil(mbrSizeX / PaintableGrid.CELL_SIZE - GRID_ROUNDING_TOLERANCE)
    surf.PaintableGridHeight = ceil(mbrSizeY / PaintableGrid.CELL_SIZE - GRID_ROUNDING_TOLERANCE)
    local margin = 2 * ss.MARGIN_HAMMER_UNITS -- Both sides
    surf.InkMapRectangle.Width  = mbrSizeX + margin
    surf.InkMapRectangle.Height = mbrSizeY + margin
end

---Sets the lengths of the vertex and the triangle arrays of a surface after they are written.
---@param surf ss.MapCache.Surface
local function SetMeshLengths(surf)
    surf.NumVertices      = #surf.PositionX
    surf.NumTriangles     = #surf.LightmapTangentX
    surf.NumVertexIndices = #surf.VertexIndices
end

---Writes the AABB of a surface with the margin to construct overlapped hash table entries.
---@param surf ss.MapCache.Surface
---@param minX number
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
local function SetAABB(surf, minX, minY, minZ, maxX, maxY, maxZ)
    local margin = ss.MARGIN_HAMMER_UNITS
    surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ = minX - margin, minY - margin, minZ - margin
    surf.AABBMaxX, surf.AABBMaxY, surf.AABBMaxZ = maxX + margin, maxY + margin, maxZ + margin
end

---Writes the minimum bounding box of a surface.
---@param surf  ss.MapCache.Surface
---@param box   number[] The origin and the orientation of the box.
---@param sizeX number
---@param sizeY number
---@param sizeZ number
local function SetMBB(surf, box, sizeX, sizeY, sizeZ)
    surf.MBBPitch,   surf.MBBYaw,     surf.MBBRoll    = Geometry.ToAngles(box)
    surf.MBBOriginX, surf.MBBOriginY, surf.MBBOriginZ = box[4], box[8], box[12]
    surf.MBBSizeX,   surf.MBBSizeY,   surf.MBBSizeZ   = sizeX, sizeY, sizeZ
end

---Lists the points of each triangle in order, which counts a point once for each triangle sharing it.
---@param xs            number[]
---@param ys            number[]
---@param zs            number[]
---@param vertexIndices integer[] Three vertices of each triangle.
---@return number[] xs
---@return number[] ys
---@return number[] zs
local function PointsOfTriangles(xs, ys, zs, vertexIndices)
    local listX, listY, listZ = {}, {}, {} ---@type number[], number[], number[]
    for i, k in ipairs(vertexIndices) do
        listX[i], listY[i], listZ[i] = xs[k], ys[k], zs[k]
    end

    return listX, listY, listZ
end

---Returns the transform of a triangle t1, t2, t3 of which the origin is t3:
---the forward along the edge t3 -> t2, the left toward t1 in the plane, and the up as the normal.
---This is the rotation of forward:AngleEx(forward:Cross(another)).
---@param xs number[]
---@param ys number[]
---@param zs number[]
---@param i1 integer t1
---@param i2 integer t2
---@param i3 integer t3
---@return number[]
local function TriangleToWorld(xs, ys, zs, i1, i2, i3)
    local forwardX, forwardY, forwardZ = xs[i2] - xs[i3], ys[i2] - ys[i3], zs[i2] - zs[i3]
    local anotherX, anotherY, anotherZ = xs[i1] - xs[i3], ys[i1] - ys[i3], zs[i1] - zs[i3]
    local fx, fy, fz = Geometry.Normalize(forwardX, forwardY, forwardZ)
    local px, py, pz = Geometry.Cross(forwardX, forwardY, forwardZ, anotherX, anotherY, anotherZ)
    local lx, ly, lz = Geometry.Normalize(Geometry.Cross(px, py, pz, fx, fy, fz))
    local ux, uy, uz = Geometry.Cross(fx, fy, fz, lx, ly, lz)
    return {
        fx, lx, ux, xs[i3],
        fy, ly, uy, ys[i3],
        fz, lz, uz, zs[i3],
    }
end

---@param surf ss.MapCache.Surface Its vertex and triangle arrays are written.
local function CalculateTriangleComponents(surf)
    local xs, ys, zs = surf.PositionX, surf.PositionY, surf.PositionZ
    local oxs, oys, ozs = surf.FlatPositionX, surf.FlatPositionY, surf.FlatPositionZ
    local vertexIndices = surf.VertexIndices
    surf.DisplacementTriangles = {}
    for i = 1, #vertexIndices, 3 do
        --                 foward = t2 - t3
        --                       ^
        --                       |
        --                      t2
        --                      /|
        --                    /  |
        --                  /    |
        -- -right         /      |
        --  = t1 - t3   /        |
        --      <---  +----------+
        --            t1         t3
        local i1 = vertexIndices[i]
        local i2 = vertexIndices[i + 1]
        local i3 = vertexIndices[i + 2]

        local worldToTriangle = Geometry.InvertRotationTranslation(TriangleToWorld(xs, ys, zs, i1, i2, i3))
        local t               = MapCache.DisplacementTriangle.new()

        -- Barycentric coordinates by the dual basis of the edges t1 -> t2 and t1 -> t3.
        t.BarycentricDot1X, t.BarycentricDot1Y, t.BarycentricDot1Z,
        t.BarycentricDot2X, t.BarycentricDot2Y, t.BarycentricDot2Z = Geometry.DualBasis(
            xs[i2] - xs[i1], ys[i2] - ys[i1], zs[i2] - zs[i1],
            xs[i3] - xs[i1], ys[i3] - ys[i1], zs[i3] - zs[i1])

        -- The rotation from the triangle to the triangle of the flat positions.
        local rotation = Geometry.Multiply(TriangleToWorld(oxs, oys, ozs, i1, i2, i3), worldToTriangle)
        local r        = t.ToFlatRotation
        r[1], r[2], r[3] = rotation[1], rotation[2],  rotation[3]
        r[4], r[5], r[6] = rotation[5], rotation[6],  rotation[7]
        r[7], r[8], r[9] = rotation[9], rotation[10], rotation[11]
        surf.DisplacementTriangles[#surf.DisplacementTriangles + 1] = t
    end

    surf.NumDisplacementTriangles = #surf.DisplacementTriangles
end

---Returns the blend factors of a vertex toward $basetexture2, 3, and 4 in the unit of the vertex color, from 0 to 255.
---WorldVertexTransition has only the first one, the vertex alpha, which is in this unit.
---@param dispVert   ss.BinaryStruct.BSP.DISP_VERTS
---@param multiblend ss.BinaryStruct.BSP.DISP_MULTIBLEND? Only for Lightmapped_4WayBlend.
---@return number blend2
---@return number blend3
---@return number blend4
local function GetVertexBlends(dispVert, multiblend)
    if not multiblend then
        return math.Clamp(dispVert.alpha, 0, 255), 0, 0
    end

    local m = multiblend.multiblend -- x, y, z, and w from 0 to 1
    return math.Clamp(m[2] * 255, 0, 255), math.Clamp(m[3] * 255, 0, 255), math.Clamp(m[4] * 255, 0, 255)
end

---Bilinear interpolation of the values at the corners (1) to (4) of a displacement, given in its figure.
---@param c1 number
---@param c2 number
---@param c3 number
---@param c4 number
---@param u  number
---@param v  number
---@return number
local function Bilerp(c1, c2, c3, c4, u, v)
    local left = c1 + (c2 - c1) * v
    local right = c4 + (c3 - c4) * v
    return left + (right - left) * u
end

---Returns the lightmap tangent and binormal of a triangle: the gradients s and t of the lightmap coordinates
---in the plane of the triangle, which satisfy u(p) = u(t1) + (p - t1)・s and v(p) = v(t1) + (p - t1)・t.
---@param surf ss.MapCache.Surface Its positions and lightmap coordinates are read.
---@param i1   integer
---@param i2   integer
---@param i3   integer
---@return number sx, number sy, number sz, number tx, number ty, number tz
local function TriangleLightmapBasis(surf, i1, i2, i3)
    local xs, ys, zs = surf.PositionX, surf.PositionY, surf.PositionZ
    local e1x, e1y, e1z = xs[i2] - xs[i1], ys[i2] - ys[i1], zs[i2] - zs[i1]
    local e2x, e2y, e2z = xs[i3] - xs[i1], ys[i3] - ys[i1], zs[i3] - zs[i1]
    if Geometry.LengthSqr(Geometry.Cross(e1x, e1y, e1z, e2x, e2y, e2z)) <= Util.eps then
        return 0, 0, 0, 0, 0, 0
    end

    -- The lightmap coordinates change by du1 along e1 and by du2 along e2,
    -- so their gradient is du1 * e1* + du2 * e2* with the dual basis e1* and e2*.
    local d1x, d1y, d1z, d2x, d2y, d2z = Geometry.DualBasis(e1x, e1y, e1z, e2x, e2y, e2z)
    local us, vs = surf.LightmapU, surf.LightmapV
    local du1, du2 = us[i2] - us[i1], us[i3] - us[i1]
    local dv1, dv2 = vs[i2] - vs[i1], vs[i3] - vs[i1]
    return d1x * du1 + d2x * du2, d1y * du1 + d2y * du2, d1z * du1 + d2z * du2,
           d1x * dv1 + d2x * dv2, d1y * dv1 + d2y * dv2, d1z * dv1 + d2z * dv2
end

---Construct a polygon from a raw displacement data
---@param bsp         ss.BSP.Lumps
---@param rawFace     ss.BinaryStruct.BSP.FACES
---@param xs          number[] The corners of the flat quadrilateral surface, which this function reorders.
---@param ys          number[]
---@param zs          number[]
---@param texInfo     ss.BinaryStruct.BSP.TEXINFO
---@param orientation number[] The orientation of the face from FaceOrientation.
---@return ss.MapCache.Surface
local function BuildFromDisplacement(bsp, rawFace, xs, ys, zs, texInfo, orientation)
    -- Collect displacement info
    local surf            = MapCache.Surface.new()
    local rawDispInfo     = bsp.DISPINFO
    local rawDispVerts    = bsp.DISP_VERTS
    local rawMultiBlend   = bsp.DISP_MULTIBLEND
    local multiblendStart = bsp.DispMultiBlendStart[rawFace.dispInfo + 1]
    local lightmapWidth   = rawFace.lightmapTextureSizeInLuxels[1]
    local lightmapHeight  = rawFace.lightmapTextureSizeInLuxels[2]
    local dispInfo        = rawDispInfo[rawFace.dispInfo + 1]
    local power           = 2 ^ dispInfo.power + 1
    local startX, startY, startZ = dispInfo.startPositionX, dispInfo.startPositionY, dispInfo.startPositionZ
    do
        -- dispInfo.startPosition isn't always equal to
        -- the first corner so find correct one and sort them
        local mindist, startindex = huge, 0
        for i = 1, #xs do
            local dist = Geometry.LengthSqr(xs[i] - startX, ys[i] - startY, zs[i] - startZ)
            if dist < mindist then
                startindex, mindist = i, dist
            end
        end

        local sortedX, sortedY, sortedZ = {}, {}, {} ---@type number[], number[], number[]
        for i = 1, 4 do
            local k = (i + startindex - 2) % 4 + 1
            sortedX[i], sortedY[i], sortedZ[i] = xs[k], ys[k], zs[k]
        end

        xs, ys, zs = sortedX, sortedY, sortedZ
    end

    --              u2   ___-->(3)
    --        ____---^^^^       ^
    --      (2)                 |
    --      ^                   |
    --  v1 /                    | v2
    --    /                     |
    --   /          u1          |
    -- (1)---------------------->(4)
    local u1x, u1y, u1z = xs[4] - xs[1], ys[4] - ys[1], zs[4] - zs[1]
    local u2x, u2y, u2z = xs[3] - xs[2], ys[3] - ys[2], zs[3] - zs[2]
    local v1x, v1y, v1z = xs[2] - xs[1], ys[2] - ys[1], zs[2] - zs[1]
    local v2x, v2y, v2z = xs[3] - xs[4], ys[3] - ys[4], zs[3] - zs[4]
    local parentNormalX, parentNormalY, parentNormalZ
        = Geometry.Normalize(Geometry.Cross(u1x, u1y, u1z, v1x, v1y, v1z))

    -- The point at (u, v) on the quadrilateral is at (u, (1 - u) * v, u * v) in this transform.
    local quadrilateralToWorld = {
        u1x, v1x, v2x, startX,
        u1y, v1y, v2y, startY,
        u1z, v1z, v2z, startZ,
    }

    ---The point at (u, v) on the quadrilateral, whose edges are stretched by scaleU along u and by scaleV along v.
    ---@param u number
    ---@param v number
    ---@param scaleU number
    ---@param scaleV number
    ---@return number x, number y, number z
    local function Subdivide(u, v, scaleU, scaleV)
        return Geometry.TransformPoint(quadrilateralToWorld, u * scaleU, (1 - u) * v * scaleV, u * v * scaleV)
    end

    -- Here we track accumulated length of edges for each direction to get proper UV coordinates.
    -- ^ v
    -- |    |  totalLengthV[xi]
    -- |    |   = ∑(i=2..power) ||(xi,i-1) to (xi,i)||
    -- |    |
    -- +----+--------- totalLengthU[yi]
    -- |    |           = ∑(i=2..power) ||(i-1,yi) to (i,yi)||
    -- +----+-----------> u
    local totalLengthU = {} ---@type number[]
    local totalLengthV = {} ---@type number[]

    -- Accumulated length of edges
    -- lengthIntegratedU[yi * power + xi + 1]
    --  = ∑(i=1..xi) ||(i-1,yi) to (i,yi)||
    -- lengthIntegratedV[yi * power + xi + 1]
    --  = ∑(i=1..yi) ||(xi,i-1) to (yi,i)||
    local lengthIntegratedU = {} ---@type number[]
    local lengthIntegratedV = {} ---@type number[]

    local textureSX, textureSY, textureSZ = texInfo.textureSX, texInfo.textureSY, texInfo.textureSZ
    local textureTX, textureTY, textureTZ = texInfo.textureTX, texInfo.textureTY, texInfo.textureTZ
    local textureOffsetS, textureOffsetT = texInfo.textureOffsetS, texInfo.textureOffsetT
    local cornerBumpmapU, cornerBumpmapV = {}, {} ---@type number[], number[]
    for i = 1, 4 do
        cornerBumpmapU[i] = Geometry.Dot(xs[i], ys[i], zs[i], textureSX, textureSY, textureSZ) + textureOffsetS
        cornerBumpmapV[i] = Geometry.Dot(xs[i], ys[i], zs[i], textureTX, textureTY, textureTZ) + textureOffsetT
    end

    local cornerLightmapU = { 0.5, 0.5,                  0.5 + lightmapWidth,  0.5 + lightmapWidth }
    local cornerLightmapV = { 0.5, 0.5 + lightmapHeight, 0.5 + lightmapHeight, 0.5 }
    local positionXs, positionYs, positionZs = surf.PositionX, surf.PositionY, surf.PositionZ -- The deformed grid points
    local vertexIndices = surf.VertexIndices
    local minX, minY, minZ = huge, huge, huge
    local maxX, maxY, maxZ = -huge, -huge, -huge
    for vi = 0, power - 1 do
        for ui = 0, power - 1 do
            local i = ui + vi * power + 1
            local dispVert = rawDispVerts[dispInfo.dispVertStart + i]
            local u = ui / (power - 1)
            local v = vi / (power - 1)
            local x, y, z = Subdivide(u, v, 1, 1)
            local offset = dispVert.distance
            x, y, z = x + dispVert.directionX * offset, y + dispVert.directionY * offset, z + dispVert.directionZ * offset
            positionXs[i], positionYs[i], positionZs[i] = x, y, z
            surf.BumpmapU[i] = Bilerp(cornerBumpmapU[1], cornerBumpmapU[2], cornerBumpmapU[3], cornerBumpmapU[4], u, v)
            surf.BumpmapV[i] = Bilerp(cornerBumpmapV[1], cornerBumpmapV[2], cornerBumpmapV[3], cornerBumpmapV[4], u, v)
            surf.Blend2[i], surf.Blend3[i], surf.Blend4[i]
                = GetVertexBlends(dispVert, multiblendStart and rawMultiBlend[multiblendStart + i - 1])
            surf.LightmapU[i] = Bilerp(cornerLightmapU[1], cornerLightmapU[2], cornerLightmapU[3], cornerLightmapU[4], u, v)
            surf.LightmapV[i] = Bilerp(cornerLightmapV[1], cornerLightmapV[2], cornerLightmapV[3], cornerLightmapV[4], u, v)

            if ui > 0 then
                local distance = Geometry.Length(x - positionXs[i - 1], y - positionYs[i - 1], z - positionZs[i - 1])
                totalLengthU[vi + 1] = (totalLengthU[vi + 1] or 0) + distance
                for j = ui + vi * power, (vi + 1) * power - 1 do
                    lengthIntegratedU[j + 1] = (lengthIntegratedU[j + 1] or 0) + distance
                end
            end

            if vi > 0 then
                local distance = Geometry.Length(x - positionXs[i - power], y - positionYs[i - power], z - positionZs[i - power])
                totalLengthV[ui + 1] = (totalLengthV[ui + 1] or 0) + distance
                for j = ui + vi * power, (power - 1) * power + ui, power do
                    lengthIntegratedV[j + 1] = (lengthIntegratedV[j + 1] or 0) + distance
                end
            end

            -- Modifies indices a bit to get two sets of indices of triangles
            local invert = Either(i % 2 == 1, 1, 0)

            -- Generate triangle indices from displacement mesh
            if ui < power - 1 and vi < power - 1 then
                vertexIndices[#vertexIndices + 1] = i + invert + power
                vertexIndices[#vertexIndices + 1] = i + 1
                vertexIndices[#vertexIndices + 1] = i
                vertexIndices[#vertexIndices + 1] = i - invert + 1
                vertexIndices[#vertexIndices + 1] = i + power
                vertexIndices[#vertexIndices + 1] = i + power + 1
            end

            -- Set bounding box
            minX, minY, minZ = min(minX, x), min(minY, y), min(minZ, z)
            maxX, maxY, maxZ = max(maxX, x), max(maxY, y), max(maxZ, z)
        end
    end

    SetAABB(surf, minX, minY, minZ, maxX, maxY, maxZ)

    -- The flat positions are on the quadrilateral stretched as long as the deformed edges,
    -- placed by the lengths of the edges, so that the paints keep their sizes on the deformed mesh.
    local meanLengthU = (Geometry.Length(u1x, u1y, u1z) + Geometry.Length(u2x, u2y, u2z)) * 0.5
    local meanLengthV = (Geometry.Length(v1x, v1y, v1z) + Geometry.Length(v2x, v2y, v2z)) * 0.5
    local scaleU = max(unpack(totalLengthU)) / meanLengthU
    local scaleV = max(unpack(totalLengthV)) / meanLengthV
    local normalXs, normalYs, normalZs = surf.NormalX, surf.NormalY, surf.NormalZ
    local normalCounts = {} ---@type integer[]
    for i = 1, #positionXs do
        local ui = (i - 1) % power
        local vi = floor((i - 1) / power)
        local u = (lengthIntegratedU[i] or 0) / totalLengthU[vi + 1]
        local v = (lengthIntegratedV[i] or 0) / totalLengthV[ui + 1]
        surf.FlatPositionX[i], surf.FlatPositionY[i], surf.FlatPositionZ[i] = Subdivide(u, v, scaleU, scaleV)
        normalXs[i], normalYs[i], normalZs[i] = 0, 0, 0
        normalCounts[i] = 0
    end

    for i = 1, #vertexIndices, 3 do
        local i1 = vertexIndices[i]
        local i2 = vertexIndices[i + 1]
        local i3 = vertexIndices[i + 2]
        -- All triangles share the engine's winding (BuildTriTLtoBR/BLtoTR of the engine),
        -- so this order gives the front side however the surface is folded.
        local nx, ny, nz = Geometry.Cross(
            positionXs[i3] - positionXs[i1], positionYs[i3] - positionYs[i1], positionZs[i3] - positionZs[i1],
            positionXs[i2] - positionXs[i1], positionYs[i2] - positionYs[i1], positionZs[i2] - positionZs[i1])
        if Geometry.LengthSqr(nx, ny, nz) > Util.eps then
            nx, ny, nz = Geometry.Normalize(nx, ny, nz)
            for _, k in ipairs { i1, i2, i3 } do
                normalXs[k], normalYs[k], normalZs[k] = normalXs[k] + nx, normalYs[k] + ny, normalZs[k] + nz
                normalCounts[k] = normalCounts[k] + 1
            end
        end

        local j = (i + 2) / 3
        surf.LightmapTangentX[j],  surf.LightmapTangentY[j],  surf.LightmapTangentZ[j],
        surf.LightmapBinormalX[j], surf.LightmapBinormalY[j], surf.LightmapBinormalZ[j]
            = TriangleLightmapBasis(surf, i1, i2, i3)
    end

    local textureSLength = Geometry.Length(textureSX, textureSY, textureSZ)
    local textureTLength = Geometry.Length(textureTX, textureTY, textureTZ)
    local sX, sY, sZ = Geometry.Normalize(textureSX, textureSY, textureSZ)
    local tX, tY, tZ = Geometry.Normalize(textureTX, textureTY, textureTZ)
    local shouldFlipTangentS
        = Geometry.Dot(parentNormalX, parentNormalY, parentNormalZ, Geometry.Cross(sX, sY, sZ, tX, tY, tZ)) > 0
    for i = 1, #positionXs do
        local nx, ny, nz = parentNormalX, parentNormalY, parentNormalZ
        if normalCounts[i] > 0 then
            nx, ny, nz = Geometry.Normalize(normalXs[i], normalYs[i], normalZs[i])
        end

        local tangentX, tangentY, tangentZ = Geometry.Cross(nx, ny, nz, tX, tY, tZ)
        if Geometry.LengthSqr(tangentX, tangentY, tangentZ) <= Util.eps then
            tangentX, tangentY, tangentZ = sX, sY, sZ
        else
            tangentX, tangentY, tangentZ = Geometry.Normalize(tangentX, tangentY, tangentZ)
        end

        local binormalX, binormalY, binormalZ = Geometry.Cross(tangentX, tangentY, tangentZ, nx, ny, nz)
        if Geometry.LengthSqr(binormalX, binormalY, binormalZ) <= Util.eps then
            binormalX, binormalY, binormalZ = tX, tY, tZ
        else
            binormalX, binormalY, binormalZ = Geometry.Normalize(binormalX, binormalY, binormalZ)
        end

        local tangentScale = shouldFlipTangentS and -textureSLength or textureSLength
        normalXs[i], normalYs[i], normalZs[i] = nx, ny, nz
        surf.TangentX[i], surf.TangentY[i], surf.TangentZ[i]
            = tangentX * tangentScale, tangentY * tangentScale, tangentZ * tangentScale
        surf.BinormalX[i], surf.BinormalY[i], surf.BinormalZ[i]
            = binormalX * textureTLength, binormalY * textureTLength, binormalZ * textureTLength
    end

    SetMeshLengths(surf)

    local originXs, originYs, originZs
        = PointsOfTriangles(surf.FlatPositionX, surf.FlatPositionY, surf.FlatPositionZ, vertexIndices)
    local mbr, mbrSizeX, mbrSizeY = MinimumBoundingBox.FindMBR(originXs, originYs, originZs, orientation)
    local mbb, mbbSizeX, mbbSizeY, mbbSizeZ = MinimumBoundingBox.FindMinimumOBB( -- For the deformed mesh
        PointsOfTriangles(positionXs, positionYs, positionZs, vertexIndices))
    local aabbSizeX = surf.AABBMaxX - surf.AABBMinX
    local aabbSizeY = surf.AABBMaxY - surf.AABBMinY
    local aabbSizeZ = surf.AABBMaxZ - surf.AABBMinZ
    if mbbSizeX * mbbSizeY * mbbSizeZ < aabbSizeX * aabbSizeY * aabbSizeZ then
        SetMBB(surf, mbb, mbbSizeX, mbbSizeY, mbbSizeZ)
    else -- The AABB is the smaller box.
        surf.MBBPitch,   surf.MBBYaw,     surf.MBBRoll    = 0, 0, 0
        surf.MBBOriginX, surf.MBBOriginY, surf.MBBOriginZ = surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ
        surf.MBBSizeX,   surf.MBBSizeY,   surf.MBBSizeZ   = aabbSizeX, aabbSizeY, aabbSizeZ
    end

    SetTransformRelatedValues(surf, mbr, mbrSizeX, mbrSizeY)
    CalculateTriangleComponents(surf)
    return surf
end

-- Construct a polygon from a raw face data
---@param bsp     ss.BSP.Lumps
---@param rawFace ss.BinaryStruct.BSP.FACES
---@return ss.MapCache.Surface?, boolean?
local function BuildFromBrushFace(bsp, rawFace)
    -- Collect texture information and see if it's valid
    local rawTexInfo   = bsp.TEXINFO
    local texInfo      = rawTexInfo[rawFace.texInfo + 1]
    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA
    local texData      = rawTexData[texInfo.texData + 1]
    local texOffset    = rawTexDict[texData.nameStringTableID + 1]
    local texIndex     = rawTexIndex[texOffset]
    local texName      = rawTexString[texIndex]:lower()
    local texMaterial  = GetMaterial(texName)
    local surfaceProp  = texMaterial:GetString "$surfaceprop" or ""

    -- Collect geometrical information
    local rawPlanes = bsp.PLANES
    local plane     = rawPlanes[rawFace.planeNum + 1]
    local firstedge = rawFace.firstEdge + 1
    local lastedge  = rawFace.firstEdge + rawFace.numEdges
    local normalX, normalY, normalZ = plane.normalX, plane.normalY, plane.normalZ

    -- Collect "raw" vertex list
    local rawXs, rawYs, rawZs = {}, {}, {} ---@type number[], number[], number[]
    for i = firstedge, lastedge do
        local k = #rawXs + 1
        local vertex = SurfEdgeToVertex(bsp, i)
        rawXs[k], rawYs[k], rawZs[k] = vertex.x, vertex.y, vertex.z
    end

    -- Filter out colinear vertices, keeping the corners where the polygon turns around the normal.
    local xs, ys, zs = {}, {}, {} ---@type number[], number[], number[]
    local numRaw = #rawXs
    for i = 1, numRaw do
        local before = (numRaw + i - 2) % numRaw + 1
        local after = i % numRaw + 1
        local x, y, z = rawXs[i], rawYs[i], rawZs[i]
        local turn = Geometry.Dot(normalX, normalY, normalZ, Geometry.Normalize(Geometry.Cross(
            rawXs[before] - x, rawYs[before] - y, rawZs[before] - z,
            rawXs[after] - x, rawYs[after] - y, rawZs[after] - z)))
        if turn > 0 then
            local k = #xs + 1
            xs[k], ys[k], zs[k] = x, y, z
        end
    end

    -- Check if it's valid to add to polygon list
    if #xs < 3 then return end
    local isDisplacement = rawFace.dispInfo >= 0
    local isWater = bit.band(texInfo.flags, SURF_WARP) ~= 0
        or texMaterial:GetShader() == "Water"
        or surfaceProp == "water"
        or surfaceProp == "slime"
    local orientation = FaceOrientation(normalX, normalY, normalZ)
    if isDisplacement then
        return BuildFromDisplacement(bsp, rawFace, xs, ys, zs, texInfo, orientation), tobool(isWater)
    end

    local surf = MapCache.Surface.new()
    local mbr, mbrSizeX, mbrSizeY, mbrSizeZ = MinimumBoundingBox.FindMBR(xs, ys, zs, orientation)
    local textureSX, textureSY, textureSZ = texInfo.textureSX, texInfo.textureSY, texInfo.textureSZ
    local textureTX, textureTY, textureTZ = texInfo.textureTX, texInfo.textureTY, texInfo.textureTZ
    local lightmapSX, lightmapSY, lightmapSZ = texInfo.lightmapSX, texInfo.lightmapSY, texInfo.lightmapSZ
    local lightmapTX, lightmapTY, lightmapTZ = texInfo.lightmapTX, texInfo.lightmapTY, texInfo.lightmapTZ
    local lightmapOffsetS = texInfo.lightmapOffsetS - rawFace.lightmapTextureMinsInLuxels[1] + 0.5
    local lightmapOffsetT = texInfo.lightmapOffsetT - rawFace.lightmapTextureMinsInLuxels[2] + 0.5

    -- The vertices of the mesh are those of the polygon.
    local minX, minY, minZ = huge, huge, huge
    local maxX, maxY, maxZ = -huge, -huge, -huge
    for i = 1, #xs do
        local x, y, z = xs[i], ys[i], zs[i]
        minX, minY, minZ = min(minX, x), min(minY, y), min(minZ, z)
        maxX, maxY, maxZ = max(maxX, x), max(maxY, y), max(maxZ, z)
        surf.PositionX[i],    surf.PositionY[i],    surf.PositionZ[i]    = x, y, z
        surf.NormalX[i],      surf.NormalY[i],      surf.NormalZ[i]      = normalX, normalY, normalZ
        surf.TangentX[i],     surf.TangentY[i],     surf.TangentZ[i]     = textureSX, textureSY, textureSZ
        surf.BinormalX[i],    surf.BinormalY[i],    surf.BinormalZ[i]    = textureTX, textureTY, textureTZ
        surf.FlatPositionX[i], surf.FlatPositionY[i], surf.FlatPositionZ[i] = x, y, z
        surf.BumpmapU[i]  = Geometry.Dot(x, y, z, textureSX,  textureSY,  textureSZ)  + texInfo.textureOffsetS
        surf.BumpmapV[i]  = Geometry.Dot(x, y, z, textureTX,  textureTY,  textureTZ)  + texInfo.textureOffsetT
        surf.LightmapU[i] = Geometry.Dot(x, y, z, lightmapSX, lightmapSY, lightmapSZ) + lightmapOffsetS
        surf.LightmapV[i] = Geometry.Dot(x, y, z, lightmapTX, lightmapTY, lightmapTZ) + lightmapOffsetT
        surf.Blend2[i], surf.Blend3[i], surf.Blend4[i] = 0, 0, 0
    end

    SetAABB(surf, minX, minY, minZ, maxX, maxY, maxZ)

    -- The triangles are a fan of the vertices.
    for i = 2, #xs - 1 do
        local j = i - 1
        surf.VertexIndices[3 * j - 2], surf.VertexIndices[3 * j - 1], surf.VertexIndices[3 * j] = 1, i, i + 1
        surf.LightmapTangentX[j],  surf.LightmapTangentY[j],  surf.LightmapTangentZ[j]  = lightmapSX, lightmapSY, lightmapSZ
        surf.LightmapBinormalX[j], surf.LightmapBinormalY[j], surf.LightmapBinormalZ[j] = lightmapTX, lightmapTY, lightmapTZ
    end

    SetMeshLengths(surf)

    if not isWater then
        SetMBB(surf, mbr, mbrSizeX, mbrSizeY, mbrSizeZ)
        SetTransformRelatedValues(surf, mbr, mbrSizeX, mbrSizeY)
    end

    return surf, tobool(isWater)
end

---Extracts surfaces from LUMP_FACES of parsed BSP structures.
---@param bsp ss.BSP.Lumps
---@param cache ss.MapCache
function SurfaceBuilder.BuildSurfaceCache(bsp, cache)
    local t0 = SysTime()
    local surf = {} ---@type ss.MapCache.Surface[]
    local water = {} ---@type ss.MapCache.Surface[]
    local lump = bsp.FACES or {}
    local faceIndexToModelIndex = {} ---@type integer[]
    for i, mdl in ipairs(bsp.MODELS) do
        for j = mdl.firstFace + 1, mdl.firstFace + mdl.numFaces do
            faceIndexToModelIndex[j] = i
        end
    end
    print "Generating inkable surfaces..."
    local validFaces = {} ---@type boolean[] face index --> is paintable
    for i, face in ipairs(lump) do
        local rawTexInfo = bsp.TEXINFO[face.texInfo + 1]
        if bit.band(rawTexInfo.flags, TextureFilterBits) == 0 then
            local rawTexData  = bsp.TEXDATA[rawTexInfo.texData + 1]
            local texOffset   = bsp.TEXDATA_STRING_TABLE[rawTexData.nameStringTableID + 1]
            local texIndex    = bsp.TexDataStringTableToIndex[texOffset]
            local texName     = bsp.TEXDATA_STRING_DATA[texIndex]:lower()
            local texMaterial = GetMaterial(texName)
            local surfaceProp = texMaterial:GetString "$surfaceprop" or ""
            local surfaceData = util.GetSurfaceData(util.GetSurfaceIndex(surfaceProp)) or {}
            if surfaceData.material ~= MAT_GRATE then
                validFaces[i] = true
            end
        end
    end

    for i, face in ipairs(lump) do
        if validFaces[i] then
            local s, iswater = BuildFromBrushFace(bsp, face)
            if s then
                if iswater then
                    water[#water + 1] = s
                else
                    s.FaceLumpIndex = i
                    s.ModelIndex = faceIndexToModelIndex[i]
                    surf[#surf + 1] = s
                end
            end
        end
    end
    cache.Surfaces = surf
    cache.NumSurfaces = #surf
    cache.WaterSurfaces = water
    cache.NumWaterSurfaces = #water
    print("    Generated " .. #surf .. " surfaces from " .. #lump .. " faces")

    local elapsed = round((SysTime() - t0) * 1000, 2)
    print("Elapsed time: " .. elapsed .. " ms.")
end

---studiohdr_t::illumposition follows id, version, checksum, name[64], length, and eyeposition.
local STUDIOHDR_ILLUMPOSITION_OFFSET = 92

---Corresponds to STATIC_PROP_USE_LIGHTING_ORIGIN in gamebspfile.h.
local STATIC_PROP_USE_LIGHTING_ORIGIN = 0x2

---Reads studiohdr_t::illumposition of the model.
---@param name string Path to the model.
---@return number[] # x, y, and z, which are the model origin if the model cannot be opened.
local function ReadIlluminationPosition(name)
    local f = file.Open(name, "rb", "GAME")
    if not f then return { 0, 0, 0 } end
    f:Seek(STUDIOHDR_ILLUMPOSITION_OFFSET)
    local illumposition = { f:ReadFloat(), f:ReadFloat(), f:ReadFloat() }
    f:Close()
    return illumposition
end

---Finds the cubemap sample the engine uses for a static prop:
---the nearest one to the lighting origin, as FindEnvCubemapForPoint in lightcache.cpp does.
---
---  lighting origin                         when (CStaticProp::Init)
---  --------------------------------------  --------------------------------------
---  LightingOrigin in the lump              STATIC_PROP_USE_LIGHTING_ORIGIN is set
---  illumposition transformed by the prop   otherwise
---@param bsp           ss.BSP.Lumps
---@param prop          ss.BinaryStruct.BSP.StaticProp
---@param illumposition number[] illumposition of the model as x, y, and z.
---@return string
local function FindStaticPropCubemap(bsp, prop, illumposition)
    local x, y, z = prop.lightingOriginX, prop.lightingOriginY, prop.lightingOriginZ
    if bit.band(prop.flags, STATIC_PROP_USE_LIGHTING_ORIGIN) == 0 then
        local modelToWorld = Geometry.FromAngles(prop.pitch, prop.yaw, prop.roll, prop.originX, prop.originY, prop.originZ)
        x, y, z = Geometry.TransformPoint(modelToWorld, illumposition[1], illumposition[2], illumposition[3])
    end

    local nearest = nil ---@type ss.BinaryStruct.BSP.CUBEMAPS?
    local nearestDistanceSqr = huge
    for _, sample in ipairs(bsp.CUBEMAPS or {}) do
        local distanceSqr = Geometry.LengthSqr(x - sample.originX, y - sample.originY, z - sample.originZ)
        if distanceSqr < nearestDistanceSqr then
            nearest = sample
            nearestDistanceSqr = distanceSqr
        end
    end

    if not nearest then return "" end
    return string.format("maps/%s/c%d_%d_%d", game.GetMap():lower(), nearest.originX, nearest.originY, nearest.originZ)
end

---Gets the dimension of the UV-unpacked rectangle for given AABB.
---
---```text
---  z
---  ^
---. |     y     size = (maxs - mins)
---. |    /        |
---. |   /'''---___V            <--height->
---. |  /         /|       -.---+----+----+
---. | /    +z   / |        |   | -x |    |
---. |/         /  |        |   +----+----+
---. |'''---___/   |        |   | -z | -y |
---. |         |+x /  ==> width +----+----+
---. |   -y    |  /         |   | +x |    |
---. |         | /          |   +----+----+
---   '''---___|/           |   | +z | +y |
---            '''---> x   -v---+----+----+
---```
---
---Width and height of each side:
---
---* +z, -z: size.x, size.y
---* +x, -x: size.y, size.z
---* +y, -y: size.x, size.z
---
---There are three patterns of unpacking and the one with minimum wasted spaces is selected.
---Each side cell additionally has m = ss.MARGIN_HAMMER_UNITS along each edge.
---The figure below omits them, so the returned size has 8m in w (4 cells) and 4m in h (2 cells) in addition:
---
---```text
---.   (1)               (2)               (3)
---. w = 2 (sx + sy)       2 (sy + sz)       2 (sx + sz)
---. h =    sx + sz           sx + sy           sy + sz
---.        sz   sx           sx   sy           sy   sz
---.      +----+----+       +----+----+       +----+----+
---.   sx | -y |    |    sy | -z |    |    sz | -x |    |
---.      +----+----+       +----+----+       +----+----+
---.   sy | -x | -z |    sz | -y | -x |    sx | -z | -y |
---.      +----+----+       +----+----+       +----+----+
---.   sx | +y |    |    sy | +z |    |    sz | +x |    |
---.      +----+----+       +----+----+       +----+----+
---.   sy | +x | +z |    sz | +y | +x |    sx | +z | +y |
---.      +----+----+       +----+----+       +----+----+
---```
---@param prop ss.MapCache.StaticProp
---@return number # w including the margins.
---@return number # h including the margins.
---@return integer # The number of the selected pattern.
local function GetStaticPropUVSize(prop)
    local sx = prop.BoundsMaxX - prop.BoundsMinX
    local sy = prop.BoundsMaxY - prop.BoundsMinY
    local sz = prop.BoundsMaxZ - prop.BoundsMinZ
    local margin = 2 * ss.MARGIN_HAMMER_UNITS -- On both edges of each side cell

    -- Pattern 1
    local width1 = 2 * (sx + sy) + 4 * margin
    local height1 = sx + sz + 2 * margin

    -- Pattern 2
    local width2 = 2 * (sy + sz) + 4 * margin
    local height2 = sx + sy + 2 * margin

    -- Pattern 3
    local width3 = 2 * (sx + sz) + 4 * margin
    local height3 = sy + sz + 2 * margin

    -- Find the pattern with the smallest area
    if sx <= sy and sx < sz then
        return width1, height1, 1
    elseif sy < sx and sy < sz then
        return width2, height2, 2
    else
        return width3, height3, 3
    end
end

---Extracts surfaces from static props.
---@param bsp ss.BSP.Lumps
---@param cache ss.MapCache
function SurfaceBuilder.BuildStaticPropCache(bsp, cache)
    print "Generating static prop surfaces..."
    local results        = {} ---@type ss.MapCache.StaticProp[]
    local illumpositions = {} ---@type table<string, number[]>
    for _, prop in ipairs(bsp.sprp.prop or {}) do
        if prop.solid > 0 then
            local modelIndex = prop.propType + 1
            local name = bsp.sprp.name[prop.propType + 1] or ""
            local info = util.GetModelInfo(name)
            local index = util.GetSurfaceIndex(info and info.SurfacePropName or "")
            local surf = util.GetSurfaceData(index)
            if info and surf and surf.material ~= MAT_GRATE then
                local scale = prop.uniformScale or 1
                illumpositions[name] = illumpositions[name] or ReadIlluminationPosition(name)
                local result = MapCache.StaticProp.new()
                local r = result.InkMapRectangle
                local maxX, maxY, maxZ = info.HullMax:Unpack()
                local minX, minY, minZ = info.HullMin:Unpack()
                result.Pitch, result.Yaw, result.Roll = prop.pitch, prop.yaw, prop.roll
                result.BoundsMaxX, result.BoundsMaxY, result.BoundsMaxZ = maxX * scale, maxY * scale, maxZ * scale
                result.BoundsMinX, result.BoundsMinY, result.BoundsMinZ = minX * scale, minY * scale, minZ * scale
                result.FadeMax = prop.fadeMaxDist
                result.FadeMin = prop.fadeMinDist
                result.ModelIndex = modelIndex
                result.PositionX, result.PositionY, result.PositionZ = prop.originX, prop.originY, prop.originZ
                result.Scale = scale
                result.Skin = prop.skin
                result.Envmap = FindStaticPropCubemap(bsp, prop, illumpositions[name])
                r.Width, r.Height, result.ShortestAxis = GetStaticPropUVSize(result)
                results[#results + 1] = result
            end
        end
    end

    cache.StaticProps = results
    cache.NumStaticProps = #results
    cache.StaticPropMDL = bsp.sprp.name or {}
    cache.NumStaticPropMDL = #cache.StaticPropMDL
    print("    Collected info for " .. #results .. " static props.")
end

return SurfaceBuilder
