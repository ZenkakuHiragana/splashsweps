
---@class ss
local ss = SplashSWEPs
if not ss then return end

-- Spatial hashing for better query performance of surfaces

local dot = Vector().Dot
local floor = math.floor
local ipairs = ipairs
local wrap = coroutine.wrap
local yield = coroutine.yield
local angle_zero = angle_zero
local vector_origin = vector_origin
local vector_one = ss.vector_one
local vector_tenth = vector_one * 0.1
local vector_16384 = vector_one * 16384
local GRID_SIZE = 128
local MAX_COS_DIFF = math.cos(math.rad(45))
local MAX_GRID_INDEX = 32768 / GRID_SIZE
local MAX_GRID_INDEX_SQR = MAX_GRID_INDEX * MAX_GRID_INDEX

---Converts real number coordinate to rough coordinate.
---@param pos Vector
---@return number x Rough coordinate X.
---@return number y Rough coordinate Y.
---@return number z Rough coordinate Z.
local function posToGrid(pos)
    pos = (pos + vector_16384) / GRID_SIZE
    return floor(pos.x), floor(pos.y), floor(pos.z)
end

---Calculates hash code from x, y, and z coordinates.
---@param x integer Rough coordinate which can be obtained from posToGrid(x: number).
---@param y integer Rough coordinate which can be obtained from posToGrid(y: number).
---@param z integer Rough coordinate which can be obtained from posToGrid(z: number).
---@return integer
local function gridToHash(x, y, z)
    return x + y * MAX_GRID_INDEX + z * MAX_GRID_INDEX_SQR
end

---Generator function that produces hash integers to look-up the surfaces within given AABB.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@return fun(): number # Generator function.
local function hashpairs(mins, maxs)
    local x0, y0, z0 = posToGrid(mins)
    local x1, y1, z1 = posToGrid(maxs)
    return wrap(function()
        for z = z0, z1 do
            for y = y0, y1 do
                for x = x0, x1 do
                    -- local gmin = Vector(x, y, z) * GRID_SIZE - vector_16384
                    -- local gmax = gmin + vector_one * GRID_SIZE
                    -- debugoverlay.Box(Vector(), gmin, gmax, FrameTime() * 20, Color(0, 255, 0, 16))
                    yield(gridToHash(x, y, z))
                end
            end
        end
    end)
end

---Generates look-up table for ss.SurfaceArray to find surfaces faster.
function ss.GenerateHashTable()
    for i, s in ipairs(ss.SurfaceArray) do
        for h in hashpairs(s.AABBMin, s.AABBMax) do
            ss.SurfaceHash[h] = ss.SurfaceHash[h] or {}
            ss.SurfaceHash[h][#ss.SurfaceHash[h] + 1] = i
        end
    end
end

---Generator function to enumerate surfaces containing given AABB and facing given normal.
---@param mins Vector AABB minimum.
---@param maxs Vector AABB maximum.
---@param normal Vector? Optional normal vector to filter out surfaces.
---@return fun(): ss.PaintableSurface
function ss.CollectSurfaces(mins, maxs, normal)
    return wrap(function()
        for h in hashpairs(mins - vector_tenth, maxs + vector_tenth) do
            for _, i in ipairs(ss.SurfaceHash[h] or {}) do
                local s = ss.SurfaceArray[i]
                if util.IsOBBIntersectingOBB(
                    vector_origin, angle_zero, s.AABBMin, s.AABBMax,
                    vector_origin, angle_zero, mins, maxs, ss.eps)
                    and (not normal or dot(s.Normal, normal) > MAX_COS_DIFF) then
                    yield(s)
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
    local mins = Vector(posToGrid(pos)) * GRID_SIZE - vector_16384
    local maxs = mins + vector_one * GRID_SIZE
    return mins, maxs
end
