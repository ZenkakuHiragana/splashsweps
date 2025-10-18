
-- Spatial hashing for better query performance of surfaces

---@class ss
local ss = SplashSWEPs
if not ss then return end

local ceil = math.ceil
local clamp = math.Clamp
local floor = math.floor
local ipairs = ipairs
local max = math.max
local min = math.min
local wrap = coroutine.wrap
local yield = coroutine.yield
local IsOBBIntersectingOBB = util.IsOBBIntersectingOBB
local OrderVectors = OrderVectors
local angle_zero = angle_zero
local vector_origin = vector_origin
local vector_one = ss.vector_one
local vector_tenth = vector_one * 0.1
local vector_16384 = vector_one * 16384
local GRID_SIZE = 128
local MAX_GRID_INDEX = 32768 / GRID_SIZE
local MAX_GRID_INDEX_SQR = MAX_GRID_INDEX * MAX_GRID_INDEX

---Converts real number coordinate to rough coordinate.
---@param pos Vector
---@return number x Rough coordinate X.
---@return number y Rough coordinate Y.
---@return number z Rough coordinate Z.
local function posToIndex(pos)
    return floor((pos.x + 16384) / GRID_SIZE),
           floor((pos.y + 16384) / GRID_SIZE),
           floor((pos.z + 16384) / GRID_SIZE)
end

---Calculates hash code from x, y, and z coordinates.
---@param x integer Rough coordinate which can be obtained from posToGrid(x: number).
---@param y integer Rough coordinate which can be obtained from posToGrid(y: number).
---@param z integer Rough coordinate which can be obtained from posToGrid(z: number).
---@return integer
local function indexToHash(x, y, z)
    return x + y * MAX_GRID_INDEX + z * MAX_GRID_INDEX_SQR
end

---Generator function that produces hash integers to look-up the surfaces within given AABB.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): number # Generator function.
local function hashpairs(mins, maxs)
    local x0, y0, z0 = posToIndex(mins)
    local x1, y1, z1 = posToIndex(maxs)
    return wrap(function()
        for z = z0, z1 do
            for y = y0, y1 do
                for x = x0, x1 do
                    -- local gmin = Vector(x, y, z) * GRID_SIZE - vector_16384
                    -- local gmax = gmin + vector_one * GRID_SIZE
                    -- debugoverlay.Box(Vector(), gmin, gmax, FrameTime() * 20, Color(0, 255, 0, 16))
                    yield(indexToHash(x, y, z))
                end
            end
        end
    end)
end

---Generates look-up table for spatial partitioning to find surfaces faster.
---@param surfaces    ss.PrecachedData.Surface[]    The source array.
---@param faceIndices integer[]                     Indices of the worldspawn surfaces.
---@param staticProps ss.PrecachedData.StaticProp[] List of static props.
---@param hash        table<integer, integer[]>     The output hash table.
function ss.BuildSurfaceHash(surfaces, faceIndices, staticProps, hash)
    print("Constructing spatial hash table for paintable surfaces...")
    for _, i in ipairs(faceIndices) do
        local s = surfaces[i]
        for h in hashpairs(s.AABBMin, s.AABBMax) do
            hash[h] = hash[h] or {}
            hash[h][#hash[h] + 1] = i
        end
    end

    for i, s in ipairs(staticProps) do
        local localToWorld = Matrix()
        localToWorld:SetAngles(s.Angles)
        localToWorld:SetTranslation(s.Position)
        local maxs = localToWorld * s.BoundsMax
        local mins = localToWorld * s.BoundsMin
        OrderVectors(mins, maxs)
        for h in hashpairs(mins, maxs) do
            hash[h] = hash[h] or {}
            hash[h][#hash[h] + 1] = #surfaces + i
        end
    end
end

---Generator function to enumerate surfaces containing given AABB.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): ss.PaintableSurface
function ss.CollectSurfaces(mins, maxs)
    mins = mins - vector_tenth
    maxs = maxs + vector_tenth
    return wrap(function()
        local hasSeenThisSurface = {} ---@type table<integer, true>
        for h in hashpairs(mins, maxs) do
            for _, i in ipairs(ss.SurfaceHash[h] or {}) do
                if not hasSeenThisSurface[i] then
                    hasSeenThisSurface[i] = true
                    local s = ss.SurfaceArray[i]
                    -- debugoverlay.BoxAngles(
                    --     s.MBBOrigin, vector_origin, s.MBBSize, s.MBBAngles,
                    --     FrameTime() * 5, Color(255, 255, 128, 0))
                    if IsOBBIntersectingOBB(
                        s.MBBOrigin, s.MBBAngles, vector_origin, s.MBBSize,
                        vector_origin, angle_zero, mins, maxs, ss.eps) then
                        yield(s)
                    end
                end
            end
        end
    end)
end

---Gets AABB of a grid for debug purpose.
---@param pos Vector Query position to retrieve a grid containing there.
---@return Vector mins AABB minimum.
---@return Vector maxs AABB maximum.
function ss.GetGridBBox(pos)
    local mins = Vector(posToIndex(pos)) * GRID_SIZE - vector_16384
    local maxs = mins + vector_one * GRID_SIZE
    return mins, maxs
end

---Converts real number coordinate to rough coordinate using given AABB size and number of division.
---@param pos Vector
---@param mins Vector The AABB minimum.
---@param maxs Vector The AABB maximum.
---@return number x Rough coordinate X.
---@return number y Rough coordinate Y.
---@return number z Rough coordinate Z.
local function posToIndexAABB(pos, mins, maxs)
    local size = maxs - mins
    local minGridSize = ss.HashParameters.MinGridSizeDisplacement
    local numDivision = ss.HashParameters.NumDivisionsDisplacement
    local maxIndicesX = clamp(ceil(size.x / minGridSize), 1, numDivision)
    local maxIndicesY = clamp(ceil(size.y / minGridSize), 1, numDivision)
    local maxIndicesZ = clamp(ceil(size.z / minGridSize), 1, numDivision)
    local gridSize = size / numDivision
    OrderVectors(vector_one * minGridSize, gridSize)
    local indices = (pos - mins) / gridSize
    return clamp(floor(indices.x), 0, maxIndicesX - 1),
           clamp(floor(indices.y), 0, maxIndicesY - 1),
           clamp(floor(indices.z), 0, maxIndicesZ - 1)
end

---Calculates hash code from x, y, and z coordinates using given AABB size and number of division.
---@param x integer Rough coordinate which can be obtained from posToGrid(x: number).
---@param y integer Rough coordinate which can be obtained from posToGrid(y: number).
---@param z integer Rough coordinate which can be obtained from posToGrid(z: number).
---@param mins Vector The AABB minimum.
---@param maxs Vector The AABB maximum.
---@return integer
local function indexToHashAABB(x, y, z, mins, maxs)
    local size = maxs - mins
    local minGridSize = ss.HashParameters.MinGridSizeDisplacement
    local numDivision = ss.HashParameters.NumDivisionsDisplacement
    local maxIndicesX = min(ceil(size.x / minGridSize), numDivision)
    local maxIndicesY = min(ceil(size.y / minGridSize), numDivision)
    return x + y * maxIndicesX + z * maxIndicesX * maxIndicesY
end

---Generator function that produces hash integers to look-up the surfaces within given AABB.
---@param queryMins Vector Minimum vector of AABB query.
---@param queryMaxs Vector Maximum vector of AABB query.
---@param mins      Vector Minimum vector of the area to search.
---@param maxs      Vector Maximum vector of the area to search.
---@return fun(): number # Generator function.
local function hashpairsAABB(queryMins, queryMaxs, mins, maxs)
    local x0, y0, z0 = posToIndexAABB(queryMins, mins, maxs)
    local x1, y1, z1 = posToIndexAABB(queryMaxs, mins, maxs)
    return wrap(function()
        for z = z0, z1 do
            for y = y0, y1 do
                for x = x0, x1 do
                    -- local gridSize = (maxs - mins) / ss.HashParameters.NumDivisionsDisplacement
                    -- OrderVectors(vector_one * ss.HashParameters.MinGridSizeDisplacement, gridSize)
                    -- local gmin = Vector(x, y, z) * gridSize + mins
                    -- local gmax = gmin + gridSize
                    -- debugoverlay.Box(Vector(), gmin, gmax, FrameTime() * 20, Color(0, 255, 0, 16))
                    yield(indexToHashAABB(x, y, z, mins, maxs))
                end
            end
        end
    end)
end

---Generates look-up table for spatial partitioning to find triangles of displacement faster.
---@param surfaces ss.PrecachedData.Surface[] The source displacement.
function ss.BuildDisplacementHash(surfaces)
    print("Constructing spatial hash table for displacement triangles...")
    for _, surf in ipairs(surfaces) do
        if surf.Triangles then
            surf.TriangleHash = {}
            local v = surf.Vertices
            for i, t in ipairs(surf.Triangles) do
                local v1 = v[t.Index].Translation
                local v2 = v[t.Index + 1].Translation
                local v3 = v[t.Index + 2].Translation
                local mins = Vector(
                    min(v1.x, v2.x, v3.x),
                    min(v1.y, v2.y, v3.y),
                    min(v1.z, v2.z, v3.z))
                local maxs = Vector(
                    max(v1.x, v2.x, v3.x),
                    max(v1.y, v2.y, v3.y),
                    max(v1.z, v2.z, v3.z))
                for h in hashpairsAABB(mins, maxs, surf.AABBMin, surf.AABBMax) do
                    surf.TriangleHash[h] = surf.TriangleHash[h] or {}
                    surf.TriangleHash[h][#surf.TriangleHash[h] + 1] = i
                end
            end
        end
    end
end

---Generator function to enumerate triangles containing given AABB in a displacement.
---@param displacement ss.PaintableSurface The displacement to search.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): ss.DisplacementTriangle triangle An array of vertices.
function ss.CollectDisplacementTriangles(displacement, mins, maxs)
    if not displacement.TriangleHash then return wrap(function() end) end
    mins = mins - vector_tenth
    maxs = maxs + vector_tenth
    return wrap(function()
        local hasSeenThisTriangle = {} ---@type table<integer, true>
        for h in hashpairsAABB(mins, maxs, displacement.AABBMin, displacement.AABBMax) do
            for _, i in ipairs(displacement.TriangleHash[h] or {}) do
                if not hasSeenThisTriangle[i] then
                    hasSeenThisTriangle[i] = true
                    local t = displacement.Triangles[i]
                    -- debugoverlay.BoxAngles(
                    --     t.MBBOrigin, vector_origin, t.MBBSize, t.MBBAngles,
                    --     FrameTime() * 5, Color(255, 255, 255, 8))
                    if IsOBBIntersectingOBB(
                        t.MBBOrigin, t.MBBAngles, vector_origin, t.MBBSize,
                        vector_origin, angle_zero, mins, maxs, ss.eps) then
                        yield(t)
                    end
                end
            end
        end
    end)
end
