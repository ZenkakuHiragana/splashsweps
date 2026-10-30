
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Geometry         = ss.import "splashsweps/shared/geometry"
local Hash             = ss.import "splashsweps/shared/hash"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local Players          = ss.import "splashsweps/shared/players"

-- Check if a player is on ink for every this seconds
local InkCheckInterval = 1 / 20

---CurTime() based time to perform traces to check player's ink state.
local NextCheckTime = ss.state("splashsweps/shared/touch/player", {}) ---@type table<Player, number>

local IDENTITY = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
}

---Returns the origin of a transform of ss.GeometryModule for debugoverlay.
---@param m number[]
---@return Vector
local function OriginOf(m)
    return Vector(m[4], m[8], m[12])
end

---Returns the angles of a transform of ss.GeometryModule for debugoverlay.
---@param m number[]
---@return Angle
local function AnglesOf(m)
    return Angle(Geometry.ToAngles(m))
end

---Draws bounding boxes and the grid origin of a surface.
---@param surf    ss.PaintableSurface
---@param toWorld number[] Transform from the surface's coordinate system to the world.
---@param t       number   Duration of the overlay.
local function DrawSurfaceBounds(surf, toWorld, t)
    local mbbToWorld = Geometry.Multiply(toWorld, Geometry.FromAngles(
        surf.MBBAngles.pitch, surf.MBBAngles.yaw, surf.MBBAngles.roll, surf.MBBOrigin:Unpack()))
    local gridToWorld = Geometry.Multiply(toWorld, Geometry.InvertRotationTranslation(surf.WorldToLocalGrid))
    local width = surf.Grid.Width * PaintableGrid.CELL_SIZE
    local height = surf.Grid.Height * PaintableGrid.CELL_SIZE
    local size = Vector(width, height)
    debugoverlay.BoxAngles(OriginOf(toWorld),
        Vector(surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ),
        Vector(surf.AABBMaxX, surf.AABBMaxY, surf.AABBMaxZ), AnglesOf(toWorld), t, color_transparent)
    debugoverlay.BoxAngles(OriginOf(mbbToWorld) + vector_up, vector_origin, surf.MBBSize, AnglesOf(mbbToWorld), t, Color(255, 255, 160, 2))
    debugoverlay.BoxAngles(OriginOf(gridToWorld), vector_origin, size, AnglesOf(gridToWorld), t, Color(0, 255, 0, 0))
end

---Draws the nearest point on a flat surface from the query point.
---@param surf         ss.PaintableSurface
---@param toWorld      number[] Transform from the surface's coordinate system to the world.
---@param worldToLocal number[] Transform from the world to the surface's coordinate system.
---@param nearestFrom  Vector   The query point in world coordinates.
---@param t            number   Duration of the overlay.
local function DrawNearestOnFlatSurface(surf, toWorld, worldToLocal, nearestFrom, t)
    local gridX, gridY = Geometry.TransformPoint(surf.WorldToLocalGrid,
        Geometry.TransformPoint(worldToLocal, nearestFrom:Unpack()))
    if not (gridX < 0 or gridX > surf.Grid.Width * PaintableGrid.CELL_SIZE
    or gridY < 0 or gridY > surf.Grid.Height * PaintableGrid.CELL_SIZE) then
        local gridToWorld = Geometry.Multiply(toWorld, Geometry.InvertRotationTranslation(surf.WorldToLocalGrid))
        local nearest = Vector(Geometry.TransformPoint(gridToWorld, gridX, gridY, 0))
        debugoverlay.Cross(nearest, 10, t, Color(255, 255, 0), true)
        debugoverlay.Line(nearestFrom, nearest, t, Color(255, 255, 0), true)
    end
end

---Returns a vertex of a displacement for debugoverlay.
---@param xs number[]
---@param ys number[]
---@param zs number[]
---@param k  integer
---@return Vector
local function VertexOf(xs, ys, zs, k)
    return Vector(xs[k], ys[k], zs[k])
end

local lastTrace ---@type Structure.TraceResult
local lastAim = Vector()
hook.Add("Move", "SplashSWEPs: Check if players are on ink", function(ply, mv)
    if not Players.Indices[ply] then return end

    local index = Players.Indices[ply] - 1
    local timeOffset = index / player.GetCount() * InkCheckInterval
    if not NextCheckTime[ply] then NextCheckTime[ply] = CurTime() end
    if CurTime() < NextCheckTime[ply] + timeOffset then return end
    NextCheckTime[ply] = CurTime() + InkCheckInterval

    local tr = ply:GetEyeTrace()
    local aim = lastAim
    local track = ply:KeyDown(IN_ATTACK2)
    if track then
        lastTrace = tr
        lastAim = ply:GetAimVector()
    else
        tr = lastTrace or tr
    end

    local origin = mv:GetOrigin() + ply:GetForward() * 2
    local nearestFrom = ply:WorldSpaceCenter() + ply:GetForward() * 2
    -- local origin = tr.HitPos
    -- local nearestFrom = origin + tr.HitNormal * 200
    local queryMins = origin + ply:OBBMins()
    local queryMaxs = origin + ply:OBBMaxs()
    -- queryMins = origin - Vector(500, 500, 500)
    -- queryMaxs = origin + Vector(500, 500, 500)
    local minX, minY, minZ = queryMins:Unpack()
    local maxX, maxY, maxZ = queryMaxs:Unpack()

    local t = InkCheckInterval + FrameTime() * 2
    debugoverlay.Cross(nearestFrom, 10, t, Color(255, 255, 0), true)

    for _, surf in ipairs(Hash.CollectSurfaces(minX, minY, minZ, maxX, maxY, maxZ)) do
        DrawSurfaceBounds(surf, IDENTITY, t)
        if surf.Triangles then
            local xs, ys, zs = surf.PositionX, surf.PositionY, surf.PositionZ
            local oxs, oys, ozs = surf.PaintOriginX, surf.PaintOriginY, surf.PaintOriginZ
            ---@cast xs -?
            ---@cast ys -?
            ---@cast zs -?
            ---@cast oxs -?
            ---@cast oys -?
            ---@cast ozs -?
            for _, tri in ipairs(Hash.CollectDisplacementTriangles(surf, minX, minY, minZ, maxX, maxY, maxZ)) do
            -- for _, tri in ipairs(surf.Triangles) do
                local i1, i2, i3 = tri.VertexIndex1, tri.VertexIndex2, tri.VertexIndex3
                local d = Vector(tri.NormalX, tri.NormalY, tri.NormalZ) * 0.5
                local p1, p2, p3 = VertexOf(xs, ys, zs, i1) + d, VertexOf(xs, ys, zs, i2) + d, VertexOf(xs, ys, zs, i3) + d
                local o1, o2, o3 = VertexOf(oxs, oys, ozs, i1) + d, VertexOf(oxs, oys, ozs, i2) + d, VertexOf(oxs, oys, ozs, i3) + d
                debugoverlay.BoxAngles(
                    tri.MBBOrigin, vector_origin,
                    tri.MBBSize, tri.MBBAngles, t, Color(255, 255, 255, 0))

                debugoverlay.Line(p1, p2, t, Color(255, 255, 0, 64))
                debugoverlay.Line(p2, p3, t, Color(255, 255, 0, 64))
                debugoverlay.Line(p3, p1, t, Color(255, 255, 0, 64))

                debugoverlay.Line(o1, o2, t, Color(192, 96, 0), true)
                debugoverlay.Line(o2, o3, t, Color(192, 96, 0), true)
                debugoverlay.Line(o3, o1, t, Color(192, 96, 0), true)

                debugoverlay.Line(p1, o1, t, Color(128, 128, 0), true)
                debugoverlay.Line(p2, o2, t, Color(128, 128, 0), true)
                debugoverlay.Line(p3, o3, t, Color(128, 128, 0), true)

                local b1, b2, b3 = PaintableSurface.BarycentricCoordinates(tri, nearestFrom:Unpack())
                if b1 > 0 and b2 > 0 and b3 > 0 then
                    local nearest = (p1 * b1 + p2 * b2 + p3 * b3) - d
                    debugoverlay.Line(nearestFrom, LerpVector(20 / nearest:Distance(nearestFrom), nearest, nearestFrom), t, Color(255, 255, 0), true)

                    local mapped = (o1 * b1 + o2 * b2 + o3 * b3) - d
                    local hitang = aim:Cross(-tr.HitNormal):Cross(tr.HitNormal):AngleEx(tr.HitNormal)
                    local mappedAngles = AnglesOf(Geometry.Multiply(tri.WorldToLocalGridRotation,
                        Geometry.FromAngles(hitang.pitch, hitang.yaw, hitang.roll, 0, 0, 0)))

                    debugoverlay.Axis(nearest, hitang, 20, t, true)
                    debugoverlay.Axis(mapped, mappedAngles, 20, t, true)
                    debugoverlay.Line(nearest, mapped, t, Color(0, 255, 255), true)
                end
            end
        else
            DrawNearestOnFlatSurface(surf, IDENTITY, IDENTITY, nearestFrom, t)
        end
    end

    -- Brush models have no displacements, so their surfaces are always flat.
    local _, modelIndices, worldToModels = Hash.CollectBrushEntities(minX, minY, minZ, maxX, maxY, maxZ)
    for k, modelIndex in ipairs(modelIndices) do
        local worldToModel = worldToModels[k]
        local modelToWorld = Geometry.InvertRotationTranslation(worldToModel)
        for _, surf in ipairs(Hash.CollectBrushModelSurfaces(modelIndex,
            Geometry.TransformAABB(worldToModel, minX, minY, minZ, maxX, maxY, maxZ))) do
            DrawSurfaceBounds(surf, modelToWorld, t)
            DrawNearestOnFlatSurface(surf, modelToWorld, worldToModel, nearestFrom, t)
        end
    end
end)

if CLIENT then return end
hook.Add("SplashSWEPs: PlayerDisconnected", "Cleanup InkCheckInterval for players", function(ply)
    NextCheckTime[ply] = nil
end)
