
-- Shapes of painted ink, defined by vmt files under materials/splashsweps/inkshapes.
-- The server defines them from its vmt files and sends the list to each client,
-- which defines the same ink shapes in the same order.

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
---@field Tag         string           The category of the ink shape, `$splashsweps_tag` of the vmt file.
---@field Mask        ss.InkShape.Mask Mask for drawing on paintable grids.
---@field MaskTexture string?          Only used clientside; mask texture to create drawing materials.
---@field Channel     "R"|"G"|"B"|"A"? Determines which channel of MaskTexture to use.

---An ink shape in the list the server sends.
---@class ss.InkShape.Received
---@field Identifier string
---@field Tag        string

---@class ss.InkShapeModule.State
---@field Shapes   ss.InkShape[]            Defined ink shapes indexed by their internal index.
---@field Lists    table<string, integer[]> Ink shape category --> list of indices to Shapes.
---@field NumBits  integer                  Required bits to transfer an ink shape index as an unsigned integer.
---@field Received ss.InkShape.Received[]?  Client only; ink shapes the server sent in the order of the indices.
local state = ss.state("splashsweps/shared/inkshape", { Shapes = {}, Lists = {} }) ---@type ss.InkShapeModule.State

---Defined ink shapes indexed by their internal index.
InkShape.Shapes = state.Shapes

---Shape masks are signed distance fields where this value (0.5 in 0-255) is the edge.
---The paint shader clips the paint by the same value.
local SHAPE_MASK_EDGE = 127.5

---Drawn instead of an ink shape the server has and the client does not.
---It is not a file to read the mask from, so the mask of such an ink shape fills the whole square of its size.
local ERROR_TEXTURE = "error"
local ERROR_TEXTURE_SIZE = 32

---Builds a mask with its integral image.
---@param width  integer
---@param height integer
---@param filled fun(x: integer, y: integer): boolean
---@return ss.InkShape.Mask
local function BuildMask(width, height, filled)
    local mask = { Width = width, Height = height, IntegralImage = {} } ---@type ss.InkShape.Mask
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local index = y * width + x + 1
            local above =  y > 0            and mask.IntegralImage[(y - 1) * width + x + 1] or 0
            local left  =  x > 0            and mask.IntegralImage[ y      * width + x    ] or 0
            local diag  = (x > 0 and y > 0) and mask.IntegralImage[(y - 1) * width + x    ] or 0
            mask[index] = filled(x, y)
            mask.IntegralImage[index] = (mask[index] and 1 or 0) + left + above - diag
        end
    end
    return mask
end

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

    local VALID_CHANNELS = { R = "R", G = "G", B = "B", A = "A" }
    local channel = VALID_CHANNELS[vmt:GetString "$channel" or "R"] or "R"
    local key = channel:lower() ---@type "r"|"g"|"b"|"a"
    ---@type ss.InkShape
    local shape = {
        Index = 0,
        Identifier = "",
        Tag = "",
        Mask = BuildMask(vtf.Images[1].Width, vtf.Images[1].Height, function(x, y)
            return VTF.ReadPixel(vtf, x, y)[key] > SHAPE_MASK_EDGE
        end),
        MaskTexture = path,
        Channel = channel,
    }

    return shape
end

---Defines an ink shape at the index.
---@param index      integer
---@param identifier string
---@param tag        string
---@param shape      ss.InkShape
local function Define(index, identifier, tag, shape)
    shape.Index = index
    shape.Identifier = identifier
    shape.Tag = tag
    state.Lists[tag] = table.ForceInsert(state.Lists[tag], index)
    state.Shapes[index] = shape
end

---Defines the ink shapes.
---The server reads all vmt files, and the client follows the list the server sent by InkShape.Write.
function InkShape.Load()
    local shapeCount = 0
    if SERVER then
        for f in Util.IterateFilesRecursive("materials/splashsweps/inkshapes", "GAME", "*.vmt") do
            local vmt = Material(f:gsub("^materials/", ""), nil)
            if not vmt:IsError() then
                local param = vmt:GetString "$splashsweps_tag" or ""
                local tag = param:match "^[a-z0-9_]+$"
                local shape = ReadPixelsFromVTF(vmt)
                if tag and shape then
                    shapeCount = shapeCount + 1
                    Define(shapeCount, (f:gsub("^materials/splashsweps/inkshapes/", "")), tag, shape)
                end
            end
        end
    else
        local received = Util.assert(state.Received, "The server did not send the ink shapes before InitPostEntity")
        local missing = {} ---@type string[]
        for i, r in ipairs(received) do
            local vmt = Material("splashsweps/inkshapes/" .. r.Identifier)
            local shape = not vmt:IsError() and ReadPixelsFromVTF(vmt) or nil
            if not shape then
                missing[#missing + 1] = r.Identifier
                shape = {
                    Index = 0,
                    Identifier = "",
                    Tag = "",
                    Mask = BuildMask(ERROR_TEXTURE_SIZE, ERROR_TEXTURE_SIZE, function() return true end),
                    MaskTexture = ERROR_TEXTURE,
                    Channel = "R",
                }
            end
            Define(i, r.Identifier, r.Tag, shape)
        end
        shapeCount = #received
        if #missing > 0 then
            print("SplashSWEPs: These ink shapes of the server are missing and drawn as errors:\n    "
                .. table.concat(missing, "\n    "))
        end
    end

    state.NumBits = math.max(select(2, math.frexp(shapeCount - 1)), 1)
end

---Writes the identifiers and the tags of the ink shapes to the net message,
---for the client to define the same ink shapes.
function InkShape.Write()
    net.WriteUInt(#state.Shapes, 16)
    for _, shape in ipairs(state.Shapes) do
        net.WriteString(shape.Identifier)
        net.WriteString(shape.Tag)
    end
end

---Reads the ink shapes InkShape.Write wrote and keeps them for InkShape.Load.
function InkShape.Read()
    local received = {} ---@type ss.InkShape.Received[]
    for i = 1, net.ReadUInt(16) do
        received[i] = { Identifier = net.ReadString(), Tag = net.ReadString() }
    end
    state.Received = received
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
