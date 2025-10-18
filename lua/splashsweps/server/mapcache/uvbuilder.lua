
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Sets up UV coordinates for precached surface data.
---@param surfInfo ss.PrecachedData.SurfaceInfo
---@param staticPropInfo ss.PrecachedData.StaticProp.UVInfo[][]
---@param staticPropRectangles Vector[]
function ss.BuildUVCache(surfInfo, staticPropInfo, staticPropRectangles)
    print "Calculation UV coordinates..."
    local totalArea = 0
    local surfaces = surfInfo.Surfaces
    for _, surf in ipairs(surfaces) do
        local info = surf.UVInfo[1]
        totalArea = totalArea + info.Width * info.Height
    end

    for _, rect in ipairs(staticPropRectangles) do
        totalArea = totalArea + rect.x * rect.y ---@type number
    end

    local t0 = SysTime()
    local estimatedRectangleSize = math.sqrt(totalArea)
    local workMatrix = Matrix() -- Work area to invert matrix.
    for rtIndex, rtSize in ipairs(ss.RenderTarget.Resolutions) do
        local rects = {} ---@type ss.Rectangle[]
        local margin = estimatedRectangleSize * ss.RT_MARGIN_PIXELS / rtSize
        for i, surf in ipairs(surfaces) do
            local info = surf.UVInfo[rtIndex]
            rects[i] = ss.MakeRectangle(info.Width + margin, info.Height + margin, 0, 0, surf)
        end

        for i, uvInfoList in ipairs(staticPropInfo) do
            local info = uvInfoList[rtIndex]
            local rect = staticPropRectangles[i]
            local tag = {
                UV = info,
                Rectangle = rect,
            }
            rects[#surfaces + i] = ss.MakeRectangle(rect.x + margin, rect.y + margin, 0, 0, tag)
        end

        local packer = ss.MakeRectanglePacker(rects):packall()
        local rectangleSizeHU = packer.maxsize -- Size of generated rectangle in Hammer Units
        surfInfo.UVScales[rtIndex] = 1 / rectangleSizeHU
        for _, index in ipairs(packer.results) do
            local rect = packer.rects[index]
            local tag = rect.tag ---@cast tag ss.PrecachedData.Surface
            local width = rect.width - margin
            local height = rect.height - margin
            if tag.UVInfo then
                local info = tag.UVInfo[rtIndex]

                -- If the face is rotated in the UV coord.
                if rect.istall ~= (info.Width < info.Height) then
                    info.Angle:RotateAroundAxis(info.Angle:Up(), 90)
                    workMatrix:Identity()
                    workMatrix:SetAngles(info.Angle)
                    info.Translation:Sub(workMatrix * Vector(0, height, 0))
                end

                info.OffsetU = rect.left   / rectangleSizeHU
                info.OffsetV = rect.bottom / rectangleSizeHU
                info.Width   = width       / rectangleSizeHU
                info.Height  = height      / rectangleSizeHU

                workMatrix:SetTranslation(info.Translation)
                workMatrix:SetAngles(info.Angle)
                workMatrix:InvertTR()
                info.Angle:Set(workMatrix:GetAngles())
                info.Translation:Set(workMatrix:GetTranslation())
            else ---@cast tag { UV: ss.PrecachedData.StaticProp.UVInfo, Rectangle: Vector }
                local rotated = rect.istall ~= (tag.Rectangle.x < tag.Rectangle.y)
                tag.UV.Width = width / rectangleSizeHU
                tag.UV.Height = height / rectangleSizeHU
                tag.UV.Offset:SetUnpacked(
                    rect.left / rectangleSizeHU,
                    rect.bottom / rectangleSizeHU,
                    rotated and 1 or 0)
            end
        end

        local elapsed = math.Round((SysTime() - t0) * 1000, 2)
        print("    Render Target size: " .. rtSize
            .. " (" .. elapsed .. " ms), pixel/hammer unit = "
            .. rtSize / rectangleSizeHU)
        t0 = SysTime()
    end
end
