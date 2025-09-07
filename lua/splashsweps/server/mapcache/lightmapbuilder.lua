
---@class ss
local ss = SplashSWEPs
if not ss then return end

local assert   = assert
local ceil     = math.ceil
local clamp    = math.Clamp
local floor    = math.floor
local pow      = math.pow
local round    = math.Round
local sqrt     = math.sqrt
local band     = bit.band
local bor      = bit.bor
local bnot     = bit.bnot
local lshift   = bit.lshift
local rshift   = bit.rshift
local byte     = string.byte
local char     = string.char
local gmatch   = string.gmatch
local sub      = string.sub
local tonumber = tonumber
local utilcrc  = util.CRC

local IDAT_SIZE_LIMIT = 8192
local ZLIB_SIZE_LIMIT = 65535
local NUM_CHANNELS = 4
local BYTES_PER_CHANNEL = 2
local BYTES_PER_PX = BYTES_PER_CHANNEL * NUM_CHANNELS
local BIT_DEPTH   = BYTES_PER_CHANNEL == 1 and "\x08" or "\x10"
local CHANNEL_MAX = BYTES_PER_CHANNEL == 1 and 255    or 65535
local gammaInv = 1 / 2.2
local expConst = -8 + (8 * BYTES_PER_CHANNEL - 1) * 2.2
local marginInLuxels = 1

---@param faces ss.Binary.BSP.FACES[]
---@param surfaces ss.PrecachedData.SurfaceInfo
---@return ss.Rectangle[]
local function GetLightmapBounds(faces, surfaces)
    local out = {} ---@type ss.Rectangle[]
    for i, surf in ipairs(surfaces) do
        local faceIndex = surf.LightmapWidth
        local rawFace = faces[faceIndex]
        if rawFace.lightOffset >= 0 then
            local widthInLuxels = rawFace.lightmapTextureSizeInLuxels[1]
            local heightInLuxels = rawFace.lightmapTextureSizeInLuxels[2]
            local width = widthInLuxels + 1 + marginInLuxels * 2
            local height = heightInLuxels + 1 + marginInLuxels * 2
            out[#out + 1] = ss.MakeRectangle(width, height, 0, 0, surf)
        end
    end

    return out
end

---@param x      integer
---@param y      integer
---@param w      integer
---@param h      integer
---@param offset integer
---@return integer
local function GetLightmapSampleIndex(x, y, w, h, offset)
    x = clamp(x, 1, w) - 1
    y = clamp(y, 1, h) - 1
    return (x + y * w) * 4 + (offset or 0) + 1
end

-- ColorRGBExp32 to sRGB
-- According to Source SDK, conversion steps are as follows:
-- 0. Let x be either r, g, or b
-- 1. Convert x to linear scale luminance
--    x' = (x / 255) * 2^exp
-- 2. Apply gamma correction and overBrightFactor = 0.5
--    x" = (x' ^ (1 / 2.2)) * 0.5
-- 3. Assume x" ranges from 0 to 1 and scale it, then clamp it
--    y' = x" * 65535
--    y  = clamp(y', 0, 65535)
-- In these steps, 2^exp is likely to be very small so precision loss is a concern.
-- I put the following assumption and try to reduce the precision loss.
--    x' = (x / 255) * 2^exp ~ (x / 256) * 2^exp = x * 2 ^ (exp - 8)
--    y' = x" * 65535 ~ x" * 65536 = x" * 2^16
-- Then I could do the following transform:
--    x" = (x * 2 ^ (exp - 8)) ^ (1 / 2.2) * 2^(-1)
--       =  x ^ (1 / 2.2) * 2 ^ ((exp - 8) / 2.2) * 2^(-1)
--    y' =  x ^ (1 / 2.2) * 2 ^ ((exp - 8) / 2.2) * 2^(-1) * 2^16
--       =  x ^ (1 / 2.2) * 2 ^ ((exp - 8 + 15 * 2.2) / 2.2)
--       = (x * 2 ^ (exp - 8 + 15 * 2.2)) ^ (1 / 2.2)
---@param r   integer
---@param g   integer
---@param b   integer
---@param exp integer
---@return integer
---@return integer
---@return integer
local function GetRGB(r, g, b, exp)
    if exp > 127 then exp = exp - 256 end
    return clamp(round(pow(r * pow(2, exp + expConst), gammaInv)), 0, CHANNEL_MAX),
           clamp(round(pow(g * pow(2, exp + expConst), gammaInv)), 0, CHANNEL_MAX),
           clamp(round(pow(b * pow(2, exp + expConst), gammaInv)), 0, CHANNEL_MAX)
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

---Converts x = a * 2^b to Float16 representation using math functions.
---@param a integer from 0x00 to 0xFF
---@param b integer from -128 to +127
---@return integer F Float16 representation
local function to16FM(a, b)
    if a == 0 then return 0x0000 end
    local x = a * pow(2, b - 1)
    local m, k = math.frexp(x)
    local M = clamp(round((m * 2 - 1) * 1024), 0, 1023)
    local E = k - 1 + 15
    if E > 30 then -- +Infinity
        return 0x7C00
    elseif E > 0 then -- Normal numbers
        return bor(lshift(E, 10), band(M, 0x03FF))
    else
        return clamp(round(x * 16777216), 0x0000, 0x03FF)
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
    -- return to16FM(r, exp), to16FM(g, exp), to16FM(b, exp)
    return to16F(r, exp), to16F(g, exp), to16F(b, exp)
end

---ColorRGBExp32 to RGB323232F
---@param r integer
---@param g integer
---@param b integer
---@param exp integer
---@return integer r
---@return integer g
---@return integer b
local function GetRGB32F(r, g, b, exp)
    if exp > 127 then exp = exp - 256 end
    return r * pow(2, exp), g * pow(2, exp), b * pow(2, exp)
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
            local sx, sy = x - marginInLuxels, y - marginInLuxels
            if rect.istall == (sw > sh) then
                ---@type number, number
                sx, sy = sy, sx
            end
            local sampleIndex = GetLightmapSampleIndex(sx, sy, sw, sh, sampleOffset)
            local r, g, b = GetRGB16F(samples:byte(sampleIndex, sampleIndex + 3))
            local bitmapIndex = (bitmapOffset + x - 1 + (y - 1) * size   ) * NUM_CHANNELS
            bitmap[bitmapIndex + 1] = r
            bitmap[bitmapIndex + 2] = g
            bitmap[bitmapIndex + 3] = b
            if NUM_CHANNELS == 4 then
                bitmap[bitmapIndex + 4] = CHANNEL_MAX
            end
        end
    end
end

---Builds uncompressed PNG binary data with given width and height.
---@param width  integer
---@param height integer
---@param data   integer[]
---@return string
local function encodePNG(width, height, data)
    ---@param n integer
    ---@return string
    local function i16(n)
        return char(
            band(0xFF, rshift(n, 8)),
            band(0xFF, rshift(n, 0)))
    end
    ---@param n integer
    ---@return string
    local function i32(n)
        return char(
            band(0xFF, rshift(n, 24)),
            band(0xFF, rshift(n, 16)),
            band(0xFF, rshift(n, 8)),
            band(0xFF, rshift(n, 0)))
    end
    ---@param str      string
    ---@param previous integer?
    ---@return number
    local function adler(str, previous)
        local s1 = band  (previous or 1, 0xFFFF)
        local s2 = rshift(previous or 1, 16)
        for c in gmatch(str, ".") do
            s1 = (s1 + byte(c)) % 65521
            s2 = (s2 + s1) % 65521
        end
        return bor(lshift(s2, 16), s1)
    end
    ---@param name string
    ---@param str  string
    ---@return string
    local function crc(name, str)
        return i32(tonumber(utilcrc(name .. str)) or 0)
    end
    ---@param chunk string
    ---@return string
    local function makeIDAT(chunk)
        assert(#chunk <= IDAT_SIZE_LIMIT)
        return i32(#chunk) .. "IDAT" .. chunk .. crc("IDAT", chunk)
    end
    ---@param length integer
    ---@param islast boolean?
    ---@return string
    local function deflateHeader(length, islast)
        local low    = band(0xFF, rshift(length, 0))
        local high   = band(0xFF, rshift(length, 8))
        local nlow   = band(0xFF, bnot(low))
        local nhigh  = band(0xFF, bnot(high))
        local len    = char(low, high)
        local nlen   = char(nlow, nhigh)
        local header = islast and "\x01" or "\x00"
        return header .. len .. nlen
    end

    local rawPixelDataSize = width * height * BYTES_PER_PX + height
    local numDeflateBlocks = ceil(rawPixelDataSize / ZLIB_SIZE_LIMIT)

    local idats = ""
    local blockCount = 1
    local deflateAdler32 = 1
    local deflateWritten = 0
    local deflateSize = numDeflateBlocks == 1 and rawPixelDataSize or ZLIB_SIZE_LIMIT
    local deflateBuffer = "\x78\x01" .. deflateHeader(deflateSize, numDeflateBlocks == 1)

    ---@param buf string
    ---@return string
    local function addDeflateBuffer(buf)
        if #buf < IDAT_SIZE_LIMIT then return buf end
        idats = idats .. makeIDAT(sub(buf, 1, IDAT_SIZE_LIMIT))
        return sub(buf, IDAT_SIZE_LIMIT + 1)
    end

    ---@param buf string
    local function addPixelData(buf)
        if deflateWritten + #buf > deflateSize then
            blockCount = blockCount + 1
            local split = sub(buf, 1, deflateSize - deflateWritten)
            local rest = sub(buf, deflateSize - deflateWritten + 1)
            local islast = blockCount >= numDeflateBlocks

            deflateSize = islast and rawPixelDataSize % ZLIB_SIZE_LIMIT or ZLIB_SIZE_LIMIT
            local add = split .. deflateHeader(deflateSize, islast) .. rest

            deflateBuffer = addDeflateBuffer(deflateBuffer .. add)
            deflateWritten = #rest
        else
            deflateBuffer = addDeflateBuffer(deflateBuffer .. buf)
            deflateWritten = deflateWritten + #buf
        end
        deflateAdler32 = adler(buf, deflateAdler32)
    end

    for i = 1, width * height * NUM_CHANNELS do
        if i % (width * NUM_CHANNELS) == 1 then addPixelData "\x00" end
        addPixelData(BYTES_PER_CHANNEL == 1 and char(data[i] or 255) or i16(data[i] or 65535))
    end

    deflateBuffer = addDeflateBuffer(deflateBuffer .. i32(deflateAdler32))
    idats = idats .. makeIDAT(deflateBuffer)
    local ihdr = i32(width) .. i32(height) .. BIT_DEPTH .. "\x06\x00\x00\x00"
    return "\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0DIHDR"
        .. ihdr .. crc("IHDR", ihdr) .. idats
        .. "\x00\x00\x00\x00IEND\xAE\x42\x60\x82"
end

-- IMAGE_FORMAT_RGBA16161616F = 0x18
-- IMAGE_FORMAT_RGB323232F = 0x1C
local VTF_HEADER
 = "VTF\x00"    .. "\x07\x00\x00\x00\x02\x00\x00\x00\x50\x00\x00\x00"
.. "%s" .. "%s" .. "\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00"
.. "\x00\x00\x80\x3F\x00\x00\x80\x3F\x00\x00\x80\x3F\x00\x00\x00\x00"
.. "\x00\x00\x80\x3F\x18\x00\x00\x00\x01\xFF\xFF\xFF\xFF\x00\x00\x01"
.. "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

---Builds RGBA16161616F VTF binary with given width and height.
---@param size integer
---@param data integer[]
---@param ishdr boolean
local function WriteVTF(size, data, ishdr)
    ---@param n integer
    ---@return string
    local function i16(n)
        return char(
            band(0xFF, n),
            band(0xFF, rshift(n, 8)))
    end
    local vtf = VTF_HEADER:format(i16(size), i16(size))
    local f = file.Open("splashsweps/" .. game.GetMap() .. (ishdr and "_hdr.vtf" or "_ldr.vtf"), "wb", "DATA")
    f:Write(vtf)
    for i = 1, size * size * NUM_CHANNELS do
        f:WriteUShort(data[i] or 0x0000)
        -- f:WriteFloat(data[i] or 0.0)
    end
    f:Close()
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
---@return string
function ss.BuildLightmapCache(bsp, surfaces, ishdr)
    local t0 = SysTime()
    print "Packing lightmap..."
    local rects = GetLightmapBounds(ishdr and bsp.FACES_HDR or bsp.FACES, surfaces)
    local elapsed = round((SysTime() - t0) * 1000, 2)
    print("    Collected surfaces in " .. elapsed .. " ms.")
    if #rects > 0 then
        t0 = SysTime()
        local packer = ss.MakeRectanglePacker(rects):packall()
        local bitmap = GenerateBitmap(bsp, packer, ishdr) or ""
        WriteLightmapUV(bsp, packer, ishdr)
        WriteVTF(packer.maxsize, bitmap, ishdr)
        elapsed = round((SysTime() - t0) * 1000, 2)
        print("    Packed " .. (ishdr and "HDR" or "LDR") .. " lightmap in " .. elapsed .. " ms.")
        return ""
    end

    return ""
end
