
-- Calls Move of the ink feature modules for every command of each ready player,
-- on the server and on the client predicting the player.
-- The server also finds here when players start touching ink, which can be shorter than the interval of the checks.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local ContactState  = ss.import "splashsweps/shared/touch/contactstate"
local InkContact    = ss.import "splashsweps/shared/touch/inkcontact"
local InkType       = ss.import "splashsweps/shared/inktype"
local Players       = ss.import "splashsweps/shared/players"
local PredictedVars = ss.import "splashsweps/shared/touch/predictedvars"

local NO_CONTACTS = {} ---@type ss.InkContact[]

hook.Add("Move", "SplashSWEPs: Touch ink", function(ply, mv)
    if not (Players.Indices[ply] and InkContact.ShouldTouch(ply)) then return end

    -- The contacts are found for every command and not kept, so the prediction has nothing more to restore.
    local origin = mv:GetOrigin()
    local velocity = mv:GetVelocity()
    local groups = InkContact.Find(ply,
        origin + ply:OBBMins(), origin + ply:OBBMaxs(), velocity * engine.TickInterval())
    local suppress = false
    for _, feature in ipairs(InkType.Features) do
        local vars = PredictedVars.Get(ply, feature)
        -- A module declaring variables waits for the entity holding them, which arrives after the player gets ready.
        if feature.Move and (vars or not feature.PredictedVars)
            and feature.Move(ply, mv, groups[feature] or NO_CONTACTS, vars) then
            suppress = true
        end
    end

    if SERVER then ContactState.Enter(ply, groups) end
    if suppress then return true end
end)
