
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.Touch then
    locals.Touch = {} ---@class ss.Locals.Touch
    locals.Touch.NextInkCheckTimePlayer = {}
end

-- Check if a player is on ink for every this seconds
local InkCheckInterval = 1 / 20

---CurTime() based time to perform traces to check player's ink state.
---@type table<Player, number>
local NextCheckTime = locals.Touch.NextInkCheckTimePlayer

local lastTrace ---@type Structure.TraceResult
local lastAim = Vector()
hook.Add("Move", "SplashSWEPs: Check if players are on ink", function(ply, mv)
    if not ss.PlayerIndices[ply] then return end

    local index = ss.PlayerIndices[ply] - 1
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
    -- queryMins = origin - ss.vector_one * 500
    -- queryMaxs = origin + ss.vector_one * 500

    local t = InkCheckInterval + FrameTime() * 2
    debugoverlay.Cross(nearestFrom, 10, t, Color(255, 255, 0), true)

    for surf in ss.CollectSurfaces(queryMins, queryMaxs) do
        local m = surf.WorldToLocalGridMatrix:GetInverseTR()
        local width = surf.Grid.Width * ss.InkGridCellSize
        local height = surf.Grid.Height * ss.InkGridCellSize
        local size = Vector(width, height)
        debugoverlay.Box(Vector(), surf.AABBMin, surf.AABBMax, t, color_transparent)
        debugoverlay.BoxAngles(surf.MBBOrigin + vector_up, vector_origin, surf.MBBSize, surf.MBBAngles, t, Color(255, 255, 160, 2))
        debugoverlay.BoxAngles(m:GetTranslation(), vector_origin, size, m:GetAngles(), t, Color(0, 255, 0, 0))
        if surf.Triangles then
            for tri in ss.CollectDisplacementTriangles(surf, queryMins, queryMaxs) do
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

                local b = ss.BarycentricCoordinates(tri, nearestFrom)
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
            local nearestLocal = surf.WorldToLocalGridMatrix * nearestFrom
            if not (nearestLocal.x < 0 or nearestLocal.x > surf.Grid.Width * ss.InkGridCellSize
            or nearestLocal.y < 0 or nearestLocal.y > surf.Grid.Height * ss.InkGridCellSize) then
                local nearest2D = Vector(nearestLocal.x, nearestLocal.y)
                local nearest = m * nearest2D
                debugoverlay.Cross(nearest, 10, t, Color(255, 255, 0), true)
                debugoverlay.Line(nearestFrom, nearest, t, Color(255, 255, 0), true)
            end
        end
    end
end)

if CLIENT then return end
hook.Add("SplashSWEPs: PlayerDisconnected", "Cleanup InkCheckInterval for players", function(ply)
    NextCheckTime[ply] = nil
end)
