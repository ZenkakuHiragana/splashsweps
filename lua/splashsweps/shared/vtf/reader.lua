---@class ss
local ss = SplashSWEPs
if not ss then return end

-- Parses VTF files and gives an ability to read pixel data of specified mipmap level.
-- Volumetric textures (that has more than a single depth),
-- cubemap textures (that has multiple faces), and
-- animated textures (that has multiple frames) are not supported.
-- Supported formats are:
-- * Uncompressed LDR formats
--   * RGBA8888
--   * BGRA8888
--   * ABGR8888
--   * ARGB8888
--   * RGB888
--   * BGR888
--   * I8
--   * A8
--   * IA88
--   * RGB565
--   * BGR565
-- * DXT compressed formats
--   * DXT1
--   * DXT1 with one bit alpha
--   * DXT3
--   * DXT5

---Decodes RGB565 16-bit integer.
---@param value integer RGB value = 0bRRRR RGGG GGGB BBBB
---@return integer r
---@return integer g
---@return integer b
local function decode565(value)
    local r = math.floor(bit.band(bit.rshift(value, 5 + 6), 0x1F) * 255 / 31)
    local g = math.floor(bit.band(bit.rshift(value, 5),     0x3F) * 255 / 63)
    local b = math.floor(bit.band(           value,         0x1F) * 255 / 31)
    return r, g, b
end

local IMAGE_FORMATS = {
    [-1] = "IMAGE_FORMAT_NONE",
    [0] = "IMAGE_FORMAT_RGBA8888",    -- = Red, Green, Blue, Alpha - 32 bpp
    "IMAGE_FORMAT_ABGR8888",          -- = Alpha, Blue, Green, Red - 32 bpp
    "IMAGE_FORMAT_RGB888",            -- = Red, Green, Blue - 24 bpp
    "IMAGE_FORMAT_BGR888",            -- = Blue, Green, Red - 24 bpp
    "IMAGE_FORMAT_RGB565",            -- = Red, Green, Blue - 16 bpp
    "IMAGE_FORMAT_I8",                -- = Luminance - 8 bpp
    "IMAGE_FORMAT_IA88",              -- = Luminance, Alpha - 16 bpp
    "IMAGE_FORMAT_P8",                -- = Paletted - 8 bpp
    "IMAGE_FORMAT_A8",                -- = Alpha- 8 bpp
    "IMAGE_FORMAT_RGB888_BLUESCREEN", -- = Red, Green, Blue, "BlueScreen" Alpha - 24 bpp
    "IMAGE_FORMAT_BGR888_BLUESCREEN", -- = Red, Green, Blue, "BlueScreen" Alpha - 24 bpp
    "IMAGE_FORMAT_ARGB8888",          -- = Alpha, Red, Green, Blue - 32 bpp
    "IMAGE_FORMAT_BGRA8888",          -- = Blue, Green, Red, Alpha - 32 bpp
    "IMAGE_FORMAT_DXT1",              -- = DXT1 compressed format - 4 bpp
    "IMAGE_FORMAT_DXT3",              -- = DXT3 compressed format - 8 bpp
    "IMAGE_FORMAT_DXT5",              -- = DXT5 compressed format - 8 bpp
    "IMAGE_FORMAT_BGRX8888",          -- = Blue, Green, Red, Unused - 32 bpp
    "IMAGE_FORMAT_BGR565",            -- = Blue, Green, Red - 16 bpp
    "IMAGE_FORMAT_BGRX5551",          -- = Blue, Green, Red, Unused - 16 bpp
    "IMAGE_FORMAT_BGRA4444",          -- = Red, Green, Blue, Alpha - 16 bpp
    "IMAGE_FORMAT_DXT1_ONEBITALPHA",  -- = DXT1 compressed format with 1-bit alpha - 4 bpp
    "IMAGE_FORMAT_BGRA5551",          -- = Blue, Green, Red, Alpha - 16 bpp
    "IMAGE_FORMAT_UV88",              -- = 2 channel format for DuDv/Normal maps - 16 bpp
    "IMAGE_FORMAT_UVWQ8888",          -- = 4 channel format for DuDv/Normal maps - 32 bpp
    "IMAGE_FORMAT_RGBA16161616F",     -- = Red, Green, Blue, Alpha - 64 bpp
    "IMAGE_FORMAT_RGBA16161616",      -- = Red, Green, Blue, Alpha signed with mantissa - 64 bpp
    "IMAGE_FORMAT_UVLX8888",          -- = 4 channel format for DuDv/Normal maps - 32 bpp
    "IMAGE_FORMAT_R32F",              -- = Luminance - 32 bpp
    "IMAGE_FORMAT_RGB323232F",        -- = Red, Green, Blue - 96 bpp
    "IMAGE_FORMAT_RGBA32323232F",     -- = Red, Green, Blue, Alpha - 128 bpp
    "IMAGE_FORMAT_NV_DST16",
    "IMAGE_FORMAT_NV_DST24",
    "IMAGE_FORMAT_NV_INTZ",
    "IMAGE_FORMAT_NV_RAWZ",
    "IMAGE_FORMAT_ATI_DST16",
    "IMAGE_FORMAT_ATI_DST24",
    "IMAGE_FORMAT_NV_NULL",
    "IMAGE_FORMAT_ATI2N",
    "IMAGE_FORMAT_ATI1N",
}
---@type table<string, fun(pixelData: string): Color>
local UNCOMPRESSED_HANDLERS = {
    IMAGE_FORMAT_RGBA8888 = function(pixelData)
        return Color(pixelData:byte(1, 4))
    end,
    IMAGE_FORMAT_ABGR8888 = function(pixelData)
        local a, b, g, r = pixelData:byte(1, 4)
        return Color(r, g, b, a)
    end,
    IMAGE_FORMAT_ARGB8888 = function(pixelData)
        local a, r, g, b = pixelData:byte(1, 4)
        return Color(r, g, b, a)
    end,
    IMAGE_FORMAT_BGRA8888 = function(pixelData)
        local b, g, r, a = pixelData:byte(1, 4)
        return Color(r, g, b, a)
    end,
    IMAGE_FORMAT_RGB888 = function(pixelData)
        local r, g, b = pixelData:byte(1, 3)
        return Color(r, g, b)
    end,
    IMAGE_FORMAT_BGR888 = function(pixelData)
        local b, g, r = pixelData:byte(1, 3)
        return Color(r, g, b)
    end,
    IMAGE_FORMAT_A8 = function(pixelData)
        return Color(255, 255, 255, pixelData:byte(1))
    end,
    IMAGE_FORMAT_I8 = function(pixelData)
        local i = pixelData:byte(1)
        return Color(i, i, i)
    end,
    IMAGE_FORMAT_IA88 = function(pixelData)
        local i, a = pixelData:byte(1, 2)
        return Color(i, i, i, a)
    end,
    IMAGE_FORMAT_RGB565 = function(pixelData)
        local byte1, byte2 = pixelData:byte(1, 2)
        local r, g, b = decode565(byte1 + bit.lshift(byte2, 8))
        return Color(r, g, b)
    end,
    IMAGE_FORMAT_BGR565 = function(pixelData)
        local byte1, byte2 = pixelData:byte(1, 2)
        local b, g, r = decode565(byte1 + bit.lshift(byte2, 8))
        return Color(r, g, b)
    end,
}
local IS_DXT = {
    IMAGE_FORMAT_DXT1 = true,
    IMAGE_FORMAT_DXT1_ONEBITALPHA = true,
    IMAGE_FORMAT_DXT3 = true,
    IMAGE_FORMAT_DXT5 = true,
}
local IS_DXT3_OR_DXT5 = {
    IMAGE_FORMAT_DXT3 = true,
    IMAGE_FORMAT_DXT5 = true,
}
local DXT_BYTES_PER_BLOCK = {
    IMAGE_FORMAT_DXT1 = 8,
    IMAGE_FORMAT_DXT1_ONEBITALPHA = 8,
    IMAGE_FORMAT_DXT3 = 16,
    IMAGE_FORMAT_DXT5 = 16,
}
local DXT_BLOCK_RGB_OFFSET = {
    IMAGE_FORMAT_DXT1 = 0,
    IMAGE_FORMAT_DXT1_ONEBITALPHA = 0,
    IMAGE_FORMAT_DXT3 = 8,
    IMAGE_FORMAT_DXT5 = 8,
}
local BYTES_PER_PIXEL = {
    IMAGE_FORMAT_RGBA8888          = 4, -- Implemented
    IMAGE_FORMAT_ABGR8888          = 4, -- Implemented
    IMAGE_FORMAT_RGB888            = 3, -- Implemented
    IMAGE_FORMAT_BGR888            = 3, -- Implemented
    IMAGE_FORMAT_RGB565            = 2, -- Implemented
    IMAGE_FORMAT_I8                = 1, -- Implemented
    IMAGE_FORMAT_IA88              = 2, -- Implemented
    IMAGE_FORMAT_P8                = 1,
    IMAGE_FORMAT_A8                = 1, -- Implemented
    IMAGE_FORMAT_RGB888_BLUESCREEN = 3,
    IMAGE_FORMAT_BGR888_BLUESCREEN = 3,
    IMAGE_FORMAT_ARGB8888          = 4, -- Implemented
    IMAGE_FORMAT_BGRA8888          = 4, -- Implemented
    IMAGE_FORMAT_DXT1              = 0, -- Implemented
    IMAGE_FORMAT_DXT3              = 0, -- Implemented
    IMAGE_FORMAT_DXT5              = 0, -- Implemented
    IMAGE_FORMAT_BGRX8888          = 4,
    IMAGE_FORMAT_BGR565            = 2, -- Implemented
    IMAGE_FORMAT_BGRX5551          = 2,
    IMAGE_FORMAT_BGRA4444          = 2,
    IMAGE_FORMAT_DXT1_ONEBITALPHA  = 0, -- Implemented
    IMAGE_FORMAT_BGRA5551          = 2,
    IMAGE_FORMAT_UV88              = 2,
    IMAGE_FORMAT_UVWQ8899          = 4,
    IMAGE_FORMAT_RGBA16161616F     = 8,
    IMAGE_FORMAT_RGBA16161616      = 8,
    IMAGE_FORMAT_UVLX8888          = 4,
    IMAGE_FORMAT_R32F              = 4,
    IMAGE_FORMAT_RGB323232F        = 12,
    IMAGE_FORMAT_RGBA32323232F     = 16,
    IMAGE_FORMAT_NV_DST16          = 2,
    IMAGE_FORMAT_NV_DST24          = 3,
    IMAGE_FORMAT_NV_INTZ           = 4,
    IMAGE_FORMAT_NV_RAWZ           = 4,
    IMAGE_FORMAT_ATI_DST16         = 2,
    IMAGE_FORMAT_ATI_DST24         = 3,
    IMAGE_FORMAT_NV_NULL           = 4,
    IMAGE_FORMAT_ATI1N             = 0.5,
    IMAGE_FORMAT_ATI2N             = 1,
}

---The VTF header.
---@class ss.Binary.VTF.Header
---@field signature          string,
---@field version            integer[]
---@field headerSize         integer
---@field width              integer
---@field height             integer
---@field flags              integer
---@field frames             integer
---@field firstFrame         integer
---@field padding0           string
---@field reflectivity       Vector
---@field padding1           string
---@field bumpmapScale       number
---@field highResImageFormat integer
---@field mipmapCount        integer
---@field lowResImageFormat  integer
---@field lowResImageWidth   integer
---@field lowResImageHeight  integer
---@field depth              integer
---@field padding2           string?
---@field numResources       integer?
---@field padding3           string?
ss.bstruct "VTF.Header" {
    "4      signature",
    "ULong  version 2",
    "ULong  headerSize",
    "UShort width",
    "UShort height",
    "ULong  flags",
    "UShort frames",
    "UShort firstFrame",
    "4      padding0",
    "Vector reflectivity",
    "4      padding1",
    "Float  bumpmapScale",
    "Long   highResImageFormat",
    "Byte   mipmapCount",
    "Long   lowResImageFormat",
    "Byte   lowResImageWidth",
    "Byte   lowResImageHeight",
    "UShort depth",        -- 7.2+
    "3      padding2",     -- 7.3+
    "ULong  numResources", -- 7.3+
    "8      padding3",     -- 7.3+
}

---@class ss.Binary.VTF.ResourceEntry
---@field tag string
---@field flags integer
---@field offset integer
ss.bstruct "VTF.ResourceEntry" {
    "3     tag",
    "Byte  flags",
    "ULong offset",
}

---@class ss.VTF.Image
---@field Width integer
---@field Height integer
---@field Buffer string
ss.struct "VTF.Image" {
    Width = 1,
    Height = 1,
    Buffer = "",
}

---Reads a pixel located at x, y for given mipmap level.
---@param vtf ss.VTF.ImageStack
---@param x integer
---@param y integer
---@param mipmapLevel integer?
---@return Color
function ss.ReadPixelFromVTF(vtf, x, y, mipmapLevel)
    local format = vtf.ImageFormat
    local image = vtf.Images[mipmapLevel or 1]
    if not image then return color_transparent end
    if UNCOMPRESSED_HANDLERS[format] then
        local length = BYTES_PER_PIXEL[format]
        local offset = (y * image.Width + x) * length + 1
        local pixelData = image.Buffer:sub(offset, offset + length - 1)
        return UNCOMPRESSED_HANDLERS[format](pixelData)
    elseif IS_DXT[format] then
        local blockX = bit.rshift(x, 2)
        local blockY = bit.rshift(y, 2)
        local blockWidth = math.ceil(image.Width / 4)
        local blockIndex = blockY * blockWidth + blockX
        local bytesPerBlock = DXT_BYTES_PER_BLOCK[format]
        local blockOffset = blockIndex * bytesPerBlock + DXT_BLOCK_RGB_OFFSET[format]
        local blockData = image.Buffer:sub(blockOffset + 1, blockOffset + 8)
        local px, py = x % 4, y % 4

        local alpha = 255
        if IS_DXT3_OR_DXT5[format] then
            local alphaOffset = blockIndex * bytesPerBlock
            local alphaData = image.Buffer:sub(alphaOffset + 1, alphaOffset + 8)
            if format == "IMAGE_FORMAT_DXT3" then
                -- Alpha: 8 bytes, 4 bits per pixel
                local value = alphaData:byte(py * 2 + ((px / 2 < 1) and 1 or 2))
                if px % 2 > 0 then value = bit.rshift(value, 4) end
                alpha = math.Remap(bit.band(value, 0x0F), 0x00, 0x0F, 0, 255)
            elseif format == "IMAGE_FORMAT_DXT5" then
                local offset = (py / 2 < 1) and 3 or 6
                local alpha0, alpha1 = alphaData:byte(1, 2)
                local c1, c2, c3 = alphaData:byte(offset, offset + 2)
                local alphaCodes = c1 + bit.lshift(c2, 8) + bit.lshift(c3, 16)
                local alphaIndex = (py % 2) * 4 + px
                local code = bit.band(bit.rshift(alphaCodes, alphaIndex * 3), 0x07)
                if code == 0 then
                    alpha = alpha0
                elseif code == 1 then
                    alpha = alpha1
                elseif alpha0 > alpha1 then
                    alpha = math.floor(((8 - code) * alpha0 + (code - 1) * alpha1 + 3) / 7)
                elseif 2 <= code and code <= 5 then
                    alpha = math.floor(((6 - code) * alpha0 + (code - 1) * alpha1 + 2) / 5)
                elseif code == 6 then
                    alpha = 0
                elseif code == 7 then
                    alpha = 255
                end
            end
        end

        local v1, v2, v3, v4, v5, v6, v7, v8 = blockData:byte(1, 8)
        local color0 = v1 + bit.lshift(v2, 8)
        local color1 = v3 + bit.lshift(v4, 8)
        local codes  = v5 + bit.lshift(v6, 8) + bit.lshift(v7, 16) + bit.lshift(v8, 24)

        local codeIndex = py * 4 + px
        local paletteIndex = bit.band(bit.rshift(codes, codeIndex * 2), 0x3) + 1
        if format == "IMAGE_FORMAT_DXT1_ONEBITALPHA" and paletteIndex == 4 then
            return color_transparent
        end

        local r0, g0, b0 = decode565(color0)
        local r1, g1, b1 = decode565(color1)
        if IS_DXT3_OR_DXT5[format] or color0 > color1 then
            return ({
                Color(r0, g0, b0, alpha),
                Color(r1, g1, b1, alpha),
                Color(math.floor((2 * r0 + r1 + 1) / 3),
                      math.floor((2 * g0 + g1 + 1) / 3),
                      math.floor((2 * b0 + b1 + 1) / 3),
                      alpha),
                Color(math.floor((r0 + 2 * r1 + 1) / 3),
                      math.floor((g0 + 2 * g1 + 1) / 3),
                      math.floor((b0 + 2 * b1 + 1) / 3),
                      alpha),
            })[paletteIndex]
        else
            return ({
                Color(r0, g0, b0, alpha),
                Color(r1, g1, b1, alpha),
                Color(math.floor((r0 + r1) / 2),
                      math.floor((g0 + g1) / 2),
                      math.floor((b0 + b1) / 2),
                      alpha),
                color_transparent,
            })[paletteIndex]
        end
    end
    return color_transparent
end

---Texture data that holds all mipmaps.
---@class ss.VTF.ImageStack
---@field ImageFormat string
---@field Images ss.VTF.Image[]
ss.struct "VTF.ImageStack" {
    ImageFormat = "IMAGE_FORMAT_NONE",
    Images = {},
}

---Calculates image size in the given format in bytes.
---@param width integer
---@param height integer
---@param format integer
---@return integer
local function getImageSize(width, height, format)
    local f = IMAGE_FORMATS[format]
    if IS_DXT[f] then
        return math.ceil(width / 4) * math.ceil(height / 4) * DXT_BYTES_PER_BLOCK[f]
    else
        return width * height * (BYTES_PER_PIXEL[f] or 0)
    end
end

---Returns the dimensions of a particular mipmap level.
---@param largestWidth integer
---@param largestHeight integer
---@param mipmapLevel integer
---@return integer width
---@return integer height
local function getMipmapDimensions(largestWidth, largestHeight, mipmapLevel)
    local width = math.max(bit.rshift(largestWidth, mipmapLevel - 1), 1)
    local height = math.max(bit.rshift(largestHeight, mipmapLevel - 1), 1)
    return width, height
end

---Returns the size of a single mipmap in bytes.
---@param largestWidth integer
---@param largestHeight integer
---@param format integer
---@param mipmapLevel integer
---@return integer size
local function getMipmapSize(largestWidth, largestHeight, format, mipmapLevel)
    local width, height = getMipmapDimensions(largestWidth, largestHeight, mipmapLevel)
    return getImageSize(width, height, format)
end

---Calculates total size of the high resolution images in bytes.
---Volumetric or animated textures are not compatible: assuming depth == 1 and frames == 1.
---@param header ss.Binary.VTF.Header
---@return integer
local function getTotalImageSize(header)
    local width = header.width
    local height = header.height
    local mipmapCount = header.mipmapCount
    local format = header.highResImageFormat
    local total = 0
    for mipmapLevel = 1, mipmapCount do
        total = total + getMipmapSize(width, height, format, mipmapLevel)
    end
    return total
end

---Returns offset to high resolution image for VTF version 7.2
---@param header ss.Binary.VTF.Header
---@return integer
local function getHighResImageOffset72(header)
    header.numResources = 0
    if header.version[2] < 2 then header.depth = 1 end
    local lowResImageSize = 0
    if header.lowResImageFormat ~= -1 then
        lowResImageSize = getImageSize(
            header.lowResImageWidth,
            header.lowResImageHeight,
            header.lowResImageFormat)
    end
    return header.headerSize + lowResImageSize
end

---Returns offset to high resolution image for VTF version 7.3+
---@param header ss.Binary.VTF.Header
---@param vtf File
---@return integer
local function getHighResImageOffset73(header, vtf)
    for _ = 1, math.min(header.numResources, 32) do
        local resource = ss.ReadStructureFromFile(vtf, "VTF.ResourceEntry")
        if resource.tag == "\x30\x00\x00" then
            return resource.offset
        end
    end

    return -1
end

---Reads VTF file.
---@param path string The path to VTF relative to materials/ folder without extension.
---@return ss.VTF.ImageStack?
function ss.ReadVTF(path)
    if not path:EndsWith ".vtf" then path = path .. ".vtf" end
    local vtf = file.Open(string.format("materials/%s", path), "rb", "GAME")
    if not vtf then return end

    local header = ss.ReadStructureFromFile(vtf, "VTF.Header")
    local minorVersion = header.version[2]
    if header.signature ~= "VTF\x00" then return end
    if header.version[1] ~= 7 then return end
    if header.depth ~= 1 and minorVersion >= 2 then return end
    if header.frames ~= 1 then return end
    if header.firstFrame ~= 0 then return end
    if not (1 <= minorVersion and minorVersion <= 5) then return end

    local offset = minorVersion <= 2
        and getHighResImageOffset72(header)
        or getHighResImageOffset73(header, vtf)
    if offset < header.headerSize then return end
    if offset >= vtf:Size() then return end

    vtf:Seek(offset)
    local buffer = vtf:Read(getTotalImageSize(header))
    local format = header.highResImageFormat
    local maxWidth = header.width
    local maxHeight = header.height
    local maxMipmapLevel = header.mipmapCount
    local mipmapOffset = 1
    local imageStack = ss.new "VTF.ImageStack"
    imageStack.ImageFormat = IMAGE_FORMATS[format]
    for mipmapLevel = maxMipmapLevel, 1, -1 do
        local width, height = getMipmapDimensions(maxWidth, maxHeight, mipmapLevel)
        local size = getImageSize(width, height, format)
        local image = ss.new "VTF.Image"
        image.Width = width
        image.Height = height
        image.Buffer = buffer:sub(mipmapOffset, mipmapOffset + size - 1)
        imageStack.Images[mipmapLevel] = image
        mipmapOffset = mipmapOffset + size
    end

    return imageStack
end

---Prints VTF to the console
---@param vtf ss.VTF.ImageStack
---@param channel string?
---@param mipmapLevel integer?
function ss.PrintVTF(vtf, channel, mipmapLevel)
    channel = (channel or "rgb"):lower()
    mipmapLevel = mipmapLevel or 1
    local s = {} ---@type string[]
    local CONVERSION
        = " `.-':_,^=;><+!rc*/z?sLTv)J7(|Fi{C}fI31tlu[neoZ5Yxjya]2ESSwwqqkk"
        .. "PP66hh99dd44VVppOOGGbbUUAAKKXXHHmm88RRDD##$$BBgg00MMNNWWQQ%%&&@@"
    local width = vtf.Images[mipmapLevel].Width
    local height = vtf.Images[mipmapLevel].Height
    width = math.min(width, 225)
    -- height = math.min(height, 225)
    for y = 0, height - 1, 2 do
        s[#s + 1] = ""
        for x = 0, width - 1 do
            local c1 = ss.ReadPixelFromVTF(vtf, x, y, mipmapLevel)
            local c2 = ss.ReadPixelFromVTF(vtf, x, y + 1, mipmapLevel)
            local scale = 0
            if channel:find "r" then scale = scale + (c1.r + c2.r) / 2 end
            if channel:find "g" then scale = scale + (c1.g + c2.g) / 2 end
            if channel:find "b" then scale = scale + (c1.b + c2.b) / 2 end
            if channel:find "a" then scale = scale + (c1.a + c2.a) / 2 end
            if channel:find "r" and channel:find "g" and channel:find "b" then
                local g1 = c1:ToVector():Dot(ss.GrayScaleFactor) * 255
                local g2 = c2:ToVector():Dot(ss.GrayScaleFactor) * 255
                scale = (g1 + g2) / 2
            else
                scale = scale / #channel
            end
            local i = math.Clamp(math.Round(scale / 2) + 1, 1, 128)
            s[#s] = s[#s] .. CONVERSION:sub(i, i)
        end
    end
    for _, si in ipairs(s) do print(si) end
end
