
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

local abs    = math.abs
local band   = bit.band
local bnot   = bit.bnot
local bor    = bit.bor
local ceil   = math.ceil
local floor  = math.floor
local lshift = bit.lshift
local min    = math.min
local max    = math.max
local rshift = bit.rshift

---The serverside canvas of a paintable surface which holds the result of paintings.
---Each cell holds the internal index of the ink type painted on it, or 0 if no ink is there.
---
---The cells are numbered k = y * Width + x from 0, and every 4 cells in the order of k are packed into an element,
---as an internal index of ink types fits in 8 bits.
---Cell k is in bits 8 * (k % 4) to 8 * (k % 4) + 7 of element floor(k / 4) + 1.
---For example, a grid of Width = 5 and Height = 3 has 4 elements:
---
---```text
---          x=0    x=1    x=2    x=3    x=4
---    y=0 [ k=0 ][ k=1 ][ k=2 ][ k=3 ][ k=4 ]
---    y=1 [ k=5 ][ k=6 ][ k=7 ][ k=8 ][ k=9 ]
---    y=2 [ k=10][ k=11][ k=12][ k=13][ k=14]
---
---             bits 0-7   bits 8-15   bits 16-23   bits 24-31
---    Grid[1]  k=0        k=1         k=2          k=3
---    Grid[2]  k=4        k=5         k=6          k=7
---    Grid[3]  k=8        k=9         k=10         k=11
---    Grid[4]  k=12       k=13        k=14         unused, always 0
---```
---
---An element can hold cells of two rows, like Grid[2].
---With ink 3 at k=0, no ink at k=1, ink 7 at k=2, and ink 1 at k=3, Grid[1] is 0x01070003:
---
---```text
---    bit 31     24 23     16 15      8 7       0
---       +---------+---------+---------+---------+
---       |  0x01   |  0x07   |  0x00   |  0x03   |
---       +---------+---------+---------+---------+
---          k=3       k=2       k=1       k=0
---```
---
---The bit library works on signed 32-bit integers, so an element is negative
---if the cell in its bits 24-31 has an internal index of 128 or more.
---The cells are still read right, as rshift is a logical shift.
---@class ss.PaintableGrid
---@field [integer] integer The elements of 4 packed cells, from 1 to ceil(Width * Height / 4).
---@field Width     integer The total columns of the grid.
---@field Height    integer The total rows of the grid.

---Creates a grid with no element, whose cells are all empty.
---PaintableGrid.Clear fills its elements in advance so that painting does not allocate them.
---@param width  integer
---@param height integer
---@return ss.PaintableGrid
function PaintableGrid.new(width, height)
    return { Width = width, Height = height }
end

---Returns the internal index of the ink type of a cell, or 0 if no ink is there,
---from the elements laid out as ss.PaintableGrid describes.
---An element not filled yet is taken as 4 empty cells.
---@param grid ss.PaintableGrid
---@param k    integer The cell y * Width + x, counting from 0.
---@return integer
local function getCell(grid, k)
    return band(rshift(grid[rshift(k, 2) + 1] or 0, lshift(band(k, 3), 3)), 0xFF)
end

---Sets the internal index of the ink type of a cell, keeping the other 3 cells of its element.
---An element not filled yet is taken as 4 empty cells.
---@param grid    ss.PaintableGrid
---@param k       integer The cell y * Width + x, counting from 0.
---@param inktype integer The internal index of the ink type from 0 to 255.
local function setCell(grid, k, inktype)
    local i = rshift(k, 2) + 1
    local shift = lshift(band(k, 3), 3)
    grid[i] = bor(band(grid[i] or 0, bnot(lshift(0xFF, shift))), lshift(inktype, shift))
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
        radius_y, radius_x)
    local indexMinX = max(floor(x_min / cellSize), 0)
    local indexMaxX = min( ceil(x_max / cellSize), surfaceGridWidth - 1)
    local indexMinY = max(floor(y_min / cellSize), 0)
    local indexMaxY = min( ceil(y_max / cellSize), surfaceGridHeight - 1)

    -- Caches
    -- The top of the shape mask faces the forward and its right faces the right (-left),
    -- so the column (index X) comes from -y in the ink system and the row (index Y) from -x.
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
                local shapeIndexMinX = floor((radius_x - y_max) * oneOverShapeCellWidth  - 0.5)
                local shapeIndexMaxX =  ceil((radius_x - y_min) * oneOverShapeCellWidth  + 0.5)
                local shapeIndexMinY = floor((radius_y - x_max) * oneOverShapeCellHeight - 0.5)
                local shapeIndexMaxY =  ceil((radius_y - x_min) * oneOverShapeCellHeight + 0.5)

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
                        setCell(surfaceGrid, iy * surfaceGridWidth + ix, inktype)
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
                local shapeIndexX = floor((radius_x - yInInkSystem) * oneOverShapeCellWidth  + 0.5)
                local shapeIndexY = floor((radius_y - xInInkSystem) * oneOverShapeCellHeight + 0.5)
                if  0 <= shapeIndexX and shapeIndexX < shapeMaskWidth
                and 0 <= shapeIndexY and shapeIndexY < shapeMaskHeight
                and shapeMask[shapeIndexY * shapeMaskWidth + shapeIndexX + 1] then
                    setCell(surfaceGrid, iy * surfaceGridWidth + ix, inktype)

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
    if 0 <= x and x < self.Grid.Width and 0 <= y and y < self.Grid.Height then
        return InkType.Types[getCell(self.Grid, y * self.Grid.Width + x)]
    end
end

---Reads a cell of the grid.
---@param self ss.PaintableSurface
---@param x    integer The column counting from 0.
---@param y    integer The row counting from 0.
---@return integer # The internal index of the ink type painted on the cell, or 0 if no ink is there.
function PaintableGrid.ReadCell(self, x, y)
    return getCell(self.Grid, y * self.Grid.Width + x)
end

---Clears all painted data in the grid by filling all its elements with 0, which also allocates them.
---@param self ss.PaintableSurface
function PaintableGrid.Clear(self)
    for i = 1, ceil(self.Grid.Width * self.Grid.Height / 4) do
        self.Grid[i] = 0
    end
end

return PaintableGrid
