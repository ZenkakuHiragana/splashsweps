
-- The serverside canvas of paintable surfaces, which also tells clients what ink is where.

---@class ss
local ss = SplashSWEPs
local Geometry = ss.import "splashsweps/shared/geometry"
local InkShape = ss.import "splashsweps/shared/inkshape"
local InkType  = ss.import "splashsweps/shared/inktype"

---@class ss.PaintableGridModule
local PaintableGrid = ss.module "splashsweps/shared/paint/paintablegrid"

---Side length of a cell of paintable grids in Hammer units.
PaintableGrid.CELL_SIZE = 12

local abs   = math.abs
local ceil  = math.ceil
local floor = math.floor
local min   = math.min
local max   = math.max

---The serverside canvas of a paintable surface which holds the result of paintings.
---@class ss.PaintableGrid
---@field [integer] integer Contains internal index of ink type for each pixel. To access specific pixel, use `index = y * Width + x`.
---@field Width     integer The total columns of the grid.
---@field Height    integer The total rows of the grid.

---Creates an empty grid.
---@param width  integer
---@param height integer
---@return ss.PaintableGrid
function PaintableGrid.new(width, height)
    return { Width = width, Height = height }
end

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
---@param axis_xx  number The x-coordinate of the forward of the inclined rectangle in the output coordinate system.
---@param axis_xy  number The y-coordinate of the forward.
---@param axis_yx  number The x-coordinate of the left of the inclined rectangle in the output coordinate system.
---@param axis_yy  number The y-coordinate of the left.
---@param scale_x  number Width / 2 of the inclined rectangle.
---@param scale_y  number Height / 2 of the inclined rectangle.
---@return number x_min
---@return number x_max
---@return number y_min
---@return number y_max
local function CalculateBounds(origin_x, origin_y, axis_xx, axis_xy, axis_yx, axis_yy, scale_x, scale_y)
    local extent_x = abs(axis_xx) * scale_x + abs(axis_yx) * scale_y
    local extent_y = abs(axis_xy) * scale_x + abs(axis_yy) * scale_y
    return origin_x - extent_x, origin_x + extent_x, origin_y - extent_y, origin_y + extent_y
end

---Paint this surface with specified ink type and shape at given position, angle, and size.
---@param self  ss.PaintableSurface
---@param paint ss.Paint The paint mapped onto the surface by Paint.EnumeratePositions.
---@return integer # Number of painted cells.
function PaintableGrid.Write(self, paint)
    -- Caches
    local cellSize = PaintableGrid.CELL_SIZE
    local surfaceGrid = self.Grid
    local surfaceGridWidth = surfaceGrid.Width
    local surfaceGridHeight = surfaceGrid.Height
    local inktype = paint.InkType
    local radius_x, radius_y = paint.RadiusX, paint.RadiusY

    ---Total number of cells painted by this operation will be here.
    local numPaintedCells = 0

    ---Represents the paint in paintable surface's coordinate system.
    ---Its columns are the forward, the left, the up, and the origin of the paint.
    local inkSystemInSurfaceSystem = Geometry.Multiply(self.WorldToLocalGrid,
        Geometry.FromAngles(paint.Pitch, paint.Yaw, paint.Roll, paint.X, paint.Y, paint.Z))
    local inkOriginInSurfaceSystemX = inkSystemInSurfaceSystem[4]
    local inkOriginInSurfaceSystemY = inkSystemInSurfaceSystem[8]

    ---Represents the origin and angle of paintable surface in target coordinate system.
    local surfaceSystemInInkSystem  = Geometry.InvertRotationTranslation(inkSystemInSurfaceSystem)
    local surfaceAxisXInInkSystemX  = surfaceSystemInInkSystem[1]
    local surfaceAxisXInInkSystemY  = surfaceSystemInInkSystem[5]
    local surfaceAxisYInInkSystemX  = surfaceSystemInInkSystem[2]
    local surfaceAxisYInInkSystemY  = surfaceSystemInInkSystem[6]
    local surfaceOriginInInkSystemX = surfaceSystemInInkSystem[4]
    local surfaceOriginInInkSystemY = surfaceSystemInInkSystem[8]

    ---Bounding box around the ink in paintable surface's coordinate system.
    ---
    ---```text
    --- The origin of the paint grid
    ---   +---> x
    ---   |
    ---   v      x_min
    ---   y  y_min +-------+-==---------------+
    ---            |      /    ^^--__         |
    ---            |     /           ^^--__   |
    ---            |    /   mappedpos      ^^-+
    ---            |   /        +-__         /|
    ---            |  /        /    ^^-> x = the forward of the paint
    ---            | /        v            /  |
    ---            |+__      y = the left /   |
    ---            |   ^^--__            /    |
    ---            |         ^^--__     /     |
    ---            +---------------==--+------+ y_max
    ---                                     x_max
    ---```
    local x_min, x_max, y_min, y_max = CalculateBounds(
        inkOriginInSurfaceSystemX, inkOriginInSurfaceSystemY,
        inkSystemInSurfaceSystem[1], inkSystemInSurfaceSystem[5],
        inkSystemInSurfaceSystem[2], inkSystemInSurfaceSystem[6],
        radius_x, radius_y)
    local indexMinX = max(floor(x_min / cellSize), 0)
    local indexMaxX = min( ceil(x_max / cellSize), surfaceGridWidth - 1)
    local indexMinY = max(floor(y_min / cellSize), 0)
    local indexMaxY = min( ceil(y_max / cellSize), surfaceGridHeight - 1)

    -- Caches
    local shapeMask              = InkShape.Shapes[paint.Shape].Mask
    local shapeMaskWidth         = shapeMask.Width
    local shapeMaskHeight        = shapeMask.Height
    local oneOverShapeCellWidth  = shapeMaskWidth  / (radius_x * 2)
    local oneOverShapeCellHeight = shapeMaskHeight / (radius_y * 2)
    local halfCellSize           = cellSize / 2

    -- These values are originally defined inside the loop (indexMinX, indexMinY --> ix, iy)
    -- I took them out for optimization.
    local xInSurfaceSystem = indexMinX * cellSize + halfCellSize
    local yInSurfaceSystem = indexMinY * cellSize + halfCellSize
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
    local xInInkSystemStep = surfaceAxisXInInkSystemX * cellSize
    local yInInkSystemStep = surfaceAxisXInInkSystemY * cellSize
    -- Difference between each outer iteration (iy).
    local xInInkSystemRewind
        = surfaceAxisYInInkSystemX * cellSize
        - xInInkSystemStep * (indexMaxX - indexMinX + 1)
    local yInInkSystemRewind
        = surfaceAxisYInInkSystemY * cellSize
        - yInInkSystemStep * (indexMaxX - indexMinX + 1)

    -- If the size of the ink is small enough then look up multiple cells of the shape grid
    if cellSize * cellSize * oneOverShapeCellWidth * oneOverShapeCellHeight > 1 then
        local shapeIntegralImage = shapeMask.IntegralImage

        -- Every cell has the same bounds in the ink system around its center.
        local cellMinX, cellMaxX, cellMinY, cellMaxY = CalculateBounds(0, 0,
            surfaceAxisXInInkSystemX, surfaceAxisXInInkSystemY,
            surfaceAxisYInInkSystemX, surfaceAxisYInInkSystemY,
            halfCellSize, halfCellSize)
        for iy = indexMinY, indexMaxY do
            for ix = indexMinX, indexMaxX do
                x_min, x_max = xInInkSystem + cellMinX, xInInkSystem + cellMaxX
                y_min, y_max = yInInkSystem + cellMinY, yInInkSystem + cellMaxY
                local shapeIndexMinX = floor((x_min + radius_x) * oneOverShapeCellWidth - 0.5)
                local shapeIndexMaxX =  ceil((x_max + radius_x) * oneOverShapeCellWidth + 0.5)
                local shapeIndexMinY = floor((y_min + radius_y) * oneOverShapeCellHeight - 0.5)
                local shapeIndexMaxY =  ceil((y_max + radius_y) * oneOverShapeCellHeight + 0.5)

                -- Check if the index range for the shape grid at least partially overlaps
                if shapeIndexMaxX >= 0
                and shapeIndexMaxY >= 0
                and shapeIndexMinX < shapeMaskWidth
                and shapeIndexMinY < shapeMaskHeight then
                    -- Total number of cells we have to look up into the shape grid.
                    local totalCells
                        = (shapeIndexMaxX - shapeIndexMinX + 1)
                        * (shapeIndexMaxY - shapeIndexMinY + 1)

                    -- Then clamp them to avoid out-of-range access
                    shapeIndexMinX = max(shapeIndexMinX, 0)
                    shapeIndexMaxX = min(shapeIndexMaxX, shapeMaskWidth  - 1)
                    shapeIndexMinY = max(shapeIndexMinY, 0)
                    shapeIndexMaxY = min(shapeIndexMaxY, shapeMaskHeight - 1)

                    local paintedCells
                        = shapeIntegralImage[shapeIndexMaxY * shapeMaskWidth + shapeIndexMaxX + 1]
                        - shapeIntegralImage[shapeIndexMaxY * shapeMaskWidth + shapeIndexMinX + 1]
                        - shapeIntegralImage[shapeIndexMinY * shapeMaskWidth + shapeIndexMaxX + 1]
                        + shapeIntegralImage[shapeIndexMinY * shapeMaskWidth + shapeIndexMinX + 1]

                    -- -- Lookup range for the mask
                    -- debugoverlay.BoxAngles(worldpos,
                    --     Vector(x_min, y_min, -1),
                    --     Vector(x_max, y_max,  1),
                    --     angle, 3, Color(0, 255, 255, 8))
                    if paintedCells >= totalCells * 0.5 then -- At least 50% of the cells should be filled.
                        surfaceGrid[iy * surfaceGridWidth + ix + 1] = inktype
                        numPaintedCells = numPaintedCells + 1

                        -- -- Painted cells
                        -- local gridToWorld = Geometry.InvertRotationTranslation(self.WorldToLocalGrid)
                        -- debugoverlay.BoxAngles(
                        --     Vector(Geometry.TransformPoint(gridToWorld,
                        --         ix * cellSize + halfCellSize,
                        --         iy * cellSize + halfCellSize, 0)),
                        --     -Vector(halfCellSize, halfCellSize, 3),
                        --     Vector(halfCellSize, halfCellSize, 3),
                        --     Angle(Geometry.ToAngles(gridToWorld)), 3, Color(255, 128, 255, 16))
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
                if  0 <= shapeIndexX and shapeIndexX < shapeMaskWidth
                and 0 <= shapeIndexY and shapeIndexY < shapeMaskHeight
                and shapeMask[shapeIndexY * shapeMaskWidth + shapeIndexX + 1] then
                    surfaceGrid[iy * surfaceGridWidth + ix + 1] = inktype

                    -- -- Painted cells
                    -- local gridToWorld = Geometry.InvertRotationTranslation(self.WorldToLocalGrid)
                    -- debugoverlay.BoxAngles(
                    --     Vector(Geometry.TransformPoint(gridToWorld,
                    --         ix * cellSize + halfCellSize,
                    --         iy * cellSize + halfCellSize, 0)),
                    --     -Vector(halfCellSize, halfCellSize, 3),
                    --     Vector(halfCellSize, halfCellSize, 3),
                    --     Angle(Geometry.ToAngles(gridToWorld)), 3, Color(128, 128, 255, 16))
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
---@param self   ss.PaintableSurface
---@param queryX number Preprocessed query point in world coordinates.
---@param queryY number
---@param queryZ number
---@return ss.InkType? # The ink type painted at corresponding pixel.  nil if no ink was there.
function PaintableGrid.Read(self, queryX, queryY, queryZ)
    local gridX, gridY = Geometry.TransformPoint(self.WorldToLocalGrid, queryX, queryY, queryZ)
    local x = floor(gridX / PaintableGrid.CELL_SIZE)
    local y = floor(gridY / PaintableGrid.CELL_SIZE)
    local pixel = self.Grid[y * self.Grid.Width + x + 1]
    if pixel and 0 <= x and x < self.Grid.Width and 0 <= y and y < self.Grid.Height then
        return InkType.Types[pixel]
    end
end

---Clears all painted data in the grid.
---@param self ss.PaintableSurface
function PaintableGrid.Clear(self)
    for i = 1, self.Grid.Width * self.Grid.Height do
        self.Grid[i] = -1
    end
end

return PaintableGrid
