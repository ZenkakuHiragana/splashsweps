
---@class ss
local ss = SplashSWEPs
if not ss then return end

local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local round = math.Round
local sqrt = math.sqrt
local sort = table.sort
local tableCopy = table.Copy
local Vector = Vector
local Matrix = Matrix
local MaterialCache = {} ---@type table<string, IMaterial>
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
        local cubemap = ss.new "PrecachedData.CubemapInfo"
        cubemap.Envmap = string.format("maps/%s/c%d_%d_%d", mapName, origin.x, origin.y, origin.z)
        cubemap.Origin:Set(origin)
        cubemap.BoxMin:Set(ss.vector_one * math.huge)
        cubemap.BoxMax:Set(ss.vector_one * -math.huge)
        cubemaps[#cubemaps + 1] = cubemap
        cubemapsByOrigin[CubemapOriginKey(origin)] = cubemap
    end

    return cubemaps, cubemapsByOrigin
end

---@param cubemap ss.PrecachedData.CubemapInfo?
---@param surf ss.PrecachedData.Surface
local function AccumulateCubemapBox(cubemap, surf)
    if not cubemap then return end
    cubemap.BoxMin:Set(ss.MinVector(cubemap.BoxMin, surf.AABBMin))
    cubemap.BoxMax:Set(ss.MaxVector(cubemap.BoxMax, surf.AABBMax))
    cubemap.FaceCount = cubemap.FaceCount + 1
    cubemap.Blend = 1
end

---@param cubemaps ss.PrecachedData.CubemapInfo[]
local function FinalizeCubemapEntries(cubemaps)
    for _, cubemap in ipairs(cubemaps) do
        if cubemap.FaceCount == 0 then
            cubemap.BoxMin:Set(cubemap.Origin)
            cubemap.BoxMax:Set(cubemap.Origin)
            cubemap.Blend = 0
        end
    end
end

---Compares two vertices used by table.sort
---@param a Vector
---@param b Vector
---@return boolean
local function VerticesComparer(a, b)
    return Either(a.x == b.x, a.y < b.y, a.x < b.x)
end

-- Generates a convex hull by monotone chain method
---@param source Vector[]
---@return Vector[]
local function GetConvex(source)
    local convex = {} ---@type Vector[]
    local vertices2D = tableCopy(source)
    sort(vertices2D, VerticesComparer)
    for i = 1, #vertices2D do
        if i > 2 then
            local p = convex[#convex]
            local q = convex[#convex - 1]
            local pq = q - p
            local pr = vertices2D[i] - p
            local cross = pq:Cross(pr)
            if cross.z > 0 or pq:LengthSqr() < ss.eps or pr:LengthSqr() < ss.eps then
                convex[#convex] = nil
            end
        end

        if i ~= #vertices2D then
            convex[#convex + 1] = vertices2D[i]
        end
    end

    for i = #vertices2D, 1, -1 do
        if i < #vertices2D - 1 then
            local p = convex[#convex]
            local q = convex[#convex - 1]
            local pq = q - p
            local pr = vertices2D[i] - p
            local cross = pq:Cross(pr)
            if cross.z > 0 or pq:LengthSqr() < ss.eps or pr:LengthSqr() < ss.eps then
                convex[#convex] = nil
            end
        end

        if i ~= 1 then
            convex[#convex + 1] = vertices2D[i]
        end
    end

    return convex
end

---Calculates minimum bounding rectangle (MBR) of given vertices.
---@param vertices Vector[] Vertices respresenting the face in the world coordinate system.
---@param angle    Angle    The angle of the face in the world coordinate system. Up() should be the normal.
---@return VMatrix origin Represents the origin and angle of the MBR in the world coordinate system.
---@return Vector  size   The size of the MBR in Hammer units.
local function FindMBR(vertices, angle)
    local center = Vector()
    for _, v in ipairs(vertices) do center:Add(v) end
    center:Div(#vertices)

    -- Transforms vertices in the world to 2D space.
    -- ```
    --   ________
    --  /        \
    -- |   +--> x |
    -- |   v      |
    -- |   y      |
    -- +----------+
    -- ```
    local vertices2D = {} ---@type Vector[]
    for i, v in ipairs(vertices) do
        vertices2D[i] = WorldToLocal(v, angle_zero, center, angle)
    end

    local mbrMins = ss.vector_one * math.huge
    local minArea = math.huge
    local mbrSize = Vector()
    local mbrRotation = Matrix()
    local convex = GetConvex(vertices2D)
    for i = 1, #convex do
        local p0, p1 = convex[i], convex[i % #convex + 1]
        local dp = p1 - p0
        if dp:LengthSqr() > 0 then
            local dir = dp:GetNormalized()
            local rotation = Matrix() -- to represent the angle of the MBR
            rotation:SetForward(dir)
            rotation:SetRight(Vector(dir.y, -dir.x))
            rotation:SetUp(vector_up)

            local maxs = ss.vector_one * -math.huge
            local mins = ss.vector_one * math.huge
            local rotationInv = rotation:GetInverseTR()
            for _, v in ipairs(convex) do
                maxs:Set(ss.MaxVector(maxs, rotationInv * v))
                mins:Set(ss.MinVector(mins, rotationInv * v))
            end

            local size = maxs - mins
            if minArea > size.x * size.y then
                minArea = size.x * size.y
                mbrMins = mins
                mbrSize = size
                mbrRotation = rotation
            end
        end
    end

    mbrRotation:SetTranslation(mbrRotation * mbrMins)

    local localToWorld = Matrix()
    localToWorld:SetAngles(angle)
    localToWorld:SetTranslation(center)
    localToWorld:Mul(mbrRotation)
    return localToWorld, mbrSize
end

---Finds the oriented minimum boundibg box from displacement positions.
---@param vertices ss.PrecachedData.Vertex[]
---@return VMatrix origin Represents the origin and angle of the minimum OBB in the world coordinate system.
---@return Vector  size   The size of the MBR in Hammer units.
local function FindMinimumOBB(vertices)
    local mean = Vector()
    for _, v in ipairs(vertices) do mean:Add(v.Translation) end
    mean:Div(#vertices)

    -- Calculates a variance-covariance matrix
    --     [ sxx sxy szx ]
    -- S = [ sxy syy syz ]
    --     [ szx syz szz ]
    local variance   = Vector() -- = ( sxx syy szz )
    local covariance = Vector() -- = ( sxy syz szx )
    for _, v in ipairs(vertices) do
        local diff = v.Translation - mean
        variance:Add(diff * diff)
        covariance:Add(Vector(
            diff.x * diff.y,
            diff.y * diff.z,
            diff.z * diff.x))
    end

    -- Here I don't divide variance by #vertices as I just need eigenvectors.

    -- The angle components will be eigenvectors by Jacobi's algorithm.
    local rotation = Matrix()
    local localToWorld = Matrix()
    for _ = 1, 20 do
        local covarianceSqr = covariance * covariance
        local maxCovarianceSqr = max(covarianceSqr:Unpack())
        if maxCovarianceSqr < ss.eps then break end
        if maxCovarianceSqr == covarianceSqr.x then
            --             [ c  -s  0 ][ xx xy xz ][  c  s  0 ]
            -- S' = RᵀSR = [ s   c  0 ][ xy yy yz ][ -s  c  0 ]
            --             [ 0   0  1 ][ xz yz zz ][  0  0  1 ]
            --             [ cxx - sxy   cxy - syy   cxz - syz ][ c -s  0 ]
            --           = [ sxx + cxy   sxy + cyy   sxz + cyz ][ s  c  0 ]
            --             [        xz          yz          zz ][ 0  0  1 ]
            --             [ ccxx - 2csxy + ssyy                     0   cxz - syz ]
            --           = [                   0   ssxx + 2csxy + ccyy   sxz + cyz ]
            --             [          cxz -  syz            sxz +  cyz          zz ]
            local tau = (variance.y - variance.x) / (2 * covariance.x)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.x
            variance:SetUnpacked(
                cos2 * variance.x + sin2 * variance.y - sincos2,
                sin2 * variance.x + cos2 * variance.y + sincos2,
                variance.z)
            covariance:SetUnpacked(
                0,
                cos * covariance.y + sin * covariance.z,
                cos * covariance.z - sin * covariance.y)
            rotation:SetUnpacked(
                cos, sin, 0, 0,
               -sin, cos, 0, 0,
                0,     0, 1, 0,
                0,     0, 0, 1)
        elseif maxCovarianceSqr == covarianceSqr.y then
            --             [ 1  0  0 ][ xx xy xz ][ 1  0  0 ]
            -- S' = RᵀSR = [ 0  c -s ][ xy yy yz ][ 0  c  s ]
            --             [ 0  s  c ][ xz yz zz ][ 0 -s  c ]
            --             [        xx          xy          xz ][ 1  0  0 ]
            --           = [ cxy - sxz   cyy - syz   cyz - szz ][ 0  c  s ]
            --             [ sxy + cxz   syy + cyz   syz + czz ][ 0 -s  c ]
            --             [        xx            cxy -  sxz            szy +  cxz ]
            --           = [ cxy - sxz   ccyy - 2csyz + sszz                     0 ]
            --             [ sxy + cxz                     0   ssyy + 2csyz + cczz ]
            local tau = (variance.z - variance.y) / (2 * covariance.y)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.y
            variance:SetUnpacked(
                variance.x,
                cos2 * variance.y + sin2 * variance.z - sincos2,
                sin2 * variance.y + cos2 * variance.z + sincos2)
            covariance:SetUnpacked(
                cos * covariance.x - sin * covariance.z,
                0,
                cos * covariance.z + sin * covariance.x)
            rotation:SetUnpacked(
                1,    0,   0, 0,
                0,  cos, sin, 0,
                0, -sin, cos, 0,
                0,    0,   0, 1)
        else
            --             [ c  0 -s ][ xx xy xz ][  c  0  s ]
            -- S' = RᵀSR = [ 0  1  0 ][ xy yy yz ][  0  1  0 ]
            --             [ s  0  c ][ xz yz zz ][ -s  0  c ]
            --             [ cxx - sxz   cxy - syz   cxz - szz ][ c  0 -s ]
            --           = [        xy          yy          yz ][ 0  1  0 ]
            --             [ sxx + cxz   sxy + cyz   sxz + czz ][ s  0  c ]
            --             [ ccxx - 2csxz + sszz   cxy - syz                     0 ]
            --           = [          cxy -  syz          yy            sxy +  cyz ]
            --             [                   0   sxy + cyz   ssxx + 2csxz + cczz ]
            local tau = (variance.z - variance.x) / (2 * covariance.z)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.z
            variance:SetUnpacked(
                cos2 * variance.x + sin2 * variance.z - sincos2,
                variance.y,
                sin2 * variance.x + cos2 * variance.z + sincos2)
            covariance:SetUnpacked(
                cos * covariance.x - sin * covariance.y,
                cos * covariance.y + sin * covariance.x,
                0)
            rotation:SetUnpacked(
                cos, 0, sin, 0,
                0,   1,   0, 0,
               -sin, 0, cos, 0,
                0,   0,   0, 1)
        end

        localToWorld:Mul(rotation)
    end

    -- ---Compares two vectors used by table.sort
    -- ---@param a Vector
    -- ---@param b Vector
    -- ---@return boolean
    -- local function LengthDescending(a, b)
    --     return a:LengthSqr() > b:LengthSqr()
    -- end
    --
    -- Sorting axes (seems broken)
    -- local axes = {
    --     localToWorld:GetForward() * variance.x,
    --     localToWorld:GetRight() * variance.y,
    --     localToWorld:GetUp() * variance.z,
    -- }
    -- sort(axes, LengthDescending)
    -- localToWorld:SetForward(axes[1]:GetNormalized())
    -- localToWorld:SetRight(axes[2]:GetNormalized())
    -- localToWorld:SetUp(axes[3]:GetNormalized())
    localToWorld:SetTranslation(mean)

    local worldToLocal = localToWorld:GetInverseTR()
    local mins = ss.vector_one * math.huge
    local maxs = ss.vector_one * -math.huge
    for _, v in ipairs(vertices) do
        local pos = worldToLocal * v.Translation
        mins:Set(ss.MinVector(mins, pos))
        maxs:Set(ss.MaxVector(maxs, pos))
    end

    localToWorld:Translate(mins)
    return localToWorld, maxs - mins
end

---Set placeholder values to VMatrix transform and 2D size fields.
---@param surf ss.PrecachedData.Surface
---@param mbrMatrix VMatrix
---@param mbrSize Vector
local function SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
    local paintGridMatrix = mbrMatrix:GetInverseTR()
    surf.TransformPaintGrid.Translation:Set(paintGridMatrix:GetTranslation())
    surf.TransformPaintGrid.Angle:Set(paintGridMatrix:GetAngles())
    surf.PaintGridWidth  = ceil(mbrSize.x / ss.InkGridCellSize)
    surf.PaintGridHeight = ceil(mbrSize.y / ss.InkGridCellSize)
    for i = 1, #ss.RenderTarget.Resolutions do
        surf.UVInfo[i] = ss.new "PrecachedData.UVInfo"
        surf.UVInfo[i].Angle:Set(mbrMatrix:GetAngles())
        surf.UVInfo[i].Translation:Set(mbrMatrix:GetTranslation())
        surf.UVInfo[i].Width  = mbrSize.x
        surf.UVInfo[i].Height = mbrSize.y
    end
end

---Collects the flattened paint-grid vertices used by a displacement surface.
---@param surf ss.PrecachedData.Surface
---@return Vector[] vertices
local function CollectDisplacementPaintOrigins(surf)
    local vertices = {} ---@type Vector[]
    for i, v in ipairs(surf.Vertices) do
        vertices[i] = v.DispPaintOrigin or v.Translation
    end

    return vertices
end

---@param surf ss.PrecachedData.Surface
local function CalculateTriangleComponents(surf)
    local WorldToLocalRotation = Matrix()
    local DispPaintOriginRotation = Matrix()
    surf.Triangles = {}
    for i = 1, #surf.Vertices, 3 do
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
        local v1 = surf.Vertices[i]
        local v2 = surf.Vertices[i + 1]
        local v3 = surf.Vertices[i + 2]
        local t1 = v1.Translation
        local t2 = v2.Translation
        local t3 = v3.Translation
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
        local t = ss.new "PrecachedData.DisplacementTriangle"
        t.Index = i
        t.BarycentricDot1 = barycentricDot1
        t.BarycentricDot2 = barycentricDot2
        t.MBBAngles = angle
        t.MBBOrigin:Set(t3 + e1 * minX)
        t.MBBSize:SetUnpacked(maxX - minX, e2:Dot(another), 0)

        local org1 = surf.Vertices[i].DispPaintOrigin
        local org2 = surf.Vertices[i + 1].DispPaintOrigin
        local org3 = surf.Vertices[i + 2].DispPaintOrigin
        local orgForward = org2 - org3
        local orgAnother = org1 - org3
        local orgAngle = orgForward:AngleEx(orgForward:Cross(orgAnother))
        DispPaintOriginRotation:SetAngles(orgAngle)
        WorldToLocalRotation:SetAngles(angle)
        WorldToLocalRotation:InvertTR()
        WorldToLocalRotation:Set(DispPaintOriginRotation * WorldToLocalRotation)
        t.WorldToLocalGridRotation:Set(WorldToLocalRotation:GetAngles())
        surf.Triangles[#surf.Triangles + 1] = t
    end
end

---Construct a polygon from a raw displacement data
---@param bsp ss.RawBSPResults
---@param rawFace ss.Binary.BSP.FACES
---@param vertices Vector[] The vertices of flat quadrilateral surface that will be modified in this function.
---@param texInfo ss.Binary.BSP.TEXINFO
---@return ss.PrecachedData.Surface
local function BuildFromDisplacement(bsp, rawFace, vertices, texInfo)
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
        if math.abs(det) <= ss.eps then
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
    local surf            = ss.new "PrecachedData.Surface"
    local rawDispInfo     = bsp.DISPINFO
    local rawDispVerts    = bsp.DISP_VERTS
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

    local deformed    = {} ---@type Vector[]
    local subdivision = {} ---@type Vector[]
    local paintorigin = {} ---@type Vector[]
    local triangles   = {} ---@type integer[] Indices of triangle mesh
    local bumpmapuv   = {} ---@type Vector[]
    local lightmapuv  = {} ---@type Vector[]  Fractional values used in lightmap sampling
    local lightmapS   = {} ---@type Vector[]
    local lightmapT   = {} ---@type Vector[]
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
            bumpmapuv[i].z = dispVert.alpha
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
            surf.AABBMax:Set(ss.MaxVector(surf.AABBMax, deformed[i]))
            surf.AABBMin:Set(ss.MinVector(surf.AABBMin, deformed[i]))
        end
    end

    -- Add margin to construct overlapped hash table entries
    surf.AABBMax:Add(ss.vector_one * ss.MARGIN_HAMMER_UNITS)
    surf.AABBMin:Sub(ss.vector_one * ss.MARGIN_HAMMER_UNITS)

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
        local triNormal = (deformed[i2] - deformed[i1]):Cross(deformed[i3] - deformed[i1])
        if triNormal:LengthSqr() > ss.eps then
            triNormal:Normalize()
            if triNormal:Dot(parentNormal) < 0 then triNormal:Mul(-1) end
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
        lightmapS[i],     lightmapT[i]     = s, t
        lightmapS[i + 1], lightmapT[i + 1] = s, t
        lightmapS[i + 2], lightmapT[i + 2] = s, t
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
        if tangents[i]:LengthSqr() <= ss.eps then
            tangents[i] = Vector(textureVecS)
        else
            tangents[i]:Normalize()
        end

        binormals[i] = tangents[i]:Cross(normals[i])
        if binormals[i]:LengthSqr() <= ss.eps then
            binormals[i] = Vector(textureVecT)
        else
            binormals[i]:Normalize()
        end

        if shouldFlipTangentS then tangents[i]:Mul(-1) end
        tangents[i]:Mul(textureVecSLength)
        binormals[i]:Mul(textureVecTLength)
    end

    for i, t in ipairs(triangles) do
        surf.Vertices[i] = ss.new "PrecachedData.Vertex"
        surf.Vertices[i].Translation:Set(deformed[t])
        surf.Vertices[i].Normal:Set(normals[t])
        surf.Vertices[i].Tangent:Set(tangents[t])
        surf.Vertices[i].Binormal:Set(binormals[t])
        surf.Vertices[i].LightmapTangent:Set(lightmapS[i])
        surf.Vertices[i].LightmapBinormal:Set(lightmapT[i])
        surf.Vertices[i].BumpmapUV:Set(bumpmapuv[t])
        surf.Vertices[i].LightmapUV:Set(lightmapuv[t])
        surf.Vertices[i].DispPaintOrigin = paintorigin[t]
    end

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
        local surf = BuildFromDisplacement(bsp, rawFace, filteredVertices, texInfo)
        local mbrMatrix, mbrSize = FindMBR(CollectDisplacementPaintOrigins(surf), angle)
        local mbbMatrix, mbbSize = FindMinimumOBB(surf.Vertices) -- For the deformed mesh
        local aabbSize = surf.AABBMax - surf.AABBMin
        if mbbSize.x * mbbSize.y * mbbSize.z < aabbSize.x * aabbSize.y * aabbSize.z then
            surf.MBBAngles:Set(mbbMatrix:GetAngles())
            surf.MBBOrigin:Set(mbbMatrix:GetTranslation())
            surf.MBBSize:Set(mbbSize)
        else
            surf.MBBAngles:Zero()
            surf.MBBOrigin:Set(surf.AABBMin)
            surf.MBBSize:Set(aabbSize)
        end

        SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
        CalculateTriangleComponents(surf)
        return surf, tobool(isWater)
    else
        local surf = ss.new "PrecachedData.Surface"
        local mbrMatrix, mbrSize = FindMBR(filteredVertices, angle)
        local bumpmapU = {} ---@type number[]
        local bumpmapV = {} ---@type number[]
        local lightmapU = {} ---@type number[]
        local lightmapV = {} ---@type number[]
        local triangles = {} ---@type integer[]
        for i, v in ipairs(filteredVertices) do
            surf.AABBMax:Set(ss.MaxVector(surf.AABBMax, v))
            surf.AABBMin:Set(ss.MinVector(surf.AABBMin, v))
            bumpmapU[i] = v:Dot(texInfo.textureVecS) + texInfo.textureOffsetS
            bumpmapV[i] = v:Dot(texInfo.textureVecT) + texInfo.textureOffsetT
            lightmapU[i] = v:Dot(texInfo.lightmapVecS)
                + texInfo.lightmapOffsetS
                - rawFace.lightmapTextureMinsInLuxels[1]
                + 0.5
            lightmapV[i] = v:Dot(texInfo.lightmapVecT)
                + texInfo.lightmapOffsetT
                - rawFace.lightmapTextureMinsInLuxels[2]
                + 0.5
        end

        -- Add margin to construct overlapped hash table entries
        surf.AABBMax:Add(ss.vector_one * ss.MARGIN_HAMMER_UNITS)
        surf.AABBMin:Sub(ss.vector_one * ss.MARGIN_HAMMER_UNITS)

        -- Construct triangles
        for i = 2, #filteredVertices - 1 do
            triangles[#triangles + 1] = 1
            triangles[#triangles + 1] = i
            triangles[#triangles + 1] = i + 1
        end

        for i, t in ipairs(triangles) do
            surf.Vertices[i] = ss.new "PrecachedData.Vertex"
            surf.Vertices[i].Translation:Set(filteredVertices[t])
            surf.Vertices[i].Normal:Set(normal)
            surf.Vertices[i].Tangent:Set(texInfo.textureVecS)
            surf.Vertices[i].Binormal:Set(texInfo.textureVecT)
            surf.Vertices[i].LightmapTangent:Set(texInfo.lightmapVecS)
            surf.Vertices[i].LightmapBinormal:Set(texInfo.lightmapVecT)
            surf.Vertices[i].BumpmapUV.x = bumpmapU[t]
            surf.Vertices[i].BumpmapUV.y = bumpmapV[t]
            surf.Vertices[i].LightmapUV.x = lightmapU[t]
            surf.Vertices[i].LightmapUV.y = lightmapV[t]
        end

        if not isWater then
            surf.MBBAngles:Set(mbrMatrix:GetAngles())
            surf.MBBOrigin:Set(mbrMatrix:GetTranslation())
            surf.MBBSize:Set(mbrSize)
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
function ss.BuildSurfaceCache(bsp, ishdr)
    local t0 = SysTime()
    local surfInfo = ss.new "PrecachedData.SurfaceInfo"
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
    print("    Generated " .. #lump .. " surfaces for " .. (ishdr and "HDR" or "LDR"))

    local elapsed = round((SysTime() - t0) * 1000, 2)
    print("Elapsed time: " .. elapsed .. " ms.")

    return surfInfo, water
end

---Extracts surfaces from static props.
---@param bsp ss.RawBSPResults
---@param cache ss.PrecachedData
function ss.BuildStaticPropCache(bsp, cache)
    print "Generating static prop surfaces..."
    local results = {} ---@type ss.PrecachedData.StaticProp[]
    local uvinfo = {} ---@type ss.PrecachedData.StaticProp.UVInfo[][]
    for _, prop in ipairs(bsp.sprp.prop or {}) do
        if prop.solid > 0 then
            local modelIndex = prop.propType + 1
            local name = bsp.sprp.name[prop.propType + 1] or ""
            local info = util.GetModelInfo(name)
            local index = util.GetSurfaceIndex(info and info.SurfacePropName or "")
            local surf = util.GetSurfaceData(index)
            if info and surf and surf.material ~= MAT_GRATE then
                local scale = prop.uniformScale or 1
                results[#results + 1] = {
                    Angles = prop.angle,
                    BoundsMax = info.HullMax * scale,
                    BoundsMin = info.HullMin * scale,
                    FadeMax = prop.fadeMaxDist,
                    FadeMin = prop.fadeMinDist,
                    ModelIndex = modelIndex,
                    Position = prop.origin,
                    Scale = scale,
                    UnwrapIndex = 1,
                }
                uvinfo[#uvinfo + 1] = {}
                for i = 1, #ss.RenderTarget.Resolutions do
                    uvinfo[#uvinfo][i] = ss.new "PrecachedData.StaticProp.UVInfo"
                end
            end
        end
    end

    cache.StaticProps = results
    cache.StaticPropHDR = uvinfo
    cache.StaticPropLDR = ss.deepcopy(uvinfo) or {}
    cache.StaticPropMDL = bsp.sprp.name or {}
    print("    Collected info for " .. #results .. " static props.")
end
