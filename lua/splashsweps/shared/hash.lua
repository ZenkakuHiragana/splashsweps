
-- Spatial hashing for better query performance of surfaces

---@class ss
local ss = SplashSWEPs
local Geometry         = ss.import "splashsweps/shared/geometry"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"
local Util             = ss.import "splashsweps/shared/util"

---@class ss.HashModule
local Hash = ss.module "splashsweps/shared/hash"

---@class ss.HashModule.State
---@field SurfaceHash ss.PrecachedData.SurfaceHash The spatial hash of the world surfaces.
---@field CellIndices table<integer, integer>      Hash value --> index of the cell in the arrays of SurfaceHash.
---@field Parameters  ss.PrecachedData.HashParameters
local state = ss.state("splashsweps/shared/hash", {
    SurfaceHash = PrecachedData.SurfaceHash.new(),
    CellIndices = {},
    Parameters = PrecachedData.HashParameters.new(),
}) ---@type ss.HashModule.State

---Sets the spatial hash of the world surfaces and the parameters, both read from the map cache.
---@param surfaceHash ss.PrecachedData.SurfaceHash
---@param parameters  ss.PrecachedData.HashParameters
function Hash.Setup(surfaceHash, parameters)
    local cellIndices = {} ---@type table<integer, integer>
    for k, h in ipairs(surfaceHash.HashValues or {}) do
        cellIndices[h] = k
    end

    state.SurfaceHash = surfaceHash
    state.CellIndices = cellIndices
    state.Parameters = parameters
end

local ceil = math.ceil
local clamp = math.Clamp
local floor = math.floor
local ipairs = ipairs
local max = math.max
local min = math.min
local IsOBBIntersectingOBB = util.IsOBBIntersectingOBB
local angle_zero = angle_zero
local vector_origin = vector_origin
local QUERY_MARGIN = 0.1 -- Hammer units added around the AABB of queries
local GRID_SIZE = 128
local MAX_GRID_INDEX = 32768 / GRID_SIZE
local MAX_GRID_INDEX_SQR = MAX_GRID_INDEX * MAX_GRID_INDEX

---Converts a real number coordinate to a rough coordinate.
---@param x number
---@return integer
local function toIndex(x)
    return floor((x + 16384) / GRID_SIZE)
end

---Calculates hash code from x, y, and z coordinates.
---@param x integer Rough coordinate which can be obtained from posToGrid(x: number).
---@param y integer Rough coordinate which can be obtained from posToGrid(y: number).
---@param z integer Rough coordinate which can be obtained from posToGrid(z: number).
---@return integer
local function indexToHash(x, y, z)
    return x + y * MAX_GRID_INDEX + z * MAX_GRID_INDEX_SQR
end

---Returns the range of rough coordinates of the cells within given AABB,
---which indexToHash(x, y, z) converts into the hash integers to look-up the surfaces.
---@param minX number AABB minimum.
---@param minY number
---@param minZ number
---@param maxX number AABB maximum.
---@param maxY number
---@param maxZ number
---@return integer x0, integer y0, integer z0, integer x1, integer y1, integer z1
local function hashRange(minX, minY, minZ, maxX, maxY, maxZ)
    return toIndex(minX), toIndex(minY), toIndex(minZ), toIndex(maxX), toIndex(maxY), toIndex(maxZ)
end

---Adds the index of a surface to the cells of the hash within given AABB.
---@param hash table<integer, integer[]> Hash value --> indices of the surfaces.
---@param i    integer The index of the surface.
---@param minX number  AABB minimum.
---@param minY number
---@param minZ number
---@param maxX number  AABB maximum.
---@param maxY number
---@param maxZ number
local function addToHash(hash, i, minX, minY, minZ, maxX, maxY, maxZ)
    local x0, y0, z0, x1, y1, z1 = hashRange(minX, minY, minZ, maxX, maxY, maxZ)
    for z = z0, z1 do
        for y = y0, y1 do
            for x = x0, x1 do
                local h = indexToHash(x, y, z)
                hash[h] = hash[h] or {}
                hash[h][#hash[h] + 1] = i
            end
        end
    end
end

---Generates look-up table for spatial partitioning to find surfaces faster.
---@param surfaces    ss.PrecachedData.Surface[]    The source array.
---@param staticProps ss.PrecachedData.StaticProp[] List of static props.
---@return ss.PrecachedData.SurfaceHash # The spatial hash given to Hash.Setup.
function Hash.BuildSurfaceHash(surfaces, staticProps)
    print("Constructing spatial hash table for paintable surfaces...")
    local hash = {} ---@type table<integer, integer[]>
    for i, s in ipairs(surfaces) do
        if s.ModelIndex == 1 then
            addToHash(hash, i, s.AABBMinX, s.AABBMinY, s.AABBMinZ, s.AABBMaxX, s.AABBMaxY, s.AABBMaxZ)
        end
    end

    for i, s in ipairs(staticProps) do
        -- World AABB of the rotated OBB, plus the margin as the other surfaces have
        local minX, minY, minZ, maxX, maxY, maxZ = Geometry.TransformAABB(
            Geometry.FromAngles(s.Pitch, s.Yaw, s.Roll, s.PositionX, s.PositionY, s.PositionZ),
            s.BoundsMinX, s.BoundsMinY, s.BoundsMinZ, s.BoundsMaxX, s.BoundsMaxY, s.BoundsMaxZ)
        local margin = ss.MARGIN_HAMMER_UNITS
        for j = 1, 6 do
            addToHash(hash, #surfaces + 6 * (i - 1) + j,
                minX - margin, minY - margin, minZ - margin,
                maxX + margin, maxY + margin, maxZ + margin)
        end
    end

    local surfaceHash = PrecachedData.SurfaceHash.new()
    local hashValues = surfaceHash.HashValues ---@cast hashValues -?
    local firstSurfaceIndex = surfaceHash.FirstSurfaceIndex ---@cast firstSurfaceIndex -?
    local numSurfaceIndices = surfaceHash.NumSurfaceIndices ---@cast numSurfaceIndices -?
    local surfaceIndices = surfaceHash.SurfaceIndices ---@cast surfaceIndices -?
    for h, indices in pairs(hash) do
        local k = #hashValues + 1
        hashValues[k] = h
        firstSurfaceIndex[k] = #surfaceIndices + 1
        numSurfaceIndices[k] = #indices
        for _, i in ipairs(indices) do
            surfaceIndices[#surfaceIndices + 1] = i
        end
    end

    surfaceHash.NumHashValues = #hashValues
    surfaceHash.TotalSurfaceIndices = #surfaceIndices
    return surfaceHash
end

---Vectors reused for the queries instead of creating them for each query.
---Discarded Vectors stay in the list of userdata that the atomic step of the GC walks at once until they are swept,
---and the step got longer when they were created for each query.
local queryMins, queryMaxs = Vector(), Vector()

---Sets the AABB of a query with the margin into the Vectors which util.IsOBBIntersectingOBB takes.
---The Vectors are shared and overwritten by the next call, so use them before calling this again.
---@param minX number
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
---@return Vector mins
---@return Vector maxs
local function queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    queryMins:SetUnpacked(minX - QUERY_MARGIN, minY - QUERY_MARGIN, minZ - QUERY_MARGIN)
    queryMaxs:SetUnpacked(maxX + QUERY_MARGIN, maxY + QUERY_MARGIN, maxZ + QUERY_MARGIN)
    return queryMins, queryMaxs
end

---Tests if the minimum bounding box of the surface intersects with given AABB.
---@param s    ss.IHasMBB
---@param mins Vector AABB minimum in the same coordinate system as the surface.
---@param maxs Vector AABB maximum in the same coordinate system as the surface.
---@return boolean
local function isIntersecting(s, mins, maxs)
    return IsOBBIntersectingOBB(
        s.MBBOrigin, s.MBBAngles, vector_origin, s.MBBSize,
        vector_origin, angle_zero, mins, maxs, Util.eps)
end

---Tests if a surface faces the direction closely enough.
---Displacements always pass because their triangles have their own normals.
---@param s      ss.PaintableSurface
---@param upX    number? The unit vector to compare with the normal of the surface, required if minCos is given.
---@param upY    number?
---@param upZ    number?
---@param minCos number? The minimum cosine of the angle between them, or nil to pass any surface.
---@return boolean
local function isFacing(s, upX, upY, upZ, minCos)
    return not minCos or s.Triangles ~= nil
        or upX * s.NormalX + upY * s.NormalY + upZ * s.NormalZ > minCos
end

---Returns the surfaces of the worldspawn and static props
---whose minimum bounding boxes intersect given AABB with a small margin.
---Surfaces of brush entities are collected by Hash.CollectBrushEntities and Hash.CollectBrushModelSurfaces.
---If minCos is given, the surfaces except displacements are also filtered by their normals.
---@param minX   number  AABB minimum.
---@param minY   number
---@param minZ   number
---@param maxX   number  AABB maximum.
---@param maxY   number
---@param maxZ   number
---@param upX    number? The unit vector the normals are compared with, required if minCos is given.
---@param upY    number?
---@param upZ    number?
---@param minCos number? The minimum cosine of the angle between the normal and the vector, or nil to skip the test.
---@return ss.PaintableSurface[]
function Hash.CollectSurfaces(minX, minY, minZ, maxX, maxY, maxZ, upX, upY, upZ, minCos)
    local mins, maxs = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    local result = {} ---@type ss.PaintableSurface[]
    local hasSeenThisSurface = {} ---@type table<integer, true>
    local surfaceHash = state.SurfaceHash
    local cellIndices = state.CellIndices
    local surfaces = PaintableSurface.Surfaces
    local x0, y0, z0, x1, y1, z1 = hashRange(
        minX - QUERY_MARGIN, minY - QUERY_MARGIN, minZ - QUERY_MARGIN,
        maxX + QUERY_MARGIN, maxY + QUERY_MARGIN, maxZ + QUERY_MARGIN)
    for z = z0, z1 do
        for y = y0, y1 do
            for x = x0, x1 do
                local k = cellIndices[indexToHash(x, y, z)]
                local first = k and surfaceHash.FirstSurfaceIndex[k] or 1
                local last = k and first + surfaceHash.NumSurfaceIndices[k] - 1 or 0
                for j = first, last do
                    local i = surfaceHash.SurfaceIndices[j]
                    if not hasSeenThisSurface[i] then
                        hasSeenThisSurface[i] = true
                        local s = surfaces[i]
                        if isFacing(s, upX, upY, upZ, minCos) and isIntersecting(s, mins, maxs) then
                            result[#result + 1] = s
                        end
                    end
                end
            end
        end
    end

    return result
end

---Returns the surfaces of a brush model whose minimum bounding boxes intersect given AABB with a small margin.
---If minCos is given, the surfaces are also filtered by their normals.
---@param modelIndex integer Index of the brush model obtained by Hash.CollectBrushEntities.
---@param minX       number  AABB minimum in the model's local coordinates.
---@param minY       number
---@param minZ       number
---@param maxX       number  AABB maximum in the model's local coordinates.
---@param maxY       number
---@param maxZ       number
---@param upX        number? The unit vector the normals are compared with in the model's local coordinates, required if minCos is given.
---@param upY        number?
---@param upZ        number?
---@param minCos     number? The minimum cosine of the angle between the normal and the vector, or nil to skip the test.
---@return ss.PaintableSurface[]
function Hash.CollectBrushModelSurfaces(modelIndex, minX, minY, minZ, maxX, maxY, maxZ, upX, upY, upZ, minCos)
    local result = {} ---@type ss.PaintableSurface[]
    local surfaces = PaintableSurface.BrushModelSurfaces[modelIndex]
    if not surfaces then return result end
    local mins, maxs = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    for i = 1, #surfaces do
        local s = surfaces[i]
        if isFacing(s, upX, upY, upZ, minCos) and isIntersecting(s, mins, maxs) then
            result[#result + 1] = s
        end
    end

    return result
end

---Vectors reused for ents.FindInBox instead of creating them for each call, as the ones for the queries.
local findMins, findMaxs = Vector(), Vector()

---Returns the brush entities with paintable surfaces near given AABB,
---as the arrays of the entities, their model indices, and the transforms from the world to the models.
---@param minX number AABB minimum in world coordinates.
---@param minY number
---@param minZ number
---@param maxX number AABB maximum in world coordinates.
---@param maxY number
---@param maxZ number
---@return Entity[] entities
---@return integer[] modelIndices
---@return number[][] worldToModels
function Hash.CollectBrushEntities(minX, minY, minZ, maxX, maxY, maxZ)
    local entities = {} ---@type Entity[]
    local modelIndices = {} ---@type integer[]
    local worldToModels = {} ---@type number[][]
    findMins:SetUnpacked(minX, minY, minZ)
    findMaxs:SetUnpacked(maxX, maxY, maxZ)
    for _, ent in ipairs(ents.FindInBox(findMins, findMaxs)) do
        local n = tonumber((ent:GetModel() or ""):match "^%*(%d+)$")
        if n and PaintableSurface.BrushModelSurfaces[n + 1] then
            -- The first 12 of the 16 values are the transform.
            local modelToWorld = { ent:GetWorldTransformMatrix():Unpack() }
            local k = #entities + 1
            entities[k] = ent
            modelIndices[k] = n + 1
            worldToModels[k] = Geometry.InvertRotationTranslation(modelToWorld)
        end
    end

    return entities, modelIndices, worldToModels
end

---The grid of the spatial hash of a displacement, which divides its AABB.
---@class ss.Hash.DisplacementGrid
---@field MinX      number The AABB minimum.
---@field MinY      number
---@field MinZ      number
---@field CellSizeX number
---@field CellSizeY number
---@field CellSizeZ number
---@field NumCellsX integer
---@field NumCellsY integer
---@field NumCellsZ integer

---Divides the AABB of a displacement into the grid of its spatial hash.
---The cells are at least MinGridSizeDisplacement long, and each side has at most NumDivisionsDisplacement of them.
---@param minX number The AABB minimum.
---@param minY number
---@param minZ number
---@param maxX number The AABB maximum.
---@param maxY number
---@param maxZ number
---@return ss.Hash.DisplacementGrid
local function displacementGrid(minX, minY, minZ, maxX, maxY, maxZ)
    local minCellSize = state.Parameters.MinGridSizeDisplacement
    local numDivisions = state.Parameters.NumDivisionsDisplacement
    local sizeX, sizeY, sizeZ = maxX - minX, maxY - minY, maxZ - minZ
    return {
        MinX = minX,
        MinY = minY,
        MinZ = minZ,
        CellSizeX = max(sizeX / numDivisions, minCellSize),
        CellSizeY = max(sizeY / numDivisions, minCellSize),
        CellSizeZ = max(sizeZ / numDivisions, minCellSize),
        NumCellsX = clamp(ceil(sizeX / minCellSize), 1, numDivisions),
        NumCellsY = clamp(ceil(sizeY / minCellSize), 1, numDivisions),
        NumCellsZ = clamp(ceil(sizeZ / minCellSize), 1, numDivisions),
    }
end

---Calculates the hash integer of a cell of a displacement from its coordinates in the grid.
---@param grid ss.Hash.DisplacementGrid
---@param x    integer
---@param y    integer
---@param z    integer
---@return integer
local function cellToHash(grid, x, y, z)
    return x + y * grid.NumCellsX + z * grid.NumCellsX * grid.NumCellsY
end

---Returns the range of the coordinates of the cells of a displacement within given AABB,
---which cellToHash converts into the hash integers to look-up the triangles.
---@param grid ss.Hash.DisplacementGrid
---@param minX number Minimum of the AABB query.
---@param minY number
---@param minZ number
---@param maxX number Maximum of the AABB query.
---@param maxY number
---@param maxZ number
---@return integer x0, integer y0, integer z0, integer x1, integer y1, integer z1
local function cellRangeAABB(grid, minX, minY, minZ, maxX, maxY, maxZ)
    local numX, numY, numZ = grid.NumCellsX, grid.NumCellsY, grid.NumCellsZ
    return clamp(floor((minX - grid.MinX) / grid.CellSizeX), 0, numX - 1),
           clamp(floor((minY - grid.MinY) / grid.CellSizeY), 0, numY - 1),
           clamp(floor((minZ - grid.MinZ) / grid.CellSizeZ), 0, numZ - 1),
           clamp(floor((maxX - grid.MinX) / grid.CellSizeX), 0, numX - 1),
           clamp(floor((maxY - grid.MinY) / grid.CellSizeY), 0, numY - 1),
           clamp(floor((maxZ - grid.MinZ) / grid.CellSizeZ), 0, numZ - 1)
end

---Generates look-up table for spatial partitioning to find triangles of displacement faster.
---@param surfaces ss.PrecachedData.Surface[] The source displacement.
function Hash.BuildDisplacementHash(surfaces)
    print("Constructing spatial hash table for displacement triangles...")
    for _, surf in ipairs(surfaces) do
        if surf.NumDisplacementTriangles > 0 then
            local cells = {} ---@type table<integer, integer[]> Hash value + 1 --> indices of the triangles
            local x, y, z = surf.PositionX, surf.PositionY, surf.PositionZ
            local vertexIndices = surf.VertexIndices
            local grid = displacementGrid(
                surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ, surf.AABBMaxX, surf.AABBMaxY, surf.AABBMaxZ)
            local numHashValues = 0
            for i = 1, surf.NumDisplacementTriangles do
                local a = vertexIndices[3 * i - 2]
                local b = vertexIndices[3 * i - 1]
                local c = vertexIndices[3 * i]
                local x0, y0, z0, x1, y1, z1 = cellRangeAABB(grid,
                    min(x[a], x[b], x[c]), min(y[a], y[b], y[c]), min(z[a], z[b], z[c]),
                    max(x[a], x[b], x[c]), max(y[a], y[b], y[c]), max(z[a], z[b], z[c]))
                for cz = z0, z1 do
                    for cy = y0, y1 do
                        for cx = x0, x1 do
                            local h = cellToHash(grid, cx, cy, cz)
                            cells[h + 1] = cells[h + 1] or {}
                            cells[h + 1][#cells[h + 1] + 1] = i
                            numHashValues = math.max(h + 1, numHashValues)
                        end
                    end
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

---Returns the triangles of a displacement whose minimum bounding boxes intersect given AABB with a small margin.
---@param displacement ss.PaintableSurface The displacement to search.
---@param minX number AABB minimum.
---@param minY number
---@param minZ number
---@param maxX number AABB maximum.
---@param maxY number
---@param maxZ number
---@return ss.DisplacementTriangle[]
function Hash.CollectDisplacementTriangles(displacement, minX, minY, minZ, maxX, maxY, maxZ)
    local result = {} ---@type ss.DisplacementTriangle[]
    local hash = displacement.TriangleHash
    if not hash then return result end
    local triangles = displacement.Triangles ---@cast triangles -?
    local mins, maxs = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    local hasSeenThisTriangle = {} ---@type table<integer, true>
    local grid = displacementGrid(
        displacement.AABBMinX, displacement.AABBMinY, displacement.AABBMinZ,
        displacement.AABBMaxX, displacement.AABBMaxY, displacement.AABBMaxZ)
    local numHashValues = hash.NumHashValues
    local firstTriangleIndex = hash.FirstTriangleIndex ---@cast firstTriangleIndex -?
    local numTriangleIndices = hash.NumTriangleIndices ---@cast numTriangleIndices -?
    local triangleIndices = hash.TriangleIndices ---@cast triangleIndices -?
    local x0, y0, z0, x1, y1, z1 = cellRangeAABB(grid,
        minX - QUERY_MARGIN, minY - QUERY_MARGIN, minZ - QUERY_MARGIN,
        maxX + QUERY_MARGIN, maxY + QUERY_MARGIN, maxZ + QUERY_MARGIN)
    for z = z0, z1 do
        for y = y0, y1 do
            for x = x0, x1 do
                local h = cellToHash(grid, x, y, z)
                if h < numHashValues then
                    local first = firstTriangleIndex[h + 1]
                    for k = first, first + numTriangleIndices[h + 1] - 1 do
                        local i = triangleIndices[k]
                        if not hasSeenThisTriangle[i] then
                            hasSeenThisTriangle[i] = true
                            local t = triangles[i]
                            if isIntersecting(t, mins, maxs) then
                                result[#result + 1] = t
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

return Hash
