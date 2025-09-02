---@class ss
local ss = SplashSWEPs
if not ss then return end

-- VTF layout <= 7.2
-- VTF Header
-- for mipmap = smallest, largest do
--   for frame = 1, numFrames do
--     for face = 1, numFaces do
--       for z = zMin, zMax do
--         VTF Image Data
--       end
--     end
--   end
-- end

-- VTF layout >= 7.3
-- VTF Header
-- Resource entries
--   VTF low resolution image data
--   Other resources
--   for mipmap = smallest, largest do
--     for frame = 1, numFrames do
--       for face = 1, numFaces do
--         for z = zMin, zMax do
--           VTF high resolution image data
--         end
--       end
--     end
--   end

local IMAGE_FORMATS = {
    [-1] = "IMAGE_FORMAT_NONE",
    [0] = "IMAGE_FORMAT_RGBA8888",    // = Red, Green, Blue, Alpha - 32 bpp
    "IMAGE_FORMAT_ABGR8888",          // = Alpha, Blue, Green, Red - 32 bpp
    "IMAGE_FORMAT_RGB888",            // = Red, Green, Blue - 24 bpp
    "IMAGE_FORMAT_BGR888",            // = Blue, Green, Red - 24 bpp
    "IMAGE_FORMAT_RGB565",            // = Red, Green, Blue - 16 bpp
    "IMAGE_FORMAT_I8",                // = Luminance - 8 bpp
    "IMAGE_FORMAT_IA88",              // = Luminance, Alpha - 16 bpp
    "IMAGE_FORMAT_P8",                // = Paletted - 8 bpp
    "IMAGE_FORMAT_A8",                // = Alpha- 8 bpp
    "IMAGE_FORMAT_RGB888_BLUESCREEN", // = Red, Green, Blue, "BlueScreen" Alpha - 24 bpp
    "IMAGE_FORMAT_BGR888_BLUESCREEN", // = Red, Green, Blue, "BlueScreen" Alpha - 24 bpp
    "IMAGE_FORMAT_ARGB8888",          // = Alpha, Red, Green, Blue - 32 bpp
    "IMAGE_FORMAT_BGRA8888",          // = Blue, Green, Red, Alpha - 32 bpp
    "IMAGE_FORMAT_DXT1",              // = DXT1 compressed format - 4 bpp
    "IMAGE_FORMAT_DXT3",              // = DXT3 compressed format - 8 bpp
    "IMAGE_FORMAT_DXT5",              // = DXT5 compressed format - 8 bpp
    "IMAGE_FORMAT_BGRX8888",          // = Blue, Green, Red, Unused - 32 bpp
    "IMAGE_FORMAT_BGR565",            // = Blue, Green, Red - 16 bpp
    "IMAGE_FORMAT_BGRX5551",          // = Blue, Green, Red, Unused - 16 bpp
    "IMAGE_FORMAT_BGRA4444",          // = Red, Green, Blue, Alpha - 16 bpp
    "IMAGE_FORMAT_DXT1_ONEBITALPHA",  // = DXT1 compressed format with 1-bit alpha - 4 bpp
    "IMAGE_FORMAT_BGRA5551",          // = Blue, Green, Red, Alpha - 16 bpp
    "IMAGE_FORMAT_UV88",              // = 2 channel format for DuDv/Normal maps - 16 bpp
    "IMAGE_FORMAT_UVWQ8888",          // = 4 channel format for DuDv/Normal maps - 32 bpp
    "IMAGE_FORMAT_RGBA16161616F",     // = Red, Green, Blue, Alpha - 64 bpp
    "IMAGE_FORMAT_RGBA16161616",      // = Red, Green, Blue, Alpha signed with mantissa - 64 bpp
    "IMAGE_FORMAT_UVLX8888",          // = 4 channel format for DuDv/Normal maps - 32 bpp
    "IMAGE_FORMAT_R32F",              // = Luminance - 32 bpp
    "IMAGE_FORMAT_RGB323232F",        // = Red, Green, Blue - 96 bpp
    "IMAGE_FORMAT_RGBA32323232F",     // = Red, Green, Blue, Alpha - 128 bpp
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

---@class ss.Binary.VTF.Header
---@field signature          integer[]
---@field version            integer[]
---@field headerSize         integer
---@field width              integer
---@field height             integer
---@field flags              integer
---@field frames             integer
---@field firstFrame         integer
---@field padding0           integer[]
---@field reflectivity       Vector
---@field padding1           integer[]
---@field bumpmapScale       number
---@field highResImageFormat integer
---@field mipmapCount        integer
---@field lowResImageFormat  integer
---@field lowResImageWidth   integer
---@field lowResImageHeight  integer
---@field depth              integer
---@field padding2           integer[]?
---@field numResources       integer?
---@field padding3           integer[]?
ss.bstruct "VTF.Header" {
    "Byte   signature 4",
    "ULong  version   2",
    "ULong  headerSize",
    "UShort width",
    "UShort height",
    "ULong  flags",
    "UShort frames",
    "UShort firstFrame",
    "Byte   padding0 4",
    "Vector reflectivity",
    "Byte   padding1 4",
    "Float  bumpmapScale",
    "Long   highResImageFormat",
    "Byte   mipmapCount",
    "Long   lowResImageFormat",
    "Byte   lowResImageWidth",
    "Byte   lowResImageHeight",
    "UShort depth",        -- 7.2+
    "Byte   padding2 3",   -- 7.3+
    "ULong  numResources", -- 7.3+
    "Byte   padding3 8",   -- 7.3+
}

---@class ss.Binary.VTF.ResourceEntry
---@field tag integer[]
---@field flags integer
---@field offset integer
ss.bstruct "VTF.ResourceEntry" {
    "String3 tag",
    "Byte    flags",
    "ULong   offset",
}

---@class ss.VTF.Image
---@field Width integer
---@field Height integer
---@field Depth integer
---@field Buffer string
ss.struct "VTF.Image" {
    Width = 1,
    Height = 1,
    Depth = 1,
    Buffer = "\x00",
}

---Decodes RGB565 16-bit integer
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
    local bpp = BYTES_PER_PIXEL[format]
    local idx = ((y - 1) * image.Width + (x - 1)) * bpp + 1
    local pixelData = image.Buffer:sub(idx, idx + bpp - 1)
    local r, g, b, a = 255, 255, 255, 255
    if format == "IMAGE_FORMAT_RGBA8888" then
        r = pixelData:byte(1)
        g = pixelData:byte(2)
        b = pixelData:byte(3)
        a = pixelData:byte(4)
    elseif format == "IMAGE_FORMAT_ABGR8888" then
        a = pixelData:byte(1)
        b = pixelData:byte(2)
        g = pixelData:byte(3)
        r = pixelData:byte(4)
    elseif format == "IMAGE_FORMAT_ARGB8888" then
        a = pixelData:byte(1)
        r = pixelData:byte(2)
        g = pixelData:byte(3)
        b = pixelData:byte(4)
    elseif format == "IMAGE_FORMAT_BGRA8888" then
        b = pixelData:byte(1)
        g = pixelData:byte(2)
        r = pixelData:byte(3)
        a = pixelData:byte(4)
    elseif format == "IMAGE_FORMAT_RGB888" then
        r = pixelData:byte(1)
        g = pixelData:byte(2)
        b = pixelData:byte(3)
    elseif format == "IMAGE_FORMAT_BGR888" then
        b = pixelData:byte(1)
        g = pixelData:byte(2)
        r = pixelData:byte(3)
    elseif format == "IMAGE_FORMAT_A8" then
        a = pixelData:byte(1)
    elseif format == "IMAGE_FORMAT_I8" then
        r = pixelData:byte(1)
        g, b = r, r
    elseif format == "IMAGE_FORMAT_IA88" then
        r = pixelData:byte(1)
        a = pixelData:byte(2)
        g, b = r, r
    elseif format == "IMAGE_FORMAT_RGB565"
        or format == "IMAGE_FORMAT_BGR565" then
        local byte1 = pixelData:byte(1)
        local byte2 = pixelData:byte(2)
        local value = byte1 + bit.lshift(byte2, 8)
        r, g, b = decode565(value)
        if format == "IMAGE_FORMAT_BGR565" then
            r, b = b, r ---@type integer, integer
        end
    elseif format == "IMAGE_FORMAT_DXT1"
        or format == "IMAGE_FORMAT_DXT1_ONEBITALPHA"
        or format == "IMAGE_FORMAT_DXT3"
        or format == "IMAGE_FORMAT_DXT5" then
        -- DXT1: 4x4 blocks, 8 bytes per block
        local blockX = math.floor((x - 1) / 4)
        local blockY = math.floor((y - 1) / 4)
        local blockWidth = math.floor((image.Width + 3) / 4)
        local blockIdx = blockY * blockWidth + blockX
        local bytesPerBlock = 8
        local colorBlockOffset = 0
        if format == "IMAGE_FORMAT_DXT3"
        or format == "IMAGE_FORMAT_DXT5" then
            bytesPerBlock = 16
            colorBlockOffset = 8
        end
        local blockOffset = blockIdx * bytesPerBlock + 1
        local block = image.Buffer:sub(blockOffset, blockOffset + bytesPerBlock - 1)
        local px = (x - 1) % 4
        local py = (y - 1) % 4
        local alpha = 255
        if format == "IMAGE_FORMAT_DXT3" then
            -- Alpha: 8 bytes, 4 bits per pixel
            local alphaWord = block:byte(1 + py * 2) + bit.lshift(block:byte(2 + py * 2), 8)
            alpha = math.floor(bit.band(bit.rshift(alphaWord, px * 4), 0xF) * 255 / 15)
        elseif format == "IMAGE_FORMAT_DXT5" then
            local alpha0 = block:byte(1)
            local alpha1 = block:byte(2)
            local alphaCodes = 0
            local alphaIdx = py * 4 + px
            for i = 6, 1, -1 do
                alphaCodes = bit.lshift(alphaCodes, 8) + block:byte(2 + i)
            end
            local code = bit.band(bit.rshift(alphaCodes, alphaIdx * 3), 0x7) + 1
            if alpha0 > alpha1 then
                alpha = math.floor(((8 - code) * alpha0 + (code - 1) * alpha1) / 7)
            elseif 3 <= code and code <= 6 then
                alpha = math.floor(((6 - code) * alpha0 + (code - 1) * alpha1) / 5)
            elseif code == 7 then
                alpha = 0
            elseif code == 8 then
                alpha = 255
            end
        end

        local color0 = block:byte(colorBlockOffset + 1)
            + bit.lshift(block:byte(colorBlockOffset + 2), 8)
        local color1 = block:byte(colorBlockOffset + 3)
            + bit.lshift(block:byte(colorBlockOffset + 4), 8)
        local codes  = block:byte(colorBlockOffset + 5)
            + bit.lshift(block:byte(colorBlockOffset + 6), 8)
            + bit.lshift(block:byte(colorBlockOffset + 7), 16)
            + bit.lshift(block:byte(colorBlockOffset + 8), 24)
        local c0r, c0g, c0b = decode565(color0)
        local c1r, c1g, c1b = decode565(color1)
        local palette = {
            Color(c0r, c0g, c0b, alpha),
            Color(c1r, c1g, c1b, alpha),
            Color(255, 255, 255, alpha),
            Color(0,   0,   0,   alpha),
        }
        if color0 > color1 or format == "IMAGE_FORMAT_DXT3" then
            palette[3].r = math.floor((2 * c0r + c1r) / 3)
            palette[3].g = math.floor((2 * c0g + c1g) / 3)
            palette[3].b = math.floor((2 * c0b + c1b) / 3)
            palette[4].r = math.floor((c0r + 2 * c1r) / 3)
            palette[4].g = math.floor((c0g + 2 * c1g) / 3)
            palette[4].b = math.floor((c0b + 2 * c1b) / 3)
        else
            palette[3].r = math.floor((c0r + c1r) / 2)
            palette[3].g = math.floor((c0g + c1g) / 2)
            palette[3].b = math.floor((c0b + c1b) / 2)
            palette[4].a = 0
        end
        local codeIdx = py * 4 + px
        local code = bit.band(bit.rshift(codes, codeIdx * 2), 0x3) + 1
        local color = palette[code]

        -- DXT1_ONEBITALPHA: if code==4, alpha=0
        if format == "IMAGE_FORMAT_DXT1_ONEBITALPHA" and code == 4 then
            color.a = 0
        end

        return color
    end
    return Color(r, g, b, a)
end

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
---@param depth integer
---@param format integer
---@return integer
local function getImageSize(width, height, depth, format)
    local str = IMAGE_FORMATS[format]
    if str == "IMAGE_FORMAT_DXT1" or str == "IMAGE_FORMAT_DXT1_ONEBITALPHA" then
        if 0 < width and width < 4 then width = 4 end
        if 0 < height and height < 4 then height = 4 end
        return ((width + 3) / 4) * ((height + 3) / 4) * 8 * depth
    elseif str == "IMAGE_FORMAT_DXT3" or str == "IMAGE_FORMAT_DXT5" then
        if 0 < width and width < 4 then width = 4 end
        if 0 < height and height < 4 then height = 4 end
        return ((width + 3) / 4) * ((height + 3) / 4) * 16 * depth
    else
        return width * height * (BYTES_PER_PIXEL[str] or 0) * depth
    end
end

---Returns the dimensions of a particular mipmap level.
---@param largestWidth integer
---@param largestHeight integer
---@param largestDepth integer
---@param mipmapLevel integer
---@return integer width
---@return integer height
---@return integer depth
local function getMipmapDimensions(largestWidth, largestHeight, largestDepth, mipmapLevel)
    local width = math.max(bit.rshift(largestWidth, mipmapLevel - 1), 1)
    local height = math.max(bit.rshift(largestHeight, mipmapLevel - 1), 1)
    local depth = math.max(bit.rshift(largestDepth, mipmapLevel - 1), 1)
    return width, height, depth
end

---Returns the size of a single mipmap in bytes.
---@param largestWidth integer
---@param largestHeight integer
---@param largestDepth integer
---@param format integer
---@param mipmapLevel integer
---@return integer size
local function getMipmapSize(largestWidth, largestHeight, largestDepth, format, mipmapLevel)
    local width, height, depth = getMipmapDimensions(largestWidth, largestHeight, largestDepth, mipmapLevel)
    return getImageSize(width, height, depth, format)
end

---Calculates total size of the high resolution images in bytes.
---@param header ss.Binary.VTF.Header
---@return integer
local function getTotalImageSize(header)
    local width = header.width
    local height = header.height
    local depth = header.depth
    local mipmapCount = header.mipmapCount
    local format = header.highResImageFormat
    local frames = header.frames
    local total = 0
    for mipmapLevel = 1, mipmapCount do
        total = total + getMipmapSize(width, height, depth, format, mipmapLevel)
    end
    return total * frames
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
            1,
            header.lowResImageFormat)
    end
    return header.headerSize + lowResImageSize
end

---Returns offset to high resolution image for VTF version 7.3+
---@param vtf File
---@param header ss.Binary.VTF.Header
---@return integer
local function getHighResImageOffset73(vtf, header)
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
    local vtf = file.Open(string.format("materials/%s.vtf", path), "rb", "GAME")
    if not vtf then return end

    local header = ss.ReadStructureFromFile(vtf, "VTF.Header")
    local majorVersion = header.version[1]
    local minorVersion = header.version[2]
    if majorVersion ~= 7 then return end
    local offset = -1
    if minorVersion <= 2 then
        offset = getHighResImageOffset72(header)
    else
        offset = getHighResImageOffset73(vtf, header)
    end

    if offset < 0 then return end

    vtf:Seek(offset)
    local buffer = vtf:Read(getTotalImageSize(header))
    local format = header.highResImageFormat
    local frames = header.frames
    local maxWidth = header.width
    local maxHeight = header.height
    local maxDepth = header.depth
    local maxMipmapLevel = header.mipmapCount
    local mipmapOffset = 0
    local imageStack = ss.new "VTF.ImageStack"
    imageStack.ImageFormat = IMAGE_FORMATS[format]
    for mipmapLevel = maxMipmapLevel, 1, -1 do
        local width, height, depth = getMipmapDimensions(maxWidth, maxHeight, maxDepth, mipmapLevel)
        local size = getImageSize(width, height, depth, format) * frames
        local image = ss.new "VTF.Image"
        image.Width = width
        image.Height = height
        image.Depth = depth
        image.Buffer = buffer:sub(mipmapOffset, mipmapOffset + size - 1)
        imageStack.Images[mipmapLevel] = image
        mipmapOffset = mipmapOffset + size
    end

    return imageStack
end
