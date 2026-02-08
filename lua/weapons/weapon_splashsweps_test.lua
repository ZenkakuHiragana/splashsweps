
local ss = SplashSWEPs
if not ss then return end

---@class SplatoonWeaponBase : Structure.SWEP, Structure.ENT, Weapon
---@field ViewModel0    string?
---@field ViewModel1    string?
---@field ViewModel2    string?
---@field Customized    boolean?
---@field SheldonsPicks boolean?
---@field SpecialWeapon string
---@field SubWeapon     string
---@field ClassID       integer
local SWEP = SWEP
if CLIENT then
    SWEP.Author = ""
    SWEP.BobScale = 1
    SWEP.BounceWeaponIcon = true
    SWEP.DrawAmmo = true
    SWEP.DrawCrosshair = true
    SWEP.DrawWeaponInfoBox = true
    SWEP.Instructions = ""
    SWEP.Purpose = ""
    SWEP.RenderGroup = RENDERGROUP_BOTH
    -- SWEP.SpeechBubbleLid = surface.GetTextureID "gui/speech_lid"
    SWEP.SwayScale = 1
    SWEP.UseHands = true
    SWEP.ViewModelFOV = 62
else
    SWEP.AutoSwitchFrom = false
    SWEP.AutoSwitchTo = false
    SWEP.Weight = 1
end

SWEP.PrintName = "Inkling base"
SWEP.Spawnable = true
SWEP.HoldType = "crossbow"
SWEP.Slot = 1
SWEP.SlotPos = 2
SWEP.IsSplatoonWeapon = true
SWEP.m_WeaponDeploySpeed = 2

SWEP.Secondary = SWEP.Secondary or {}
SWEP.Secondary.Automatic = false
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Ammo = "Ink"

SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 1 / 120

SWEP.InkTypeIndex = 1
SWEP.InkTypes = {
    "splashsweps/inktypes/color_red",
    "splashsweps/inktypes/color_seal",
    "splashsweps/inktypes/material_test",
}

function SWEP:Initialize()
    self.LoopSound = CreateSound(self, "items/suitcharge1.wav")
end

function SWEP:OnRemove()
    if self.LoopSound:IsPlaying() then
        self.LoopSound:Stop()
    end
end

function SWEP:Reload()
    local owner = self:GetOwner() ---@cast owner Player
    if not owner:KeyPressed(IN_RELOAD) then return end
    self:EmitSound("Weapon_AR2.Empty")
    self.InkTypeIndex = self.InkTypeIndex % #self.InkTypes + 1
end

function SWEP:PrimaryAttack()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    self:EmitSound("Weapon_AR2.Single")
    local tr = Owner:GetEyeTrace()
    local radius = 80
    local pos = tr.HitPos
    local normal = tr.HitNormal
    local right = normal:Cross(tr.StartPos - pos):GetNormalized()
    local ang = right:Cross(normal):AngleEx(normal)
    local id = ss.FindInkTypeID(self.InkTypes[self.InkTypeIndex])
    debugoverlay.Axis(pos, ang, 20, 5, false)
    ss.Paint(pos, ang, Vector(radius, radius, radius * 0),
        ss.SelectRandomShape("builtin_drop").Index, id or -1)
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
end

function SWEP:SecondaryAttack()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    self:EmitSound("Weapon_AR2.Empty")
    local tr = Owner:GetEyeTrace()
    local pos = tr.HitPos
    local normal = tr.HitNormal
    for surf in ss.CollectSurfaces(pos - ss.vector_one, pos + ss.vector_one) do
        for y = 0, surf.Grid.Height - 1 do
            for x = 0, surf.Grid.Width - 1 do
                local pixel = surf.Grid[y * surf.Grid.Width + x + 1] or 0
                local xy = Vector(x + 0.5, y + 0.5, 0.1) * ss.InkGridCellSize
                local color = pixel > 0 and Color(128, 255, 128) or Color(255, 255, 255)
                debugoverlay.Cross(surf.WorldToLocalGridMatrix:GetInverseTR() * xy, ss.InkGridCellSize / 2, 5, color, true)
            end
        end
    end
end

function SWEP:Think()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    local tr = util.QuickTrace(Owner:GetPos(), -vector_up * 16, Owner)
    if tr.HitWorld then
        local mins = tr.HitPos - ss.vector_one
        local maxs = tr.HitPos + ss.vector_one
        for surf in ss.CollectSurfaces(mins, maxs) do
            for pos, ang in ss.EnumeratePaintPositions(surf, mins, maxs, tr.HitPos, tr.HitNormal:Angle()) do
                local color = ss.ReadGrid(surf, pos)
                debugoverlay.Box(
                    tr.HitPos, -ss.vector_one, ss.vector_one + vector_up * 72, FrameTime() * 2,
                    color and Color(0, 255, 128, 16) or Color(255, 255, 255, 16))
                if color then
                    self.LoopSound:Play()
                else
                    self.LoopSound:Stop()
                end
                break
            end
        end
    else
        self.LoopSound:Stop()
    end
end
