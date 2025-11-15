
---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.SkylinePacker
---@field Wavefront integer[]
---@field MaxWidth integer
---@field MaxHeight integer
---@field MinHeight integer
---@field AreaUsed integer
---@field SortID integer
ss.struct "SkylinePacker" {
    Wavefront = {},
    MaxWidth = 0,
    MaxHeight = 0,
    MinHeight = -1,
    AreaUsed = 0,
    SortID = 0,
}

---Creates a new image packer.
---@param sortID integer
---@param maxWidth integer
---@param maxHeight integer
---@return ss.SkylinePacker
function ss.NewSkylinePacker(sortID, maxWidth, maxHeight)
    local self = ss.new "SkylinePacker"

    self.SortID = sortID
    self.MaxWidth = maxWidth
    self.MaxHeight = maxHeight

    for i = 1, self.MaxWidth do
        self.Wavefront[i] = -1
    end

    return self
end

---Gets the sort ID of the packer.
---@param self ss.SkylinePacker
---@return integer
function ss.SkylinePacker_GetSortId(self)
    return self.SortID
end

---Finds the highest point on the skyline within a given width.
---@param self ss.SkylinePacker
---@param firstX integer
---@param width integer
---@return integer maxY
---@return integer maxYIndex
function ss.SkylinePacker_GetMaxY(self, firstX, width)
    local maxY = -1
    local maxYIndex = 0
    for x = firstX, firstX + width - 1 do
        if self.Wavefront[x] >= maxY then
            maxY = self.Wavefront[x]
            maxYIndex = x
        end
    end
    return maxY, maxYIndex
end

---Increments the sort ID of the packer.
---@param self ss.SkylinePacker
function ss.SkylinePacker_IncrementSortId(self)
    self.SortID = self.SortID + 1
end

---Attempts to add a block to the image.
---@param self ss.SkylinePacker
---@param width integer
---@param height integer
---@return boolean success
---@return integer? x
---@return integer? y
function ss.SkylinePacker_AddBlock(self, width, height)
    local bestX = -1
    local outerMinY = self.MaxHeight
    local lastX = self.MaxWidth - width
    local lastMaxYVal = -2
    local outerX = 1

    while outerX <= lastX + 1 do
        if self.Wavefront[outerX] == lastMaxYVal then
            outerX = outerX + 1
            goto continue
        end

        local maxY, maxYIndex = ss.SkylinePacker_GetMaxY(self, outerX, width)
        lastMaxYVal = maxY
        if outerMinY > lastMaxYVal then
            outerMinY = lastMaxYVal
            bestX = outerX
        end
        outerX = maxYIndex + 1

        ::continue::
    end

    if bestX == -1 then
        return false
    end

    local returnX = bestX - 1
    local returnY = outerMinY + 1

    if returnY + height >= self.MaxHeight - 1 then
        return false
    end

    if returnY + height > self.MinHeight then
        self.MinHeight = returnY + height
    end

    for x = bestX, bestX + width - 1 do
        self.Wavefront[x] = outerMinY + height
    end

    self.AreaUsed = self.AreaUsed + width * height
    return true, returnX, returnY
end

---Gets the minimum required dimensions for the packed image.
---@param self ss.SkylinePacker
---@return integer width
---@return integer height
function ss.SkylinePacker_GetMinimumDimensions(self)
    ---@param n integer
    ---@return integer
    local function ceilPow2(n)
        n = n - 1
        n = bit.bor(n, bit.rshift(n, 1))
        n = bit.bor(n, bit.rshift(n, 2))
        n = bit.bor(n, bit.rshift(n, 4))
        n = bit.bor(n, bit.rshift(n, 8))
        n = bit.bor(n, bit.rshift(n, 16))
        return n + 1
    end

    -- In the source code, it seems to get aspect ratio from HardwareConfig()->MaxTextureAspectRatio()
    -- but I will just hardcode it to 8 for now.
    local MAX_ASPECT_RATIO = 8

    local width = ceilPow2(self.MaxWidth)
    local height = ceilPow2(self.MinHeight)

    local aspect = width / height
    if aspect > MAX_ASPECT_RATIO then
        height = width / MAX_ASPECT_RATIO
    end

    return width, height
end