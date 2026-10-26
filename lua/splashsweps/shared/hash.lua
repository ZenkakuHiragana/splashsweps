
-- Spatial hashing for better query performance of surfaces

---@class ss
local ss = SplashSWEPs
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"
local Util             = ss.import "splashsweps/shared/util"

---@class ss.HashModule
local Hash = ss.module "splashsweps/shared/hash"

---@class ss.HashModule.State
---@field SurfaceHash table<integer, integer[]> Grid hash --> indices of PaintableSurface.Surfaces in the grid.
---@field Parameters  ss.PrecachedData.HashParameters
local state = ss.state("splashsweps/shared/hash", {
    SurfaceHash = {},
    Parameters = PrecachedData.HashParameters.new(),
}) ---@type ss.HashModule.State

---Sets the spatial hash of the world surfaces and the parameters, both read from the map cache.
---@param surfaceHash ss.PrecachedData.SurfaceHashEntry[]? The cells of the spatial hash, nil if there is none.
---@param parameters  ss.PrecachedData.HashParameters
function Hash.Setup(surfaceHash, parameters)
    local cells = {} ---@type table<integer, integer[]>
    for _, entry in ipairs(surfaceHash or {}) do
        cells[entry.HashValue] = entry.SurfaceIndices
    end

    state.SurfaceHash = cells
    state.Parameters = parameters
end

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
local vector_tenth = Util.vector_one * 0.1
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
                    -- local gmin = Vector(x, y, z) * GRID_SIZE - Util.vector_one * 16384
                    -- local gmax = gmin + Util.vector_one * GRID_SIZE
                    -- debugoverlay.Box(Vector(), gmin, gmax, FrameTime() * 20, Color(0, 255, 0, 16))
                    yield(indexToHash(x, y, z))
                end
            end
        end
    end)
end

---Generates look-up table for spatial partitioning to find surfaces faster.
---@param surfaces    ss.PrecachedData.Surface[]    The source array.
---@param staticProps ss.PrecachedData.StaticProp[] List of static props.
---@return ss.PrecachedData.SurfaceHashEntry[] # The cells of the spatial hash, given to Hash.Setup.
function Hash.BuildSurfaceHash(surfaces, staticProps)
    print("Constructing spatial hash table for paintable surfaces...")
    local hash = {} ---@type table<integer, integer[]>
    for i, s in ipairs(surfaces) do
        if s.ModelIndex == 1 then
            for h in hashpairs(s.AABBMin, s.AABBMax) do
                hash[h] = hash[h] or {}
                hash[h][#hash[h] + 1] = i
            end
        end
    end

    local localToWorld = Matrix()
    for i, s in ipairs(staticProps) do
        -- World AABB of the rotated OBB, plus the margin as the other surfaces have
        localToWorld:SetAngles(s.Angles)
        localToWorld:SetTranslation(s.Position)
        local mins, maxs = Util.TransformAABB(localToWorld, s.BoundsMin, s.BoundsMax)
        mins:Sub(Util.vector_one * ss.MARGIN_HAMMER_UNITS)
        maxs:Add(Util.vector_one * ss.MARGIN_HAMMER_UNITS)
        for h in hashpairs(mins, maxs) do
            hash[h] = hash[h] or {}
            for j = 1, 6 do
                hash[h][#hash[h] + 1] = #surfaces + 6 * (i - 1) + j
            end
        end
    end

    local entries = {} ---@type ss.PrecachedData.SurfaceHashEntry[]
    for h, indices in pairs(hash) do
        local entry = PrecachedData.SurfaceHashEntry.new()
        entry.HashValue = h
        entry.NumSurfaceIndices = #indices
        entry.SurfaceIndices = indices
        entries[#entries + 1] = entry
    end

    return entries
end

---Tests if the minimum bounding box of the surface intersects with given AABB.
---@param s    ss.PaintableSurface
---@param mins Vector AABB minimum in the same coordinate system as the surface.
---@param maxs Vector AABB maximum in the same coordinate system as the surface.
---@return boolean
local function isSurfaceIntersecting(s, mins, maxs)
    return IsOBBIntersectingOBB(
        s.MBBOrigin, s.MBBAngles, vector_origin, s.MBBSize,
        vector_origin, angle_zero, mins, maxs, Util.eps)
end

---Generator function to enumerate surfaces of the worldspawn and static props containing given AABB.
---Surfaces of brush entities are enumerated by Hash.CollectBrushEntities and Hash.CollectBrushModelSurfaces.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): ss.PaintableSurface
function Hash.CollectSurfaces(mins, maxs)
    mins = mins - vector_tenth
    maxs = maxs + vector_tenth
    return wrap(function()
        local hasSeenThisSurface = {} ---@type table<integer, true>
        for h in hashpairs(mins, maxs) do
            for _, i in ipairs(state.SurfaceHash[h] or {}) do
                if not hasSeenThisSurface[i] then
                    hasSeenThisSurface[i] = true
                    local s = PaintableSurface.Surfaces[i]
                    if isSurfaceIntersecting(s, mins, maxs) then
                        yield(s)
                    end
                end
            end
        end
    end)
end

---Generator function to enumerate surfaces of a brush model containing given AABB.
---@param modelIndex integer Index of the brush model obtained by Hash.CollectBrushEntities.
---@param mins       Vector  AABB minimum in the model's local coordinates.
---@param maxs       Vector  AABB maximum in the model's local coordinates.
---@return fun(): ss.PaintableSurface
function Hash.CollectBrushModelSurfaces(modelIndex, mins, maxs)
    mins = mins - vector_tenth
    maxs = maxs + vector_tenth
    return wrap(function()
        for _, s in ipairs(PaintableSurface.BrushModelSurfaces[modelIndex] or {}) do
            if isSurfaceIntersecting(s, mins, maxs) then
                yield(s)
            end
        end
    end)
end

---Generator function to enumerate brush entities with paintable surfaces near given AABB.
---@param mins Vector AABB minimum in world coordinates.
---@param maxs Vector AABB maximum in world coordinates.
---@return fun(): Entity, integer, VMatrix # The entity, its model index, and world-to-model transformation.
function Hash.CollectBrushEntities(mins, maxs)
    return wrap(function()
        for _, ent in ipairs(ents.FindInBox(mins, maxs)) do
            local n = tonumber((ent:GetModel() or ""):match "^%*(%d+)$")
            if n and PaintableSurface.BrushModelSurfaces[n + 1] then
                local worldToModel = ent:GetWorldTransformMatrix()
                worldToModel:InvertTR()
                yield(ent, n + 1, worldToModel)
            end
        end
    end)
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
    local minGridSize = state.Parameters.MinGridSizeDisplacement
    local numDivision = state.Parameters.NumDivisionsDisplacement
    local maxIndicesX = clamp(ceil(size.x / minGridSize), 1, numDivision)
    local maxIndicesY = clamp(ceil(size.y / minGridSize), 1, numDivision)
    local maxIndicesZ = clamp(ceil(size.z / minGridSize), 1, numDivision)
    local gridSize = size / numDivision
    OrderVectors(Util.vector_one * minGridSize, gridSize)
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
    local minGridSize = state.Parameters.MinGridSizeDisplacement
    local numDivision = state.Parameters.NumDivisionsDisplacement
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
                    -- local gridSize = (maxs - mins) / state.Parameters.NumDivisionsDisplacement
                    -- OrderVectors(Util.vector_one * state.Parameters.MinGridSizeDisplacement, gridSize)
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
function Hash.BuildDisplacementHash(surfaces)
    print("Constructing spatial hash table for displacement triangles...")
    for _, surf in ipairs(surfaces) do
        if surf.NumTriangles > 0 then
            local cells = {} ---@type table<integer, integer[]> Hash value + 1 --> indices of the triangles
            local v = surf.Vertices
            local numHashValues = 0
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
                    cells[h + 1] = cells[h + 1] or {}
                    cells[h + 1][#cells[h + 1] + 1] = i
                    numHashValues = math.max(h + 1, numHashValues)
                end
            end

            local hash = surf.TriangleHash
            hash.NumHashValues = numHashValues
            for k = 1, numHashValues do
                local indices = cells[k] or {}
                hash.FirstTriangleIndex[k] = #hash.TriangleIndices + 1
                hash.NumTriangleIndices[k] = #indices
                for _, i in ipairs(indices) do
                    hash.TriangleIndices[#hash.TriangleIndices + 1] = i
                end
            end

            hash.TotalTriangleIndices = #hash.TriangleIndices
        end
    end
end

---Generator function to enumerate triangles containing given AABB in a displacement.
---@param displacement ss.PaintableSurface The displacement to search.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): ss.DisplacementTriangle triangle An array of vertices.
function Hash.CollectDisplacementTriangles(displacement, mins, maxs)
    local hash = displacement.TriangleHash
    if not hash then return wrap(function() end) end
    mins = mins - vector_tenth
    maxs = maxs + vector_tenth
    return wrap(function()
        local hasSeenThisTriangle = {} ---@type table<integer, true>
        for h in hashpairsAABB(mins, maxs, displacement.AABBMin, displacement.AABBMax) do
            if h < hash.NumHashValues then
                local first = hash.FirstTriangleIndex[h + 1]
                for k = first, first + hash.NumTriangleIndices[h + 1] - 1 do
                    local i = hash.TriangleIndices[k]
                    if not hasSeenThisTriangle[i] then
                        hasSeenThisTriangle[i] = true
                        local t = displacement.Triangles[i]
                        -- debugoverlay.BoxAngles(
                        --     t.MBBOrigin, vector_origin, t.MBBSize, t.MBBAngles,
                        --     FrameTime() * 5, Color(255, 255, 255, 8))
                        if IsOBBIntersectingOBB(
                            t.MBBOrigin, t.MBBAngles, vector_origin, t.MBBSize,
                            vector_origin, angle_zero, mins, maxs, Util.eps) then
                            yield(t)
                        end
                    end
                end
            end
        end
    end)
end

return Hash
