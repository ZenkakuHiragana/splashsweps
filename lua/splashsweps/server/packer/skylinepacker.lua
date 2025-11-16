
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
        if self.Wavefront[x] >= maxY then
            maxY = self.Wavefront[x]
            maxYIndex = x
        end
    end
    return maxY, maxYIndex
end

---Attempts to add a block to the image.
---@param self ss.SkylinePacker
---@param width integer
---@param height integer
---@return boolean success
---@return integer? x
---@return integer? y
local function AddBlock(self, width, height)
    local bestX = -1
    local outerMinY = self.MaxHeight
    local lastX = self.MaxWidth - width
    local lastMaxYVal = -2
    local outerX = 1

    while outerX <= lastX + 1 do
        if self.Wavefront[outerX] == lastMaxYVal then
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
    }

    for i = 1, t.MaxWidth do
        t.Wavefront[i] = -1
    end

    return t
end
