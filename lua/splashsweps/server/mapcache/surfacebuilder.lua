
-- Builds the paintable surfaces and static props of the map cache from the BSP.

---@class ss
local ss = SplashSWEPs
local PaintableGrid = ss.import "splashsweps/shared/paint/paintablegrid"
local BoundingBox   = ss.import "splashsweps/server/mapcache/boundingbox"
local Util          = ss.import "splashsweps/shared/util"
local PrecachedData = ss.import "splashsweps/shared/typing/precachedata"

---@class ss.SurfaceBuilderModule
local SurfaceBuilder = ss.module "splashsweps/server/mapcache/surfacebuilder"

local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local round = math.Round
local Vector = Vector
local Matrix = Matrix
local MaterialCache = {} ---@type table<string, IMaterial>
local WorkMatrix = Matrix() -- Work area to rebuild matrices from angles.
local TextureFilterBits = bit.bor(
    SURF_SKY, SURF_NOPORTAL, SURF_TRIGGER,
    SURF_NODRAW, SURF_HINT, SURF_SKIP)

---Index to SURFEDGES array -> actual vertex index
---@param bsp ss.RawBSPResults
---@param index integer
---@return integer
local function SurfEdgeToVertexIndex(bsp, index)
    local surfedge  = bsp.SURFEDGES[index]
    local edge      = bsp.EDGES[abs(surfedge) + 1]
    return edge[surfedge < 0 and 2 or 1]
end

---Index to SURFEDGES array -> actual vertex
---@param bsp ss.RawBSPResults
---@param index integer
---@return Vector
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

---Converts \\ to /, strips the extension, and hdr variant
---@param name string?
---@return string?
local function NormalizeTextureName(name)
    if not name or name == "" then return end
    local normalized = name:lower():gsub("\\", "/"):gsub("%.vtf$", ""):gsub("%.hdr$", "")
    return normalized
end

---Gets the string "<X>_<Y>_<Z>" from given vector (X, Y, Z).
---@param origin Vector
---@return string
local function CubemapOriginKey(origin)
    return string.format("%d_%d_%d", round(origin.x), round(origin.y), round(origin.z))
end

---Parses resolved cubemap texture name and returns its origin key "<X>_<Y>_<Z>".
---@param name string?
---@return string?
local function ParseCubemapOriginKey(name)
    name = NormalizeTextureName(name)
    if not name then return end

    local x, y, z = name:match("/c(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    if not x then
        x, y, z = name:match("^c(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    end
    if not x then
        x, y, z = name:match("_(%-?%d+)_(%-?%d+)_(%-?%d+)$")
    end
    if not x then return end

    return string.format("%d_%d_%d", tonumber(x), tonumber(y), tonumber(z))
end

---@param bsp ss.RawBSPResults
---@return ss.PrecachedData.CubemapInfo[] cubemaps
---@return table<string, ss.PrecachedData.CubemapInfo> cubemapsByOrigin
local function BuildCubemapEntries(bsp)
    local cubemaps = {} ---@type ss.PrecachedData.CubemapInfo[]
    local cubemapsByOrigin = {} ---@type table<string, ss.PrecachedData.CubemapInfo>
    local mapName = game.GetMap():lower()
    for _, sample in ipairs(bsp.CUBEMAPS or {}) do
        local origin = Vector(round(sample.origin.x), round(sample.origin.y), round(sample.origin.z))
        local cubemap = PrecachedData.CubemapInfo.new()
        cubemap.Envmap = string.format("maps/%s/c%d_%d_%d", mapName, origin.x, origin.y, origin.z)
        cubemap.OriginX, cubemap.OriginY, cubemap.OriginZ = origin:Unpack()
        cubemap.BoxMinX, cubemap.BoxMinY, cubemap.BoxMinZ = math.huge, math.huge, math.huge
        cubemap.BoxMaxX, cubemap.BoxMaxY, cubemap.BoxMaxZ = -math.huge, -math.huge, -math.huge
        cubemaps[#cubemaps + 1] = cubemap
        cubemapsByOrigin[CubemapOriginKey(origin)] = cubemap
    end

    return cubemaps, cubemapsByOrigin
end

---@param cubemap ss.PrecachedData.CubemapInfo?
---@param surf ss.PrecachedData.Surface
local function AccumulateCubemapBox(cubemap, surf)
    if not cubemap then return end
    cubemap.BoxMinX = min(cubemap.BoxMinX, surf.AABBMinX)
    cubemap.BoxMinY = min(cubemap.BoxMinY, surf.AABBMinY)
    cubemap.BoxMinZ = min(cubemap.BoxMinZ, surf.AABBMinZ)
    cubemap.BoxMaxX = max(cubemap.BoxMaxX, surf.AABBMaxX)
    cubemap.BoxMaxY = max(cubemap.BoxMaxY, surf.AABBMaxY)
    cubemap.BoxMaxZ = max(cubemap.BoxMaxZ, surf.AABBMaxZ)
    cubemap.FaceCount = cubemap.FaceCount + 1
    cubemap.Blend = 1
end

---@param cubemaps ss.PrecachedData.CubemapInfo[]
local function FinalizeCubemapEntries(cubemaps)
    for _, cubemap in ipairs(cubemaps) do
        if cubemap.FaceCount == 0 then
            cubemap.BoxMinX, cubemap.BoxMinY, cubemap.BoxMinZ = cubemap.OriginX, cubemap.OriginY, cubemap.OriginZ
            cubemap.BoxMaxX, cubemap.BoxMaxY, cubemap.BoxMaxZ = cubemap.OriginX, cubemap.OriginY, cubemap.OriginZ
            cubemap.Blend = 0
        end
    end
end

---Bakes the transform into the paint grid, and sets the sizes of the paint grid and of the UV space.
---@param surf ss.PrecachedData.Surface
---@param mbrMatrix VMatrix
---@param mbrSize Vector
local function SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
    -- Built through the angles so that the values stay the same as when the cache stored the angles.
    -- SetAngles keeps the scale of the matrix with rounding errors, so the matrix is reset first.
    local paintGridMatrix = mbrMatrix:GetInverseTR()
    WorkMatrix:Identity()
    WorkMatrix:SetAngles(paintGridMatrix:GetAngles())
    WorkMatrix:SetTranslation(paintGridMatrix:GetTranslation())
    local g = surf.WorldToLocalGrid
    g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12] = WorkMatrix:Unpack()
    surf.PaintGridWidth  = ceil(mbrSize.x / PaintableGrid.CELL_SIZE)
    surf.PaintGridHeight = ceil(mbrSize.y / PaintableGrid.CELL_SIZE)
    surf.MBRMatrix = mbrMatrix
    for i = 1, #PrecachedData.InkMapResolutions do
        surf.UVInfo[i] = PrecachedData.UVInfo.new()
        surf.UVInfo[i].Width  = mbrSize.x
        surf.UVInfo[i].Height = mbrSize.y
    end
end

---Writes vertex k of the mesh of a surface into its vertex arrays.
---@param surf        ss.PrecachedData.Surface
---@param k           integer
---@param position    Vector
---@param normal      Vector
---@param tangent     Vector
---@param binormal    Vector
---@param paintOrigin Vector
local function SetVertex(surf, k, position, normal, tangent, binormal, paintOrigin)
    surf.PositionX[k],    surf.PositionY[k],    surf.PositionZ[k]    = position:Unpack()
    surf.NormalX[k],      surf.NormalY[k],      surf.NormalZ[k]      = normal:Unpack()
    surf.TangentX[k],     surf.TangentY[k],     surf.TangentZ[k]     = tangent:Unpack()
    surf.BinormalX[k],    surf.BinormalY[k],    surf.BinormalZ[k]    = binormal:Unpack()
    surf.PaintOriginX[k], surf.PaintOriginY[k], surf.PaintOriginZ[k] = paintOrigin:Unpack()
end

---Writes triangle j of the mesh of a surface into its triangle arrays.
---@param surf             ss.PrecachedData.Surface
---@param j                integer
---@param i1               integer
---@param i2               integer
---@param i3               integer
---@param lightmapTangent  Vector
---@param lightmapBinormal Vector
local function SetTriangle(surf, j, i1, i2, i3, lightmapTangent, lightmapBinormal)
    local i = 3 * j
    surf.VertexIndices[i - 2], surf.VertexIndices[i - 1], surf.VertexIndices[i] = i1, i2, i3
    surf.LightmapTangentX[j],  surf.LightmapTangentY[j],  surf.LightmapTangentZ[j]  = lightmapTangent:Unpack()
    surf.LightmapBinormalX[j], surf.LightmapBinormalY[j], surf.LightmapBinormalZ[j] = lightmapBinormal:Unpack()
end

---Sets the lengths of the vertex and the triangle arrays of a surface after they are written.
---@param surf ss.PrecachedData.Surface
local function SetMeshLengths(surf)
    surf.NumVertices      = #surf.PositionX
    surf.NumTriangles     = #surf.LightmapTangentX
    surf.NumVertexIndices = #surf.VertexIndices
end

---Writes the AABB of a surface with the margin to construct overlapped hash table entries.
---@param surf ss.PrecachedData.Surface
---@param mins Vector
---@param maxs Vector
local function SetAABB(surf, mins, maxs)
    local margin = ss.MARGIN_HAMMER_UNITS
    local minX, minY, minZ = mins:Unpack()
    local maxX, maxY, maxZ = maxs:Unpack()
    surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ = minX - margin, minY - margin, minZ - margin
    surf.AABBMaxX, surf.AABBMaxY, surf.AABBMaxZ = maxX + margin, maxY + margin, maxZ + margin
end

---Writes the minimum bounding box of a surface.
---@param surf   ss.PrecachedData.Surface
---@param matrix VMatrix The origin and the orientation of the box.
---@param size   Vector
local function SetMBB(surf, matrix, size)
    surf.MBBPitch,   surf.MBBYaw,     surf.MBBRoll    = matrix:GetAngles():Unpack()
    surf.MBBOriginX, surf.MBBOriginY, surf.MBBOriginZ = matrix:GetTranslation():Unpack()
    surf.MBBSizeX,   surf.MBBSizeY,   surf.MBBSizeZ   = size:Unpack()
end

---Lists the vertices of each triangle in order, which counts a vertex once for each triangle sharing it.
---@param vertices      Vector[]
---@param vertexIndices integer[] Three vertices of each triangle.
---@return Vector[]
local function VerticesOfTriangles(vertices, vertexIndices)
    local list = {} ---@type Vector[]
    for i, k in ipairs(vertexIndices) do
        list[i] = vertices[k]
    end

    return list
end

---@param surf          ss.PrecachedData.Surface
---@param positions     Vector[]  Positions of the vertices.
---@param paintOrigins  Vector[]  Reference points of the vertices to compute the ink UV coordinates.
---@param vertexIndices integer[] Three vertices of each triangle.
local function CalculateTriangleComponents(surf, positions, paintOrigins, vertexIndices)
    local WorldToLocalRotation = Matrix()
    local DispPaintOriginRotation = Matrix()
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
        local t1 = positions[i1]
        local t2 = positions[i2]
        local t3 = positions[i3]
        local forward = t2 - t3
        local another = t1 - t3
        local angle = forward:AngleEx(forward:Cross(another))
        local e1 = angle:Forward()
        local e2 = -angle:Right()
        local minX = min(0, e1:Dot(another))
        local maxX = max(e1:Dot(forward), e1:Dot(another))
        local t1t2 = t2 - t1
        local t1t3 = -another
        local d1212 = t1t2:Dot(t1t2)
        local d1213 = t1t2:Dot(t1t3)
        local d1313 = t1t3:Dot(t1t3)
        local denominator = d1212 * d1313 - d1213 * d1213
        local barycentricDot1 = (d1313 * t1t2 - d1213 * t1t3) / denominator
        local barycentricDot2 = (d1212 * t1t3 - d1213 * t1t2) / denominator
        local t = PrecachedData.DisplacementTriangle.new()
        t.BarycentricDot1X, t.BarycentricDot1Y, t.BarycentricDot1Z = barycentricDot1:Unpack()
        t.BarycentricDot2X, t.BarycentricDot2Y, t.BarycentricDot2Z = barycentricDot2:Unpack()
        t.MBBPitch, t.MBBYaw, t.MBBRoll = angle:Unpack()
        t.MBBOriginX, t.MBBOriginY, t.MBBOriginZ = (t3 + e1 * minX):Unpack()
        t.MBBSizeX, t.MBBSizeY = maxX - minX, e2:Dot(another)

        local org1 = paintOrigins[i1]
        local org2 = paintOrigins[i2]
        local org3 = paintOrigins[i3]
        local orgForward = org2 - org3
        local orgAnother = org1 - org3
        local orgAngle = orgForward:AngleEx(orgForward:Cross(orgAnother))
        DispPaintOriginRotation:SetAngles(orgAngle)
        WorldToLocalRotation:SetAngles(angle)
        WorldToLocalRotation:InvertTR()
        WorldToLocalRotation:Set(DispPaintOriginRotation * WorldToLocalRotation)

        -- Built through the angles so that the values stay the same as when the cache stored the angles.
        WorkMatrix:Identity()
        WorkMatrix:SetAngles(WorldToLocalRotation:GetAngles())
        local e11, e12, e13, _, e21, e22, e23, _, e31, e32, e33 = WorkMatrix:Unpack()
        local r = t.WorldToLocalGridRotation
        r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] = e11, e12, e13, e21, e22, e23, e31, e32, e33
        surf.DisplacementTriangles[#surf.DisplacementTriangles + 1] = t
    end

    surf.NumDisplacementTriangles = #surf.DisplacementTriangles
end

---Returns the blend factors of a vertex toward $basetexture2, 3, and 4 from 0 to 1.
---WorldVertexTransition has only the first one, the vertex alpha from 0 to 255.
---@param dispVert   ss.Binary.BSP.DISP_VERTS
---@param multiblend ss.Binary.BSP.DISP_MULTIBLEND? Only for Lightmapped_4WayBlend.
---@return number blend2
---@return number blend3
---@return number blend4
local function GetVertexBlends(dispVert, multiblend)
    if not multiblend then
        return math.Clamp(dispVert.alpha / 255, 0, 1), 0, 0
    end

    local m = multiblend.multiblend -- x, y, z, w
    return math.Clamp(m[2], 0, 1), math.Clamp(m[3], 0, 1), math.Clamp(m[4], 0, 1)
end

---Construct a polygon from a raw displacement data
---@param bsp ss.RawBSPResults
---@param rawFace ss.Binary.BSP.FACES
---@param vertices Vector[] The vertices of flat quadrilateral surface that will be modified in this function.
---@param texInfo ss.Binary.BSP.TEXINFO
---@param angle Angle The angle of the face in the world coordinate system. Up() should be the normal.
---@return ss.PrecachedData.Surface
local function BuildFromDisplacement(bsp, rawFace, vertices, texInfo, angle)
    ---@param p Vector
    ---@return Vector
    local function GetBaseTexelUV(p)
        return Vector(
            p:Dot(texInfo.textureVecS) + texInfo.textureOffsetS,
            p:Dot(texInfo.textureVecT) + texInfo.textureOffsetT)
    end

    ---@param c1 Vector
    ---@param c2 Vector
    ---@param c3 Vector
    ---@param c4 Vector
    ---@param u number
    ---@param v number
    ---@return Vector
    local function Bilerp(c1, c2, c3, c4, u, v)
        local left = c1 + (c2 - c1) * v
        local right = c4 + (c3 - c4) * v
        return left + (right - left) * u
    end

    ---@param p1 Vector World position 1
    ---@param p2 Vector World position 2
    ---@param p3 Vector World position 3
    ---@param l1 Vector Lightmap texel position 1
    ---@param l2 Vector Lightmap texel position 2
    ---@param l3 Vector Lightmap texel position 3
    ---@return Vector lightmapVecS
    ---@return Vector lightmapVecT
    local function BuildTriangleLightmapBasis(p1, p2, p3, l1, l2, l3)
        local e1 = p2 - p1
        local e2 = p3 - p1
        local e11 = e1:Dot(e1)
        local e12 = e1:Dot(e2)
        local e22 = e2:Dot(e2)
        local det = e11 * e22 - e12 * e12
        if math.abs(det) <= Util.eps then
            return Vector(), Vector()
        end

        -- dual basis:
        -- dot(e1, dual1) = 1, dot(e2, dual1) = 0
        -- dot(e1, dual2) = 0, dot(e2, dual2) = 1
        local invDet = 1 / det
        local dual1 = (e1 * e22 - e2 * e12) * invDet
        local dual2 = (e2 * e11 - e1 * e12) * invDet
        local du1 = l2.x - l1.x
        local du2 = l3.x - l1.x
        local dv1 = l2.y - l1.y
        local dv2 = l3.y - l1.y
        local lightmapVecS = dual1 * du1 + dual2 * du2
        local lightmapVecT = dual1 * dv1 + dual2 * dv2
        return lightmapVecS, lightmapVecT
    end

    -- Collect displacement info
    local surf            = PrecachedData.Surface.new()
    local rawDispInfo     = bsp.DISPINFO
    local rawDispVerts    = bsp.DISP_VERTS
    local rawMultiBlend   = bsp.DISP_MULTIBLEND
    local multiblendStart = bsp.DispMultiBlendStart[rawFace.dispInfo + 1]
    local lightmapWidth   = rawFace.lightmapTextureSizeInLuxels[1]
    local lightmapHeight  = rawFace.lightmapTextureSizeInLuxels[2]
    local dispInfo        = rawDispInfo[rawFace.dispInfo + 1]
    local power           = 2 ^ dispInfo.power + 1
    do
        -- dispInfo.startPosition isn't always equal to
        -- vertices[1] so find correct one and sort them
        local indices = {} ---@type integer[]
        local mindist, startindex = math.huge, 0
        for i, v in ipairs(vertices) do
            local dist = dispInfo.startPosition:DistToSqr(v)
            if dist < mindist then
                startindex, mindist = i, dist
            end
        end

        for i = 1, 4 do
            indices[i] = (i + startindex - 2) % 4 + 1
        end

        -- Sort them using index table
        vertices[1], vertices[2],
        vertices[3], vertices[4]
            = vertices[indices[1]], vertices[indices[2]],
              vertices[indices[3]], vertices[indices[4]]
    end

    --              u2   ___-->(3)
    --        ____---^^^^       ^
    --      (2)                 |
    --      ^                   |
    --  v1 /                    | v2
    --    /                     |
    --   /          u1          |
    -- (1)---------------------->(4)
    local u1 = vertices[4] - vertices[1]
    local u2 = vertices[3] - vertices[2]
    local v1 = vertices[2] - vertices[1]
    local v2 = vertices[3] - vertices[4]
    local parentNormal = u1:Cross(v1):GetNormalized()
    local subdivisionMatrix = Matrix()
    subdivisionMatrix:SetForward(u1)
    subdivisionMatrix:SetRight(-v1)
    subdivisionMatrix:SetUp(v2)
    subdivisionMatrix:SetTranslation(dispInfo.startPosition)

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

    local aabbMax     = Util.vector_one * -math.huge
    local aabbMin     = Util.vector_one * math.huge
    local deformed    = {} ---@type Vector[]
    local subdivision = {} ---@type Vector[]
    local paintorigin = {} ---@type Vector[]
    local triangles   = {} ---@type integer[] Indices of triangle mesh
    local bumpmapuv   = {} ---@type Vector[]
    local lightmapuv  = {} ---@type Vector[]  Fractional values used in lightmap sampling
    local bumpmapCorners = {
        GetBaseTexelUV(vertices[1]),
        GetBaseTexelUV(vertices[2]),
        GetBaseTexelUV(vertices[3]),
        GetBaseTexelUV(vertices[4]),
    }
    local lightmapCorners = {
        Vector(0.5,                 0.5),
        Vector(0.5,                 0.5 + lightmapHeight),
        Vector(0.5 + lightmapWidth, 0.5 + lightmapHeight),
        Vector(0.5 + lightmapWidth, 0.5),
    }
    for vi = 0, power - 1 do
        for ui = 0, power - 1 do
            local i = ui + vi * power + 1
            local dispVert = rawDispVerts[dispInfo.dispVertStart + i]
            local u = ui / (power - 1)
            local v = vi / (power - 1)
            subdivision[i] = Vector(u, (1 - u) * v, u * v)
            subdivision[i]:Mul(subdivisionMatrix)
            deformed[i] = subdivision[i] + dispVert.vec * dispVert.dist
            bumpmapuv[i] = Bilerp(
                bumpmapCorners[1], bumpmapCorners[2],
                bumpmapCorners[3], bumpmapCorners[4], u, v)
            surf.Blend2[i], surf.Blend3[i], surf.Blend4[i]
                = GetVertexBlends(dispVert, multiblendStart and rawMultiBlend[multiblendStart + i - 1])
            lightmapuv[i] = Bilerp(
                lightmapCorners[1], lightmapCorners[2],
                lightmapCorners[3], lightmapCorners[4], u, v)
            paintorigin[i] = Vector()

            if ui > 0 then
                local previous = deformed[i - 1]
                local distance = deformed[i]:Distance(previous)
                totalLengthU[vi + 1] = (totalLengthU[vi + 1] or 0) + distance
                for j = ui + vi * power, (vi + 1) * power - 1 do
                    lengthIntegratedU[j + 1] = (lengthIntegratedU[j + 1] or 0) + distance
                end
            end

            if vi > 0 then
                local previous = deformed[i - power]
                local distance = deformed[i]:Distance(previous)
                totalLengthV[ui + 1] = (totalLengthV[ui + 1] or 0) + distance
                for j = ui + vi * power, (power - 1) * power + ui, power do
                    lengthIntegratedV[j + 1] = (lengthIntegratedV[j + 1] or 0) + distance
                end
            end

            -- Modifies indices a bit to get two sets of indices of triangles
            local invert = Either(i % 2 == 1, 1, 0)

            -- Generate triangle indices from displacement mesh
            if ui < power - 1 and vi < power - 1 then
                triangles[#triangles + 1] = i + invert + power
                triangles[#triangles + 1] = i + 1
                triangles[#triangles + 1] = i
                triangles[#triangles + 1] = i - invert + 1
                triangles[#triangles + 1] = i + power
                triangles[#triangles + 1] = i + power + 1
            end

            -- Set bounding box
            aabbMax:Set(Util.MaxVector(aabbMax, deformed[i]))
            aabbMin:Set(Util.MinVector(aabbMin, deformed[i]))
        end
    end

    SetAABB(surf, aabbMin, aabbMax)

    local tangents     = {} ---@type Vector[]
    local binormals    = {} ---@type Vector[]
    local normals      = {} ---@type Vector[]
    local normalCounts = {} ---@type integer[]
    local meanLengthU  = (u1:Length() + u2:Length()) * 0.5
    local meanLengthV  = (v1:Length() + v2:Length()) * 0.5
    local maxTotalLengthU = max(unpack(totalLengthU))
    local maxTotalLengthV = max(unpack(totalLengthV))
    local scaleU = maxTotalLengthU / meanLengthU
    local scaleV = maxTotalLengthV / meanLengthV
    local scaleUV = Vector(scaleU, scaleV, scaleV)
    subdivisionMatrix:Scale(scaleUV)
    for i, p in ipairs(paintorigin) do
        local ui = (i - 1) % power
        local vi = floor((i - 1) / power)
        local u = (lengthIntegratedU[i] or 0) / totalLengthU[vi + 1]
        local v = (lengthIntegratedV[i] or 0) / totalLengthV[ui + 1]
        p:SetUnpacked(u, (1 - u) * v, u * v)
        p:Mul(subdivisionMatrix)
        normals[i] = Vector()
        normalCounts[i] = 0
    end

    for i = 1, #triangles, 3 do
        local i1 = triangles[i]
        local i2 = triangles[i + 1]
        local i3 = triangles[i + 2]
        -- All triangles share the engine's winding (BuildTriTLtoBR/BLtoTR in builddisp.cpp),
        -- so this order gives the front side however the surface is folded.
        local triNormal = (deformed[i3] - deformed[i1]):Cross(deformed[i2] - deformed[i1])
        if triNormal:LengthSqr() > Util.eps then
            triNormal:Normalize()
            normals[i1]:Add(triNormal)
            normals[i2]:Add(triNormal)
            normals[i3]:Add(triNormal)
            normalCounts[i1] = normalCounts[i1] + 1
            normalCounts[i2] = normalCounts[i2] + 1
            normalCounts[i3] = normalCounts[i3] + 1
        end

        local s, t = BuildTriangleLightmapBasis(
            deformed[i1], deformed[i2], deformed[i3],
            lightmapuv[i1], lightmapuv[i2], lightmapuv[i3])
        SetTriangle(surf, (i + 2) / 3, i1, i2, i3, s, t)
    end

    local textureVecSLength  = texInfo.textureVecS:Length()
    local textureVecTLength  = texInfo.textureVecT:Length()
    local textureVecS        = texInfo.textureVecS:GetNormalized()
    local textureVecT        = texInfo.textureVecT:GetNormalized()
    local shouldFlipTangentS = parentNormal:Dot(textureVecS:Cross(textureVecT)) > 0
    for i = 1, #deformed do
        if normalCounts[i] > 0 then
            normals[i]:Div(normalCounts[i])
            normals[i]:Normalize()
        else
            normals[i]:Set(parentNormal)
        end

        tangents[i] = normals[i]:Cross(textureVecT)
        if tangents[i]:LengthSqr() <= Util.eps then
            tangents[i] = Vector(textureVecS)
        else
            tangents[i]:Normalize()
        end

        binormals[i] = tangents[i]:Cross(normals[i])
        if binormals[i]:LengthSqr() <= Util.eps then
            binormals[i] = Vector(textureVecT)
        else
            binormals[i]:Normalize()
        end

        if shouldFlipTangentS then tangents[i]:Mul(-1) end
        tangents[i]:Mul(textureVecSLength)
        binormals[i]:Mul(textureVecTLength)
    end

    -- The vertices of the mesh are the grid points.
    for i, p in ipairs(deformed) do
        SetVertex(surf, i, p, normals[i], tangents[i], binormals[i], paintorigin[i])
        surf.BumpmapU[i], surf.BumpmapV[i] = bumpmapuv[i].x, bumpmapuv[i].y
        surf.LightmapU[i], surf.LightmapV[i] = lightmapuv[i].x, lightmapuv[i].y
    end

    SetMeshLengths(surf)

    local mbrMatrix, mbrSize = BoundingBox.FindMBR(VerticesOfTriangles(paintorigin, triangles), angle)
    local mbbMatrix, mbbSize = BoundingBox.FindMinimumOBB(VerticesOfTriangles(deformed, triangles)) -- For the deformed mesh
    local aabbSizeX = surf.AABBMaxX - surf.AABBMinX
    local aabbSizeY = surf.AABBMaxY - surf.AABBMinY
    local aabbSizeZ = surf.AABBMaxZ - surf.AABBMinZ
    if mbbSize.x * mbbSize.y * mbbSize.z < aabbSizeX * aabbSizeY * aabbSizeZ then
        SetMBB(surf, mbbMatrix, mbbSize)
    else -- The AABB is the smaller box.
        surf.MBBPitch,   surf.MBBYaw,     surf.MBBRoll    = 0, 0, 0
        surf.MBBOriginX, surf.MBBOriginY, surf.MBBOriginZ = surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ
        surf.MBBSizeX,   surf.MBBSizeY,   surf.MBBSizeZ   = aabbSizeX, aabbSizeY, aabbSizeZ
    end

    SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
    CalculateTriangleComponents(surf, deformed, paintorigin, triangles)
    return surf
end

-- Construct a polygon from a raw face data
---@param bsp ss.RawBSPResults
---@param rawFace ss.Binary.BSP.FACES
---@return ss.PrecachedData.Surface?, boolean?
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
    local normal    = plane.normal

    -- Collect "raw" vertex list
    local rawVertices = {} ---@type Vector[]
    for i = firstedge, lastedge do
        rawVertices[#rawVertices + 1] = SurfEdgeToVertex(bsp, i)
    end

    -- Filter out colinear vertices and calculate the center
    local filteredVertices = {} ---@type Vector[]
    for i, current in ipairs(rawVertices) do
        local prevIndex = (#rawVertices + i - 2) % #rawVertices + 1
        local nextIndex = i % #rawVertices + 1
        local before = rawVertices[prevIndex]
        local after  = rawVertices[nextIndex]
        local cross  = (before - current):Cross(after - current)
        local colinear = normal:Dot(cross:GetNormalized()) > 0
        if colinear then
            filteredVertices[#filteredVertices + 1] = current
        end
    end

    -- Check if it's valid to add to polygon list
    if #filteredVertices < 3 then return end
    local isDisplacement = rawFace.dispInfo >= 0
    local isWater = bit.band(texInfo.flags, SURF_WARP) ~= 0
        or texMaterial:GetShader() == "Water"
        or surfaceProp == "water"
        or surfaceProp == "slime"
    local angle = normal:Angle()
    angle:RotateAroundAxis(angle:Right(), -90) -- Make sure the up vector is the normal
    assert(normal:GetNormalized():Dot(angle:Up()) > 0.999)

    if isDisplacement then
        return BuildFromDisplacement(bsp, rawFace, filteredVertices, texInfo, angle), tobool(isWater)
    else
        local surf = PrecachedData.Surface.new()
        local mbrMatrix, mbrSize = BoundingBox.FindMBR(filteredVertices, angle)

        -- The vertices of the mesh are those of the polygon.
        local aabbMax = Util.vector_one * -math.huge
        local aabbMin = Util.vector_one * math.huge
        for i, v in ipairs(filteredVertices) do
            aabbMax:Set(Util.MaxVector(aabbMax, v))
            aabbMin:Set(Util.MinVector(aabbMin, v))
            SetVertex(surf, i, v, normal, texInfo.textureVecS, texInfo.textureVecT, v)
            surf.BumpmapU[i] = v:Dot(texInfo.textureVecS) + texInfo.textureOffsetS
            surf.BumpmapV[i] = v:Dot(texInfo.textureVecT) + texInfo.textureOffsetT
            surf.Blend2[i], surf.Blend3[i], surf.Blend4[i] = 0, 0, 0
            surf.LightmapU[i] = v:Dot(texInfo.lightmapVecS)
                + texInfo.lightmapOffsetS
                - rawFace.lightmapTextureMinsInLuxels[1]
                + 0.5
            surf.LightmapV[i] = v:Dot(texInfo.lightmapVecT)
                + texInfo.lightmapOffsetT
                - rawFace.lightmapTextureMinsInLuxels[2]
                + 0.5
        end

        SetAABB(surf, aabbMin, aabbMax)

        -- The triangles are a fan of the vertices.
        for i = 2, #filteredVertices - 1 do
            SetTriangle(surf, i - 1, 1, i, i + 1, texInfo.lightmapVecS, texInfo.lightmapVecT)
        end

        SetMeshLengths(surf)

        if not isWater then
            SetMBB(surf, mbrMatrix, mbrSize)
            SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
        end

        return surf, tobool(isWater)
    end
end

---Extract surfaces from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@param ishdr boolean
---@return ss.PrecachedData.SurfaceInfo surf
---@return ss.PrecachedData.Surface[] water
function SurfaceBuilder.BuildSurfaceCache(bsp, ishdr)
    local t0 = SysTime()
    local surfInfo = PrecachedData.SurfaceInfo.new()
    local surf = surfInfo.Surfaces
    local water = {} ---@type ss.PrecachedData.Surface[]
    local lump = ishdr and bsp.FACES_HDR or bsp.FACES or {}
    local cubemaps, cubemapsByOrigin = BuildCubemapEntries(bsp)
    local faceIndexToModelIndex = {} ---@type integer[]
    for i, mdl in ipairs(bsp.MODELS) do
        for j = mdl.firstFace + 1, mdl.firstFace + mdl.numFaces do
            faceIndexToModelIndex[j] = i
        end
    end
    surfInfo.Cubemaps = cubemaps

    print("Generating inkable surfaces for " .. (ishdr and "HDR" or "LDR") .. "...")
    local validFaces  = {} ---@type boolean[] face index --> is paintable
    local faceCubemaps = {} ---@type table<integer, ss.PrecachedData.CubemapInfo>
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
                local envmap = texMaterial:GetString "$envmap"
                local cubemapKey = ParseCubemapOriginKey(envmap) or ParseCubemapOriginKey(texName)
                faceCubemaps[i] = cubemapKey and cubemapsByOrigin[cubemapKey] or nil
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
                    AccumulateCubemapBox(faceCubemaps[i], s)
                    surf[#surf + 1] = s
                end
            end
        end
    end
    FinalizeCubemapEntries(cubemaps)
    surfInfo.NumSurfaces = #surf
    surfInfo.NumCubemaps = #cubemaps
    print("    Generated " .. #lump .. " surfaces for " .. (ishdr and "HDR" or "LDR"))

    local elapsed = round((SysTime() - t0) * 1000, 2)
    print("Elapsed time: " .. elapsed .. " ms.")

    return surfInfo, water
end

---studiohdr_t::illumposition follows id, version, checksum, name[64], length, and eyeposition.
local STUDIOHDR_ILLUMPOSITION_OFFSET = 92

---Corresponds to STATIC_PROP_USE_LIGHTING_ORIGIN in gamebspfile.h.
local STATIC_PROP_USE_LIGHTING_ORIGIN = 0x2

---Reads studiohdr_t::illumposition of the model.
---@param name string Path to the model.
---@return Vector # The model origin if the model cannot be opened.
local function ReadIlluminationPosition(name)
    local f = file.Open(name, "rb", "GAME")
    if not f then return Vector() end
    f:Seek(STUDIOHDR_ILLUMPOSITION_OFFSET)
    local illumposition = Vector(f:ReadFloat(), f:ReadFloat(), f:ReadFloat())
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
---@param bsp           ss.RawBSPResults
---@param prop          ss.Binary.BSP.StaticProp
---@param illumposition Vector illumposition of the model.
---@return integer # Index to the cubemap samples in the lump, or 0 if the map has no cubemaps.
local function FindStaticPropCubemap(bsp, prop, illumposition)
    local lightingOrigin = prop.lightingOrigin
    if bit.band(prop.flags, STATIC_PROP_USE_LIGHTING_ORIGIN) == 0 then
        lightingOrigin = LocalToWorld(illumposition, angle_zero, prop.origin, prop.angle)
    end

    local nearestIndex = 0
    local nearestDistanceSqr = math.huge
    for i, sample in ipairs(bsp.CUBEMAPS or {}) do
        local distanceSqr = lightingOrigin:DistToSqr(sample.origin)
        if distanceSqr < nearestDistanceSqr then
            nearestIndex = i
            nearestDistanceSqr = distanceSqr
        end
    end

    return nearestIndex
end

---Extracts surfaces from static props.
---@param bsp ss.RawBSPResults
---@param cache ss.PrecachedData
function SurfaceBuilder.BuildStaticPropCache(bsp, cache)
    print "Generating static prop surfaces..."
    local results = {} ---@type ss.PrecachedData.StaticProp[]
    local uvinfo = {} ---@type ss.PrecachedData.StaticProp.UVInfo[]
    local illumpositions = {} ---@type table<string, Vector>
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
                local result = PrecachedData.StaticProp.new()
                result.Pitch, result.Yaw, result.Roll = prop.angle:Unpack()
                result.BoundsMaxX, result.BoundsMaxY, result.BoundsMaxZ = (info.HullMax * scale):Unpack()
                result.BoundsMinX, result.BoundsMinY, result.BoundsMinZ = (info.HullMin * scale):Unpack()
                result.FadeMax = prop.fadeMaxDist
                result.FadeMin = prop.fadeMinDist
                result.ModelIndex = modelIndex
                result.PositionX, result.PositionY, result.PositionZ = prop.origin:Unpack()
                result.Scale = scale
                result.Skin = prop.skin
                result.UnwrapIndex = 1
                result.CubemapIndex = FindStaticPropCubemap(bsp, prop, illumpositions[name])
                results[#results + 1] = result
                for _ = 1, #PrecachedData.InkMapResolutions do
                    uvinfo[#uvinfo + 1] = PrecachedData.StaticPropUVInfo.new()
                end
            end
        end
    end

    cache.StaticProps = results
    cache.NumStaticProps = #results
    cache.StaticPropHDR = uvinfo
    cache.NumStaticPropHDR = #uvinfo
    cache.StaticPropLDR = Util.deepcopy(uvinfo) or {}
    cache.NumStaticPropLDR = #cache.StaticPropLDR
    cache.StaticPropMDL = bsp.sprp.name or {}
    cache.NumStaticPropMDL = #cache.StaticPropMDL
    print("    Collected info for " .. #results .. " static props.")
end

return SurfaceBuilder
