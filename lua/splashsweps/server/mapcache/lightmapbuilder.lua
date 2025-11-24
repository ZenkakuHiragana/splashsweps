
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band

-- From public/bspflags.h
local SURF_NOLIGHT = 0x0400

-- From public\materialsystem\imaterial.h
local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)

---Generates lightmap packing information for all faces in a BSP.
---@param bsp ss.RawBSPResults
---@param ishdr boolean
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param cache ss.PrecachedData
function ss.BuildLightmapInfo(bsp, ishdr, surfaceInfo, cache)
    print("    Generating lightmap info (" .. (ishdr and "HDR" or "LDR") .. ")...")
    local faces = ishdr and bsp.FACES_HDR or bsp.FACES
    if not faces or #faces == 0 then return end

    local rawTexInfo   = bsp.TEXINFO
    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA
    local rawSamples   = ishdr and bsp.LIGHTING_HDR or bsp.LIGHTING
    local power2 ---@type number[]
    local materialIDs = {} ---@type table<string, integer>
    local needsBumpedLightmaps = {} ---@type boolean[]
    for i, texName in ipairs(rawTexString) do
        local sanitized = texName:lower():StripExtension():gsub("\\", "/")
        local mat = Material(sanitized)
        needsBumpedLightmaps[i] = mat and not mat:IsError() and
            band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0
        materialIDs[sanitized] = i
        cache.MaterialNames[i] = sanitized
    end

    local faceLumpIndexToSurfaceInfoIndex = {} ---@type integer[]
    for i, surf in ipairs(surfaceInfo.Surfaces) do
        faceLumpIndexToSurfaceInfoIndex[surf.FaceLumpIndex] = i
        surf.FaceLumpIndex = nil
    end

    -- Create a list of face objects with all necessary info for sorting
    for i, rawFace in ipairs(faces) do
        local texInfo     = rawTexInfo[rawFace.texInfo + 1]
        local texData     = rawTexData[texInfo.texData + 1]
        local texOffset   = rawTexDict[texData.nameStringTableID + 1]
        local texIndex    = rawTexIndex[texOffset]
        local texName     = rawTexString[texIndex]
        local materialID  = materialIDs[texName:lower():StripExtension():gsub("\\", "/")] or 0
        local lightOffset = rawFace.lightOffset + 1
        local lightStyles = rawFace.styles
        local width       = rawFace.lightmapTextureSizeInLuxels[1]
        local height      = rawFace.lightmapTextureSizeInLuxels[2]
        local hasLightmap = band(texInfo.flags, SURF_NOLIGHT) == 0 and
                            lightOffset > 0 and width * height > 0
        local t = ss.new "PrecachedData.LightmapInfo"
        t.FaceIndex = faceLumpIndexToSurfaceInfoIndex[i]
        t.HasLightmap = hasLightmap and 1 or nil
        t.HasLightStyles = (lightStyles[1] ~= 0 and
                            lightStyles[1] ~= 255 or
                            lightStyles[2] ~= 255) and 1 or nil
        t.MaterialIndex = materialID
        t.Width = hasLightmap and width + 1 or 0
        t.Height = hasLightmap and height + 1 or 0
        -- CheckSurfaceLighting
        if t.HasLightStyles then
            if not power2 then
                power2 = {}
                for exp = 0, 255 do
                    power2[exp] = math.pow(2, exp - 128)
                end
            end

            local minLightValue = 1 / 1023
            local maxLightmapIndex = 1
            local offset = (width + 1) * (height + 1)
            if needsBumpedLightmaps[materialID] then
                offset = offset * 4
            end

            while lightStyles[maxLightmapIndex + 1]
              and lightStyles[maxLightmapIndex + 1] ~= 255 do
                maxLightmapIndex = maxLightmapIndex + 1
            end

            for j = maxLightmapIndex, 1, -1 do
                local maxLength = -1
                local maxR, maxG, maxB ---@type number, number, number
                for k = 0, offset - 1 do
                    local ptr = lightOffset + ((j - 1) * offset + k) * 4
                    local r, g, b, e = rawSamples:byte(ptr, ptr + 3)
                    local length = r * r + g * g + b * b
                    if length > maxLength then
                        maxLength = length
                        -- TexLightToLinear
                        maxR = r * power2[e]
                        maxG = g * power2[e]
                        maxB = b * power2[e]
                    end
                end
                if maxR < minLightValue and maxG < minLightValue and maxB < minLightValue then
                    maxLightmapIndex = maxLightmapIndex - 1
                end
            end

            t.HasLightStyles = maxLightmapIndex > 1 and 1 or nil
        end
        surfaceInfo.Lightmaps[i] = t
    end
end
