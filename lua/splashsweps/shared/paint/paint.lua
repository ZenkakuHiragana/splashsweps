
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Clamp = math.Clamp
local min = math.min
local Round = math.Round
local Remap = math.Remap
local NormalizeAngle = math.NormalizeAngle
local net_Start = net.Start
local net_WriteUInt = net.WriteUInt
local net_WriteInt = net.WriteInt

---@diagnostic disable-next-line: undefined-field
local net_Broadcast = net.Broadcast ---@type fun()

---Maximum paint scale of a single drop to be networked
local MAX_RADIUS = math.pow(2, ss.MAX_INK_RADIUS_BITS) - 1

---Gets AABB of incoming paint.
---@param pos     Vector The origin.
---@param angle   Angle  The normal and rotation.
---@param scale_x number Scale along the forward vector.
---@param scale_y number Scale along the right vector.
---@return Vector mins   The minimum bounding box.
---@return Vector maxs   The maximum bounding box.
function ss.GetPaintBoundingBox(pos, angle, scale_x, scale_y)
    local axis_x = angle:Forward()
    local axis_y = -angle:Right()
    local mins = ss.vector_one * math.huge
    local maxs = ss.vector_one * -math.huge
    for _, v in ipairs {
        pos + axis_x * scale_x + axis_y * scale_y,
        pos + axis_x * scale_x - axis_y * scale_y,
        pos - axis_x * scale_x + axis_y * scale_y,
        pos - axis_x * scale_x - axis_y * scale_y,
    } do
        mins = ss.MinVector(mins, v)
        maxs = ss.MaxVector(maxs, v)
    end

    return mins, maxs
end

---Paints an ink with given information.
---@param pos     Vector  The origin.
---@param angle   Angle   The normal and rotation.
---@param scale_x number  Scale along the forward vector (angle:Forward()) which is limited to 510 Hammer units because of network optimization.
---@param scale_y number  Scale along the right vector (angle:Right()) which is limited to 510 Hammer units because of network optimization.
---@param shape   integer The internal index of shape to paint.
---@param inktype integer The internal index of ink type.
function ss.Paint(pos, angle, scale_x, scale_y, shape, inktype)
    if SERVER then
        -- Parameter limit to reduce network traffic
        local x     = Round(pos.x / 2)
        local y     = Round(pos.y / 2) -- -16384 to 16384, 2 step
        local z     = Round(pos.z / 2)
        local sx    = Round(min(scale_x, MAX_RADIUS) / 2) -- 0 to MAX_RADIUS, 2 step, integer
        local sy    = Round(min(scale_y, MAX_RADIUS) / 2) -- 0 to MAX_RADIUS, 2 step, integer
        local pitch = Clamp(Round(NormalizeAngle(angle.pitch) / 180 * 128), -128, 127)
        local yaw   = Clamp(Round(NormalizeAngle(angle.yaw)   / 180 * 128), -128, 127)
        local roll  = Clamp(Round(NormalizeAngle(angle.roll)  / 180 * 128), -128, 127)

        net_Start "SplashSWEPs: Paint"
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
        net_Broadcast()

        pos:SetUnpacked(x * 2, y * 2, z * 2)
        angle:SetUnpacked(
            Remap(pitch, -128, 127, -180, 180),
            Remap(yaw,   -128, 127, -180, 180),
            Remap(roll,  -128, 127, -180, 180))
        scale_x, scale_y = sx * 2, sy * 2
    end

    -- -- Bounding box for finding surfaces
    -- debugoverlay.Box(vector_origin, mins, maxs, 3, Color(255, 255, 0, 8))
    -- -- The shape we are painting
    -- for y = 0, shape.Grid.Height - 1 do
    --     for x = 0, shape.Grid.Width - 1 do
    --         debugoverlay.BoxAngles(
    --             pos + angle:Forward() * (x / shape.Grid.Width  - 0.5) * scale_x * 2
    --                 - angle:Right()   * (y / shape.Grid.Height - 0.5) * scale_y * 2,
    --             Vector(-scale_x / shape.Grid.Width, -scale_y / shape.Grid.Height, -1),
    --             Vector( scale_x / shape.Grid.Width,  scale_y / shape.Grid.Height,  1), angle, 3,
    --             shape.Grid[y * shape.Grid.Width + x + 1] and Color(0, 255, 0, 64) or Color(255, 255, 255, 8))
    --     end
    -- end

    local mins, maxs = ss.GetPaintBoundingBox(pos, angle, scale_x, scale_y)
    for surf in ss.CollectSurfaces(mins - ss.vector_one, maxs + ss.vector_one) do
        ss.WriteGrid(surf, pos, angle, scale_x, scale_y, inktype, shape)
    end
end

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(ss.SurfaceArray) do ss.ClearGrid(s) end
    if SERVER then return end

    local rt = ss.RenderTarget
    render.PushRenderTarget(rt.StaticTextures.Albedo)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(0, 0, 0, 0)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()

    render.PushRenderTarget(rt.StaticTextures.Normal)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(128, 128, 255, 255)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
end
