
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

hook.Add("Move", "SplashSWEPs: Check if players are on ink", function(ply, mv)
    if not ss.PlayerIndices[ply] then return end

    local index = ss.PlayerIndices[ply] - 1
    local timeOffset = index / player.GetCount() * InkCheckInterval
    if not NextCheckTime[ply] then NextCheckTime[ply] = CurTime() end
    if CurTime() < NextCheckTime[ply] + timeOffset then return end
    NextCheckTime[ply] = CurTime() + InkCheckInterval

    local t = InkCheckInterval + FrameTime() * 2
    for surf in ss.CollectSurfaces(
        mv:GetOrigin() + ply:OBBMins() - ss.vector_one,
        mv:GetOrigin() + ply:OBBMaxs() + ss.vector_one) do
        local m = surf.WorldToLocalGridMatrix:GetInverseTR()
        local width = surf.Grid.Width * ss.InkGridCellSize
        local height = surf.Grid.Height * ss.InkGridCellSize
        local mins = Vector()
        local maxs = Vector(width, height, 0)
        local nearest = surf.WorldToLocalGridMatrix * ply:WorldSpaceCenter()
        local nearest2D = Vector(nearest.x, nearest.y)
        local nearest3D = m * nearest2D
        debugoverlay.Box(Vector(), surf.AABBMin, surf.AABBMax, t, color_transparent)
        debugoverlay.BoxAngles(m:GetTranslation(), mins, maxs, m:GetAngles(), t, Color(0, 255, 0, 64))
        debugoverlay.Cross(nearest3D, 10, t, Color(255, 255, 0), true)
    end

    if CLIENT then
        print(IsFirstTimePredicted(), ply == LocalPlayer(), ply)
    end
end)

if CLIENT then return end
hook.Add("SplashSWEPs: PlayerDisconnected", "Cleanup InkCheckInterval for players", function(ply)
    NextCheckTime[ply] = nil
end)
