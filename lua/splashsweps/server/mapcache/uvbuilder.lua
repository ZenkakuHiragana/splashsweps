
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Sets up UV coordinates for precached surface data.
---@param surfaces ss.PrecachedData.Surface[]
---@return integer
function ss.BuildUVCache(surfaces)
    print "Calculation UV coordinates..."
    local numMeshTriangles = 0
    local totalArea = 0
    for _, surf in ipairs(surfaces) do
        local info = surf.UVInfo[1]
        totalArea = totalArea + info.Width * info.Height
        numMeshTriangles = numMeshTriangles + #surf.Vertices / 3
    end

    local t0 = SysTime()
    local estimatedRectangleSize = math.sqrt(totalArea)
    for rtIndex, rtSize in ipairs(ss.RenderTargetSize) do
        local rects = {} ---@type ss.Rectangle[]
        local margin = estimatedRectangleSize / rtSize * ss.RT_MARGIN_PIXELS
        for i, surf in ipairs(surfaces) do
            local info = surf.UVInfo[rtIndex]
            rects[i] = ss.MakeRectangle(info.Width + margin, info.Height + margin, 0, 0, surf)
        end

        local packer = ss.MakeRectanglePacker(rects):packall()
        local rectangleSizeHU = packer.maxsize -- Size of generated rectangle in Hammer Units
        for _, index in ipairs(packer.results) do
            local rect = packer.rects[index]
            local surf = rect.tag ---@type ss.PrecachedData.Surface
            local info = surf.UVInfo[rtIndex]
            local offset = Vector(rect.left + 1, rect.bottom + 1, 0)
            local scale = Vector(rect.width, rect.height, 1)
            if rect.istall then
                scale.x, scale.y = scale.y, scale.x
                info.Transform:Rotate(Angle(0, 90, 0))
                info.Transform:Translate(Vector(0, -scale.y, 0))
            end
            info.Width = scale.x / rectangleSizeHU
            info.Height = scale.y / rectangleSizeHU
            info.Transform:Scale(scale)
            info.Transform:Translate(-offset)
            info.Transform:Invert()
        end

        collectgarbage "collect"
        local elapsed = math.Round((SysTime() - t0) * 1000, 2)
        print("    Render Target size: " .. rtSize .. " (" .. elapsed .. " ms)")
        t0 = SysTime()
    end

    return numMeshTriangles
end
