
---@class ss
local ss = SplashSWEPs
if not ss then return end

util.AddNetworkString "SplashSWEPs: Paint"

local Clamp = math.Clamp
local min = math.min
local Round = math.Round

---Paints an ink with given information.
---@param pos     Vector      The origin.
---@param angle   Angle       The normal and rotation.
---@param scale_x number      Scale along the forward vector (angle:Forward()) which is limited to 510 Hammer units because of network optimization.
---@param scale_y number      Scale along the right vector (angle:Right()) which is limited to 510 Hammer units because of network optimization.
---@param shape   ss.InkShape The shape to paint.
---@param inktype string      The identifier of ink type.
function ss.Paint(pos, angle, scale_x, scale_y, shape, inktype)
    local inktypeIndex = ss.FindInkTypeID(inktype)
    if not inktypeIndex then return end

    -- Parameter limit to reduce network traffic
    pos.x       = Round(pos.x / 2)
    pos.y       = Round(pos.y / 2) -- -16384 to 16384, 2 step
    pos.z       = Round(pos.z / 2)
    scale_x     = min(Round(scale_x / 2), 255) -- 0 to 510, 2 step, integer
    scale_y     = min(Round(scale_y / 2), 255) -- 0 to 510, 2 step, integer
    angle.pitch = Clamp(Round(math.NormalizeAngle(angle.pitch) / 180 * 128), -128, 127)
    angle.yaw   = Clamp(Round(math.NormalizeAngle(angle.yaw)   / 180 * 128), -128, 127)
    angle.roll  = Clamp(Round(math.NormalizeAngle(angle.roll)  / 180 * 128), -128, 127)

    net.Start "SplashSWEPs: Paint"
    net.WriteUInt(inktypeIndex - 1, ss.MAX_INKTYPE_BITS) -- Ink type
    net.WriteUInt(shape.Index, ss.MAX_INKSHAPE_BITS) -- Ink shape
    net.WriteInt(angle.pitch, 8) -- Pitch
    net.WriteInt(angle.yaw,   8) -- Yaw
    net.WriteInt(angle.roll,  8) -- Roll
    net.WriteInt(pos.x, 15) -- X
    net.WriteInt(pos.y, 15) -- Y
    net.WriteInt(pos.z, 15) -- Z
    net.WriteUInt(scale_x, 8) -- Scale X
    net.WriteUInt(scale_y, 8) -- Scale Y
    net.Broadcast()

    pos     = pos     * 2
    scale_x = scale_x * 2
    scale_y = scale_y * 2
    angle.pitch = math.Remap(angle.pitch, -128, 127, -180, 180)
    angle.yaw   = math.Remap(angle.yaw,   -128, 127, -180, 180)
    angle.roll  = math.Remap(angle.roll,  -128, 127, -180, 180)
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

    for surf in ss.CollectSurfaces(mins - ss.vector_one, maxs + ss.vector_one, angle:Up()) do
        surf:WriteGrid(pos, angle, scale_x, scale_y, inktypeIndex, shape)
    end
end
