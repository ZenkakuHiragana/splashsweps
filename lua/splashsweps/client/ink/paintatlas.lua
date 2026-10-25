
-- Atlases of the textures of ink types and the masks of ink shapes, which the paint shader reads.

---@class ss
local ss = SplashSWEPs
local InkShape        = ss.import "splashsweps/shared/inkshape"
local InkType         = ss.import "splashsweps/shared/inktype"
local RectanglePacker = ss.import "splashsweps/shared/packer/packer"
local Structures      = ss.import "splashsweps/shared/packer/structures"
local Util            = ss.import "splashsweps/shared/util"
local VTF             = ss.import "splashsweps/shared/vtf/reader"

---@class ss.PaintAtlasModule
local PaintAtlas = ss.module "splashsweps/client/ink/paintatlas"

---Range of an image in an atlas: (minU, minV, maxU, maxV).
---Min U is strictly positive due to the margin; its sign encodes transposition.
---@alias ss.PaintAtlas.Range [number, number, number, number]

---@class ss.PaintAtlasModule.State
---@field Albedo  ITexture?                           $basetexture and height maps of ink types.
---@field Tint    ITexture?                           $tinttexture of ink types in RGB and masks of ink shapes in alpha.
---@field BaseUV  table<integer, ss.PaintAtlas.Range> Ink type index --> range of its $basetexture.
---@field TintUV  table<integer, ss.PaintAtlas.Range> Ink type index --> range of its $tinttexture.
---@field ShapeUV table<integer, ss.PaintAtlas.Range> Ink shape index --> range of its mask.
local state = ss.state("splashsweps/client/ink/paintatlas", {
    BaseUV = {},
    TintUV = {},
    ShapeUV = {},
}) ---@type ss.PaintAtlasModule.State

---Ink type index --> range of its $basetexture in the albedo atlas, for every ink type after PaintAtlas.Allocate.
PaintAtlas.BaseUV = state.BaseUV

---Ink type index --> range of its $tinttexture in the tint atlas, for every ink type after PaintAtlas.Allocate.
PaintAtlas.TintUV = state.TintUV

---Ink shape index --> range of its mask in the tint atlas, for every ink shape after PaintAtlas.Allocate.
PaintAtlas.ShapeUV = state.ShapeUV

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }
local cp = Material "splashsweps/shaders/copy"

---Image formats whose alpha channel can be used as a height map.
---DXT1 and BGRA5551 are excluded as their 1-bit alpha can't represent heights.
local FORMATS_WITH_ALPHA = {
    IMAGE_FORMAT_RGBA8888      = true,
    IMAGE_FORMAT_ABGR8888      = true,
    IMAGE_FORMAT_IA88          = true,
    IMAGE_FORMAT_A8            = true,
    IMAGE_FORMAT_ARGB8888      = true,
    IMAGE_FORMAT_BGRA8888      = true,
    IMAGE_FORMAT_DXT3          = true,
    IMAGE_FORMAT_DXT5          = true,
    IMAGE_FORMAT_BGRA4444      = true,
    IMAGE_FORMAT_RGBA16161616F = true,
    IMAGE_FORMAT_RGBA16161616  = true,
    IMAGE_FORMAT_RGBA32323232F = true,
}

---Checks if specified texture has alpha channel.
---@param path string Path to the texture
---@return boolean? hasAlpha True if it has alpha channel.
local function HasAlphaChannel(path)
    local vtf = VTF.Read(path)
    return vtf and FORMATS_WITH_ALPHA[vtf.ImageFormat]
end

---Adds a vertex of CopyTextureToRect.
---@param x number Destination position
---@param y number Destination position
---@param s number Source texture coordinate along the destination x axis
---@param t number Source texture coordinate along the destination y axis
---@param transposed boolean? True to read the source with its axes swapped
local function AddCopyVertex(x, y, s, t, transposed)
    if transposed then s, t = t, s end
    mesh.Position(x, y, 0)
    mesh.TexCoord(0, s, t)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
end

---Copies a texture into the rectangle's one-pixel inset, transposing UVs if rect.rotated.
---The quad also covers the one-pixel margin, which the copy shader fills with the edge pixels,
---so that bilinear filtering up to the edge of the inset never reads the margin.
---Uses the current RT/2D context; the shared copy material's $c0_x selects the source alpha channel.
-- I couldn't make it work with surface.DrawTexturedRect for some reason;
-- sometimes all TEXCOORD0 are (0.5, 0.5), so I use the mesh library instead.
---@param tex ITexture|string
---@param rect ss.Rectangle
---@param drawcolor boolean
---@param drawalpha boolean
local function CopyTextureToRect(tex, rect, drawcolor, drawalpha)
    cp:SetTexture("$basetexture", tex)
    cp:SetInt("$c0_y", 0)
    render.SetMaterial(cp)
    render.OverrideBlend(true,
        drawcolor and BLEND_ONE or BLEND_ZERO,
        drawcolor and BLEND_ZERO or BLEND_ONE,
        BLENDFUNC_ADD,
        drawalpha and BLEND_ONE or BLEND_ZERO,
        drawalpha and BLEND_ZERO or BLEND_ONE,
        BLENDFUNC_ADD)
    -- The quad covers the whole rectangle, so its source coordinates go beyond [0, 1] by the margin.
    local s0, s1 = -HALF_MARGIN / (rect.width - MARGIN), 1 + HALF_MARGIN / (rect.width - MARGIN)
    local t0, t1 = -HALF_MARGIN / (rect.height - MARGIN), 1 + HALF_MARGIN / (rect.height - MARGIN)
    -- Transpose source UVs with the packed cell; negative atlas min U tells drawink_vs30 to undo it.
    mesh.Begin(MATERIAL_QUADS, 1)
    AddCopyVertex(rect.left,  rect.bottom, s0, t0, rect.rotated)
    AddCopyVertex(rect.left,  rect.top,    s0, t1, rect.rotated)
    AddCopyVertex(rect.right, rect.top,    s1, t1, rect.rotated)
    AddCopyVertex(rect.right, rect.bottom, s1, t0, rect.rotated)
    mesh.End()
    render.OverrideBlend(false)
end

---Collects textures and packing rectangles.
---@return ss.PaintAtlas.Sources sources
local function ReadInkTypeSources()
    local sources = { ---@class ss.PaintAtlas.Sources
        BaseNames        = {}, ---@type string[]
        BaseKeys         = {}, ---@type string[] $basetexture and height map source sharing an atlas cell
        BaseCache        = {}, ---@type table<string, integer>
        BaseRects        = {}, ---@type ss.Rectangle[]
        BaseAlphaHeight  = {}, ---@type boolean[]
        HeightNames      = {}, ---@type string[]
        HeightChannels   = {}, ---@type string[]
        TintNames        = {}, ---@type string[]
        TintCache        = {}, ---@type table<string, integer>
        TintRects        = {}, ---@type ss.Rectangle[]
        ShapeRects       = {}, ---@type ss.Rectangle[]
    }
    cp:SetTexture("$basetexture", "color/black")
    local black = cp:GetTexture "$basetexture"
    cp:SetTexture("$basetexture", "color/white")
    local white = cp:GetTexture "$basetexture"
    for i, inktype in ipairs(InkType.Types) do
        local mat = Material(inktype.Identifier)

        cp:SetTexture("$basetexture", mat:GetString "$basetexture" or "???")
        local base = cp:GetTexture "$basetexture"
        if not base then
            ErrorNoHalt(string.format(
                "SplashSWEPs: $basetexture seems invalid for ink type '%s'\n",
                inktype.Identifier))
            base = white
        end
        sources.BaseNames[i] = base:GetName()

        cp:SetTexture("$basetexture", mat:GetString "$tinttexture" or "???")
        local tint = cp:GetTexture "$basetexture"
        if not tint then
            local alpha = mat:GetFloat "$alpha" or 1
            local tintcolor = mat:GetVector "$tintcolor" or Util.vector_one
            local translucent = alpha < 1 or not tintcolor:IsEqualTol(Util.vector_one, Util.eps)
            tint = translucent and white or black
        end
        sources.TintNames[i] = tint:GetName()
        if not sources.TintCache[tint:GetName()] then
            sources.TintCache[tint:GetName()] = i
            sources.TintRects[#sources.TintRects + 1] = Structures.MakeRectangle(
                tint:Width() + MARGIN, tint:Height() + MARGIN, 0, 0, inktype)
        end

        cp:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = cp:GetTexture "$basetexture"
        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        sources.HeightNames[i]     = height and height:GetName()
        sources.HeightChannels[i]  = mat:GetString "$heightchannel" or "R"
        sources.BaseAlphaHeight[i] = basealphaheightmap > 0 and HasAlphaChannel(sources.BaseNames[i]) or nil

        -- The height map is written to the alpha channel of the $basetexture cell,
        -- so the cell is identified by both and takes the larger size of them.
        local heightSource, heightKey = nil, ""
        if height then
            heightSource = height
            heightKey = "$heightmap " .. height:GetName() .. " " .. sources.HeightChannels[i]
        elseif sources.BaseAlphaHeight[i] then
            heightKey = "$basetexture alpha"
        elseif HasAlphaChannel(tint:GetName()) then
            heightSource = tint
            heightKey = "$tinttexture alpha " .. tint:GetName()
        end
        local baseKey = base:GetName() .. "|" .. heightKey
        sources.BaseKeys[i] = baseKey
        if not sources.BaseCache[baseKey] then
            sources.BaseCache[baseKey] = i
            sources.BaseRects[#sources.BaseRects + 1] = Structures.MakeRectangle(
                math.max(base:Width(),  heightSource and heightSource:Width()  or 0) + MARGIN,
                math.max(base:Height(), heightSource and heightSource:Height() or 0) + MARGIN,
                0, 0, inktype)
        end
    end

    for i, shape in ipairs(InkShape.Shapes) do
        sources.ShapeRects[i] = Structures.MakeRectangle(
            shape.Mask.Width + MARGIN, shape.Mask.Height + MARGIN, 0, 0, shape)
    end

    print "$basetexture"
    PrintTable(sources.BaseNames)
    print "$tinttexture"
    PrintTable(sources.TintNames)
    print "$heightmap"
    PrintTable(sources.HeightNames)
    return sources
end

---Gets an RGBA atlas render target sized to the packed images.
---@param name string
---@param size number Side length of the packed images
---@return ITexture
local function GetAtlasRenderTarget(name, size)
    return GetRenderTargetEx(name,
        size, size,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        256 + 512 + 32768 + 8388608, 0, -- NOMIP | NOLOD | RENDERTARGET | NODEPTHBUFFER
        IMAGE_FORMAT_RGBA8888)
end

---Packed layout of the atlases.
---@class ss.PaintAtlas.Plan
---@field Sources     ss.PaintAtlas.Sources
---@field BasePacker  ss.RectanglePacker
---@field TintPacker  ss.RectanglePacker
---@field ShapePacker ss.RectanglePacker

---Collects the textures of ink types and the masks of ink shapes, and packs them.
---@return ss.PaintAtlas.Plan
function PaintAtlas.Plan()
    local sources = ReadInkTypeSources()
    return {
        Sources     = sources,
        BasePacker  = RectanglePacker.new(sources.BaseRects):packall(),
        -- Tint images and shape masks are packed separately into color and alpha,
        -- so the atlas takes the larger size of them.
        TintPacker  = RectanglePacker.new(sources.TintRects):packall(),
        ShapePacker = RectanglePacker.new(sources.ShapeRects):packall(),
    }
end

---Returns the atlas range of a packed rectangle.
---@param rect ss.Rectangle
---@param rt ITexture
---@param inset number Distance from the edge of the rectangle in pixels
---@return ss.PaintAtlas.Range
local function GetAtlasRange(rect, rt, inset)
    return {
        (rect.rotated and -1 or 1) * (rect.left + inset) / rt:Width(),
        (rect.bottom + inset) / rt:Height(),
        (rect.right  - inset) / rt:Width(),
        (rect.top    - inset) / rt:Height(),
    }
end

---Creates the atlas render targets and assigns the atlas ranges of ink types and ink shapes.
---@param plan ss.PaintAtlas.Plan
function PaintAtlas.Allocate(plan)
    local sources = plan.Sources
    state.Albedo = GetAtlasRenderTarget("splashsweps_albedo", plan.BasePacker.maxsize)
    state.Tint = GetAtlasRenderTarget("splashsweps_tint", math.max(plan.TintPacker.maxsize, plan.ShapePacker.maxsize))
    table.Empty(state.BaseUV)
    table.Empty(state.TintUV)
    table.Empty(state.ShapeUV)
    for _, rect in ipairs(plan.BasePacker.rects) do
        local inktype = rect.tag ---@type ss.InkType
        state.BaseUV[inktype.Index] = GetAtlasRange(rect, state.Albedo, HALF_MARGIN + 0.5)
    end
    for _, rect in ipairs(plan.TintPacker.rects) do
        local inktype = rect.tag ---@type ss.InkType
        state.TintUV[inktype.Index] = GetAtlasRange(rect, state.Tint, HALF_MARGIN + 0.5)
    end
    -- The whole mask spans the paint quad, as PaintableGrid.Write does.
    for _, rect in ipairs(plan.ShapePacker.rects) do
        local shape = rect.tag ---@type ss.InkShape
        state.ShapeUV[shape.Index] = GetAtlasRange(rect, state.Tint, HALF_MARGIN)
    end
    -- Ink types sharing a cell share its range.
    for _, inktype in ipairs(InkType.Types) do
        local i = inktype.Index
        state.BaseUV[i] = state.BaseUV[i] or state.BaseUV[sources.BaseCache[sources.BaseKeys[i]]]
        state.TintUV[i] = state.TintUV[i] or state.TintUV[sources.TintCache[sources.TintNames[i]]]
    end
end

---Draws the textures and masks into the atlases.
---Needs a rendering context, so call it after PaintAtlas.Allocate, from the next frame.
---@param plan ss.PaintAtlas.Plan
function PaintAtlas.Draw(plan)
    local sources = plan.Sources
    render.PushRenderTarget(state.Albedo)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        for _, rect in ipairs(plan.BasePacker.rects) do
            local inktype = rect.tag ---@type ss.InkType
            cp:SetInt("$c0_x", 3)
            CopyTextureToRect(sources.BaseNames[inktype.Index], rect, true, true)
            if sources.HeightNames[inktype.Index] then
                cp:SetInt("$c0_x", CHANNEL_INDEX[sources.HeightChannels[inktype.Index]] or 0)
                CopyTextureToRect(sources.HeightNames[inktype.Index], rect, false, true)
            elseif not sources.BaseAlphaHeight[inktype.Index] then
                -- The alpha channel is used as the height map
                local tex = sources.TintNames[inktype.Index]
                if not HasAlphaChannel(tex) then
                    tex = "grey" -- $tinttexture with no alpha channel
                    cp:SetInt("$c0_x", 0)
                end
                CopyTextureToRect(tex, rect, false, true)
            end
        end
    cam.End2D()
    render.PopRenderTarget()

    render.PushRenderTarget(state.Tint)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        for _, rect in ipairs(plan.TintPacker.rects) do
            local inktype = rect.tag ---@type ss.InkType
            CopyTextureToRect(sources.TintNames[inktype.Index], rect, true, false)
        end

        -- Write shape atlas to the alpha channel.
        -- The margin repeats the edge pixels for bilinear filtering at the edge of the mask.
        for _, rect in ipairs(plan.ShapePacker.rects) do
            local shape = rect.tag ---@type ss.InkShape
            cp:SetInt("$c0_x", CHANNEL_INDEX[shape.Channel] or 3)
            CopyTextureToRect(shape.MaskTexture:StripExtension(), rect, false, true)
        end
    cam.End2D()
    render.PopRenderTarget()
end

return PaintAtlas
