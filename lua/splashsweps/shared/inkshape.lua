
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Mask array used to draw on PaintableSurface grid.  
---Access the mask value using `InkShape.GridBrush[x][y]`: boolean.
---@class ss.InkShape.GridBrush
---@field [integer] boolean[]
---@field Width integer
---@field Weight integer
---@overload fun(width?: integer, height?: integer): ss.InkShape.GridBrush
ss.struct "InkShape.GridBrush" {
    Width = 0,
    Weight = 0,
}

---Constructor for InkShape.GridBrush.
---@param this ss.InkShape.GridBrush
---@param width? integer
---@param height? integer
ss.ctor "InkShape.GridBrush" (function (this, width, height)
    if not (width and height) then return end
    this.Width = width
    this.Weight = height
    for i = 1, width do
        this[i] = {}
        for j = 1, height do
            this[i][j] = false
        end
    end
end)

---Defines the shape of painted ink.
---@class ss.InkShape
---@field Identifier string The identifier of this ink shape as the key of ss.InkShapes.
---@field MaskTexture string Only used clientside; mask texture to create drawing materials.
---@field GridBrush ss.InkShape.GridBrush Mask for drawing on PaintableSurface grid.  
ss.struct "InkShape" {
    Identifier = "",
    MaskTexture = "",
    GridBrush = ss.new "InkShape.GridBrush"
}

---Read pixels from givem texture and stores them to the mask.
---@param vmt IMaterial definition of the ink shape.
---@return ss.InkShape # the mask to be stored to.
local function ReadPixelsFromVTF(vmt)
    ---Uncompressed texture to define the mask.
    local vtf = vmt:GetTexture "$basetexture"
    ss.assert(not vtf:IsErrorTexture(), "Shape mask has invalid texture.")

    local path = vtf:GetName()
    local width = vtf:GetMappingWidth()
    local height = vtf:GetMappingHeight()
    local shape = ss.new "InkShape"
    local grid = ss.new "InkShape.GridBrush" (width, height)
    shape.GridBrush = grid
    shape.MaskTexture = path

    local threshold = vmt:GetFloat "$splashsweps_maskthreshold" or 0.5
    if threshold < 1 then threshold = threshold * 255 end
    for i = 1, width do
        grid[i] = {}
        for j = 1, height do
            grid[i][j] = vtf:GetColor(i - 1, j - 1).a > threshold
        end
    end

    return shape
end

---Reads all vmt files and defines all ink shapes used in this addon.
function ss.LoadInkShapes()
    for f in ss.IterateFilesRecursive("materials/splashsweps/paints", "GAME", "*.vmt") do
        local vmt = Material(f:gsub("^materials/", ""))
        if not vmt:IsError() then
            local param = vmt:GetString "$splashsweps_tag"
            local tag = param:match "^[a-z0-9]+$"
            if tag then
                local shape = ReadPixelsFromVTF(vmt)
                shape.Identifier = f:gsub("^materials/splashsweps/paints/", "")
                ss.InkShapeLists[tag] = table.ForceInsert(ss.InkShapeLists[tag], shape.Identifier)
                ss.InkShapes[shape.Identifier] = shape
            end
        end
    end
end

---Picks up random ink shape within the category of "tag" using given random seed.
---@param tag string tag to search for.
---@param seed? number optional random seed such as `CurTime()`.
---@return ss.InkShape # Randomly chosen ink shape.
function ss.SelectRandomShape(tag, seed)
    local keys = ss.InkShapeLists[tag]
    local name = "SplashSWEPs: Select random shape"
    return ss.InkShapes[keys[util.SharedRandom(name, 1, #keys, seed)]]
end
