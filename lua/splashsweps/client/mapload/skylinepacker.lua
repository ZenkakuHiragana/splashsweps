
-- An image packer that places blocks on a skyline, like CImagePacker of Source.

---@class ss
local ss = SplashSWEPs

---@class ss.SkylinePacker
---@field Wavefront integer[] Height of the skyline at each x, 1-based.
---@field MaxWidth integer
---@field MaxHeight integer
---@field MaxBlockWidth integer Width of the smallest block that has failed to fit.
---@field MaxBlockHeight integer Height of the smallest block that has failed to fit.
---@field MinHeight integer Height the placed blocks need, or -1 before any block is placed.
---@field SortID integer
local SkylinePacker = ss.module "splashsweps/client/mapload/skylinepacker"
SkylinePacker.__index = SkylinePacker

---Finds the highest point on the skyline within a given width.
---@param self ss.SkylinePacker
---@param firstX integer
---@param width integer
---@return integer maxY
---@return integer maxYIndex
local function GetMaxY(self, firstX, width)
    local maxY = -1
    local maxYIndex = 0
    for x = firstX, firstX + width - 1 do
        if self.Wavefront[x + 1] >= maxY then
            maxY = self.Wavefront[x + 1]
            maxYIndex = x
        end
    end
    return maxY, maxYIndex
end

---Attempts to add a block to the image.
---@param width integer
---@param height integer
---@return integer? x
---@return integer? y
function SkylinePacker:AddBlock(width, height)
    -- If we've already determined that a block this big couldn't fit
    -- then blow off checking again...
    if width >= self.MaxBlockWidth and height >= self.MaxBlockHeight then
        return
    end

    local bestX = -1
    local outerX = 0
    local outerMinY = self.MaxHeight
    local lastX = self.MaxWidth - width
    local lastMaxYVal = -2

    while outerX <= lastX do
        if self.Wavefront[outerX + 1] == lastMaxYVal then
            outerX = outerX + 1
        else
            local maxY, maxYIndex = GetMaxY(self, outerX, width)
            lastMaxYVal = maxY
            if outerMinY > lastMaxYVal then
                outerMinY = lastMaxYVal
                bestX = outerX
            end
            outerX = maxYIndex + 1
        end
    end

    if bestX == -1 then
        -- If we failed to add it, remember the block size that failed
        -- *only if both dimensions are smaller*!!
        -- Just because a 1x10 block failed, doesn't mean a 10x1 block will fail
        if width <= self.MaxBlockWidth and height <= self.MaxBlockHeight then
            self.MaxBlockWidth = width
            self.MaxBlockHeight = height
        end

        return
    end

    local returnX = bestX
    local returnY = outerMinY + 1
    if returnY + height >= self.MaxHeight - 1 then
        if width <= self.MaxBlockWidth and height <= self.MaxBlockHeight then
            self.MaxBlockWidth = width
            self.MaxBlockHeight = height
        end

        return
    end

    if returnY + height > self.MinHeight then
        self.MinHeight = returnY + height
    end

    for x = bestX, bestX + width - 1 do
        self.Wavefront[x + 1] = outerMinY + height
    end

    return returnX, returnY
end

---Gets the minimum required dimensions for the packed image.
---@return integer width
---@return integer height
function SkylinePacker:GetMinimumDimensions()
    ---@param n integer
    ---@return integer
    local function ceilPow2(n)
        local retval = 1
        while retval < n do
            retval = bit.lshift(retval, 1)
        end
        return retval
    end

    -- In the source code, it seems to get aspect ratio from HardwareConfig()->MaxTextureAspectRatio()
    -- but I will just hardcode it to 8 for now.
    local MAX_ASPECT_RATIO = 16

    local width = ceilPow2(self.MaxWidth)
    local height = ceilPow2(self.MinHeight)

    local aspect = width / height
    if aspect > MAX_ASPECT_RATIO then
        height = width / MAX_ASPECT_RATIO
    end

    return width, height
end

---Creates an empty image packer.
---@param sortID integer
---@param maxWidth integer
---@param maxHeight integer
---@return ss.SkylinePacker
function SkylinePacker.new(sortID, maxWidth, maxHeight)
    local wavefront = {} ---@type integer[]
    for i = 1, maxWidth do
        wavefront[i] = -1
    end

    return setmetatable({
        Wavefront = wavefront,
        MaxWidth = maxWidth,
        MaxHeight = maxHeight,
        MaxBlockWidth = maxWidth + 1,
        MaxBlockHeight = maxHeight + 1,
        MinHeight = -1,
        SortID = sortID,
    }, SkylinePacker)
end

return SkylinePacker
