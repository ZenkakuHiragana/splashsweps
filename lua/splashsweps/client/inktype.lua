
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkTypeRT then
    ---@class ss.Locals.InkTypeRT
    ---@field BaseTextureNames string[] $basetexture of each ink type, which also provides its average height
    ---@field DetailTextures ITexture[] Detail image of each grid cell
    ---@field DetailSlots table<integer, integer> Grid cell of each ink type, nil if the ink type has no detail image
    locals.InkTypeRT = {
        BaseTextureNames = {},
        DetailTextures = {},
        DetailSlots = {},
    }
end

local InkTypeRT = locals.InkTypeRT

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }
local cp = Material "splashsweps/shaders/copy"
local detailCopyMaterial = Material "splashsweps/shaders/copydetail"

---Checks if specified texture has alpha channel.
---DXT1 and DXT3 only support 1-bit alpha which can't be used as a height map.
---@param path string Path to the texture
---@return any? hasAlpha Non-nil value if it has alpha channel.
local function HasAlphaChannel(path)
    local vtf = ss.ReadVTF(path)
    return vtf and (
        vtf.ImageFormat == "DXT5" or
        vtf.ImageFormat:sub(#"IMAGE_FORMAT_"):find "A")
end

---Copies a texture into a rectangle with optional RGB and alpha writes.
-- I couldn't make it work with surface.DrawTexturedRect for some reason;
-- sometimes all TEXCOORD0 are (0.5, 0.5), so I use the mesh library instead.
---@param tex ITexture|string
---@param rect ss.Rectangle
---@param drawcolor boolean
---@param drawalpha boolean
local function draw(tex, rect, drawcolor, drawalpha)
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
    mesh.Begin(MATERIAL_QUADS, 1)
    mesh.Position(rect.left + HALF_MARGIN, rect.bottom + HALF_MARGIN, 0)
    mesh.TexCoord(0, 0, 0)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.left + HALF_MARGIN, rect.top - HALF_MARGIN, 0)
    mesh.TexCoord(0, 0, 1)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.right - HALF_MARGIN, rect.top - HALF_MARGIN, 0)
    mesh.TexCoord(0, 1, 1)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.Position(rect.right - HALF_MARGIN, rect.bottom + HALF_MARGIN, 0)
    mesh.TexCoord(0, 1, 0)
    mesh.TexCoord(1, 1, 1, 1, 1)
    mesh.AdvanceVertex()
    mesh.End()
    render.OverrideBlend(false)
end

---Encodes material parameters of an ink type into the data rows read by the shader.
---@param mat IMaterial The material of the ink type
---@param detailSlot integer? Grid cell of the detail image, nil if the ink type has none
---@return number[][] rows Data rows of four components each
local function ReadParameters(mat, detailSlot)
    local detailtexturetransform     = mat:GetMatrix "$detailtexturetransform" or Matrix()
    local detailtransformscale       = detailtexturetransform:GetScale()
    local detailtransformtranslation = detailtexturetransform:GetTranslation()
    local detailtransformaxis        = detailtexturetransform:GetForward():GetNormalized() -- (cos, sin, 0)
    local detailperiod               = mat:GetFloat "$detailperiod" or 512
    local detailblendscale           = { mat:GetVector4D "$detailblendscale" }
    local color                      = mat:GetVector "$color"     or ss.vector_one
    local tintcolor                  = mat:GetVector "$tintcolor" or ss.vector_one
    local alpha                      = mat:GetFloat "$alpha" or 1
    local edgecolor                  = mat:GetVector "$edgecolor"
    local edgeflag                   = edgecolor and 128 or 0
    local edgeadditive               = edgecolor or vector_origin
    return {
        { color.x,     color.y,     color.z,     alpha },
        { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
        {
            (mat:GetInt "$maxlayers" or 1) / 255,
            mat:GetFloat "$maxheight" or 1,
            math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
            mat:GetFloat "$heightbaseline" or -1,
        }, {
            mat:GetFloat "$erase"           or 0,
            mat:GetFloat "$flatten"         or 0,
            mat:GetFloat "$viscosity"       or 1,
            (mat:GetInt "$nodig"      or 0) * 0.5 +
            (mat:GetInt "$heightonly" or 0) * 0.125,
        }, {
            mat:GetFloat "$metallic"        or 0,
            mat:GetFloat "$roughness"       or 0,
            mat:GetFloat "$specularscale"   or 1,
            1 - 1 / (mat:GetFloat "$refractiveindex" or 1.33), -- Refraction strength for the shader
        },
        {
            -- Additive color of a single $alpha layer of $edgecolor, in gamma space as in the ink map
            edgeadditive.x * alpha,
            edgeadditive.y * alpha,
            edgeadditive.z * alpha,
            -- Bit 7: $edgecolor is set, bits 0-6: $bumpblendfactor
            (edgeflag + math.Clamp(mat:GetFloat "$bumpblendfactor" or 1, 0, 1) * 127) / 255,
        },
        {
            -- 127 / 255 represents 1
            (detailblendscale[1] or 1) * 127 / 255,
            (detailblendscale[2] or 1) * 127 / 255,
            (detailblendscale[3] or 1) * 127 / 255,
            (detailblendscale[4] or 1) * 127 / 255,
        }, {
            detailtransformtranslation.x % 1,
            detailtransformtranslation.y % 1,
            -- 127 / 255 represents zero
            (detailtransformaxis.x + 1) * 127 / 255,
            (detailtransformaxis.y + 1) * 127 / 255,
        }, {
            -- Image repeats per Hammer unit, log2 with 24 steps per octave from 2^-13
            (math.log(detailtransformscale.x / detailperiod, 2) + 13) * 24 / 255,
            (math.log(detailtransformscale.y / detailperiod, 2) + 13) * 24 / 255,
            ((detailSlot or 1) - 1) / 255, -- Grid index of the detail image
            0, -- Unused
        },
    }
end

---Copies detail images into their grid cells with one-texel borders wrapping around the image.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param textures table<integer, ITexture> Grid cell --> detail image
local function WriteDetailCells(textures)
    local gridColumns = ss.RenderTarget.DetailGridColumns
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    surface.SetDrawColor(255, 255, 255, 255)
    for slot, texture in pairs(textures) do
        local cellSize = ss.RenderTarget.DetailsImageSize / gridColumns
        local detailSize = cellSize - MARGIN
        local x = (slot - 1) % gridColumns * cellSize
        local y = math.floor((slot - 1) / gridColumns) * cellSize
        local uvMin, uvMax = -1 / detailSize, 1 + 1 / detailSize
        detailCopyMaterial:SetTexture("$basetexture", texture)
        surface.SetMaterial(detailCopyMaterial)
        -- Explicit UVs preserve the one-texel border without surface's rectangle UV correction.
        surface.DrawPoly {
            { x = x,            y = y,            u = uvMin, v = uvMin },
            { x = x + cellSize, y = y,            u = uvMax, v = uvMin },
            { x = x + cellSize, y = y + cellSize, u = uvMax, v = uvMax },
            { x = x,            y = y + cellSize, u = uvMin, v = uvMax },
        }
    end
    render.OverrideBlend(false)
end

---Writes data rows of ink types below the grid cells so that they can be read in the shader.
---A negative $heightbaseline is then replaced with the average height of $basetexture.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param parameters table<integer, number[][]> Ink type index --> data rows from ReadParameters()
local function WriteInkTypeRows(parameters)
    if not next(parameters) then return end
    local rtSize = ss.RenderTarget.DetailsImageSize
    local numRows = 0
    for _, rows in pairs(parameters) do
        numRows = numRows + #rows
    end

    cp:SetTexture("$basetexture", "color/white")
    cp:SetInt("$c0_x", 3)
    cp:SetInt("$c0_y", 1)
    render.SetMaterial(cp)
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_POINTS, numRows)
    for i, rows in pairs(parameters) do
        for j, float4 in ipairs(rows) do
            mesh.Position(i, j + rtSize, 0)
            mesh.TexCoord(0, 0.5, 0.5)
            mesh.TexCoord(1, unpack(float4))
            mesh.AdvanceVertex()
        end
    end
    mesh.End()
    render.OverrideBlend(false)

    -- Writes the average height of each ink type
    for i, rows in pairs(parameters) do
        local heightbaseline = rows[3][4]
        if heightbaseline < 0 then
            draw(InkTypeRT.BaseTextureNames[i], ss.MakeRectangle(1, 1, i - 1, 3 - 1 + rtSize), false, true)
        end
    end
end

---Collects textures and packing rectangles, and encodes ink type parameters.
---@return ss.InkTypeAtlasSources sources
---@return number[][][] parameters
local function ReadInkTypeSources()
    local sources = { ---@class ss.InkTypeAtlasSources
        BaseNames       = {}, ---@type string[]
        BaseCache       = {}, ---@type table<string, integer>
        BaseRects       = {}, ---@type ss.Rectangle[]
        BaseAlphaHeight = {}, ---@type boolean[]
        HeightNames     = {}, ---@type string[]
        HeightChannels  = {}, ---@type string[]
        TintNames       = {}, ---@type string[]
        TintCache       = {}, ---@type table<string, integer>
        TintRects       = {}, ---@type ss.Rectangle[]
        ShapeRects      = {}, ---@type ss.Rectangle[]
        DetailNames     = {}, ---@type string[]
        DetailCache     = {}, ---@type table<string, integer>
        DetailTextures  = {}, ---@type ITexture[]
        DetailSlots     = {}, ---@type table<integer, integer>
    }
    local parameters = {} ---@type number[][][]
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
        if not sources.BaseCache[base:GetName()] then
            sources.BaseCache[base:GetName()] = i
            sources.BaseRects[#sources.BaseRects + 1] = ss.MakeRectangle(
                base:Width() + MARGIN, base:Height() + MARGIN, 0, 0, inktype)
        end

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

        cp:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = cp:GetTexture "$basetexture"
        if detail then
            local name = detail:GetName()
            sources.DetailNames[i] = name
            inktype.DetailBlendMode = mat:GetInt "$detailblendmode" or 0
            if not sources.DetailCache[name] then
                sources.DetailTextures[#sources.DetailTextures + 1] = detail
                sources.DetailCache[name] = #sources.DetailTextures
            end
            sources.DetailSlots[i] = sources.DetailCache[name]
        end

        cp:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = cp:GetTexture "$basetexture"
        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        sources.HeightNames[i]     = height and height:GetName()
        sources.HeightChannels[i]  = mat:GetString "$heightchannel" or "R"
        sources.BaseAlphaHeight[i] = basealphaheightmap > 0 and HasAlphaChannel(sources.BaseNames[i]) or nil

        parameters[i] = ReadParameters(mat, sources.DetailSlots[i])
    end

    for i, shape in ipairs(ss.InkShapes) do
        sources.ShapeRects[i] = ss.MakeRectangle(
            shape.Grid.Width + MARGIN, shape.Grid.Height + MARGIN, 0, 0, shape)
    end

    print "$basetexture"
    PrintTable(sources.BaseNames)
    print "$tinttexture"
    PrintTable(sources.TintNames)
    print "$detail"
    PrintTable(sources.DetailNames)
    print "$heightmap"
    PrintTable(sources.HeightNames)
    return sources, parameters
end

---Creates the Details render target and sets its layout, mappings, and shader constants.
---@param sources ss.InkTypeAtlasSources
---@param parameters number[][][]
local function SetupDetailAtlas(sources, parameters)
    -- Calculating detail texture layout
    local gridColumns = math.ceil(math.sqrt(#sources.DetailTextures))
    local detailSize, rtSize = 0, 0
    for _, texture in ipairs(sources.DetailTextures) do
        detailSize = math.max(detailSize, texture:Width(), texture:Height())
    end
    if #sources.DetailTextures > 0 then
        detailSize = math.min(detailSize, math.floor((16384 - #parameters[1]) / gridColumns) - MARGIN)
        rtSize = gridColumns * (detailSize + MARGIN)
    end

    local dataWidth, dataHeight = math.max(rtSize, #parameters), rtSize + #parameters[1]
    ss.RenderTarget.DetailsImageSize = rtSize
    ss.RenderTarget.DetailGridColumns = gridColumns
    InkTypeRT.BaseTextureNames = sources.BaseNames
    InkTypeRT.DetailTextures = sources.DetailTextures
    InkTypeRT.DetailSlots = sources.DetailSlots
    ss.RenderTarget.StaticTextures.Details = GetRenderTargetEx(
        "splashsweps_details",
        dataWidth, dataHeight,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
        -- Detail images use bilinear filtering; numeric rows are read at texel centers.
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    local drawInk = Material "splashsweps/shaders/drawink"
    local inkWater = Material "splashsweps/shaders/inkmesh"
    drawInk:SetFloat("$c3_w", rtSize)
    inkWater:SetFloat("$c3_w", rtSize)
    inkWater:SetFloat("$c1_x", gridColumns)
    for material in pairs(ss.InkMeshMaterials) do
        material:SetFloat("$c3_w", rtSize)
        material:SetFloat("$c1_x", gridColumns)
    end
end

---Builds the albedo and height atlas and assigns base UV ranges.
---@param sources ss.InkTypeAtlasSources
local function BuildAlbedoAtlas(sources)
    local rt = ss.RenderTarget.StaticTextures.Albedo
    local packer = ss.MakeRectanglePacker(sources.BaseRects):packall()
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            cp:SetInt("$c0_x", 3)
            draw(sources.BaseNames[inktype.Index], rect, true, true)
            if sources.HeightNames[inktype.Index] then
                cp:SetInt("$c0_x", CHANNEL_INDEX[sources.HeightChannels[inktype.Index]] or 0)
                draw(sources.HeightNames[inktype.Index], rect, false, true)
            elseif not sources.BaseAlphaHeight[inktype.Index] then
                -- The alpha channel is used as the height map
                local tex = sources.TintNames[inktype.Index]
                if not HasAlphaChannel(tex) then
                    tex = "grey" -- $tinttexture with no alpha channel
                    cp:SetInt("$c0_x", 0)
                end
                draw(tex, rect, false, true)
            end

            -- Then store corresponding UV ranges passed to the shader
            inktype.BaseUV = {
                (rect.left   + HALF_MARGIN + 0.5) / rt:Width(),
                (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
            }
        end
    cam.End2D()
    render.PopRenderTarget()

    for _, inktype in ipairs(ss.InkTypes) do
        inktype.BaseUV = inktype.BaseUV
            or ss.InkTypes[sources.BaseCache[sources.BaseNames[inktype.Index]]].BaseUV
    end
end

---Builds the tint and shape atlas and assigns their UV ranges.
---@param sources ss.InkTypeAtlasSources
local function BuildTintAtlas(sources)
    local rt = ss.RenderTarget.StaticTextures.Tint
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        local packer = ss.MakeRectanglePacker(sources.TintRects):packall()
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            draw(sources.TintNames[inktype.Index], rect, true, false)
            inktype.TintUV = {
                (rect.left   + HALF_MARGIN + 0.5) / rt:Width(),
                (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
            }
        end

        -- Write shape atlas to the alpha channel
        packer = ss.MakeRectanglePacker(sources.ShapeRects):packall()
        for _, rect in ipairs(packer.rects) do
            local shape = rect.tag ---@type ss.InkShape
            cp:SetInt("$c0_x", CHANNEL_INDEX[shape.Channel] or 3)
            draw(shape.MaskTexture:StripExtension(), rect, false, true)
            shape.UV = {
                (rect.left   + HALF_MARGIN + 0.5) / rt:Width(),
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

---Builds the detail image grid and writes ink type data and average heights.
---@param detailTextures ITexture[]
---@param parameters number[][][]
local function BuildDetailsAtlas(detailTextures, parameters)
    local rt = ss.RenderTarget.StaticTextures.Details
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        WriteDetailCells(detailTextures)
        WriteInkTypeRows(parameters)
    cam.End2D()
    render.PopRenderTarget()
end

---Updates detail cells and ink type data.
---@param cells integer[] Detail cells
---@param inkTypes integer[] Ink type indices
function ss.UpdateInkTypesRT(cells, inkTypes)
    if #cells == 0 and #inkTypes == 0 then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(cells) do
        textures[slot] = InkTypeRT.DetailTextures[slot]
    end

    local parameters = {} ---@type table<integer, number[][]>
    for _, i in ipairs(inkTypes) do
        parameters[i] = ReadParameters(Material(ss.InkTypes[i].Identifier), InkTypeRT.DetailSlots[i])
    end

    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
    cam.Start2D()
        WriteDetailCells(textures)
        WriteInkTypeRows(parameters)
    cam.End2D()
    render.PopRenderTarget()
end

function ss.LoadInkTypesRT()
    local sources, parameters = ReadInkTypeSources()
    if #parameters == 0 then return end
    SetupDetailAtlas(sources, parameters)

    timer.Simple(0, function()
        BuildAlbedoAtlas(sources)
        BuildTintAtlas(sources)
        BuildDetailsAtlas(sources.DetailTextures, parameters)
    end)
end
