
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band
local byte = string.byte
local Clamp = math.Clamp
local floor = math.floor
local pow = math.pow

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
    local materialIDs = {} ---@type table<string, integer>
    local needsBumpedLightmaps = {} ---@type boolean[]
    local power2 ---@type number[]
    local linearToScreen ---@type number[]
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
        if t.HasLightmap and t.HasLightStyles then
            if not power2 then
                power2 = {}
                for exp = 1, 128 do
                    power2[exp] = pow(2, exp - 1)
                end
                for exp = 129, 256 do
                    power2[exp] = pow(2, exp - 256 - 1)
                end

                linearToScreen = {}
                for j = 1, 1024 do
                    linearToScreen[j] = Clamp(floor(
                        255 * pow((j - 1) / 1023, 1 / 2.2)), 0, 255)
                end
            end

            local minLightValue = 1
            local maxLightmapIndex = 1
            local offset = (width + 1) * (height + 1)
            if needsBumpedLightmaps[materialID] then
                offset = offset * 4
            end

            while lightStyles[maxLightmapIndex + 1]
              and lightStyles[maxLightmapIndex + 1] ~= 255 do
                maxLightmapIndex = maxLightmapIndex + 1
            end

            for j = maxLightmapIndex, 2, -1 do
                local maxLength = -1
                local maxR, maxG, maxB ---@type number, number, number
                for k = 0, offset - 1 do
                    local ptr = lightOffset + ((j - 1) * offset + k) * 4
                    local r, g, b, e = byte(rawSamples, ptr, ptr + 3)
                    -- TexLightToLinear
                    r = r * power2[e + 1]
                    g = g * power2[e + 1]
                    b = b * power2[e + 1]
                    local length = r * r + g * g + b * b
                    if length > maxLength then
                        maxLength = length
                        maxR = r
                        maxG = g
                        maxB = b
                    end
                end

                if maxR and maxG and maxB then
                    maxR = linearToScreen[Clamp(floor(maxR * 1023), 0, 1023) + 1]
                    maxG = linearToScreen[Clamp(floor(maxG * 1023), 0, 1023) + 1]
                    maxB = linearToScreen[Clamp(floor(maxB * 1023), 0, 1023) + 1]
                    if maxR <= minLightValue and maxG <= minLightValue and maxB <= minLightValue then
                        maxLightmapIndex = maxLightmapIndex - 1
                    end
                end
            end

            if maxLightmapIndex == 1 then
                t.HasLightStyles = nil
            end
        end
        surfaceInfo.Lightmaps[i] = t
    end
end
