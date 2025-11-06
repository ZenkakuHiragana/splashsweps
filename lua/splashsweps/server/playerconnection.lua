
---@class ss
local ss = SplashSWEPs
if not ss then return end

util.AddNetworkString "SplashSWEPs: PlayerInitialSpawn"
util.AddNetworkString "SplashSWEPs: Refresh players table"
net.Receive("SplashSWEPs: PlayerInitialSpawn", function(_, ply)
    local index = #ss.PlayersReady + 1
    ss.PlayersReady[index] = ply
    ss.PlayerIndices[ply] = index
    hook.Run("SplashSWEPs: PlayerInitialSpawn", ply)
    net.Start "SplashSWEPs: Refresh players table"
    net.WriteTable(ss.PlayersReady, true)
    net.Send(ply)
end)

hook.Add("PlayerDisconnected", "SplashSWEPs: PlayerDisconnected", function(ply)
    table.RemoveByValue(ss.PlayersReady, ply)
    table.Empty(ss.PlayerIndices)
    table.Merge(ss.PlayerIndices, table.Flip(ss.PlayersReady))
    hook.Run("SplashSWEPs: PlayerDisconnected", ply)
    net.Start "SplashSWEPs: Refresh players table"
    net.WriteTable(ss.PlayersReady)
    net.Broadcast()
end)
