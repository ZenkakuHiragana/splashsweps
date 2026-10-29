
local ss = SplashSWEPs
if not ss then return end

local Geometry      = ss.import "splashsweps/shared/geometry"
local Hash          = ss.import "splashsweps/shared/hash"
local InkShape      = ss.import "splashsweps/shared/inkshape"
local InkType       = ss.import "splashsweps/shared/inktype"
local Paint         = ss.import "splashsweps/shared/paint/paint"
local PaintableGrid = ss.import "splashsweps/shared/paint/paintablegrid"
local Util          = ss.import "splashsweps/shared/util"

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
    "splashsweps/inks/color_red",
    "splashsweps/inks/color_seal",
    "splashsweps/inks/material_test",
    "splashsweps/inks/height1",
    "splashsweps/inks/depth1",
    "splashsweps/inks/depth2",
    "splashsweps/inks/detail_samples/plain",
    "splashsweps/inks/detail_samples/normal_ridges",
    "splashsweps/inks/detail_samples/normal_crossed",
    "splashsweps/inks/detail_samples/normal_rotated",
    "splashsweps/inks/detail_samples/material_finish",
    "splashsweps/inks/detail_samples/emission_tiles",
    "splashsweps/inks/detail_samples/color_tiles",
    "splashsweps/inks/detail_samples/thin_film",
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
    local ang = normal:Cross(right):AngleEx(normal)
    local id = InkType.FindIndex(self.InkTypes[self.InkTypeIndex])
    debugoverlay.Axis(pos, ang, 20, 5, false)
    Paint.Paint(pos, ang, Vector(radius, radius, 100),
        InkShape.SelectRandom("builtin_drop").Index, id or -1)
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
end

---Draws the serverside paint grid of a surface.
---@param surf    ss.PaintableSurface
---@param toWorld number[]? Transform from the surface's coordinate system to the world if it is a brush model.
local function DrawGrid(surf, toWorld)
    local gridToWorld = Geometry.InvertRotationTranslation(surf.WorldToLocalGrid)
    if toWorld then gridToWorld = Geometry.Multiply(toWorld, gridToWorld) end
    local cellSize = PaintableGrid.CELL_SIZE
    for y = 0, surf.Grid.Height - 1 do
        for x = 0, surf.Grid.Width - 1 do
            local pixel = PaintableGrid.ReadCell(surf, x, y)
            local center = Vector(Geometry.TransformPoint(gridToWorld,
                (x + 0.5) * cellSize, (y + 0.5) * cellSize, 0.1 * cellSize))
            local color = pixel > 0 and Color(128, 255, 128) or Color(255, 255, 255)
            debugoverlay.Cross(center, cellSize / 2, 5, color, true)
        end
    end
end

function SWEP:SecondaryAttack()
    local Owner = self:GetOwner()
    if not Owner:IsPlayer() then return end ---@cast Owner Player
    self:EmitSound("Weapon_AR2.Empty")
    local tr = Owner:GetEyeTrace()
    local x, y, z = tr.HitPos:Unpack()
    for surf in Hash.CollectSurfaces(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1) do
        DrawGrid(surf)
    end

    for _, modelIndex, worldToModel in Hash.CollectBrushEntities(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1) do
        local localX, localY, localZ = Geometry.TransformPoint(worldToModel, x, y, z)
        for surf in Hash.CollectBrushModelSurfaces(modelIndex,
            localX - 1, localY - 1, localZ - 1, localX + 1, localY + 1, localZ + 1) do
            DrawGrid(surf, Geometry.InvertRotationTranslation(worldToModel))
        end
    end
end

---Returns a paint of no size, which looks up the paint grids at a pose.
---@param x     number
---@param y     number
---@param z     number
---@param pitch number
---@param yaw   number
---@param roll  number
---@return ss.Paint
local function Probe(x, y, z, pitch, yaw, roll)
    return {
        X = x, Y = y, Z = z, Pitch = pitch, Yaw = yaw, Roll = roll,
        RadiusX = 0, RadiusY = 0, RadiusZ = 0, Shape = 0, InkType = 0,
    }
end

---Checks if the ink is painted under the player and indicates it by a sound.
---@param self     SplatoonWeaponBase
---@param surfaces fun(): ss.PaintableSurface Surfaces to check.
---@param probe    ss.Paint The pose to check in the surfaces' coordinate system.
---@param worldPos Vector   Position to draw debug overlay in world coordinates.
local function CheckInk(self, surfaces, probe, worldPos)
    for surf in surfaces do
        for p in Paint.EnumeratePositions(surf, probe,
            probe.X - 1, probe.Y - 1, probe.Z - 1, probe.X + 1, probe.Y + 1, probe.Z + 1) do
            local color = PaintableGrid.Read(surf, p.X, p.Y, p.Z)
            debugoverlay.Box(
                worldPos, -Util.vector_one, Util.vector_one + vector_up * 72, FrameTime() * 2,
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
    ang:RotateAroundAxis(ang:Right(), -90)
    local x, y, z = tr.HitPos:Unpack()
    if tr.HitWorld then
        CheckInk(self, Hash.CollectSurfaces(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1),
            Probe(x, y, z, ang.pitch, ang.yaw, ang.roll), tr.HitPos)
        return
    end

    if IsValid(tr.Entity) then
        for ent, modelIndex, worldToModel in Hash.CollectBrushEntities(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1) do
            if ent == tr.Entity then
                local probeToModel = Geometry.Multiply(worldToModel,
                    Geometry.FromAngles(ang.pitch, ang.yaw, ang.roll, x, y, z))
                local probe = Probe(probeToModel[4], probeToModel[8], probeToModel[12], Geometry.ToAngles(probeToModel))
                CheckInk(self, Hash.CollectBrushModelSurfaces(modelIndex,
                    probe.X - 1, probe.Y - 1, probe.Z - 1, probe.X + 1, probe.Y + 1, probe.Z + 1),
                    probe, tr.HitPos)
                return
            end
        end
    end

    self.LoopSound:Stop()
end
