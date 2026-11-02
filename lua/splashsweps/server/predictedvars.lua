
-- Creates the entities having the predicted variables for each ready player, and removes them when the player leaves.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local PredictedVars = ss.import "splashsweps/shared/touch/predictedvars"

hook.Add("SplashSWEPs: PlayerInitialSpawn", "SplashSWEPs: Create predicted variables", function(ply)
    for group = 1, PredictedVars.GetNumGroups() do
        local ent = ents.Create(PredictedVars.CLASS_NAME) --[[@as ss.PredictedVarsEntity]]
        ent:SetOwner(ply)
        ent:SetGroup(group)
        ent:Spawn()
    end
end)

hook.Add("SplashSWEPs: PlayerDisconnected", "SplashSWEPs: Remove predicted variables", function(ply)
    for _, ent in pairs(PredictedVars.Entities[ply] or {}) do
        ent:Remove()
    end
end)
