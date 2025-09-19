
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

---Index to SURFEDGES array -> actual vertex
---@param bsp ss.RawBSPResults
---@param index integer
---@return Vector
local function SurfEdgeToVertex(bsp, index)
    local surfedge  = bsp.SURFEDGES[index]
    local edge      = bsp.EDGES[abs(surfedge) + 1]
    local vertindex = edge[surfedge < 0 and 2 or 1]
    return bsp.VERTEXES[vertindex + 1]
end

---@param name string
---@return IMaterial
local function GetMaterial(name)
    if not MaterialCache[name] then
        MaterialCache[name] = Material(name)
    end
    return MaterialCache[name]
end

---Compares two vertices used by table.sort
---@param a Vector
---@param b Vector
---@return boolean
local function VerticesComparer(a, b)
    return Either(a.x == b.x, a.y < b.y, a.x < b.x)
end

---Compares two vectors used by table.sort
---@param a Vector
---@param b Vector
---@return boolean
local function LengthDescending(a, b)
    return a:LengthSqr() > b:LengthSqr()
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
---@param center   Vector   The center of vertices = 1/N ∑ vi
---@return VMatrix origin Represents the origin and angle of the MBR in the world coordinate system.
---@return Vector  size   The size of the MBR in Hammer units.
local function FindMBR(vertices, angle, center)
    -- Convert each vertex to 2D coordinate system.
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
            local dir  = dp:GetNormalized()
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

---Set placeholder values to VMatrix transform and 2D size fields
---@param surf ss.PrecachedData.Surface
---@param mbrLocalToWorld VMatrix
---@param mbrSize Vector
local function SetTransformRelatedValues(surf, mbrLocalToWorld, mbrSize)
    local paintGridMatrix = mbrLocalToWorld:GetInverseTR()
    surf.TransformPaintGrid.Translation:Set(paintGridMatrix:GetTranslation())
    surf.TransformPaintGrid.Angle:Set(paintGridMatrix:GetAngles())
    surf.PaintGridWidth  = ceil(mbrSize.x / ss.InkGridCellSize)
    surf.PaintGridHeight = ceil(mbrSize.y / ss.InkGridCellSize)
    for i = 1, #ss.RenderTarget.Resolutions do
        surf.UVInfo[i] = ss.new "PrecachedData.UVInfo"
        surf.UVInfo[i].Angle:Set(mbrLocalToWorld:GetAngles())
        surf.UVInfo[i].Translation:Set(mbrLocalToWorld:GetTranslation())
        surf.UVInfo[i].Width  = mbrSize.x
        surf.UVInfo[i].Height = mbrSize.y
    end
end

---Construct a polygon from a raw displacement data
---@param bsp ss.RawBSPResults
---@param rawFace ss.Binary.BSP.FACES
---@param vertices Vector[]
---@return ss.PrecachedData.Surface
local function BuildFromDisplacement(bsp, rawFace, vertices)
    -- Collect displacement info
    local surf            = ss.new "PrecachedData.Surface"
    local rawDispInfo     = bsp.DISPINFO
    local rawDispVerts    = bsp.DISP_VERTS
    local dispInfo        = rawDispInfo[rawFace.dispInfo + 1]
    local power           = 2 ^ dispInfo.power + 1
    local numMeshVertices = power ^ 2
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

    --  ^ y
    --  |
    -- (4) -------- (3)
    --  |            |
    --  ^            ^
    -- v1           v2
    --  |            |
    -- (1) -u1->--- (2) --> x
    local u1 = vertices[4] - vertices[1]
    local v1 = vertices[2] - vertices[1]
    local v2 = vertices[3] - vertices[4]
    local triangles    = {} ---@type integer[] Indices of triangle mesh
    local dispVertices = {} ---@type { pos: Vector, ang: Angle, org: Vector, lightmapSamplePoint: Vector }[]  List of vertices
    for i = 1, numMeshVertices do
        -- Calculate x-y offset
        local dispVert = rawDispVerts[dispInfo.dispVertStart + i]
        local xi, yi = (i - 1) % power, floor((i - 1) / power)
        local x,  y  = xi / (power - 1), yi / (power - 1)
        local origin = u1 * x + LerpVector(x, v1, v2) * y

        -- Calculate mesh vertex position
        local displacement = dispVert.vec * dispVert.dist
        local localPos = origin + displacement
        local worldPos = dispInfo.startPosition + localPos
        dispVertices[#dispVertices + 1] = {
            pos = worldPos,
            ang = dispVert.vec:Angle(),
            org = dispInfo.startPosition + origin,
            lightmapSamplePoint = Vector(x, y),
        }

        -- Modifies indices a bit to invert triangle orientation
        local invert = Either(i % 2 == 1, 1, 0)

        -- Generate triangle indices from displacement mesh
        if xi < power - 1 and yi < power - 1 then
            triangles[#triangles + 1] = i + invert + power
            triangles[#triangles + 1] = i + 1
            triangles[#triangles + 1] = i
            triangles[#triangles + 1] = i - invert + 1
            triangles[#triangles + 1] = i + power
            triangles[#triangles + 1] = i + power + 1
        end

        -- Set bounding box
        surf.AABBMax:Set(ss.MaxVector(surf.AABBMax, worldPos))
        surf.AABBMin:Set(ss.MinVector(surf.AABBMin, worldPos))
    end

    for i, t in ipairs(triangles) do
        surf.Vertices[i] = ss.new "PrecachedData.Vertex"
        surf.Vertices[i].Angle = dispVertices[t].ang
        surf.Vertices[i].Translation = dispVertices[t].pos
        surf.Vertices[i].LightmapUV:Zero()
        surf.Vertices[i].LightmapSamplePoint = dispVertices[t].lightmapSamplePoint
        surf.Vertices[i].DisplacementOrigin = dispVertices[t].org
    end

    surf.Triangles = {}
    for i = 1, #surf.Vertices, 3 do
        local t1 = surf.Vertices[i].Translation
        local t2 = surf.Vertices[i + 1].Translation
        local t3 = surf.Vertices[i + 2].Translation
        local forward = t2 - t3
        local another = t1 - t3
        local angle = forward:AngleEx(forward:Cross(another))
        local e1 = angle:Forward()
        local e2 = -angle:Right()
        local minX = min(0, e1:Dot(another))
        local maxX = max(e1:Dot(forward), e1:Dot(another))
        local v12 = t2 - t1
        local v13 = t3 - t1
        local d1212 = v12:Dot(v12);
        local d1213 = v12:Dot(v13);
        local d1313 = v13:Dot(v13);
        local denominator = d1212 * d1313 - d1213 * d1213;
        local barycentricDot1 = (d1313 * v12 - d1213 * v13) / denominator
        local barycentricDot2 = (d1212 * v13 - d1213 * v12) / denominator
        local t = ss.new "PrecachedData.DisplacementTriangle"
        t.Index = i
        t.BarycentricDot1 = barycentricDot1
        t.BarycentricDot2 = barycentricDot2
        -- t.BarycentricAdd1 = -t1:Dot(barycentricDot1) -- They need double precision
        -- t.BarycentricAdd2 = -t1:Dot(barycentricDot2) -- which can't be stored
        t.MBBAngles = angle
        t.MBBOrigin:Set(t3 + e1 * minX)
        t.MBBSize:SetUnpacked(maxX - minX, e2:Dot(another), 0)
        surf.Triangles[#surf.Triangles + 1] = t
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
    if bit.band(texInfo.flags, TextureFilterBits) ~= 0 then return end

    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA
    local texData      = rawTexData[texInfo.texData + 1]
    local texOffset    = rawTexDict[texData.nameStringTableID + 1]
    local texIndex     = rawTexIndex[texOffset]
    local texName      = rawTexString[texIndex]:lower()
    if texName:find "tools/" then return end

    local texMaterial  = GetMaterial(texName)
    local surfaceProp = texMaterial:GetString "$surfaceprop" or ""
    local surfaceIndex = util.GetSurfaceIndex(surfaceProp)
    local surfaceData = util.GetSurfaceData(surfaceIndex) or {}
    if surfaceData.material == MAT_GRATE then return end

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
    local vertexSum = Vector()
    local filteredVertices = {} ---@type Vector[]
    for i, current in ipairs(rawVertices) do
        local before = rawVertices[(#rawVertices + i - 2) % #rawVertices + 1]
        local after  = rawVertices[i % #rawVertices + 1]
        local cross  = (before - current):Cross(after - current)
        if normal:Dot(cross:GetNormalized()) > 0 then
            vertexSum:Add(current)
            filteredVertices[#filteredVertices + 1] = current
        end
    end

    -- Check if it's valid to add to polygon list
    if #filteredVertices < 3 then return end
    local center = vertexSum / #filteredVertices
    local isDisplacement = rawFace.dispInfo >= 0
    local isWater = texName:find "water"
    local surf = nil ---@type ss.PrecachedData.Surface?
    local angle = normal:Angle()
    angle:RotateAroundAxis(angle:Right(), -90) -- Make sure the up vector is the normal
    assert(normal:GetNormalized():Dot(angle:Up()) > 0.999)

    if isDisplacement then
        surf = BuildFromDisplacement(bsp, rawFace, filteredVertices)

        -- For the original flat plane of the displacement
        local mbrMatrix, mbrSize = FindMBR(filteredVertices, angle, center)
        SetTransformRelatedValues(surf, mbrMatrix, mbrSize)

        -- For the deformed mesh
        local mbbMatrix, mbbSize = FindMinimumOBB(surf.Vertices)
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
    else
        surf = ss.new "PrecachedData.Surface"
        local mbrMatrix, mbrSize = FindMBR(filteredVertices, angle, center)
        local triangles = {} ---@type integer[]
        for i = 2, #filteredVertices - 1 do
            triangles[#triangles + 1] = 1
            triangles[#triangles + 1] = i
            triangles[#triangles + 1] = i + 1
        end
        for _, v in ipairs(filteredVertices) do
            surf.AABBMax:Set(ss.MaxVector(surf.AABBMax, v))
            surf.AABBMin:Set(ss.MinVector(surf.AABBMin, v))
        end
        for i, t in ipairs(triangles) do
            surf.Vertices[i] = ss.new "PrecachedData.Vertex"
            surf.Vertices[i].Translation:Set(filteredVertices[t])
            surf.Vertices[i].Angle:Set(angle)
        end
        if not isWater then
            SetTransformRelatedValues(surf, mbrMatrix, mbrSize)
            surf.MBBAngles:Set(mbrMatrix:GetAngles())
            surf.MBBOrigin:Set(mbrMatrix:GetTranslation())
            surf.MBBSize:Set(mbrSize)
        end
    end

    return surf, tobool(isWater)
end

---Extract surfaces from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@param modelCache ss.PrecachedData.ModelInfo[]
---@param ishdr boolean
---@return ss.PrecachedData.SurfaceInfo surf
---@return ss.PrecachedData.Surface[] water
function ss.BuildSurfaceCache(bsp, modelCache, ishdr)
    local t0 = SysTime()
    local modelIndices = {} ---@type integer[] Face index --> model index
    for modelIndex, lump in ipairs(bsp.MODELS) do
        for i = 1, lump.numFaces do
            modelIndices[lump.firstFace + i] = modelIndex
        end
    end

    local surfInfo = ss.new "PrecachedData.SurfaceInfo"
    local surf = surfInfo.Surfaces
    local water = {} ---@type ss.PrecachedData.Surface[]
    local lump = ishdr and bsp.FACES_HDR or bsp.FACES or {}
    print("Generating inkable surfaces for " .. (ishdr and "HDR" or "LDR") .. "...")
    for i, face in ipairs(lump) do
        local s, iswater = BuildFromBrushFace(bsp, face)
        if s then
            if iswater then
                water[#water + 1] = s
            else
                s.FaceLumpIndex = i
                surf[#surf + 1] = s

                local modelIndex = modelIndices[i]
                local modelInfo = modelCache[modelIndex]
                modelInfo.FaceIndices[#modelInfo.FaceIndices + 1] = #surf
                modelInfo.NumTriangles = modelInfo.NumTriangles + #s.Vertices / 3
            end
        end
    end
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
    cache.StaticPropMDL = bsp.sprp.name
    print("    Collected info for " .. #results .. " static props.")
end
