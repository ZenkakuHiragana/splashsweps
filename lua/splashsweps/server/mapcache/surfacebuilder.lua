
---@class ss
local ss = SplashSWEPs
if not ss then return end

local InkGridSize, NumRenderTargetOptions = 1, 5 -- TODO: Make them global

local abs = math.abs
local ModelMeshCache = {} ---@type table<string, Structure.MeshVertex[]>
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

---@param name string
---@return { material: string, triangles: Structure.MeshVertexWithWeights[], vertices: Structure.MeshVertexWithWeights[] }[]
local function GetModelMeshes(name)
    if not ModelMeshCache[name] then
        ModelMeshCache[name] = util.GetModelMeshes(name)
    end
    return ModelMeshCache[name]
end

-- Generates a convex hull by monotone chain method
---@param source Vector[]
---@return Vector[]
local function GetConvex(source)
    local vertices2D = table.Copy(source)
    table.sort(vertices2D, function(a, b)
        return Either(a.x == b.x, a.y < b.y, a.x < b.x)
    end)

    local convex = {} ---@type Vector[]
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
---@param vertices Vector[]
---@param angle Angle
---@param center Vector
---@return VMatrix origin, Vector size
local function FindMBR(vertices, angle, center)
    local vertices2D = {} ---@type Vector[]
    for i, v in ipairs(vertices) do
        vertices2D[i] = WorldToLocal(v, angle_zero, center, angle)
    end

    local minarea = math.huge
    local mbrSize = Vector()
    local mbrRotation = Matrix()
    local convex = GetConvex(vertices2D)
    for i = 1, #convex do
        local p0, p1 = convex[i], convex[i % #convex + 1]
        local dp = p1 - p0
        if dp:LengthSqr() > 0 then
            local dir  = dp:GetNormalized()
            local rotation = Matrix() -- to represent the angle of the MBR
            local maxs = ss.vector_one * -math.huge
            local mins = ss.vector_one * math.huge
            rotation:SetForward(dir)
            rotation:SetRight(Vector(dir.y, -dir.x))
            for _, v in ipairs(convex) do
                maxs = ss.MaxVector(maxs, rotation * v)
                mins = ss.MinVector(mins, rotation * v)
            end

            local size = maxs - mins
            if minarea > size.x * size.y then
                minarea = size.x * size.y
                mbrSize = size
                mbrRotation = rotation
                if size.x < size.y then
                    -- X axis of the MBR should be wide
                    mbrRotation:Rotate(Angle(0, 0, 90))
                    mbrSize.x, mbrSize.y = mbrSize.y, mbrSize.x
                end
            end
        end
    end

    local mins = ss.vector_one * math.huge
    for _, v in ipairs(vertices2D) do
        mins = ss.MinVector(mins, mbrRotation * v)
    end

    -- Represents the origin and angle of the MBR
    -- in the world coordinate system.
    local worldToMBR = Matrix()
    worldToMBR:SetAngles(angle)
    worldToMBR:SetTranslation(center)
    worldToMBR:Mul(mbrRotation)
    worldToMBR:Translate(mins)
    return worldToMBR, mbrSize
end

---Set placeholder values to VMatrix transform and 2D size fields
---@param surf ss.PrecachedData.Surface
---@param worldToMBR VMatrix
---@param mbrSize Vector
local function SetTransformRelatedValues(surf, worldToMBR, mbrSize)
    surf.PaintGridWidth  = math.ceil(mbrSize.x / InkGridSize)
    surf.PaintGridHeight = math.ceil(mbrSize.y / InkGridSize)
    surf.TransformPaintGrid = Matrix(worldToMBR)
    surf.TransformPaintGrid:Scale(Vector(
        surf.PaintGridWidth  / mbrSize.x,
        surf.PaintGridHeight / mbrSize.y, 1))
    for i = 1, NumRenderTargetOptions do
        surf.UVInfo[i] = ss.new "PrecachedData.UVInfo"
        surf.UVInfo[i].Transform = Matrix(worldToMBR)
        surf.UVInfo[i].Transform:Scale(Vector(1 / mbrSize.x, 1 / mbrSize.y, 1))
        surf.UVInfo[i].Width = mbrSize.x
        surf.UVInfo[i].Height = mbrSize.y
    end
end

---Construct a polygon from a raw displacement data
---@param bsp ss.RawBSPResults
---@param rawFace BSP.Face
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
    local dispVertices = {} ---@type VMatrix[]  List of vertices
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
        local m = Matrix()
        m:SetTranslation(worldPos)
        m:SetAngles(dispVert.vec:Angle())

        -- Relative UV coordinates
        m:SetField(4, 1, x) -- u1
        m:SetField(4, 2, y) -- v1

        dispVertices[#dispVertices + 1] = m

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
        surf.Vertices[i] = dispVertices[t]
    end

    return surf
end

-- Construct a polygon from a raw face data
---@param bsp ss.RawBSPResults
---@param rawFace BSP.Face
---@return ss.PrecachedData.Surface?, boolean?
local function BuildFromBrushFace(bsp, rawFace)
    -- Collect texture information and see if it's valid
    local rawTexInfo   = bsp.TEXINFO
    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA
    local texInfo      = rawTexInfo[rawFace.texInfo + 1]
    local texData      = rawTexData[texInfo.texData + 1]
    local texOffset    = rawTexDict[texData.nameStringTableID + 1]
    local texIndex     = rawTexIndex[texOffset]
    local texName      = rawTexString[texIndex]:lower()
    local texMaterial  = GetMaterial(texName)
    if bit.band(texInfo.flags, TextureFilterBits) ~= 0 then return end
    if texMaterial:GetString "$surfaceprop" == "metalgrate" then return end
    if texName:find "tools/" then return end

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
    local contents = util.PointContents(center - normal * ss.eps)
    local isDisplacement = rawFace.dispInfo >= 0
    local isSolid = bit.band(contents, MASK_SOLID) > 0
    local isWater = texName:find "water"
    if not (isDisplacement or isSolid or isWater) then return end

    local surf = nil ---@type ss.PrecachedData.Surface?
    local angle = normal:Angle()
    angle:RotateAroundAxis(angle:Right(), -90) -- Make sure the up vector is the normal
    assert(normal:GetNormalized():Dot(angle:Up()) > 0.999)

    if isDisplacement then
        surf = BuildFromDisplacement(bsp, rawFace, filteredVertices)
    else
        surf = ss.new "PrecachedData.Surface"
        for i, v in ipairs(filteredVertices) do
            surf.Vertices[i] = Matrix()
            surf.Vertices[i]:SetTranslation(v)
            surf.Vertices[i]:SetAngles(angle)
            surf.AABBMax = ss.MaxVector(surf.AABBMax, v)
            surf.AABBMin = ss.MinVector(surf.AABBMin, v)
        end
    end

    if not isWater then
        SetTransformRelatedValues(
            surf, FindMBR(filteredVertices, angle, center))
    end

    return surf, tobool(isWater)
end

local PROJECTION_NORMALS = {
    ["x+"] = Vector( 1,  0,  0),
    ["y+"] = Vector( 0,  1,  0),
    ["z+"] = Vector( 0,  0,  1),
    ["x-"] = Vector(-1,  0,  0),
    ["y-"] = Vector( 0, -1,  0),
    ["z-"] = Vector( 0,  0, -1),
}
local PROJECTION_ANGLES = {
    ["x+"] = PROJECTION_NORMALS["x+"]:Angle(),
    ["y+"] = PROJECTION_NORMALS["y+"]:Angle(),
    ["z+"] = PROJECTION_NORMALS["z+"]:Angle(),
    ["x-"] = PROJECTION_NORMALS["x-"]:Angle(),
    ["y-"] = PROJECTION_NORMALS["y-"]:Angle(),
    ["z-"] = PROJECTION_NORMALS["z-"]:Angle(),
}
---@param origin Vector
---@param angle Angle
---@param triangles { pos: Vector, normal: Vector }[]
---@return table<string, ss.PrecachedData.Surface>
local function ProcessStaticPropConvex(origin, angle, triangles)
    local surfaces = {
        ["x+"] = ss.new "PrecachedData.Surface",
        ["y+"] = ss.new "PrecachedData.Surface",
        ["z+"] = ss.new "PrecachedData.Surface",
        ["x-"] = ss.new "PrecachedData.Surface",
        ["y-"] = ss.new "PrecachedData.Surface",
        ["z-"] = ss.new "PrecachedData.Surface",
    }
    local maxs_all = {
        ["x+"] = -ss.vector_one * math.huge,
        ["y+"] = -ss.vector_one * math.huge,
        ["z+"] = -ss.vector_one * math.huge,
        ["x-"] = -ss.vector_one * math.huge,
        ["y-"] = -ss.vector_one * math.huge,
        ["z-"] = -ss.vector_one * math.huge,
    }
    local mins_all = {
        ["x+"] = ss.vector_one * math.huge,
        ["y+"] = ss.vector_one * math.huge,
        ["z+"] = ss.vector_one * math.huge,
        ["x-"] = ss.vector_one * math.huge,
        ["y-"] = ss.vector_one * math.huge,
        ["z-"] = ss.vector_one * math.huge,
    }

    local center = Vector()
    local vertices = {} ---@type Vector[]
    for i = 1, #triangles, 3 do
        local v1 = LocalToWorld(triangles[i    ].pos, angle_zero, origin, angle)
        local v2 = LocalToWorld(triangles[i + 1].pos, angle_zero, origin, angle)
        local v3 = LocalToWorld(triangles[i + 2].pos, angle_zero, origin, angle)
        local n = (triangles[i    ].normal or Vector())
                + (triangles[i + 1].normal or Vector())
                + (triangles[i + 2].normal or Vector())
        if n:IsZero() then
            local v2v1 = v1 - v2
            local v2v3 = v3 - v2
            n = v2v1:Cross(v2v3) -- normal around v1<-v2->v3
            if n:LengthSqr() < 1 then continue end -- normal is valid then
        else
            n = LocalToWorld(n, angle_zero, vector_origin, angle)
        end

        -- Find proper plane for projection
        local nx, ny, nz, plane_index = abs(n.x), abs(n.y), abs(n.z)
        if nx > ny and nx > nz then
            plane_index = n.x > 0 and "x+" or "x-"
        elseif ny > nx and ny > nz then
            plane_index = n.y > 0 and "y+" or "y-"
        else
            plane_index = n.z > 0 and "z+" or "z-"
        end

        OrderVectors(Vector(v1), maxs_all[plane_index])
        OrderVectors(Vector(v2), maxs_all[plane_index])
        OrderVectors(Vector(v3), maxs_all[plane_index])
        OrderVectors(mins_all[plane_index], Vector(v1))
        OrderVectors(mins_all[plane_index], Vector(v2))
        OrderVectors(mins_all[plane_index], Vector(v3))

        center:Add(v1 + v2 + v3)
        vertices[#vertices + 1] = v1
        vertices[#vertices + 1] = v2
        vertices[#vertices + 1] = v3

        local surf = surfaces[plane_index]
        surf.Vertices[#surf.Vertices + 1] = Matrix()
        surf.Vertices[#surf.Vertices]:SetAngles(n:Angle())
        surf.Vertices[#surf.Vertices]:SetTranslation(v1)
        surf.Vertices[#surf.Vertices + 1] = Matrix()
        surf.Vertices[#surf.Vertices]:SetAngles(n:Angle())
        surf.Vertices[#surf.Vertices]:SetTranslation(v2)
        surf.Vertices[#surf.Vertices + 1] = Matrix()
        surf.Vertices[#surf.Vertices]:SetAngles(n:Angle())
        surf.Vertices[#surf.Vertices]:SetTranslation(v3)
    end

    for k, ang in pairs(PROJECTION_ANGLES) do
        local surf = surfaces[k]
        if #vertices >= 3 then
            center:Div(#vertices)
            surf.AABBMax = maxs_all[k]
            surf.AABBMin = mins_all[k]
            SetTransformRelatedValues(surf, FindMBR(vertices, ang, center))
        end
    end

    return surfaces
end

---@param ph PhysObj
---@param name string?
---@param org Vector?
---@param ang Angle?
---@return ss.PrecachedData.Surface[]?
local function BuildFacesFromPropMesh(ph, name, org, ang)
    if not IsValid(ph) then return end
    local mat = ph:GetMaterial()
    if mat:find "chain" or mat:find "grate" then return end

    local meshes = name and GetModelMeshes(name) or ph:GetMeshConvexes()
    if not meshes or #meshes == 0 then return end

    local surfaces = {} ---@type ss.PrecachedData.Surface[]
    org, ang = org or ph:GetPos(), ang or ph:GetAngles()
    for _, t in ipairs(meshes) do
        if t.material then
            local m = GetMaterial(t.material)
            if m then
                if m:IsError() then continue end
                if (m:GetInt "$translucent" or 0) ~= 0 then continue end
                if (m:GetInt "$alphatest" or 0) ~= 0 then continue end
            end
        end
        for _, surf in pairs(ProcessStaticPropConvex(org, ang, t.triangles or t)) do
            if #surf.Vertices >= 3 then
                surfaces[#surfaces + 1] = surf
            end
        end
    end

    return surfaces
end

---@param ph PhysObj
---@param name string
---@param origin Vector
---@param angle Angle
---@param mins Vector
---@param maxs Vector
---@return ss.PrecachedData.Surface[]?
local function BuildStaticPropSurface(ph, name, origin, angle, mins, maxs)
    if IsValid(ph) then
       local mat = ph:GetMaterial()
       if mat:find "chain" or mat:find "grate" then return end
    end

    local surf = ss.new "PrecachedData.Surface"
    local meshes = GetModelMeshes(name)
    -- surf.IsSmallProp = true
    surf.AABBMax = LocalToWorld(maxs, angle_zero, origin, angle)
    surf.AABBMin = LocalToWorld(mins, angle_zero, origin, angle)
    OrderVectors(surf.AABBMin, surf.AABBMax)
    local vertices = {} ---@type Vector[]
    for _, t in ipairs(meshes) do
        local m = GetMaterial(t.material or "")
        if m then
            if m:IsError() then continue end
            if (m:GetInt "$translucent" or 0) ~= 0 then continue end
            if (m:GetInt "$alphatest" or 0) ~= 0 then continue end
        end
        local triangles = t.triangles
        for i = 1, #triangles, 3 do
            local v1 = LocalToWorld(triangles[i    ].pos, angle_zero, origin, angle)
            local v2 = LocalToWorld(triangles[i + 1].pos, angle_zero, origin, angle)
            local v3 = LocalToWorld(triangles[i + 2].pos, angle_zero, origin, angle)
            vertices[#vertices + 1] = v1
            vertices[#vertices + 1] = v2
            vertices[#vertices + 1] = v1
            surf.Vertices[#surf.Vertices + 1] = Matrix()
            surf.Vertices[#surf.Vertices]:SetTranslation(v1)
            surf.Vertices[#surf.Vertices]:SetAngles(angle)
            surf.Vertices[#surf.Vertices]:SetField(4, 4, -1) -- (u2, v2) = (0, -1)
            surf.Vertices[#surf.Vertices + 1] = Matrix()
            surf.Vertices[#surf.Vertices]:SetTranslation(v2)
            surf.Vertices[#surf.Vertices]:SetAngles(angle)
            surf.Vertices[#surf.Vertices]:SetField(4, 4, -1) -- (u2, v2) = (0, -1)
            surf.Vertices[#surf.Vertices + 1] = Matrix()
            surf.Vertices[#surf.Vertices]:SetTranslation(v3)
            surf.Vertices[#surf.Vertices]:SetAngles(angle)
            surf.Vertices[#surf.Vertices]:SetField(4, 4, -1) -- (u2, v2) = (0, -1)
        end
    end

    if #surf.Vertices < 3 then return end
    SetTransformRelatedValues(surf, FindMBR(vertices, angle, origin))
    return { surf }
end

---@param bsp ss.RawBSPResults
---@param prop BSP.StaticProp
---@return ss.PrecachedData.Surface[]?
---@return boolean?
local function BuildStaticProp(bsp, prop)
    local name = bsp.sprp.name[prop.propType + 1]
    if not name then return end
    if not file.Exists(name, "GAME") then return end
    if not file.Exists(name:sub(1, -4) .. "phy", "GAME") then return end

    local mdl = ents.Create "base_anim"
    if not IsValid(mdl) then return end
    mdl:SetModel(name)
    mdl:Spawn()
    local ph ---@type PhysObj
    local mins, maxs = mdl:GetModelBounds()
    local size = maxs - mins
    if prop.solid == SOLID_VPHYSICS then
        mdl:PhysicsInit(SOLID_VPHYSICS)
        ph = mdl:GetPhysicsObject()
    end
    mdl:Remove()

    size.x = 11 -- Always use physics collision mesh instead of model mesh for now
    if math.max(size.x, size.y, size.z) > 10 then
        return BuildFacesFromPropMesh(ph, nil, prop.origin, prop.angle), false
    else
        return BuildStaticPropSurface(ph, name, prop.origin, prop.angle, mins, maxs), true
    end
end

---Extract surfaces from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@param ishdr boolean
---@param water ss.PrecachedData.Surface[]
---@return ss.PrecachedData.Surface[]
function ss.BuildSurfaceCache(bsp, ishdr, water)
    local t0 = SysTime()
    local surf = {} ---@type ss.PrecachedData.Surface[]
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
            end
        end
    end
    print("    Generated " .. #lump .. " surfaces for " .. (ishdr and "HDR" or "LDR"))

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("Elapsed time: " .. elapsed .. " ms.")

    return surf
end

---Extracts surfaces from static props and func_lods.
---@param bsp ss.RawBSPResults
---@return ss.PrecachedData.Surface[]
function ss.BuildStaticPropCache(bsp)
    print "Generating static prop surfaces..."
    local numLargeProps = 0
    local numSmallProps = 0
    local results = {} ---@type ss.PrecachedData.Surface[]
    for _, prop in ipairs(bsp.sprp.prop or {}) do
        local surfaces, issmall = BuildStaticProp(bsp, prop)
        if issmall then
            numSmallProps = numSmallProps + 1
        else
            numLargeProps = numLargeProps + 1
        end

        for _, surf in ipairs(surfaces or {}) do
            results[#results + 1] = surf
        end
    end
    print("    Generated surfaces for "
    .. numLargeProps .. " standard static props and "
    .. numSmallProps .. " small static props.")

    print "Generating surfaces for func_lods..."
    local funclod = ents.FindByClass "func_lod"
    for _, prop in ipairs(funclod) do
        local ph = prop:GetPhysicsObject()
        for _, surf in ipairs(BuildFacesFromPropMesh(ph) or {}) do
            results[#results + 1] = surf
        end
    end
    print("    Generated surfaces for " .. #funclod .. " func_lods.")
    return results
end
