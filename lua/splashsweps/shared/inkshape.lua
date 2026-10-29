
-- Shapes of painted ink, defined by vmt files under materials/splashsweps/inkshapes.

---@class ss
local ss = SplashSWEPs
local VTF  = ss.import "splashsweps/shared/vtf/reader"
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkShapeModule
local InkShape = ss.module "splashsweps/shared/inkshape"

---Ink shape mask: the ink shape texture binarized for the server to update paintable grids.
---Access the mask value using `shape.Mask[y * shape.Mask.Width + x + 1]`: boolean.
---@class ss.InkShape.Mask
---@field [integer]     boolean   True for filled pixel, index = y * Width + x + 1
---@field Width         integer   The width of the mask.
---@field Height        integer   The height of the mask.
---@field IntegralImage integer[] Integral image for faster filtering, index = y * Width + x + 1

---Defines the shape of painted ink.
---@class ss.InkShape
---@field Index       integer          The internal index used in networking.
---@field Identifier  string           The path of the vmt file under materials/splashsweps/inkshapes.
---@field Mask        ss.InkShape.Mask Mask for drawing on paintable grids.
---@field MaskTexture string?          Only used clientside; mask texture to create drawing materials.
---@field Channel     "R"|"G"|"B"|"A"? Determines which channel of MaskTexture to use.

---@class ss.InkShapeModule.State
---@field Shapes  ss.InkShape[]            Defined ink shapes indexed by their internal index.
---@field Lists   table<string, integer[]> Ink shape category --> list of indices to Shapes.
---@field NumBits integer                  Required bits to transfer an ink shape index as an unsigned integer.
local state = ss.state("splashsweps/shared/inkshape", { Shapes = {}, Lists = {} }) ---@type ss.InkShapeModule.State

---Defined ink shapes indexed by their internal index.
InkShape.Shapes = state.Shapes

---Shape masks are signed distance fields where this value (0.5 in 0-255) is the edge.
---The paint shader clips the paint by the same value.
local SHAPE_MASK_EDGE = 127.5

---Reads pixels from the given texture and stores them in the mask.
---@param vmt IMaterial definition of the ink shape.
---@return ss.InkShape? # the mask to be stored to.
local function ReadPixelsFromVTF(vmt)
    ---Uncompressed texture to define the mask.
    local path = vmt:GetString "$basetexture"
    if not path then return end
    if not path:EndsWith ".vtf" then path = path .. ".vtf" end
    if not file.Exists("materials/" .. path, "GAME") then return end
    local vtf = VTF.Read(path)
    Util.assert(vtf, "Shape mask has invalid texture (" .. path .. ")") ---@cast vtf -?

    local width = vtf.Images[1].Width
    local height = vtf.Images[1].Height
    local VALID_CHANNELS = { R = "R", G = "G", B = "B", A = "A" }
    ---@type ss.InkShape
    local shape = {
        Index = 0,
        Identifier = "",
        Mask = { Width = width, Height = height, IntegralImage = {} },
        MaskTexture = path,
        Channel = VALID_CHANNELS[vmt:GetString "$channel" or "R"] or "R",
    }

    local mask = shape.Mask
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local index = y * width + x + 1
            local above =  y > 0            and mask.IntegralImage[(y - 1) * width + x + 1] or 0
            local left  =  x > 0            and mask.IntegralImage[ y      * width + x    ] or 0
            local diag  = (x > 0 and y > 0) and mask.IntegralImage[(y - 1) * width + x    ] or 0
            mask[index] = VTF.ReadPixel(vtf, x, y).a > SHAPE_MASK_EDGE
            mask.IntegralImage[index] = (mask[index] and 1 or 0) + left + above - diag
        end
    end

    return shape
end

---Reads all vmt files and defines all ink shapes used in this addon.
function InkShape.Load()
    local shapeCount = 0
    for f in Util.IterateFilesRecursive("materials/splashsweps/inkshapes", "GAME", "*.vmt") do
        local vmt = Material(f:gsub("^materials/", ""), nil)
        if not vmt:IsError() then
            local param = vmt:GetString "$splashsweps_tag" or ""
            local tag = param:match "^[a-z0-9_]+$"
            local shape = ReadPixelsFromVTF(vmt)
            if tag and shape then
                shapeCount = shapeCount + 1
                shape.Index = shapeCount
                shape.Identifier = f:gsub("^materials/splashsweps/inkshapes/", "")
                state.Lists[tag] = table.ForceInsert(state.Lists[tag], shape.Index)
                state.Shapes[shape.Index] = shape
            end
        end
    end

    state.NumBits = math.max(select(2, math.frexp(shapeCount - 1)), 1)
end

---Returns the required bits to transfer an ink shape index as an unsigned integer.
---@return integer
function InkShape.GetNumBits()
    return state.NumBits
end

---Picks up random ink shape within the category of "tag" using given random seed.
---@param tag string tag to search for.
---@param seed? number optional random seed such as `CurTime()`.
---@return ss.InkShape # Randomly chosen ink shape.
function InkShape.SelectRandom(tag, seed)
    local indices = state.Lists[tag]
    local name = "SplashSWEPs: Select random shape"
    local i = math.min(math.floor(util.SharedRandom(name, 1, #indices + 1, seed)), #indices)
    return state.Shapes[indices[i]]
end

return InkShape
