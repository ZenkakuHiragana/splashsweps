
-- The entity having the predicted variables of a group of ink feature modules for a player, its owner.

AddCSLuaFile()

---@class ss
local ss = SplashSWEPs
if not ss then return end

local PredictedVars = ss.import "splashsweps/shared/contact/predictedvars"

---@class ss.PredictedVars.Entity : Structure.ENT, Entity
---@field GetGroup fun(self): integer
---@field SetGroup fun(self, group: integer)
---@diagnostic disable-next-line: deprecated
local ENT = ENT

ENT.Type = "anim"
ENT.Base = "base_anim"

function ENT:SetupDataTables()
    self:NetworkVar("Int", PredictedVars.GROUP_SLOT, "Group")
end

function ENT:Initialize()
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    if SERVER then
        -- Cleaning up the map keeps it, as the player keeps using it.
        self:AddEFlags(EFL_KEEP_ON_RECREATE_ENTITIES)
    end

    PredictedVars.Add(self)
end

---@param fullUpdate boolean? Client only; true on a full update, after which the client keeps the entity.
function ENT:OnRemove(fullUpdate)
    if not fullUpdate then PredictedVars.Remove(self) end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end
