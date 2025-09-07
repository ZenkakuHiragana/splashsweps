
---@class ss
local ss = SplashSWEPs
if not ss then return end

local clamp    = math.Clamp
local round    = math.Round
local band     = bit.band
local bor      = bit.bor
local lshift   = bit.lshift
local rshift   = bit.rshift
local tonumber = tonumber

local NUM_CHANNELS = 4
local MARGIN_IN_LUXELS = 1

---Picks up width and height of all surfaces from their lightmap info and packs them to an array.
---@param faces ss.Binary.BSP.FACES[]
---@param surfaces ss.PrecachedData.SurfaceInfo
---@return ss.Rectangle[]
local function CreateRectangles(faces, surfaces)
    local out = {} ---@type ss.Rectangle[]
    for _, surf in ipairs(surfaces) do
        local faceIndex = surf.LightmapWidth -- Index was written here temporarily in surfacebulder.lua
        local rawFace = faces[faceIndex]
        if rawFace.lightOffset >= 0 then
            local widthInLuxels = rawFace.lightmapTextureSizeInLuxels[1]
            local heightInLuxels = rawFace.lightmapTextureSizeInLuxels[2]
            local width = widthInLuxels + 1 + MARGIN_IN_LUXELS * 2
            local height = heightInLuxels + 1 + MARGIN_IN_LUXELS * 2
            out[#out + 1] = ss.MakeRectangle(width, height, 0, 0, surf)
        end
    end

    return out
end

---2^k = POWER_OF_TWO[k]
local POWER_OF_TWO = { [0] = 1, 2, 4, 8, 16, 32, 64, 128 }

---= math.floor(math.log(x, 2))
---@param x integer
---@return integer k = math.floor(math.log(x, 2))
local function floorlog2(x)
    local k = 0
    if band(x, 0xF0) ~= 0 then x = rshift(x, 4) k = k + 4 end
    if band(x, 0x0C) ~= 0 then x = rshift(x, 2) k = k + 2 end
    if band(x, 0x02) ~= 0 then return               k + 1 end
    return k
end

---Converts x = a * 2^b to Float16 representation.
---@param a integer from 0x00 to 0xFF
---@param b integer from -128 to +127
---@return integer F Float16 representation
local function to16F(a, b)
    if a == 0 then return 0x0000 end
    local k = floorlog2(a)
    local exp = k + b - 2 -- -2 means overbright factor = x0.25
    if exp > 15 then -- +Infinity
        return 0x7C00
    elseif exp > -15 then -- Normal numbers
        return bor(
           lshift(exp + 15, 10),
           band(lshift(a - POWER_OF_TWO[k], 10 - k), 0x03FF))
    else -- Subnormal numbers
        exp = b + 24
        return exp > 0
           and band(lshift(a, exp), 0x03FF)
           or  band(rshift(a, exp), 0x03FF)
    end
end

---ColorRGBExp32 to RGB161616F
---@param r integer
---@param g integer
---@param b integer
---@param exp integer
---@return integer r
---@return integer g
---@return integer b
local function GetRGB16F(r, g, b, exp)
    if exp > 127 then exp = exp - 256 end
    return to16F(r, exp), to16F(g, exp), to16F(b, exp)
end

---@param bitmap  integer[]
---@param size    integer
---@param rect    ss.Rectangle
---@param rawFace ss.Binary.BSP.FACES
---@param samples string
local function UpdateBitmap(bitmap, size, rect, rawFace, samples)
    local x0, y0 = rect.left, rect.bottom
    local sw = rawFace.lightmapTextureSizeInLuxels[1] + 1
    local sh = rawFace.lightmapTextureSizeInLuxels[2] + 1
    local sampleOffset = rawFace.lightOffset
    local bitmapOffset = x0 + y0 * size
    for y = 1, rect.height do
        for x = 1, rect.width do
            local sx, sy = x - MARGIN_IN_LUXELS, y - MARGIN_IN_LUXELS
            if rect.istall == (sw > sh) then
                sx, sy = sy, sx ---@type number, number
            end
            sx = clamp(sx, 1, sw) - 1
            sy = clamp(sy, 1, sh) - 1
            local sampleIndex =  (sx + sy * sw) * 4 + (sampleOffset or 0) + 1
            local r, g, b = GetRGB16F(samples:byte(sampleIndex, sampleIndex + 3))
            local bitmapIndex = (bitmapOffset + x - 1 + (y - 1) * size) * NUM_CHANNELS
            bitmap[bitmapIndex + 1] = r
            bitmap[bitmapIndex + 2] = g
            bitmap[bitmapIndex + 3] = b
            if NUM_CHANNELS == 4 then
                bitmap[bitmapIndex + 4] = 0x3C00 -- +1.0 in Float16
            end
        end
    end
end

---@param bsp ss.RawBSPResults
---@param packer ss.RectanglePacker
---@param ishdr boolean
---@return integer[]
local function GenerateBitmap(bsp, packer, ishdr)
    local bitmap = {}
    local size = packer.maxsize
    local samples = ishdr and bsp.LIGHTING_HDR or bsp.LIGHTING
    local faces = ishdr and bsp.FACES_HDR or bsp.FACES
    if not samples then return {} end
    for _, index in ipairs(packer.results) do
        local rect = packer.rects[index]
        local surf = rect.tag ---@type ss.PrecachedData.Surface
        local faceIndex = surf.LightmapWidth
        local rawFace = faces[faceIndex]
        UpdateBitmap(bitmap, size, rect, rawFace, samples)
    end

    return bitmap
end

---@param bsp ss.RawBSPResults
---@param packer ss.RectanglePacker
---@param ishdr boolean
local function WriteLightmapUV(bsp, packer, ishdr)
    local size = packer.maxsize
    local faces = ishdr and bsp.FACES_HDR or bsp.FACES
    local rawTexInfo = bsp.TEXINFO
    for _, index in ipairs(packer.results) do
        local rect = packer.rects[index]
        local surf = rect.tag ---@type ss.PrecachedData.Surface
        local faceIndex = surf.LightmapWidth
        local rawFace = faces[faceIndex]
        local s0, t0 = rect.left + 1, rect.bottom + 1
        local sw = rawFace.lightmapTextureSizeInLuxels[1] + 1
        local sh = rawFace.lightmapTextureSizeInLuxels[2] + 1
        surf.LightmapWidth = sw / size
        surf.LightmapHeight = sh / size
        if rawFace.dispInfo >= 0 then
            for _, v in ipairs(surf.Vertices) do
                local s = v.LightmapSamplePoint.x * sw
                local t = v.LightmapSamplePoint.y * sh
                if rect.istall == (sw > sh) then
                    s, t = t, s ---@type number, number
                end
                v.LightmapUV.x = (s + s0) / size
                v.LightmapUV.y = (t + t0) / size
            end
        else
            local texInfo = rawTexInfo[rawFace.texInfo + 1]
            local basisS = texInfo.lightmapVecS
            local basisT = texInfo.lightmapVecT
            local offsetS = texInfo.lightmapOffsetS
            local offsetT = texInfo.lightmapOffsetT
            local minsInLuxelsS = rawFace.lightmapTextureMinsInLuxels[1]
            local minsInLuxelsT = rawFace.lightmapTextureMinsInLuxels[2]
            for _, v in ipairs(surf.Vertices) do
                local s = basisS:Dot(v.Translation) + offsetS - minsInLuxelsS
                local t = basisT:Dot(v.Translation) + offsetT - minsInLuxelsT
                if rect.istall == (sw > sh) then
                    s, t = t, s ---@type number, number
                end
                v.LightmapUV.x = (s + s0) / size
                v.LightmapUV.y = (t + t0) / size
            end
        end
    end
end

---Builds RGBA16161616F VTF binary with given width and height.
---@param size integer
---@param data integer[]
---@param ishdr boolean
local function WriteBinary(size, data, ishdr)
    ---@type ss.Binary.VTF.Header
    local header = {
        signature          = "VTF\x00",
        version            = { 7, 2 },
        headerSize         = 0x50,
        width              = size,
        height             = size,
        flags              = 0,
        frames             = 1,
        firstFrame         = 0,
        padding0           = "\x00\x00\x00\x00",
        reflectivity       = ss.vector_one,
        padding1           = "\x00\x00\x00\x00",
        bumpmapScale       = 1.0,
        highResImageFormat = 0x18, -- IMAGE_FORMAT_RGBA16161616F
        mipmapCount        = 1,
        lowResImageFormat  = -1,
        lowResImageWidth   = 0,
        lowResImageHeight  = 0,
        depth              = 1,
        padding2           = "\x00\x00\x00",
        numResources       = 0,
        padding3           = "\x00\x00\x00\x00\x00\x00\x00\x00",
    }
    local fmt = "splashsweps/%s_%s.vtf"
    local path = fmt:format(game.GetMap(), ishdr and "hdr" or "ldr")
    local f = file.Open(path, "wb", "DATA")
    ss.WriteStructureToFile(f, "VTF.Header", header)
    for i = 1, size * size * NUM_CHANNELS do
        f:WriteUShort(data[i] or 0x0000)
    end
    f:Close()
end

---Finds light_environment entity in the ENTITIES lump and fetches directional light info.
---@param bsp ss.RawBSPResults
---@return Color ldr, Color hdr, number scale
function ss.FindLightEnvironment(bsp)
    for _, entities in ipairs(bsp.ENTITIES) do
        for k in entities:gmatch "{[^}]+}" do
            if k:find "light_environment" then
                local t = util.KeyValuesToTable("\"-\" " .. k)
                if t.classname == "light_environment" then
                    local lightScaleHDR = t._lightscalehdr
                    local lightColor    = t._light:Split " "
                    local lightColorHDR = t._lighthdr and t._lighthdr:Split " " or {}
                    local nlightColor = {} ---@type number[]
                    local nlightColorHDR = {} ---@type number[]
                    for i = 1, 4 do
                        nlightColor[i] = tonumber(lightColor[i])
                        nlightColorHDR[i] = tonumber(lightColorHDR[i])
                        if not nlightColorHDR[i] or nlightColorHDR[i] < 0 then
                            nlightColorHDR[i] = nlightColor[i]
                        end
                    end
                    print(string.format("    light_environment found:\n"
                        .. "        lightColor    = [%s %s %s %s]\n"
                        .. "        lightColorHDR = [%s %s %s %s]\n"
                        .. "        lightScaleHDR = %s",
                        lightColor[1], lightColor[2], lightColor[3], lightColor[4],
                        lightColorHDR[1], lightColorHDR[2], lightColorHDR[3], lightColorHDR[4],
                        lightScaleHDR))
                    return Color(unpack(nlightColor)),
                           Color(unpack(nlightColorHDR)),
                           tonumber(lightScaleHDR) or 1
                end
            end
        end
    end

    return color_transparent, color_transparent, 1
end

---Sets up lightmap info for the cache.
---@param bsp ss.RawBSPResults
---@param surfaces ss.PrecachedData.SurfaceInfo
---@param ishdr boolean
function ss.BuildLightmapCache(bsp, surfaces, ishdr)
    local t0 = SysTime()
    print "Packing lightmap..."
    local rects = CreateRectangles(ishdr and bsp.FACES_HDR or bsp.FACES, surfaces)
    local elapsed = round((SysTime() - t0) * 1000, 2)
    print("    Collected surfaces in " .. elapsed .. " ms.")
    if #rects > 0 then
        t0 = SysTime()
        local packer = ss.MakeRectanglePacker(rects):packall()
        local bitmap = GenerateBitmap(bsp, packer, ishdr) or {}
        WriteLightmapUV(bsp, packer, ishdr)
        WriteBinary(packer.maxsize, bitmap, ishdr)
        elapsed = round((SysTime() - t0) * 1000, 2)
        print("    Packed " .. (ishdr and "HDR" or "LDR") .. " lightmap in " .. elapsed .. " ms.")
    end
end
