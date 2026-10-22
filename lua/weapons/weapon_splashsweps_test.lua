
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
---@diagnostic disable-next-line: deprecated
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

SWEP.Primary.Automatic = true
SWEP.Primary.Delay = 1 / 30

SWEP.InkTypeIndex = 1
SWEP.InkTypes = {
    "splashsweps/inktypes/color_red",
    "splashsweps/inktypes/color_seal",
    "splashsweps/inktypes/material_test",
    "splashsweps/inktypes/height1",
    "splashsweps/inktypes/depth1",
    "splashsweps/inktypes/depth2",
    "splashsweps/inktypes/detail_samples/plain",
    "splashsweps/inktypes/detail_samples/normal_ridges",
    "splashsweps/inktypes/detail_samples/normal_crossed",
    "splashsweps/inktypes/detail_samples/normal_rotated",
    "splashsweps/inktypes/detail_samples/material_finish",
    "splashsweps/inktypes/detail_samples/emission_tiles",
    "splashsweps/inktypes/detail_samples/color_tiles",
    "splashsweps/inktypes/detail_samples/thin_film",
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
    owner:ChatPrint(string.format("%d: %s", self.InkTypeIndex, self.InkTypes[self.InkTypeIndex]))
end

function SWEP:PrimaryAttack()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    self:EmitSound("Weapon_AR2.Single")
    local tr = Owner:GetEyeTrace()
    local radius = 200
    local pos = tr.HitPos
    local normal = tr.HitNormal
    local right = normal:Cross(tr.StartPos - pos):GetNormalized()
    local ang = right:Cross(normal):AngleEx(normal)
    local id = ss.FindInkTypeID(self.InkTypes[self.InkTypeIndex])
    debugoverlay.Axis(pos, ang, 20, 5, false)
    ss.Paint(pos, ang, Vector(radius, radius, 100),
        ss.SelectRandomShape("builtin_drop").Index, id or -1)
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
end

---Draws the serverside paint grid of a surface.
---@param surf    ss.PaintableSurface
---@param toWorld VMatrix? Transformation from the surface's coordinate system to the world if it is a brush model.
local function DrawGrid(surf, toWorld)
    local gridToWorld = surf.WorldToLocalGridMatrix:GetInverseTR()
    if toWorld then gridToWorld = toWorld * gridToWorld end
    for y = 0, surf.Grid.Height - 1 do
        for x = 0, surf.Grid.Width - 1 do
            local pixel = surf.Grid[y * surf.Grid.Width + x + 1] or 0
            local xy = Vector(x + 0.5, y + 0.5, 0.1) * ss.InkGridCellSize
            local color = pixel > 0 and Color(128, 255, 128) or Color(255, 255, 255)
            debugoverlay.Cross(gridToWorld * xy, ss.InkGridCellSize / 2, 5, color, true)
        end
    end
end

function SWEP:SecondaryAttack()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    self:EmitSound("Weapon_AR2.Empty")
    local tr = Owner:GetEyeTrace()
    local pos = tr.HitPos
    for surf in ss.CollectSurfaces(pos - ss.vector_one, pos + ss.vector_one) do
        DrawGrid(surf)
    end

    for ent, modelIndex, worldToModel in ss.CollectBrushEntities(pos - ss.vector_one, pos + ss.vector_one) do
        local localPos = worldToModel * pos
        for surf in ss.CollectBrushModelSurfaces(modelIndex, localPos - ss.vector_one, localPos + ss.vector_one) do
            DrawGrid(surf, ent:GetWorldTransformMatrix())
        end
    end
end

---Checks if the ink is painted under the player and indicates it by a sound.
---@param self     SplatoonWeaponBase
---@param surfaces fun(): ss.PaintableSurface Surfaces to check.
---@param mins     Vector AABB minimum to check in the surfaces' coordinate system.
---@param maxs     Vector AABB maximum to check in the surfaces' coordinate system.
---@param pos      Vector Position to check in the surfaces' coordinate system.
---@param ang      Angle  Angles of the surface normal in the surfaces' coordinate system.
---@param worldPos Vector Position to draw debug overlay in world coordinates.
local function CheckInk(self, surfaces, mins, maxs, pos, ang, worldPos)
    for surf in surfaces do
        for p in ss.EnumeratePaintPositions(surf, mins, maxs, pos, ang) do
            local color = ss.ReadGrid(surf, p)
            debugoverlay.Box(
                worldPos, -ss.vector_one, ss.vector_one + vector_up * 72, FrameTime() * 2,
                color and Color(0, 255, 128, 16) or Color(255, 255, 255, 16))
            if color then
                self.LoopSound:Play()
            else
                self.LoopSound:Stop()
            end
            break
        end
    end
end

function SWEP:Think()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    local tr = util.QuickTrace(Owner:GetPos(), -vector_up * 16, Owner)
    local ang = tr.HitNormal:Angle()
    local mins = tr.HitPos - ss.vector_one
    local maxs = tr.HitPos + ss.vector_one
    ang:RotateAroundAxis(ang:Right(), -90)
    if tr.HitWorld then
        CheckInk(self, ss.CollectSurfaces(mins, maxs), mins, maxs, tr.HitPos, ang, tr.HitPos)
        return
    end

    if IsValid(tr.Entity) then
        for ent, modelIndex, worldToModel in ss.CollectBrushEntities(mins, maxs) do
            if ent == tr.Entity then
                local normalInWorld = Matrix()
                normalInWorld:SetAngles(ang)
                local localPos = worldToModel * tr.HitPos
                local localAng = (worldToModel * normalInWorld):GetAngles()
                local localMins = localPos - ss.vector_one
                local localMaxs = localPos + ss.vector_one
                CheckInk(self, ss.CollectBrushModelSurfaces(modelIndex, localMins, localMaxs),
                    localMins, localMaxs, localPos, localAng, tr.HitPos)
                return
            end
        end
    end

    self.LoopSound:Stop()
end
