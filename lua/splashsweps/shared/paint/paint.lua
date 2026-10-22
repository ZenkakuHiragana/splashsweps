
---@class ss
local ss = SplashSWEPs
if not ss then return end

local wrap = coroutine.wrap
local yield = coroutine.yield
local Clamp = math.Clamp
local max = math.max
local min = math.min
local Round = math.Round
local Remap = math.Remap
local NormalizeAngle = math.NormalizeAngle
local GetPredictionPlayer = GetPredictionPlayer
local net_Start = net.Start
local net_WriteUInt = net.WriteUInt
local net_WriteInt = net.WriteInt
---@diagnostic disable-next-line undefined-field
local net_SendOmit = net.SendOmit

---Temporary variable
local inkSystemInWorld = Matrix()

---Maximum paint scale of a single drop to be networked
local MAX_RADIUS = math.pow(2, ss.MAX_INK_RADIUS_BITS + 1) - 1

---Maximum angle difference allowed to paint.
local MAX_COS = math.cos(math.rad(45))
local MAX_COS_PROP = math.cos(math.rad(60))

---Gets AABB of incoming paint.
---@param pos   Vector The origin.
---@param angle Angle  The normal and rotation.
---@param scale Vector Scale along the angles.
---@return Vector mins The minimum bounding box.
---@return Vector maxs The maximum bounding box.
function ss.GetPaintBoundingBox(pos, angle, scale)
    local axis_x = angle:Forward()
    local axis_y = -angle:Right()
    local axis_z = angle:Up()
    local mins = ss.vector_one * math.huge
    local maxs = -ss.vector_one * math.huge
    local scale_z = max(scale.z, min(scale.x, scale.y) * 0.5)
    for _, dx in ipairs { axis_x * scale.x, -axis_x * scale.x } do
        for _, dy in ipairs { axis_y * scale.y, -axis_y * scale.y } do
            for _, dz in ipairs { axis_z * scale_z, -axis_z * scale_z } do
                mins = ss.MinVector(mins, dx + dy + dz)
                maxs = ss.MaxVector(maxs, dx + dy + dz)
            end
        end
    end

    return pos + mins, pos + maxs
end

---Before processing paintings, if the target surface is a displacement,
---we have to map the worldpos to the flat surface where it came from.
---
---So this function enumerates preprocessed positions
---for 3D-2D conversion to handle deformed surfaces correctly.
---
---Returns A generator function that returns points to paint ready to convert by WorldToLocal matrix.
---Returns a generator function that returns:
---  1. a matrix of the incoming ink
---  2. a matrix to convert world system to surface-local system.
---@param surf ss.PaintableSurface The surface to search.
---@param mins Vector AABB minimum to enumerate triangles of displacement.
---@param maxs Vector AABB minimum to enumerate triangles of displacement.
---@param pos  Vector Query point to be projected onto the surface.
---@param ang  Angle  Query angle to be localized to the surface.
---@return fun(): Vector, Angle generator
function ss.EnumeratePaintPositions(surf, mins, maxs, pos, ang)
    return wrap(function()
        if surf.Triangles then
            local min_score = -math.huge
            local min_coordinates = nil ---@type Vector
            local min_triangle = nil ---@type ss.DisplacementTriangle?
            local angleMatrix = Matrix()
            angleMatrix:SetAngles(ang)
            for t in ss.CollectDisplacementTriangles(surf, mins, maxs) do
                local b = ss.BarycentricCoordinates(t, pos)
                if b.x > 0 and b.y > 0 and b.z > 0 then
                    if ang:Up():Dot(t.MBBAngles:Up()) > MAX_COS then
                        local localPos = t[4] * b.x + t[5] * b.y + t[6] * b.z
                        local localAng = t.WorldToLocalRotation * angleMatrix
                        yield(localPos, localAng:GetAngles())
                        min_score = math.huge
                        min_triangle = nil
                    end
                else
                    local score = min(b.x, 0) + min(b.y, 0) + min(b.z, 0)
                    if score > min_score then -- score <= 0 and min_score should be close to 0
                        min_score = score
                        min_coordinates = b
                        min_triangle = t
                    end
                end
            end

            -- If the paint position is outside, find the nearest triangle roughly and return it.
            if min_triangle then
                if ang:Up():Dot(min_triangle.MBBAngles:Up()) > MAX_COS then
                    local localPos =
                        min_triangle[4] * min_coordinates.x +
                        min_triangle[5] * min_coordinates.y +
                        min_triangle[6] * min_coordinates.z
                    local localAng = min_triangle.WorldToLocalRotation * angleMatrix
                    yield(localPos, localAng:GetAngles())
                end
            end
        elseif ang:Up():Dot(surf.Normal) > (surf.StaticPropUnwrapIndex and MAX_COS_PROP or MAX_COS) then
            yield(pos, ang)
        end
    end)
end

---Quantizes the position and the angles in place to the precision of the network messages.
---@param pos Vector The position to be quantized.
---@param ang Angle  The angles to be quantized.
---@return integer x
---@return integer y
---@return integer z
---@return integer pitch
---@return integer yaw
---@return integer roll
local function QuantizePose(pos, ang)
    local x     = Round(pos.x * 0.5)
    local y     = Round(pos.y * 0.5) -- -16384 to 16384, 2 step
    local z     = Round(pos.z * 0.5)
    local pitch = Round(Remap(NormalizeAngle(ang.pitch), -180, 180, -128, 127))
    local yaw   = Round(Remap(NormalizeAngle(ang.yaw),   -180, 180, -128, 127))
    local roll  = Round(Remap(NormalizeAngle(ang.roll),  -180, 180, -128, 127))
    pos:SetUnpacked(x * 2, y * 2, z * 2)
    ang:SetUnpacked(
        Remap(pitch, -128, 127, -180, 180),
        Remap(yaw,   -128, 127, -180, 180),
        Remap(roll,  -128, 127, -180, 180))
    return x, y, z, pitch, yaw, roll
end

---Writes the common part of paint messages and sends it to the players except the predicting one.
local function WritePaintAndSend(inktype, shape, x, y, z, pitch, yaw, roll, sx, sy, sz)
    net_WriteUInt(inktype - 1, ss.MAX_INKTYPE_BITS) -- Ink type
    net_WriteUInt(shape - 1, ss.MAX_INKSHAPE_BITS) -- Ink shape
    net_WriteInt(pitch, 8) -- Pitch
    net_WriteInt(yaw,   8) -- Yaw
    net_WriteInt(roll,  8) -- Roll
    net_WriteInt(x, 15) -- X
    net_WriteInt(y, 15) -- Y
    net_WriteInt(z, 15) -- Z
    net_WriteUInt(sx, ss.MAX_INK_RADIUS_BITS) -- Scale X
    net_WriteUInt(sy, ss.MAX_INK_RADIUS_BITS) -- Scale Y
    net_WriteUInt(sz, ss.MAX_INK_RADIUS_BITS) -- Scale Z
    net_SendOmit(ss.sp and NULL or GetPredictionPlayer())
end

---Paints the surfaces given by the generator.
---The position and the angles must be in the same coordinate system as the surfaces.
---@param surfaces fun(): ss.PaintableSurface
---@param mins     Vector  AABB minimum of the ink.
---@param maxs     Vector  AABB maximum of the ink.
---@param pos      Vector  The origin.
---@param ang      Angle   The normal and rotation.
---@param scale    Vector  Scale along the angles.
---@param shape    integer The internal index of shape to paint.
---@param inktype  integer The internal index of ink type.
local function PaintSurfaces(surfaces, mins, maxs, pos, ang, scale, shape, inktype)
    for surf in surfaces do
        for p, a in ss.EnumeratePaintPositions(surf, mins, maxs, pos, ang) do
            ss.WriteGrid(surf, p, a, scale, inktype, shape)
            if CLIENT then
                ss.PushPaintRenderTargetQueue(surf, p, a, scale, shape, inktype)
            end
        end
    end
end

---Paints the worldspawn and static props without networking.
---The arguments must be already quantized by ss.Paint.
---@param worldPos Vector  The origin.
---@param worldAng Angle   The normal and rotation.
---@param scale    Vector  Scale along the angles.
---@param shape    integer The internal index of shape to paint.
---@param inktype  integer The internal index of ink type.
function ss.PaintWorld(worldPos, worldAng, scale, shape, inktype)
    local mins, maxs = ss.GetPaintBoundingBox(worldPos, worldAng, scale)
    PaintSurfaces(ss.CollectSurfaces(mins, maxs), mins, maxs, worldPos, worldAng, scale, shape, inktype)
end

---Paints a brush model without networking.
---The arguments must be already quantized by ss.Paint.
---@param modelIndex integer The index of the brush model.
---@param localPos   Vector  The origin in the model's local coordinates.
---@param localAng   Angle   The normal and rotation in the model's local coordinates.
---@param scale      Vector  Scale along the angles.
---@param shape      integer The internal index of shape to paint.
---@param inktype    integer The internal index of ink type.
function ss.PaintBrushModel(modelIndex, localPos, localAng, scale, shape, inktype)
    local mins, maxs = ss.GetPaintBoundingBox(localPos, localAng, scale)
    PaintSurfaces(ss.CollectBrushModelSurfaces(modelIndex, mins, maxs),
        mins, maxs, localPos, localAng, scale, shape, inktype)
end

---Paints an ink with given information.
---If scale.z == 0, paints surfaces with specific angles.
---If scale.z > 0, paints surfaces with all directions.
---@param worldPos Vector  The origin.
---@param worldAng Angle   The normal and rotation.
---@param scale    Vector  Scale along the angles which is limited to 510 Hammer units because of network optimization.
---@param shape    integer The internal index of shape to paint.
---@param inktype  integer The internal index of ink type.
function ss.Paint(worldPos, worldAng, scale, shape, inktype)
    -- Parameter limit to reduce network traffic
    local sx = Round(min(scale.x, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local sy = Round(min(scale.y, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local sz = Round(min(scale.z, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local x, y, z, pitch, yaw, roll = QuantizePose(worldPos, worldAng)
    scale:SetUnpacked(sx * 2, sy * 2, sz * 2)
    ss.PaintWorld(worldPos, worldAng, scale, shape, inktype)
    if SERVER then
        net_Start "SplashSWEPs: Paint"
        WritePaintAndSend(inktype, shape, x, y, z, pitch, yaw, roll, sx, sy, sz)
    end

    -- Brush entities can move, so the ink is localized to their models and networked separately.
    -- The receiving clients do not search for the entities; only the predicting client does.
    local mins, maxs = ss.GetPaintBoundingBox(worldPos, worldAng, scale)
    inkSystemInWorld:SetTranslation(worldPos)
    inkSystemInWorld:SetAngles(worldAng)
    for _, modelIndex, worldToModel in ss.CollectBrushEntities(mins, maxs) do
        local inkSystemInModel = worldToModel * inkSystemInWorld
        local localPos = inkSystemInModel:GetTranslation()
        local localAng = inkSystemInModel:GetAngles()
        local lx, ly, lz, lpitch, lyaw, lroll = QuantizePose(localPos, localAng)
        if SERVER then
            net_Start "SplashSWEPs: Paint brush model"
            net_WriteUInt(modelIndex - 1, ss.MAX_MODEL_INDEX_BITS) -- Model index
            WritePaintAndSend(inktype, shape, lx, ly, lz, lpitch, lyaw, lroll, sx, sy, sz)
        end

        ss.PaintBrushModel(modelIndex, localPos, localAng, scale, shape, inktype)
    end
end
