
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Matrix = Matrix
local ceil  = math.ceil
local floor = math.floor
local min   = math.min
local max   = math.max

---The serverside canvas of a paintable surface which holds the result of paintings.
---@class ss.PaintableGrid
---@field [integer] integer Contains internal index of ink type for each pixel. To access specific pixel, use `index = y * Width + x`.
---@field Width     integer The total columns of the grid.
---@field Height    integer The total rows of the grid.
ss.struct "PaintableGrid" {
    Width = 0,
    Height = 0,
}

---Calculates minimum bounding box from inclined rectangle.
---
---```text
---    x_min
---y_min +-------+-==---------------+
---      |      /    ^^--__         |
---      |     /           ^^--__   |
---      |    /     origin       ^^-+
---      |   /        +-__         /|
---      |  /        /    ^^-> x = axis_x
---      | /        v            /  |
---      |+__      y = axis_y   /   |
---      |   ^^--__            /    |
---      |         ^^--__     /     |
---      +---------------==--+------+ y_max
---                               x_max
---```
---@param origin_x number The x-coordinate of the inclined rectangle in the output coordinate system.
---@param origin_y number The y-coordinate of the inclined rectangle in the output coordinate system.
---@param axis_x   Vector Angle:Forward() of the inclined rectangle in the output coordinate system.
---@param axis_y   Vector -Angle:Right() of the inclined rectangle in the output coordinate system.
---@param scale_x  number Width / 2 of the inclined rectangle.
---@param scale_y  number Height / 2 of the inclined rectangle.
---@return number x_min
---@return number x_max
---@return number y_min
---@return number y_max
local function CalculateBounds(origin_x, origin_y, axis_x, axis_y, scale_x, scale_y)
    local axis_xx, axis_xy = axis_x.x, axis_x.y
    local axis_yx, axis_yy = axis_y.x, axis_y.y
    local corners_x = {
        axis_xx *  scale_x + axis_yx *  scale_y,
        axis_xx * -scale_x + axis_yx *  scale_y,
        axis_xx * -scale_x + axis_yx * -scale_y,
        axis_xx *  scale_x + axis_yx * -scale_y,
    }
    local corners_y = {
        axis_xy *  scale_x + axis_yy *  scale_y,
        axis_xy * -scale_x + axis_yy *  scale_y,
        axis_xy * -scale_x + axis_yy * -scale_y,
        axis_xy *  scale_x + axis_yy * -scale_y,
    }
    local x_min = origin_x + min(corners_x[1], corners_x[2], corners_x[3], corners_x[4])
    local x_max = origin_x + max(corners_x[1], corners_x[2], corners_x[3], corners_x[4])
    local y_min = origin_y + min(corners_y[1], corners_y[2], corners_y[3], corners_y[4])
    local y_max = origin_y + max(corners_y[1], corners_y[2], corners_y[3], corners_y[4])
    return x_min, x_max, y_min, y_max
end

---Paint this surface with specified ink type and shape at given position, angle, and size.
---@param self     ss.PaintableSurface
---@param worldpos Vector  The origin of the ink in world coordinate system.
---@param angle    Angle   The normal and rotation of the ink in world coordinate system.
---@param radius_x number  Scale along the forward vector (angle:Forward()), distance between the center and horizontal tip.
---@param radius_y number  Scale along the right vector (angle:Right()), distance between the center and vertical tip.
---@param inktype  integer The internal index of ink type.
---@param shape    integer The internal index of shape.
---@return integer # Number of painted cells.
function ss.WriteGrid(self, worldpos, angle, radius_x, radius_y, inktype, shape)
    -- Caches
    local inkGridCellSize = ss.InkGridCellSize
    local surfaceGrid = self.Grid
    local surfaceGridWidth = surfaceGrid.Width
    local surfaceGridHeight = surfaceGrid.Height

    ---Total number of cells painted by this operation will be here.
    local numPaintedCells = 0

    ---Represents the given position and angles in the world coordinate system.
    local inkSystemInWorld = Matrix()
    inkSystemInWorld:SetTranslation(worldpos)
    inkSystemInWorld:SetAngles(angle)

    ---Represents the given position and angles in paintable surface's coordinate system.
    local inkSystemInSurfaceSystem = self.WorldToLocalGridMatrix * inkSystemInWorld
    local inkOriginInSurfaceSystem = inkSystemInSurfaceSystem:GetTranslation()
    local inkOriginInSurfaceSystemX = inkOriginInSurfaceSystem.x
    local inkOriginInSurfaceSystemY = inkOriginInSurfaceSystem.y

    ---Represents the origin and angle of paintable surface in target coordinate system.
    local surfaceSystemInInkSystem  = inkSystemInSurfaceSystem:GetInverseTR()
    local surfaceAxisXInInkSystem   = surfaceSystemInInkSystem:GetForward()
    local surfaceAxisXInInkSystemX  = surfaceAxisXInInkSystem.x
    local surfaceAxisXInInkSystemY  = surfaceAxisXInInkSystem.y
    local surfaceAxisYInInkSystem   = -surfaceSystemInInkSystem:GetRight()
    local surfaceAxisYInInkSystemX  = surfaceAxisYInInkSystem.x
    local surfaceAxisYInInkSystemY  = surfaceAxisYInInkSystem.y
    local surfaceOriginInInkSystem  = surfaceSystemInInkSystem:GetTranslation()
    local surfaceOriginInInkSystemX = surfaceOriginInInkSystem.x
    local surfaceOriginInInkSystemY = surfaceOriginInInkSystem.y

    ---Bounding box around the ink in paintable surface's coordinate system.
    ---
    ---```text
    --- self.WorldToLocalGridMatrix^-1:GetTranslation()
    ---   +---> x = self.WorldToLocalGridMatrix^-1:GetForward()
    ---   |
    ---   v      x_min
    ---   y  y_min +-------+-==---------------+
    ---            |      /    ^^--__         |
    ---            |     /           ^^--__   |
    ---            |    /    worldpos      ^^-+
    ---            |   /        +-__         /|
    ---            |  /        /    ^^-> x = inkSystemInSurfaceSystem
    ---            | /        v            /  |   :GetAngles():Forward()
    ---            |+__      y            /   |
    ---            |   ^^--__            /    |
    ---            |         ^^--__     /     |
    ---            +---------------==--+------+ y_max
    ---                                     x_max
    ---```
    local x_min, x_max, y_min, y_max = CalculateBounds(
        inkOriginInSurfaceSystemX, inkOriginInSurfaceSystemY,
        inkSystemInSurfaceSystem:GetForward(),
       -inkSystemInSurfaceSystem:GetRight(),
        radius_x, radius_y)
    local indexMinX = max(floor(x_min / inkGridCellSize), 0)
    local indexMaxX = min( ceil(x_max / inkGridCellSize), surfaceGridWidth - 1)
    local indexMinY = max(floor(y_min / inkGridCellSize), 0)
    local indexMaxY = min( ceil(y_max / inkGridCellSize), surfaceGridHeight - 1)

    -- Caches
    local shapeGrid              = ss.InkShapes[shape].Grid
    local shapeGridWidth         = shapeGrid.Width
    local shapeGridHeight        = shapeGrid.Height
    local oneOverShapeCellWidth  = shapeGridWidth  / (radius_x * 2)
    local oneOverShapeCellHeight = shapeGridHeight / (radius_y * 2)
    local inkGridCellSizeHalf    = inkGridCellSize / 2

    -- These values are originally defined inside the loop (indexMinX, indexMinY --> ix, iy)
    -- I took them out for optimization.
    local xInSurfaceSystem = indexMinX * inkGridCellSize + inkGridCellSizeHalf
    local yInSurfaceSystem = indexMinY * inkGridCellSize + inkGridCellSizeHalf
    local xInInkSystem
        = surfaceAxisXInInkSystemX * xInSurfaceSystem
        + surfaceAxisYInInkSystemX * yInSurfaceSystem
        + surfaceOriginInInkSystemX
    local yInInkSystem
        = surfaceAxisXInInkSystemY * xInSurfaceSystem
        + surfaceAxisYInInkSystemY * yInSurfaceSystem
        + surfaceOriginInInkSystemY

    -- Instead of calculating above values every time inside the loop,
    -- knowing the differences between each iteration here
    -- effectively removes multiplication inside the loop.
    --
    -- Difference between each inner iteration (ix).
    local xInInkSystemStep = surfaceAxisXInInkSystemX * inkGridCellSize
    local yInInkSystemStep = surfaceAxisXInInkSystemY * inkGridCellSize
    -- Difference between each outer iteration (iy).
    local xInInkSystemRewind
        = surfaceAxisYInInkSystemX * inkGridCellSize
        - xInInkSystemStep * (indexMaxX - indexMinX + 1)
    local yInInkSystemRewind
        = surfaceAxisYInInkSystemY * inkGridCellSize
        - yInInkSystemStep * (indexMaxX - indexMinX + 1)

    -- If the size of the ink is small enough then look up multiple cells of the shape grid
    if inkGridCellSize * inkGridCellSize * oneOverShapeCellWidth * oneOverShapeCellHeight > 1 then
        local shapeIntegralImage = shapeGrid.IntegralImage
        for iy = indexMinY, indexMaxY do
            for ix = indexMinX, indexMaxX do
                x_min, x_max, y_min, y_max = CalculateBounds(
                    xInInkSystem, yInInkSystem,
                    surfaceAxisXInInkSystem, surfaceAxisYInInkSystem,
                    inkGridCellSizeHalf, inkGridCellSizeHalf)
                local shapeIndexMinX = floor((x_min + radius_x) * oneOverShapeCellWidth - 0.5)
                local shapeIndexMaxX =  ceil((x_max + radius_x) * oneOverShapeCellWidth + 0.5)
                local shapeIndexMinY = floor((y_min + radius_y) * oneOverShapeCellHeight - 0.5)
                local shapeIndexMaxY =  ceil((y_max + radius_y) * oneOverShapeCellHeight + 0.5)

                -- Check if the index range for the shape grid at least partially overlaps
                if shapeIndexMaxX >= 0
                and shapeIndexMaxY >= 0
                and shapeIndexMinX < shapeGridWidth
                and shapeIndexMinY < shapeGridHeight then
                    -- Total number of cells we have to look up into the shape grid.
                    local totalCells
                        = (shapeIndexMaxX - shapeIndexMinX + 1)
                        * (shapeIndexMaxY - shapeIndexMinY + 1)

                    -- Then clamp them to avoid out-of-range access
                    shapeIndexMinX = max(shapeIndexMinX, 0)
                    shapeIndexMaxX = min(shapeIndexMaxX, shapeGridWidth  - 1)
                    shapeIndexMinY = max(shapeIndexMinY, 0)
                    shapeIndexMaxY = min(shapeIndexMaxY, shapeGridHeight - 1)

                    local paintedCells
                        = shapeIntegralImage[shapeIndexMaxY * shapeGridWidth + shapeIndexMaxX + 1]
                        - shapeIntegralImage[shapeIndexMaxY * shapeGridWidth + shapeIndexMinX + 1]
                        - shapeIntegralImage[shapeIndexMinY * shapeGridWidth + shapeIndexMaxX + 1]
                        + shapeIntegralImage[shapeIndexMinY * shapeGridWidth + shapeIndexMinX + 1]

                    -- -- Lookup range for the mask
                    -- debugoverlay.BoxAngles(worldpos,
                    --     Vector(x_min, y_min, -1),
                    --     Vector(x_max, y_max,  1),
                    --     angle, 3, Color(0, 255, 255, 8))
                    if paintedCells >= totalCells * 0.5 then -- At least 50% of the cells should be filled.
                        surfaceGrid[iy * surfaceGridWidth + ix + 1] = inktype
                        numPaintedCells = numPaintedCells + 1

                        -- -- Painted cells
                        -- debugoverlay.BoxAngles(
                        --     self.WorldToLocalGridMatrix:GetInverseTR() * Vector(
                        --         ix * inkGridCellSize + inkGridCellSizeHalf,
                        --         iy * inkGridCellSize + inkGridCellSizeHalf),
                        --     -Vector(inkGridCellSizeHalf, inkGridCellSizeHalf, 3),
                        --     Vector(inkGridCellSizeHalf, inkGridCellSizeHalf, 3),
                        --     self.WorldToLocalGridMatrix:GetInverseTR():GetAngles(), 3, Color(255, 128, 255, 16))
                    end
                end
                xInInkSystem = xInInkSystem + xInInkSystemStep
                yInInkSystem = yInInkSystem + yInInkSystemStep
            end
            xInInkSystem = xInInkSystem + xInInkSystemRewind ---@type number Remove this annotation
            yInInkSystem = yInInkSystem + yInInkSystemRewind ---@type number after LuaLS fixed the issue
        end
    else -- Otherwise, look up the nearest one
        for iy = indexMinY, indexMaxY do
            for ix = indexMinX, indexMaxX do
                local shapeIndexX = floor((xInInkSystem + radius_x) * oneOverShapeCellWidth + 0.5)
                local shapeIndexY = floor((yInInkSystem + radius_y) * oneOverShapeCellHeight + 0.5)
                if  0 <= shapeIndexX and shapeIndexX < shapeGridWidth
                and 0 <= shapeIndexY and shapeIndexY < shapeGridHeight
                and shapeGrid[shapeIndexY * shapeGridWidth + shapeIndexX + 1] then
                    surfaceGrid[iy * surfaceGridWidth + ix + 1] = inktype

                    -- -- Painted cells
                    -- debugoverlay.BoxAngles(
                    --     self.WorldToLocalGridMatrix:GetInverseTR() * Vector(
                    --         ix * inkGridCellSize + inkGridCellSizeHalf,
                    --         iy * inkGridCellSize + inkGridCellSizeHalf),
                    --     -Vector(inkGridCellSizeHalf, inkGridCellSizeHalf, 3),
                    --     Vector(inkGridCellSizeHalf, inkGridCellSizeHalf, 3),
                    --     self.WorldToLocalGridMatrix:GetInverseTR():GetAngles(), 3, Color(128, 128, 255, 16))
                end
                xInInkSystem = xInInkSystem + xInInkSystemStep
                yInInkSystem = yInInkSystem + yInInkSystemStep
            end
            xInInkSystem = xInInkSystem + xInInkSystemRewind
            yInInkSystem = yInInkSystem + yInInkSystemRewind
        end
    end

    return numPaintedCells
end

---Reads a pixel from the grid using given position in world coordinates.
---@param self ss.PaintableSurface
---@param query Vector Query point in world coordinates.
---@return ss.InkType? # The ink type painted at corresponding pixel.  nil if no ink was there.
function ss.ReadGrid(self, query)
    local query2d = self.WorldToLocalGridMatrix * query
    local x = floor(query2d.x / ss.InkGridCellSize)
    local y = floor(query2d.y / ss.InkGridCellSize)
    local pixel = self.Grid[y * self.Grid.Width + x + 1]
    if pixel and 0 <= x and x < self.Grid.Width and 0 <= y and y < self.Grid.Height then
        return ss.InkTypes[pixel]
    end
end

---Clears all painted data in the grid.
---@param self ss.PaintableSurface
function ss.ClearGrid(self)
    for i = 1, self.Grid.Width * self.Grid.Height do
        self.Grid[i] = nil
    end
end
