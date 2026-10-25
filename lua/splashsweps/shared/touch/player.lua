
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Hash             = ss.import "splashsweps/shared/hash"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local Players          = ss.import "splashsweps/shared/players"
local Util             = ss.import "splashsweps/shared/util"

-- Check if a player is on ink for every this seconds
local InkCheckInterval = 1 / 20

---CurTime() based time to perform traces to check player's ink state.
local NextCheckTime = ss.state("splashsweps/shared/touch/player", {}) ---@type table<Player, number>

local identity = Matrix()

---Draws bounding boxes and the grid origin of a surface.
---@param surf    ss.PaintableSurface
---@param toWorld VMatrix Transformation from the surface's coordinate system to the world.
---@param t       number  Duration of the overlay.
local function DrawSurfaceBounds(surf, toWorld, t)
    local mbb = Matrix()
    mbb:SetTranslation(surf.MBBOrigin)
    mbb:SetAngles(surf.MBBAngles)
    mbb = toWorld * mbb
    local m = toWorld * surf.WorldToLocalGridMatrix:GetInverseTR()
    local width = surf.Grid.Width * PaintableGrid.CELL_SIZE
    local height = surf.Grid.Height * PaintableGrid.CELL_SIZE
    local size = Vector(width, height)
    debugoverlay.BoxAngles(toWorld:GetTranslation(), surf.AABBMin, surf.AABBMax, toWorld:GetAngles(), t, color_transparent)
    debugoverlay.BoxAngles(mbb:GetTranslation() + vector_up, vector_origin, surf.MBBSize, mbb:GetAngles(), t, Color(255, 255, 160, 2))
    debugoverlay.BoxAngles(m:GetTranslation(), vector_origin, size, m:GetAngles(), t, Color(0, 255, 0, 0))
end

---Draws the nearest point on a flat surface from the query point.
---@param surf         ss.PaintableSurface
---@param toWorld      VMatrix Transformation from the surface's coordinate system to the world.
---@param worldToLocal VMatrix Transformation from the world to the surface's coordinate system.
---@param nearestFrom  Vector  The query point in world coordinates.
---@param t            number  Duration of the overlay.
local function DrawNearestOnFlatSurface(surf, toWorld, worldToLocal, nearestFrom, t)
    local nearestLocal = surf.WorldToLocalGridMatrix * (worldToLocal * nearestFrom)
    if not (nearestLocal.x < 0 or nearestLocal.x > surf.Grid.Width * PaintableGrid.CELL_SIZE
    or nearestLocal.y < 0 or nearestLocal.y > surf.Grid.Height * PaintableGrid.CELL_SIZE) then
        local nearest2D = Vector(nearestLocal.x, nearestLocal.y)
        local nearest = toWorld * (surf.WorldToLocalGridMatrix:GetInverseTR() * nearest2D)
        debugoverlay.Cross(nearest, 10, t, Color(255, 255, 0), true)
        debugoverlay.Line(nearestFrom, nearest, t, Color(255, 255, 0), true)
    end
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
    -- queryMins = origin - Util.vector_one * 500
    -- queryMaxs = origin + Util.vector_one * 500

    local t = InkCheckInterval + FrameTime() * 2
    debugoverlay.Cross(nearestFrom, 10, t, Color(255, 255, 0), true)

    for surf in Hash.CollectSurfaces(queryMins, queryMaxs) do
        local m = surf.WorldToLocalGridMatrix:GetInverseTR()
        DrawSurfaceBounds(surf, identity, t)
        if surf.Triangles then
            for tri in Hash.CollectDisplacementTriangles(surf, queryMins, queryMaxs) do
            -- for _, tri in ipairs(surf.Triangles) do
                local d = tri.MBBAngles:Up() * 0.5
                debugoverlay.BoxAngles(
                    tri.MBBOrigin, vector_origin,
                    tri.MBBSize, tri.MBBAngles, t, Color(255, 255, 255, 0))

                debugoverlay.Line(tri[1] + d, tri[2] + d, t, Color(255, 255, 0, 64))
                debugoverlay.Line(tri[2] + d, tri[3] + d, t, Color(255, 255, 0, 64))
                debugoverlay.Line(tri[3] + d, tri[1] + d, t, Color(255, 255, 0, 64))

                debugoverlay.Line(tri[4] + d, tri[5] + d, t, Color(192, 96, 0), true)
                debugoverlay.Line(tri[5] + d, tri[6] + d, t, Color(192, 96, 0), true)
                debugoverlay.Line(tri[6] + d, tri[4] + d, t, Color(192, 96, 0), true)

                debugoverlay.Line(tri[1] + d, tri[4] + d, t, Color(128, 128, 0), true)
                debugoverlay.Line(tri[2] + d, tri[5] + d, t, Color(128, 128, 0), true)
                debugoverlay.Line(tri[3] + d, tri[6] + d, t, Color(128, 128, 0), true)

                local b = PaintableSurface.BarycentricCoordinates(tri, nearestFrom)
                if b.x > 0 and b.y > 0 and b.z > 0 then
                    local nearest = tri[1] * b.x + tri[2] * b.y + tri[3] * b.z
                    debugoverlay.Line(nearestFrom, LerpVector(20 / nearest:Distance(nearestFrom), nearest, nearestFrom), t, Color(255, 255, 0), true)

                    local mapped = tri[4] * b.x + tri[5] * b.y + tri[6] * b.z
                    local query2d = surf.WorldToLocalGridMatrix * mapped
                    local hitang = aim:Cross(-tr.HitNormal):Cross(tr.HitNormal):AngleEx(tr.HitNormal)
                    local R = Matrix()
                    R:SetAngles(hitang)
                    R:Set(tri.WorldToLocalRotation * R)

                    debugoverlay.Axis(nearest, hitang, 20, t, true)
                    debugoverlay.Axis(m * query2d, R:GetAngles(), 20, t, true)
                    debugoverlay.Line(nearest, m * query2d, t, Color(0, 255, 255), true)
                end
            end
        else
            DrawNearestOnFlatSurface(surf, identity, identity, nearestFrom, t)
        end
    end

    -- Brush models have no displacements, so their surfaces are always flat.
    for ent, modelIndex, worldToModel in Hash.CollectBrushEntities(queryMins, queryMaxs) do
        local modelToWorld = ent:GetWorldTransformMatrix()
        local localMins, localMaxs = Util.TransformAABB(worldToModel, queryMins, queryMaxs)
        for surf in Hash.CollectBrushModelSurfaces(modelIndex, localMins, localMaxs) do
            DrawSurfaceBounds(surf, modelToWorld, t)
            DrawNearestOnFlatSurface(surf, modelToWorld, worldToModel, nearestFrom, t)
        end
    end
end)

if CLIENT then return end
hook.Add("SplashSWEPs: PlayerDisconnected", "Cleanup InkCheckInterval for players", function(ply)
    NextCheckTime[ply] = nil
end)
