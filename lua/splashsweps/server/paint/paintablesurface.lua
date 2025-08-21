
---@class ss
local ss = SplashSWEPs
if not ss then return end

local Matrix = Matrix
local Vector = Vector
local Clamp = math.Clamp
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

---This class holds information around serverside paintings.
---```text
---World origin
---  +--> x
---  |
---  v   WorldToLocalGridMatrix:GetInverseTR():GetTranslation()
---  y      +--> X
---         |
---         v   * (Xi, Yi) = WorldToLocalGridMatrix * (xi, yi)
---         Y
---```
---@class ss.PaintableSurface
---@field AABBMax                Vector  AABB maximum of this surface in world coordinates.
---@field AABBMin                Vector  AABB minimum of this surface in world coordinates.
---@field WorldToLocalGridMatrix VMatrix The transformation matrix to convert world coordinates into local coordinates. This does not modify scales.
---@field LocalToWorldGridMatrix VMatrix The inverse matrix of WorldToLocalGridMatrix that contains origin and angle of this surface.
---@field Grid          ss.PaintableGrid
local PaintableSurfaceTemplate = {
    AABBMax = Vector(),
    AABBMin = Vector(),
    WorldToLocalGridMatrix = Matrix(),
    LocalToWorldGridMatrix = Matrix(),
    Grid = ss.new "PaintableGrid",
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
---@param transform VMatrix Transformation matrix to represent the center position and orientation of the inclined rectangle.
---@param scale_x number Width / 2 of the inclined rectangle.
---@param scale_y number Height / 2 of the inclined rectangle.
---@return number x_min
---@return number x_max
---@return number y_min
---@return number y_max
local function CalculateBounds(transform, scale_x, scale_y)
    local origin =  transform:GetTranslation()
    local axis_x =  transform:GetForward()
    local axis_y = -transform:GetRight()
    local corners = {
        axis_x *  scale_x + axis_y *  scale_y,
        axis_x * -scale_x + axis_y *  scale_y,
        axis_x * -scale_x + axis_y * -scale_y,
        axis_x *  scale_x + axis_y * -scale_y,
    }
    local x_min = origin.x + min(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local x_max = origin.x + max(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local y_min = origin.y + min(corners[1].y, corners[2].y, corners[3].y, corners[4].y)
    local y_max = origin.y + max(corners[1].y, corners[2].y, corners[3].y, corners[4].y)
    return x_min, x_max, y_min, y_max
end

---Paint this surface with specified ink type and shape at given position, angle, and size.
---@param self     ss.PaintableSurface
---@param worldpos Vector      The origin.
---@param angle    Angle       The normal and rotation.
---@param radius_x number      Scale along the forward vector (angle:Forward()).
---@param radius_y number      Scale along the right vector (angle:Right()).
---@param inktype  integer     The internal index of ink type.
---@param shape    ss.InkShape The shape.
---@return integer # Number of painted cells.
function ss.WriteGrid(self, worldpos, angle, radius_x, radius_y, inktype, shape)
    -- Caches
    local inkGridSize = ss.InkGridSize
    local surfaceGrid = self.Grid
    local surfaceGridWidth = surfaceGrid.Width
    local surfaceGridHeight = surfaceGrid.Height

    ---Total number of cells painted by this operation will be here.
    local numPaintedCells = 0

    ---Transformation matrix representing the origin and orientation of the paint.
    local transform = Matrix()
    transform:SetTranslation(worldpos)
    transform:SetAngles(angle)

    ---Transformation matrix which converts
    ---from shape's coordinate system
    ---to paintable surface's coordinate system.
    local shapeCS_to_surfaceCS = self.WorldToLocalGridMatrix * transform

    ---Transformation matrix which converts
    ---from paintable surface's coordinate system
    ---to shape's coordinate system.
    local surfaceCS_to_shapeCS = shapeCS_to_surfaceCS:GetInverseTR()

    ---Origin of the shape in the paintable surface's local coordinate system.
    ---
    ---```text
    --- self.WorldToLocalGridMatrix^-1:GetTranslation()
    ---   +---> x = self.WorldToLocalGridMatrix^-1:GetForward()
    ---   |
    ---   v      x_min
    ---   y  y_min +-------+-==---------------+
    ---            |      /    ^^--__         |
    ---            |     /           ^^--__   |
    ---            |    /     origin       ^^-+
    ---            |   /        +-__         /|
    ---            |  /        /    ^^-> x = axis_x
    ---            | /        v            /  |
    ---            |+__      y = axis_y   /   |
    ---            |   ^^--__            /    |
    ---            |         ^^--__     /     |
    ---            +---------------==--+------+ y_max
    ---                                     x_max
    ---```
    local x_min, x_max, y_min, y_max = CalculateBounds(shapeCS_to_surfaceCS, radius_x, radius_y)
    local indexMinX = Clamp(floor(x_min / inkGridSize), 0, surfaceGridWidth - 1)
    local indexMaxX = Clamp( ceil(x_max / inkGridSize), 0, surfaceGridWidth - 1)
    local indexMinY = Clamp(floor(y_min / inkGridSize), 0, surfaceGridHeight - 1)
    local indexMaxY = Clamp( ceil(y_max / inkGridSize), 0, surfaceGridHeight - 1)

    -- Caches
    local shapeGridWidth = shape.Grid.Width
    local shapeGridHeight = shape.Grid.Height
    local shapeIntegralImage = shape.Grid.IntegralImage
    local shapeScaleWidth = shapeGridWidth / (radius_x * 2)
    local shapeScaleHeight = shapeGridHeight / (radius_y * 2)
    local surfaceCellRadius = inkGridSize / 2

    -- Temporary objects used in the loop
    ---The center position of each cell of the surface in paintable surface's coordinate system.
    local surfaceCellOriginInSurfaceCS = Vector(0, 0, 0)
    local surfaceCellCS_to_shapeCS = Matrix()
    surfaceCellCS_to_shapeCS:SetAngles(surfaceCS_to_shapeCS:GetAngles())

    for iy = indexMinY, indexMaxY do
        surfaceCellOriginInSurfaceCS.y = (iy + 0.5) * inkGridSize
        for ix = indexMinX, indexMaxX do
            surfaceCellOriginInSurfaceCS.x = (ix + 0.5) * inkGridSize
            surfaceCellCS_to_shapeCS:SetTranslation(surfaceCS_to_shapeCS * surfaceCellOriginInSurfaceCS)
            x_min, x_max, y_min, y_max = CalculateBounds(surfaceCellCS_to_shapeCS, surfaceCellRadius, surfaceCellRadius)
            local shapeIndexMinX = floor((x_min + radius_x) * shapeScaleWidth)
            local shapeIndexMaxX =  ceil((x_max + radius_x) * shapeScaleWidth)
            local shapeIndexMinY = floor((y_min + radius_y) * shapeScaleHeight)
            local shapeIndexMaxY =  ceil((y_max + radius_y) * shapeScaleHeight)

            -- Check if the index range for the shape grid at least partially overlaps
            if shapeIndexMaxX >= 0
            and shapeIndexMaxY >= 0
            and shapeIndexMinX < shapeGridWidth
            and shapeIndexMinY < shapeGridHeight then
                local totalCells = (shapeIndexMaxX - shapeIndexMinX + 1) * (shapeIndexMaxY - shapeIndexMinY + 1)

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
                
                -- Lookup range for the mask
                -- debugoverlay.BoxAngles(worldpos,
                --     Vector(x_min, y_min, -1),
                --     Vector(x_max, y_max,  1),
                --     angle, 3, Color(0, 255, 255, 8))
                if paintedCells > totalCells * 0.5 then -- At least 50% of the cells should be filled.
                    surfaceGrid[iy * surfaceGridWidth + ix + 1] = inktype
                    numPaintedCells = numPaintedCells + 1

                    -- Painted cells
                    -- debugoverlay.BoxAngles(
                    --     self.LocalToWorldGridMatrix * surfaceCellOriginInSurfaceCS,
                    --     -Vector(surfaceCellRadius, surfaceCellRadius, 3),
                    --     Vector(surfaceCellRadius, surfaceCellRadius, 3),
                    --     self.LocalToWorldGridMatrix:GetAngles(), 3, Color(255, 128, 255, 64))
                end
            end
        end
    end

    return numPaintedCells
end

---Paint this surface with specified ink type and shape at given position, angle, and size.
---@param worldpos Vector      The origin.
---@param angle    Angle       The normal and rotation.
---@param radius_x number      Scale along the forward vector (angle:Forward()).
---@param radius_y number      Scale along the right vector (angle:Right()).
---@param inktype  integer     The internal index of ink type.
---@param shape    ss.InkShape The shape.
---@return integer # Number of painted cells.
function PaintableSurfaceTemplate:WriteGrid(worldpos, angle, radius_x, radius_y, inktype, shape)
    return ss.WriteGrid(self, worldpos, angle, radius_x, radius_y, inktype, shape)
end

---Reads a pixel from the grid using given position in world coordinates.
---@param query Vector Query point in world coordinates.
---@return ss.InkType? # The ink type painted at corresponding pixel.  nil if no ink was there.
function PaintableSurfaceTemplate:ReadGrid(query)
    local query2d = self.WorldToLocalGridMatrix * query
    local x = floor(query2d.x / ss.InkGridSize)
    local y = floor(query2d.y / ss.InkGridSize)
    local pixel = self.Grid[y * self.Grid.Width + x + 1]
    if pixel and 0 <= x and x < self.Grid.Width and 0 <= y and y < self.Grid.Height then
        return ss.InkTypes[pixel]
    end
end

ss.struct "PaintableSurface" (PaintableSurfaceTemplate)

---Reads a surface list from a file and stores them for later use.
function ss.SetupSurfaces()
    local surfacesPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local surfaces = util.JSONToTable(file.Read(surfacesPath) or "", true) ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then
        return
    end

    ---@type ss.PaintableSurface[]
    ss.SurfaceArray = {}
    for i, surf in ipairs(surfaces) do
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToLocalGridMatrix:SetAngles(surf.TransformPaintGrid.Angle)
        ps.WorldToLocalGridMatrix:SetTranslation(surf.TransformPaintGrid.Translation)
        ps.LocalToWorldGridMatrix = ps.WorldToLocalGridMatrix:GetInverseTR()
        ps.Grid.Width = surf.PaintGridWidth
        ps.Grid.Height = surf.PaintGridHeight
        ss.SurfaceArray[i] = ps
    end
end
