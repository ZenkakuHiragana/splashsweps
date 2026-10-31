
-- Spatial hashing for better query performance of surfaces

---@class ss
local ss = SplashSWEPs
local Geometry         = ss.import "splashsweps/shared/geometry"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local PrecachedData    = ss.import "splashsweps/shared/typing/precachedata"

---@class ss.HashModule
local Hash = ss.module "splashsweps/shared/hash"

---A level of the grid of the world surfaces and static props, whose cells have the same size.
---@class ss.HashModule.Level
---@field CellSize number  The length of the sides of the cells.
---@field NumCells integer The number of the cells along each axis of the map.
---@field Cells    table<integer, integer[]> Hash value of a cell --> indices of the surfaces in PaintableSurface.Surfaces.

---@class ss.HashModule.State
---@field Levels     ss.HashModule.Level[] The levels that have surfaces, from the smallest cells.
---@field Parameters ss.PrecachedData.HashParameters
local state = ss.state("splashsweps/shared/hash", {
    Levels = {},
    Parameters = PrecachedData.HashParameters.new(),
}) ---@type ss.HashModule.State

local ceil = math.ceil
local clamp = math.Clamp
local floor = math.floor
local ipairs = ipairs
local max = math.max
local min = math.min
local QUERY_MARGIN = 0.1 -- Hammer units added around the AABB of queries
local MAP_SIZE = 32768   -- The map is within -16384 to 16384 along each axis.
local MIN_CELL_SIZE = 128
local NUM_LEVELS = 9     -- The cells of the largest level are as large as the map.

---Returns the center and the half extents of the box of a query, which is given AABB with QUERY_MARGIN around it.
---@param minX number
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
---@return number cx, number cy, number cz, number hx, number hy, number hz
local function queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    return (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5,
        (maxX - minX) * 0.5 + QUERY_MARGIN, (maxY - minY) * 0.5 + QUERY_MARGIN, (maxZ - minZ) * 0.5 + QUERY_MARGIN
end

---Returns the AABB the grid has a surface in: that of the surface,
---or that of the box of a static prop with ss.MARGIN_HAMMER_UNITS more around it.
---@param s ss.PaintableSurface
---@return number minX, number minY, number minZ, number maxX, number maxY, number maxZ
local function gridAABB(s)
    local m = s.StaticPropUnwrapIndex and ss.MARGIN_HAMMER_UNITS or 0
    return s.AABBMinX - m, s.AABBMinY - m, s.AABBMinZ - m, s.AABBMaxX + m, s.AABBMaxY + m, s.AABBMaxZ + m
end

---Returns the number of the level whose cells are at least half as long as given length, or the largest level.
---@param length number
---@return integer
local function levelOf(length)
    local n = 1
    while n < NUM_LEVELS and MIN_CELL_SIZE * 2 ^ n < length do
        n = n + 1
    end

    return n
end

---Returns the range of the cells of a level that given AABB overlaps.
---The cells at the ends of the map also contain the coordinates outside the map.
---@param level ss.HashModule.Level
---@param minX  number
---@param minY  number
---@param minZ  number
---@param maxX  number
---@param maxY  number
---@param maxZ  number
---@return integer x0, integer y0, integer z0, integer x1, integer y1, integer z1
local function cellRange(level, minX, minY, minZ, maxX, maxY, maxZ)
    local size, last, offset = level.CellSize, level.NumCells - 1, MAP_SIZE / 2
    return clamp(floor((minX + offset) / size), 0, last),
        clamp(floor((minY + offset) / size), 0, last),
        clamp(floor((minZ + offset) / size), 0, last),
        clamp(floor((maxX + offset) / size), 0, last),
        clamp(floor((maxY + offset) / size), 0, last),
        clamp(floor((maxZ + offset) / size), 0, last)
end

---Returns the hash value of a cell of a level.
---@param level ss.HashModule.Level
---@param x     integer
---@param y     integer
---@param z     integer
---@return integer
local function cellHash(level, x, y, z)
    local n = level.NumCells
    return x + y * n + z * n * n
end

---Sets the parameters read from the map cache, and builds the grid of the world surfaces and static props
---from PaintableSurface.Surfaces, which PaintableSurface.Setup and PaintableSurface.SetupStaticProps make first.
---
---The grid has levels whose cells are 128, 256, ..., 32768 hammer units long.
---A surface is in the cells of the level whose cells are at least half as long as the longest side of its AABB,
---so that it is in 27 cells at most. A static prop is in the grid once as the box of its 6 faces.
---@param parameters ss.PrecachedData.HashParameters
function Hash.Setup(parameters)
    state.Parameters = parameters
    local isBrushModelSurface = {} ---@type table<ss.PaintableSurface, true>
    for _, list in pairs(PaintableSurface.BrushModelSurfaces) do
        for _, s in ipairs(list) do
            isBrushModelSurface[s] = true
        end
    end

    local levels = {} ---@type table<integer, ss.HashModule.Level>
    local surfaces = PaintableSurface.Surfaces
    local i = 1
    while i <= #surfaces do
        local s = surfaces[i]
        if not isBrushModelSurface[s] then
            local minX, minY, minZ, maxX, maxY, maxZ = gridAABB(s)
            local n = levelOf(max(maxX - minX, maxY - minY, maxZ - minZ))
            local cellSize = MIN_CELL_SIZE * 2 ^ (n - 1)
            local level = levels[n] or { CellSize = cellSize, NumCells = MAP_SIZE / cellSize, Cells = {} }
            levels[n] = level
            local x0, y0, z0, x1, y1, z1 = cellRange(level, minX, minY, minZ, maxX, maxY, maxZ)
            for z = z0, z1 do
                for y = y0, y1 do
                    for x = x0, x1 do
                        local h = cellHash(level, x, y, z)
                        local list = level.Cells[h] or {}
                        level.Cells[h] = list
                        list[#list + 1] = i
                    end
                end
            end
        end

        -- The 6 faces of a static prop are next to each other, and the grid has the first one.
        i = i + (s.StaticPropUnwrapIndex and 6 or 1)
    end

    state.Levels = {}
    for n = 1, NUM_LEVELS do
        state.Levels[#state.Levels + 1] = levels[n]
    end
end

---Returns the indices of the surfaces the grid has near given AABB, whose AABBs in the grid overlap it, each once.
---@param minX number
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
---@return integer[]
local function surfacesNear(minX, minY, minZ, maxX, maxY, maxZ)
    local indices = {} ---@type integer[]
    local hasSeenThisSurface = {} ---@type table<integer, true>
    local surfaces = PaintableSurface.Surfaces
    for _, level in ipairs(state.Levels) do
        local x0, y0, z0, x1, y1, z1 = cellRange(level, minX, minY, minZ, maxX, maxY, maxZ)
        for z = z0, z1 do
            for y = y0, y1 do
                for x = x0, x1 do
                    local list = level.Cells[cellHash(level, x, y, z)]
                    if list then
                        for _, i in ipairs(list) do
                            if not hasSeenThisSurface[i] then
                                hasSeenThisSurface[i] = true
                                local aMinX, aMinY, aMinZ, aMaxX, aMaxY, aMaxZ = gridAABB(surfaces[i])
                                if aMinX <= maxX and aMaxX >= minX and aMinY <= maxY and aMaxY >= minY
                                and aMinZ <= maxZ and aMaxZ >= minZ then
                                    indices[#indices + 1] = i
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return indices
end

---Tests if the minimum bounding box of a surface intersects with the box of a query.
---@param s  ss.PaintableSurface
---@param cx number The center of the box of the query in the same coordinate system as the surface.
---@param cy number
---@param cz number
---@param hx number The half extents of the box of the query.
---@param hy number
---@param hz number
---@return boolean
local function isIntersecting(s, cx, cy, cz, hx, hy, hz)
    return Geometry.IsBoxIntersectingAABB(s.WorldToMBB, s.MBBSizeX, s.MBBSizeY, s.MBBSizeZ, cx, cy, cz, hx, hy, hz)
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

---Returns the surfaces of the worldspawn and static props whose minimum bounding boxes intersect given AABB with a small margin,
---except those whose AABBs in the grid do not.
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
    local result = {} ---@type ss.PaintableSurface[]
    local surfaces = PaintableSurface.Surfaces
    local cx, cy, cz, hx, hy, hz = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    for _, i in ipairs(surfacesNear(cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz)) do
        local s = surfaces[i]
        if s.StaticPropUnwrapIndex then
            -- The 6 faces of a static prop share the box.
            if isIntersecting(s, cx, cy, cz, hx, hy, hz) then
                for k = i, i + 5 do
                    if isFacing(surfaces[k], upX, upY, upZ, minCos) then
                        result[#result + 1] = surfaces[k]
                    end
                end
            end
        elseif isFacing(s, upX, upY, upZ, minCos) and isIntersecting(s, cx, cy, cz, hx, hy, hz) then
            result[#result + 1] = s
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
    local cx, cy, cz, hx, hy, hz = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    for _, s in ipairs(surfaces) do
        if isFacing(s, upX, upY, upZ, minCos) and isIntersecting(s, cx, cy, cz, hx, hy, hz) then
            result[#result + 1] = s
        end
    end

    return result
end

---Vectors reused for ents.FindInBox instead of creating them for each call.
---Discarded Vectors stay in the list of userdata that the atomic step of the GC walks at once until they are swept.
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

---Returns the triangles of a displacement that intersect given AABB with a small margin.
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
    local xs, ys, zs = displacement.PositionX, displacement.PositionY, displacement.PositionZ
    ---@cast xs -?
    ---@cast ys -?
    ---@cast zs -?
    local numHashValues = hash.NumHashValues
    local firstTriangleIndex = hash.FirstTriangleIndex ---@cast firstTriangleIndex -?
    local numTriangleIndices = hash.NumTriangleIndices ---@cast numTriangleIndices -?
    local triangleIndices = hash.TriangleIndices ---@cast triangleIndices -?
    local hasSeenThisTriangle = {} ---@type table<integer, true>
    local grid = displacementGrid(
        displacement.AABBMinX, displacement.AABBMinY, displacement.AABBMinZ,
        displacement.AABBMaxX, displacement.AABBMaxY, displacement.AABBMaxZ)
    local cx, cy, cz, hx, hy, hz = queryBox(minX, minY, minZ, maxX, maxY, maxZ)
    local x0, y0, z0, x1, y1, z1 = cellRangeAABB(grid, cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz)
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
                            local a, b, c = t.VertexIndex1, t.VertexIndex2, t.VertexIndex3
                            if Geometry.IsTriangleIntersectingAABB(
                                xs[a], ys[a], zs[a], xs[b], ys[b], zs[b], xs[c], ys[c], zs[c], cx, cy, cz, hx, hy, hz) then
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
