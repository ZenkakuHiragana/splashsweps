
---@class ss
local ss = SplashSWEPs
if not ss then return end

net.Receive("SplashSWEPs: Paint", function()
    local inktype    = net.ReadUInt(ss.MAX_INKTYPE_BITS) + 1 -- Ink type
    local shapeIndex = net.ReadUInt(ss.MAX_INKSHAPE_BITS) + 1 -- Ink shape
    local pitch      = net.ReadInt(8) -- Pitch
    local yaw        = net.ReadInt(8) -- Yaw
    local roll       = net.ReadInt(8) -- Roll
    local x          = net.ReadInt(15) * 2 -- X
    local y          = net.ReadInt(15) * 2 -- Y
    local z          = net.ReadInt(15) * 2 -- Z
    local scale_x    = net.ReadUInt(8) * 2 -- Scale X
    local scale_y    = net.ReadUInt(8) * 2 -- Scale Y
    local pos = Vector(x, y, z)
    local angle = Angle(
        math.Remap(pitch, -128, 127, -180, 180),
        math.Remap(yaw,   -128, 127, -180, 180),
        math.Remap(roll,  -128, 127, -180, 180))
    ss.Paint(pos, angle, scale_x, scale_y, shapeIndex, inktype)
    ss.PaintRenderTarget(pos, angle, scale_x, scale_y, shapeIndex, inktype)
end)

---Paints an ink to the render target with given information.
---@param pos     Vector  The origin.
---@param angle   Angle   The normal and rotation.
---@param scale_x number  Scale along the forward vector.
---@param scale_y number  Scale along the right vector.
---@param shape   integer The internal index of shape to paint.
---@param inktype integer The internal index of ink type.
function ss.PaintRenderTarget(pos, angle, scale_x, scale_y, shape, inktype)
    local rt = ss.RenderTarget
    local albedo = rt.StaticTextures.Albedo
    local normal = rt.StaticTextures.Normal
    local hammerUnitsToPixels = rt.HammerUnitsToPixels

    local gap = ss.RT_MARGIN_PIXELS / 2
    local mins, maxs = ss.GetPaintBoundingBox(pos, angle, scale_x, scale_y)
    local width = scale_x * 2 * hammerUnitsToPixels
    local height = scale_y * 2 * hammerUnitsToPixels
    local rotationMatrix = Matrix()
    rotationMatrix:SetAngles(angle)

    surface.SetDrawColor(128, 128, 255, 255)
    surface.SetMaterial(ss.GetInkMaterial(ss.InkTypes[inktype], ss.InkShapes[shape]))
    for surf in ss.CollectSurfaces(mins - ss.vector_one, maxs + ss.vector_one, angle:Up()) do
        local uv = surf.WorldToUVMatrix * pos * hammerUnitsToPixels
        local localRotation = surf.WorldToUVMatrix * rotationMatrix
        local localAngles = localRotation:GetAngles()
        render.PushRenderTarget(albedo, surf.OffsetV, surf.OffsetU, surf.UVHeight, surf.UVWidth)
        render.SetRenderTargetEx(1, normal)
        cam.Start2D()
        surface.DrawTexturedRectRotated(uv.y + gap, uv.x + gap, height, width, localAngles.yaw)
        cam.End2D()
        render.PopRenderTarget()
    end
end
