
-- Players ready to receive networked paint, in the order they became ready.

---@class ss
local ss = SplashSWEPs

---@class ss.PlayersModule
local Players = ss.module "splashsweps/shared/players"

---@class ss.PlayersModule.State
---@field Ready   Player[]               Players ready to network.
---@field Indices table<Player, integer> Lookup table equal to table.Flip(Ready).
local state = ss.state("splashsweps/shared/players", { Ready = {}, Indices = {} }) ---@type ss.PlayersModule.State

---Players ready to network.
Players.Ready = state.Ready

---Lookup table equal to table.Flip(Players.Ready).
Players.Indices = state.Indices

---Adds a player who became ready.
---@param ply Player
function Players.Add(ply)
    local index = #state.Ready + 1
    state.Ready[index] = ply
    state.Indices[ply] = index
end

---Removes a player who disconnected.
---@param ply Player
function Players.Remove(ply)
    table.RemoveByValue(state.Ready, ply)
    table.Empty(state.Indices)
    table.Merge(state.Indices, table.Flip(state.Ready))
end

---Replaces the list with the one the server sent.
---@param ready Player[]
function Players.Replace(ready)
    table.Empty(state.Ready)
    table.Empty(state.Indices)
    table.Merge(state.Ready, ready)
    table.Merge(state.Indices, table.Flip(ready))
end

return Players
