
---@class ss
local ss = SplashSWEPs
if not ss then return end

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
    local vtf = ss.ReadVTF(path)
    return vtf and FORMATS_WITH_ALPHA[vtf.ImageFormat]
end

---Copies a texture into the rectangle's one-pixel inset, transposing UVs if rect.rotated.
---Uses the current RT/2D context; the shared copy material's $c0_x selects the source alpha channel.
-- I couldn't make it work with surface.DrawTexturedRect for some reason;
-- sometimes all TEXCOORD0 are (0.5, 0.5), so I use the mesh library instead.
---@param tex ITexture|string
---@param rect ss.Rectangle
---@param drawcolor boolean
---@param drawalpha boolean
function ss.CopyTextureToRect(tex, rect, drawcolor, drawalpha)
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
    -- Transpose source UVs with the packed cell; negative atlas min U tells drawink_vs30 to undo it.
    mesh.Begin(MATERIAL_QUADS, 1)
    mesh.Position(rect.left + HALF_MARGIN, rect.bottom + HALF_MARGIN, 0)
    mesh.TexCoord(0, 0, 0)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.left + HALF_MARGIN, rect.top - HALF_MARGIN, 0)
    mesh.TexCoord(0, rect.rotated and 1 or 0, rect.rotated and 0 or 1)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.right - HALF_MARGIN, rect.top - HALF_MARGIN, 0)
    mesh.TexCoord(0, 1, 1)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.right - HALF_MARGIN, rect.bottom + HALF_MARGIN, 0)
    mesh.TexCoord(0, rect.rotated and 0 or 1, rect.rotated and 1 or 0)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.End()
    render.OverrideBlend(false)
end

---Collects textures and packing rectangles.
---@return ss.InkTypeAtlasSources sources
local function ReadInkTypeSources()
    local sources = { ---@class ss.InkTypeAtlasSources
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
    for i, inktype in ipairs(ss.InkTypes) do
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
            local tintcolor = mat:GetVector "$tintcolor" or ss.vector_one
            local translucent = alpha < 1 or not tintcolor:IsEqualTol(ss.vector_one, ss.eps)
            tint = translucent and white or black
        end
        sources.TintNames[i] = tint:GetName()
        if not sources.TintCache[tint:GetName()] then
            sources.TintCache[tint:GetName()] = i
            sources.TintRects[#sources.TintRects + 1] = ss.MakeRectangle(
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
            sources.BaseRects[#sources.BaseRects + 1] = ss.MakeRectangle(
                math.max(base:Width(),  heightSource and heightSource:Width()  or 0) + MARGIN,
                math.max(base:Height(), heightSource and heightSource:Height() or 0) + MARGIN,
                0, 0, inktype)
        end
    end

    for i, shape in ipairs(ss.InkShapes) do
        sources.ShapeRects[i] = ss.MakeRectangle(
            shape.Grid.Width + MARGIN, shape.Grid.Height + MARGIN, 0, 0, shape)
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

---Builds the albedo and height atlas and assigns base UV ranges.
---@param sources ss.InkTypeAtlasSources
local function BuildAlbedoAtlas(sources)
    local packer = ss.MakeRectanglePacker(sources.BaseRects):packall()
    local rt = GetAtlasRenderTarget("splashsweps_albedo", packer.maxsize)
    ss.RenderTarget.StaticTextures.Albedo = rt
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            cp:SetInt("$c0_x", 3)
            ss.CopyTextureToRect(sources.BaseNames[inktype.Index], rect, true, true)
            if sources.HeightNames[inktype.Index] then
                cp:SetInt("$c0_x", CHANNEL_INDEX[sources.HeightChannels[inktype.Index]] or 0)
                ss.CopyTextureToRect(sources.HeightNames[inktype.Index], rect, false, true)
            elseif not sources.BaseAlphaHeight[inktype.Index] then
                -- The alpha channel is used as the height map
                local tex = sources.TintNames[inktype.Index]
                if not HasAlphaChannel(tex) then
                    tex = "grey" -- $tinttexture with no alpha channel
                    cp:SetInt("$c0_x", 0)
                end
                ss.CopyTextureToRect(tex, rect, false, true)
            end

            -- Min U is strictly positive due to the margin; its sign encodes transposition.
            inktype.BaseUV = {
                (rect.rotated and -1 or 1) * (rect.left + HALF_MARGIN + 0.5) / rt:Width(),
                (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
            }
        end
    cam.End2D()
    render.PopRenderTarget()

    for _, inktype in ipairs(ss.InkTypes) do
        inktype.BaseUV = inktype.BaseUV
            or ss.InkTypes[sources.BaseCache[sources.BaseKeys[inktype.Index]]].BaseUV
    end
end

---Builds the tint and shape atlas and assigns their UV ranges.
---@param sources ss.InkTypeAtlasSources
local function BuildTintAtlas(sources)
    -- Tint images and shape masks are packed separately into color and alpha,
    -- so the atlas takes the larger size of them.
    local tintPacker  = ss.MakeRectanglePacker(sources.TintRects):packall()
    local shapePacker = ss.MakeRectanglePacker(sources.ShapeRects):packall()
    local rt = GetAtlasRenderTarget("splashsweps_tint", math.max(tintPacker.maxsize, shapePacker.maxsize))
    ss.RenderTarget.StaticTextures.Tint = rt
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        for _, rect in ipairs(tintPacker.rects) do
            local inktype = rect.tag ---@type ss.InkType
            ss.CopyTextureToRect(sources.TintNames[inktype.Index], rect, true, false)
            inktype.TintUV = {
                (rect.rotated and -1 or 1) * (rect.left + HALF_MARGIN + 0.5) / rt:Width(),
                (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
            }
        end

        -- Write shape atlas to the alpha channel
        for _, rect in ipairs(shapePacker.rects) do
            local shape = rect.tag ---@type ss.InkShape
            cp:SetInt("$c0_x", CHANNEL_INDEX[shape.Channel] or 3)
            ss.CopyTextureToRect(shape.MaskTexture:StripExtension(), rect, false, true)
            shape.UV = {
                (rect.rotated and -1 or 1) * (rect.left + HALF_MARGIN + 0.5) / rt:Width(),
                (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
            }
        end
    cam.End2D()
    render.PopRenderTarget()

    for _, inktype in ipairs(ss.InkTypes) do
        inktype.TintUV = inktype.TintUV
            or ss.InkTypes[sources.TintCache[sources.TintNames[inktype.Index]]].TintUV
    end
end

function ss.LoadInkTypesRT()
    local sources = ReadInkTypeSources()
    local rowsByType = ss.PrepareInkDetailsRT(sources.BaseNames)
    if not rowsByType then return end
    timer.Simple(0, function()
        BuildAlbedoAtlas(sources)
        BuildTintAtlas(sources)
        ss.WriteInitialInkDetailsRT(rowsByType)
    end)
end
