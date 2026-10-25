
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Players = ss.import "splashsweps/shared/players"

util.AddNetworkString "SplashSWEPs: PlayerInitialSpawn"
util.AddNetworkString "SplashSWEPs: Refresh players table"
net.Receive("SplashSWEPs: PlayerInitialSpawn", function(_, ply)
    Players.Add(ply)
    hook.Run("SplashSWEPs: PlayerInitialSpawn", ply)
    net.Start "SplashSWEPs: Refresh players table"
    net.WriteTable(Players.Ready, true)
    net.Send(ply)
end)

hook.Add("PlayerDisconnected", "SplashSWEPs: PlayerDisconnected", function(ply)
    Players.Remove(ply)
    hook.Run("SplashSWEPs: PlayerDisconnected", ply)
    net.Start "SplashSWEPs: Refresh players table"
    net.WriteTable(Players.Ready)
    net.Broadcast()
end)
