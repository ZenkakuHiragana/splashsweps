
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Sets up UV coordinates for precached surface data.
---@param surfaces ss.PrecachedData.SurfaceInfo
---@param staticPropInfo ss.PrecachedData.StaticProp.UVInfo[][]
---@param staticPropRectangles Vector[]
function ss.BuildUVCache(surfaces, staticPropInfo, staticPropRectangles)
    print "Calculation UV coordinates..."
    local totalArea = 0
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
    for rtIndex, rtSize in ipairs(ss.RenderTargetSize) do
        local rects = {} ---@type ss.Rectangle[]
        local margin = estimatedRectangleSize * ss.RT_MARGIN_PIXELS / rtSize
        for i, surf in ipairs(surfaces) do
            local info = surf.UVInfo[rtIndex]
            rects[i] = ss.MakeRectangle(info.Width + margin, info.Height + margin, 0, 0, surf)
        end

        for i, uvInfoList in ipairs(staticPropInfo) do
            local info = uvInfoList[rtIndex]
            local rect = staticPropRectangles[i]
            rects[#surfaces + i] = ss.MakeRectangle(rect.x + margin, rect.y + margin, 0, 0, info)
        end

        local packer = ss.MakeRectanglePacker(rects):packall()
        local rectangleSizeHU = packer.maxsize -- Size of generated rectangle in Hammer Units
        surfaces.UVScales[rtIndex] = 1 / rectangleSizeHU
        for _, index in ipairs(packer.results) do
            local rect = packer.rects[index]
            local tag = rect.tag ---@cast tag ss.PrecachedData.Surface
            if tag.UVInfo then
                local info = tag.UVInfo[rtIndex]
                local offset = Vector(rect.left, rect.bottom, 0)
                local width = rect.width - margin
                local height = rect.height - margin
                if rect.istall then
                    width, height = height, width ---@type number, number
                    info.Angle:RotateAroundAxis(info.Angle:Up(), 90)
                    offset:Add(Vector(0, width, 0))
                end
                info.Width  = width / rectangleSizeHU
                info.Height = height / rectangleSizeHU
                workMatrix:Identity()
                workMatrix:SetAngles(info.Angle)
                info.Translation:Sub(workMatrix * offset)

                workMatrix:SetTranslation(info.Translation)
                workMatrix:SetAngles(info.Angle)
                workMatrix = workMatrix:GetInverseTR() -- InvertTR() seems broken #6401
                info.Angle:Set(workMatrix:GetAngles())
                info.Translation:Set(workMatrix:GetTranslation())
            else ---@cast tag ss.PrecachedData.StaticProp.UVInfo
                tag.Width = rect.width / rectangleSizeHU
                tag.Height = rect.height / rectangleSizeHU
                tag.Offset = Vector(rect.left, rect.bottom, 0) / rectangleSizeHU
            end
        end

        local elapsed = math.Round((SysTime() - t0) * 1000, 2)
        print("    Render Target size: " .. rtSize
            .. " (" .. elapsed .. " ms), pixel/hammer unit = "
            .. rtSize / rectangleSizeHU)
        t0 = SysTime()
    end
end
