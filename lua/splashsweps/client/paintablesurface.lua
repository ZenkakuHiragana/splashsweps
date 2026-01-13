
---@class ss
local ss = SplashSWEPs
if not ss then return end

net.Receive("SplashSWEPs: Paint", function()
    local inktype    = net.ReadUInt(ss.MAX_INKTYPE_BITS) + 1 -- Ink type
    local shapeIndex = net.ReadUInt(ss.MAX_INKSHAPE_BITS) + 1 -- Ink shape
    local pitch = net.ReadInt(8) -- Pitch
    local yaw   = net.ReadInt(8) -- Yaw
    local roll  = net.ReadInt(8) -- Roll
    local x     = net.ReadInt(15) * 2 -- X
    local y     = net.ReadInt(15) * 2 -- Y
    local z     = net.ReadInt(15) * 2 -- Z
    local sx    = net.ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale X
    local sy    = net.ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale Y
    local sz    = net.ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale Z
    local pos = Vector(x, y, z)
    local angle = Angle(
        math.Remap(pitch, -128, 127, -180, 180),
        math.Remap(yaw,   -128, 127, -180, 180),
        math.Remap(roll,  -128, 127, -180, 180))
    local scale = Vector(sx, sy, sz)
    ss.Paint(pos, angle, scale, shapeIndex, inktype)
    ss.PaintRenderTarget(pos, angle, scale, shapeIndex, inktype)
end)

---Paints an ink to the render target with given information.
---@param pos     Vector  The origin.
---@param angle   Angle   The normal and rotation.
---@param scale   Vector  Scale along the angles.
---@param shape   integer The internal index of shape to paint.
---@param inktype integer The internal index of ink type.
function ss.PaintRenderTarget(pos, angle, scale, shape, inktype)
    local rt = ss.RenderTarget
    local albedo = rt.StaticTextures.Albedo
    local normal = rt.StaticTextures.Normal
    local pbr    = rt.StaticTextures.PseudoPBR
    local hammerUnitsToPixels = rt.HammerUnitsToPixels

    local gap = ss.RT_MARGIN_PIXELS / 2
    local mins, maxs = ss.GetPaintBoundingBox(pos, angle, scale)
    local width = scale.x * 2 * hammerUnitsToPixels
    local height = scale.y * 2 * hammerUnitsToPixels
    local rotationMatrix = Matrix()
    rotationMatrix:SetAngles(angle)
    surface.SetDrawColor(128, 128, 255, 255)
    surface.SetMaterial(ss.GetInkMaterial(ss.InkTypes[inktype], ss.InkShapes[shape]))
    for surf in ss.CollectSurfaces(mins, maxs) do
        for posWarp, angWarp in ss.EnumeratePaintPositions(surf, mins, maxs, pos, angle) do
            local uv = surf.WorldToUVMatrix * posWarp * hammerUnitsToPixels
            -- local localToWorld = surf.WorldToLocalGridMatrix:GetInverseTR()
            -- debugoverlay.Axis(localToWorld:GetTranslation(), localToWorld:GetAngles(), 100, 3, true)
            -- print(surf.OffsetV, surf.OffsetU)
            -- print(uv)
            local localRotation = surf.WorldToUVMatrix * rotationMatrix
            local localAngles = localRotation:GetAngles()
            render.PushRenderTarget(albedo, surf.OffsetV, surf.OffsetU, surf.UVHeight, surf.UVWidth)
            render.SetRenderTargetEx(1, normal)
            render.SetRenderTargetEx(2, pbr)
            cam.Start2D()
            surface.DrawTexturedRectRotated(uv.y + gap, uv.x + gap, height, width, localAngles.yaw)
            cam.End2D()
            render.PopRenderTarget()
        end
    end
end
