
-- Makes the entities having the predicted variables of the local player predictable.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local PredictedVars = ss.import "splashsweps/shared/contact/predictedvars"

-- This is called with shouldTransmit true when the client creates the entity,
-- and after a full update, which unmarks the entity as predictable.
hook.Add("NotifyShouldTransmit", "SplashSWEPs: Predict the variables", function(ent, shouldTransmit)
    if shouldTransmit and ent:GetClass() == PredictedVars.CLASS_NAME and ent:GetOwner() == LocalPlayer() then
        ent:SetPredictable(true)
    end
end)
