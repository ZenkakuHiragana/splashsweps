
---@class ss
local ss = SplashSWEPs
if not ss then return end

local abs = math.abs
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
---@param angle    Angle    The angle of the face in the world coordinate system.
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
                maxs = ss.MaxVector(maxs, rotationInv * v)
                mins = ss.MinVector(mins, rotationInv * v)
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

    ss.Debug.mbr = ss.Debug.mbr or {}
    table.insert(ss.Debug.mbr, {
        localToWorld = localToWorld,
        size = mbrSize,
    })
    return localToWorld, mbrSize
end

---Set placeholder values to VMatrix transform and 2D size fields
---@param surf ss.PrecachedData.Surface
---@param mbrLocalToWorld VMatrix
---@param mbrSize Vector
local function SetTransformRelatedValues(surf, mbrLocalToWorld, mbrSize)
    local paintGridMatrix = mbrLocalToWorld:GetInverseTR()
    surf.TransformPaintGrid.Translation = paintGridMatrix:GetTranslation()
    surf.TransformPaintGrid.Angle       = paintGridMatrix:GetAngles()
    surf.PaintGridWidth  = math.ceil(mbrSize.x / ss.InkGridCellSize)
    surf.PaintGridHeight = math.ceil(mbrSize.y / ss.InkGridCellSize)
    for i = 1, #ss.RenderTarget.Resolutions do
        surf.UVInfo[i] = ss.new "PrecachedData.UVInfo"
        surf.UVInfo[i].Angle       = mbrLocalToWorld:GetAngles()
        surf.UVInfo[i].Translation = mbrLocalToWorld:GetTranslation()
        surf.UVInfo[i].Width       = mbrSize.x
        surf.UVInfo[i].Height      = mbrSize.y
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
        local xi, yi = (i - 1) % power, math.floor((i - 1) / power)
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
        surf.AABBMax = ss.MaxVector(surf.AABBMax, worldPos)
        surf.AABBMin = ss.MinVector(surf.AABBMin, worldPos)
    end

    for i, t in ipairs(triangles) do
        surf.Vertices[i] = ss.new "PrecachedData.Vertex"
        surf.Vertices[i].Angle       = dispVertices[t].ang
        surf.Vertices[i].Translation = dispVertices[t].pos
        surf.Vertices[i].DisplacementOrigin = dispVertices[t].org
        surf.Vertices[i].LightmapSamplePoint = dispVertices[t].lightmapSamplePoint
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
    else
        surf = ss.new "PrecachedData.Surface"
        local triangles = {} ---@type integer[]
        for i = 2, #filteredVertices - 1 do
            triangles[#triangles + 1] = 1
            triangles[#triangles + 1] = i
            triangles[#triangles + 1] = i + 1
        end
        for _, v in ipairs(filteredVertices) do
            surf.AABBMax = ss.MaxVector(surf.AABBMax, v)
            surf.AABBMin = ss.MinVector(surf.AABBMin, v)
        end
        for i, t in ipairs(triangles) do
            local v = filteredVertices[t]
            surf.Vertices[i] = ss.new "PrecachedData.Vertex"
            surf.Vertices[i].Translation = v
            surf.Vertices[i].Angle = angle
        end
    end

    if not isWater then
        SetTransformRelatedValues(surf, FindMBR(filteredVertices, angle, center))
    end

    return surf, tobool(isWater)
end

---Extract surfaces from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@param modelCache ss.PrecachedData.ModelInfo[]
---@param ishdr boolean
---@return ss.PrecachedData.SurfaceInfo surf, ss.PrecachedData.SurfaceInfo water
function ss.BuildSurfaceCache(bsp, modelCache, ishdr)
    local t0 = SysTime()
    local modelIndices = {} ---@type integer[] Face index --> model index
    for modelIndex, lump in ipairs(bsp.MODELS) do
        for i = 1, lump.numFaces do
            modelIndices[lump.firstFace + i] = modelIndex
        end
    end

    local surf = ss.new "PrecachedData.SurfaceInfo"
    local water = ss.new "PrecachedData.SurfaceInfo"
    local lump = ishdr and bsp.FACES_HDR or bsp.FACES or {}
    print("Generating inkable surfaces for " .. (ishdr and "HDR" or "LDR") .. "...")
    for i, face in ipairs(lump) do
        local s, iswater = BuildFromBrushFace(bsp, face)
        if s then
            if iswater then
                water[#water + 1] = s
            else
                -- Used to retrieve face lump when building lightmap UV
                -- Honestly I don't want such a dirty hack but it's not
                -- acceptable to add extra field (that will be saved as a file!)
                -- just for this
                s.LightmapWidth = i
                surf[#surf + 1] = s

                local modelIndex = modelIndices[i]
                local modelInfo = modelCache[modelIndex]
                modelInfo.FaceIndices[#modelInfo.FaceIndices + 1] = #surf
                modelInfo.NumTriangles = modelInfo.NumTriangles + #s.Vertices / 3
            end
        end
    end
    print("    Generated " .. #lump .. " surfaces for " .. (ishdr and "HDR" or "LDR"))

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("Elapsed time: " .. elapsed .. " ms.")

    return surf, water
end

---Extracts surfaces from static props.
---@param bsp ss.RawBSPResults
---@return ss.PrecachedData.StaticProp[]
---@return ss.PrecachedData.StaticProp.UVInfo[][]
---@return ss.PrecachedData.StaticProp.UVInfo[][]
function ss.BuildStaticPropCache(bsp)
    print "Generating static prop surfaces..."
    local results = {} ---@type ss.PrecachedData.StaticProp[]
    local uvinfo = {} ---@type ss.PrecachedData.StaticProp.UVInfo[][]
    for _, prop in ipairs(bsp.sprp.prop or {}) do
        if prop.solid > 0 then
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
                    ModelName = name,
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
    print("    Collected info for " .. #results .. " static props.")
    return results, uvinfo, ss.deepcopy(uvinfo) or {}
end
