
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkShapeLists then
    locals.InkShapeLists = {}
end

---Map of ink shape category --> list of indices to actual definition
---@type table<string, integer[]>
local InkShapeLists = locals.InkShapeLists

---Mask array used to draw on PaintableSurface grid.  
---Access the mask value using `InkShape.Grid[y * InkShape.Width + x]`: boolean.
---@class ss.InkShape.Grid
---@field [integer]     boolean   True for filled pixel, index = y * Width + x
---@field Width         integer   The width of the grid.
---@field Height        integer   The height of the grid.
---@field IntegralImage integer[] Integral image for faster filtering, index = y * Width + x
---@overload fun(width?: integer, height?: integer): ss.InkShape.Grid
ss.struct "InkShape.Grid" {
    Width = 0,
    Height = 0,
    IntegralImage = {},
}

---Constructor for InkShape.Grid.
---@param this   ss.InkShape.Grid
---@param width  integer
---@param height integer
ss.ctor "InkShape.Grid" (function (this, width, height)
    this.Width = width
    this.Height = height
end)

---Defines the shape of painted ink.
---@class ss.InkShape
---@field Index       integer The internal index used in networking.
---@field Identifier  string  The identifier of this ink shape as the key of ss.InkShapes.
---@field MaskTexture string  Only used clientside; mask texture to create drawing materials.
---@field Grid        ss.InkShape.Grid Only used serverside; mask for drawing on PaintableSurface grid.
ss.struct "InkShape" {
    Index = 0,
    Identifier = "",
    MaskTexture = "",
    Grid = ss.new "InkShape.Grid"
}

---Read pixels from givem texture and stores them to the mask.
---@param vmt IMaterial definition of the ink shape.
---@return ss.InkShape? # the mask to be stored to.
local function ReadPixelsFromVTF(vmt)
    ---Uncompressed texture to define the mask.
    local path = vmt:GetString "$basetexture"
    if not path then return end
    if not path:EndsWith ".vtf" then path = path .. ".vtf" end
    if not file.Exists("materials/" .. path, "GAME") then return end
    local vtf = ss.ReadVTF(path)
    ss.assert(vtf, "Shape mask has invalid texture (" .. path .. ")") ---@cast vtf -?

    local width = vtf.Images[1].Width
    local height = vtf.Images[1].Height
    local shape = ss.new "InkShape"
    shape.Grid = ss.new "InkShape.Grid" (width, height)
    shape.MaskTexture = path

    local grid = shape.Grid
    local threshold = vmt:GetFloat "$alphatestreference" or 0.5
    if threshold < 1 then threshold = threshold * 255 end
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local index = y * width + x + 1
            local above =  y > 0            and grid.IntegralImage[(y - 1) * width + x + 1] or 0
            local left  =  x > 0            and grid.IntegralImage[ y      * width + x    ] or 0
            local diag  = (x > 0 and y > 0) and grid.IntegralImage[(y - 1) * width + x    ] or 0
            grid[index] = ss.ReadPixelFromVTF(vtf, x, y).a > threshold
            grid.IntegralImage[index] = (grid[index] and 1 or 0) + left + above - diag
        end
    end

    return shape
end

---Reads all vmt files and defines all ink shapes used in this addon.
function ss.LoadInkShapes()
    local shapeCount = 0
    for f in ss.IterateFilesRecursive("materials/splashsweps/paints", "GAME", "*.vmt") do
        local vmt = Material(f:gsub("^materials/", ""), nil)
        if not vmt:IsError() then
            local param = vmt:GetString "$splashsweps_tag" or ""
            local tag = param:match "^[a-z0-9_]+$"
            if tag then
                local shape = ReadPixelsFromVTF(vmt)
                if shape then
                    shapeCount = shapeCount + 1
                    shape.Index = shapeCount
                    shape.Identifier = f:gsub("^materials/splashsweps/paints/", "")
                    InkShapeLists[tag] = table.ForceInsert(InkShapeLists[tag], shape.Index)
                    ss.InkShapes[shape.Index] = shape
                end
            end
        end
    end

    ---Total number of defined ink shapes.
    ss.NumInkShapes = shapeCount

    ---Required bits to transfer ink shape type as an unsigned integer.
    ss.MAX_INKSHAPE_BITS = math.max(select(2, math.frexp(shapeCount - 1)), 1)
end

---Picks up random ink shape within the category of "tag" using given random seed.
---@param tag string tag to search for.
---@param seed? number optional random seed such as `CurTime()`.
---@return ss.InkShape # Randomly chosen ink shape.
function ss.SelectRandomShape(tag, seed)
    local indices = InkShapeLists[tag]
    local name = "SplashSWEPs: Select random shape"
    local i = math.min(math.floor(util.SharedRandom(name, 1, #indices + 1, seed)), #indices)
    return ss.InkShapes[indices[i]]
end
