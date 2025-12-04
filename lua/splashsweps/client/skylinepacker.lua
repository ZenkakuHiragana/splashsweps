
---@class ss
local ss = SplashSWEPs
if not ss then return end

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
---@param self ss.SkylinePacker
---@param width integer
---@param height integer
---@return integer? x
---@return integer? y
local function AddBlock(self, width, height)
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

    if bestX == -1 then return end

    local returnX = bestX
    local returnY = outerMinY + 1
    if returnY + height >= self.MaxHeight - 1 then return end

    if returnY + height > self.MinHeight then
        self.MinHeight = returnY + height
    end

    for x = bestX, bestX + width - 1 do
        self.Wavefront[x + 1] = outerMinY + height
    end

    self.AreaUsed = self.AreaUsed + width * height
    return returnX, returnY
end

---Gets the minimum required dimensions for the packed image.
---@param self ss.SkylinePacker
---@return integer width
---@return integer height
local function GetMinimumDimensions(self)
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

---Creates a new image packer.
---@param sortID integer
---@param maxWidth integer
---@param maxHeight integer
---@return ss.SkylinePacker
function ss.MakeSkylinePacker(sortID, maxWidth, maxHeight)
    ---@class ss.SkylinePacker
    local t = {
        Wavefront = {}, ---@type integer[]
        MaxWidth = maxWidth,
        MaxHeight = maxHeight,
        MinHeight = -1,
        AreaUsed = 0,
        SortID = sortID,
        AddBlock = AddBlock,
        GetMinimumDimensions = GetMinimumDimensions,
    }

    for i = 1, t.MaxWidth do
        t.Wavefront[i] = -1
    end

    return t
end
