
---@class ss
local ss = SplashSWEPs
if not ss then return end

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }
local DETAIL_MODE = {
    MATERIAL = 0,
    NORMAL = 1,
    EMISSION = 2,
    COLOR = 3,
    NONE = 255,
}

-- Lua rows start at 1; the matching ID_* constants in inkmesh_common.hlsl start at 0.
local DATA_ROW = {
    COLOR_ALPHA = 1,
    TINT_GEOMETRYPAINT = 2,
    EDGE = 3,
    HEIGHT_MAXLAYERS = 4,
    MATERIAL_REFRACT = 5,
    MISC = 6,
    DETAIL_MAPPING = 7,
    OTHERS = 8,
    DETAIL_MODE = 9,
    DETAIL_STRENGTH = 10,
    DETAIL_ORIGIN = 11,
    DETAIL_SIZE = 12,
}

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

---@class ss.InkDetailTransfer
---@field texture ITexture
---@field normal boolean Whether transposition also exchanges RG.

---@param value number
---@return number
local function EncodeByte(value)
    return math.Round(math.Clamp(value, 0, 1) * 255) / 255
end

---@param turns number
---@return number
local function EncodeTurn(turns)
    return math.Round(turns * 256) % 256 / 255
end

---@param strength number
---@return number
local function EncodeDetailStrength(strength)
    return math.Round(math.Clamp(strength, 0, 2) * 127) / 255
end

---@param x integer
---@param y integer
---@return number[]
local function EncodeAtlasXY(x, y)
    assert(x >= 0 and x <= 65535 and y >= 0 and y <= 65535, "Detail atlas range exceeds uint16")
    return {
        x % 256 / 255,
        math.floor(x / 256) / 255,
        y % 256 / 255,
        math.floor(y / 256) / 255,
    }
end

---@param mat IMaterial
---@param detailMode integer
---@param detailRect ss.Rectangle?
---@return number[][]
local function EncodeMaterialParameters(mat, detailMode, detailRect)
    local scaleX, scaleY = 1, 1
    local rotationTurns, translationU, translationV = 0, 0, 0
    local transform = mat:GetMatrix "$detailtexturetransform"
    if transform then
        local scale = transform:GetScale()
        local translation = transform:GetTranslation()
        scaleX, scaleY = scale.x, scale.y
        rotationTurns = transform:GetAngles().y / 360
        translationU, translationV = translation.x, translation.y
    end
    local period = math.Clamp(mat:GetFloat "$detailperiod" or 512, 16, 4096)
    local strengthX, strengthY, strengthZ, strengthW = 1, 1, 1, 1
    if mat:GetVector "$detailblendscale" then
        strengthX, strengthY, strengthZ, strengthW = mat:GetVector4D "$detailblendscale"
    end

    local detailOrigin = { 0, 0, 0, 0 }
    local detailSize = { 0, 0, 0, 0 }
    if detailRect then
        detailOrigin = EncodeAtlasXY(detailRect.left + HALF_MARGIN, detailRect.bottom + HALF_MARGIN)
        detailSize = EncodeAtlasXY(detailRect.width - MARGIN, detailRect.height - MARGIN)
    end

    local color = mat:GetVector "$color" or ss.vector_one
    local tintColor = mat:GetVector "$tintcolor" or ss.vector_one
    local edgeColor = mat:GetVector "$edgecolor" or ss.vector_one
    return {
        [DATA_ROW.COLOR_ALPHA] = {
            color.x,
            color.y,
            color.z,
            mat:GetFloat "$alpha" or 1,
        },
        [DATA_ROW.TINT_GEOMETRYPAINT] = {
            tintColor.x,
            tintColor.y,
            tintColor.z,
            mat:GetFloat "$geometrypaintbias" or 0,
        },
        [DATA_ROW.EDGE] = {
            edgeColor.x,
            edgeColor.y,
            edgeColor.z,
            mat:GetFloat "$edgewidth" or 1,
        },
        [DATA_ROW.HEIGHT_MAXLAYERS] = {
            (mat:GetInt "$maxlayers" or 1) / 255,
            mat:GetFloat "$maxheight" or 1,
            math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
            mat:GetFloat "$heightbaseline" or -1,
        },
        [DATA_ROW.MATERIAL_REFRACT] = {
            mat:GetFloat "$metallic" or 0,
            mat:GetFloat "$roughness" or 0,
            mat:GetFloat "$specularscale" or 1,
            mat:GetFloat "$refractscale" or 1,
        },
        [DATA_ROW.MISC] = {
            mat:GetFloat "$erase" or 0,
            mat:GetFloat "$flatten" or 0,
            mat:GetFloat "$viscosity" or 1,
            (mat:GetInt "$nodig" or 0) * 0.5 + (mat:GetInt "$heightonly" or 0) * 0.125,
        },
        [DATA_ROW.DETAIL_MAPPING] = {
            EncodeByte(math.Remap(scaleX, 0.5, 2, 0, 1)),
            EncodeByte(math.Remap(scaleY, 0.5, 2, 0, 1)),
            EncodeTurn(rotationTurns),
            EncodeByte(math.log(period / 16, 2) / 8),
        },
        [DATA_ROW.OTHERS] = {
            mat:GetFloat "$edgehardness" or 0,
            mat:GetFloat "$miscibility" or 0,
            mat:GetFloat "$mixturetag" or 0,
            mat:GetInt "$developer" or 0,
        },
        [DATA_ROW.DETAIL_MODE] = {
            EncodeTurn(translationU),
            EncodeTurn(translationV),
            detailMode / 255,
            mat:GetFloat "$bumpblendfactor" or 1,
        },
        [DATA_ROW.DETAIL_STRENGTH] = {
            EncodeDetailStrength(strengthX),
            EncodeDetailStrength(strengthY),
            EncodeDetailStrength(strengthZ),
            EncodeDetailStrength(strengthW),
        },
        [DATA_ROW.DETAIL_ORIGIN] = detailOrigin,
        [DATA_ROW.DETAIL_SIZE] = detailSize,
    }
end

---Pixel boundaries are offset by half a pixel: copy VS only applies cViewProj,
---and does not itself compensate for D3D9's integer pixel sample positions.
---@param x number
---@param y number
---@param width number
---@param height number
---@param u0 number
---@param v0 number
---@param u1 number
---@param v1 number
---@param tint number[]? Numeric data for the generic copy shader, when needed.
local function WriteQuad(x, y, width, height, u0, v0, u1, v1, tint)
    for corner = 0, 3 do
        local right = corner >= 2
        local bottom = corner == 1 or corner == 2
        mesh.Position(x + (right and width or 0) - 0.5, y + (bottom and height or 0) - 0.5, 0)
        mesh.TexCoord(0, right and u1 or u0, bottom and v1 or v0)
        if tint then mesh.TexCoord(1, unpack(tint)) end
        mesh.AdvanceVertex()
    end
end

---@param inkIndex integer
---@param rowIndex integer
---@param imageHeight integer
---@param values number[]
local function WriteParameterPixel(inkIndex, rowIndex, imageHeight, values)
    WriteQuad(inkIndex - 1, imageHeight + rowIndex - 1, 1, 1, 0.5, 0.5, 0.5, 0.5, values)
end

function ss.LoadInkTypesRT()
    local materials          = {} ---@type IMaterial[]
    local detailModes        = {} ---@type integer[]
    local baseAlphaHeight    = {} ---@type boolean[]
    local baseTextureNames   = {} ---@type string[]
    local baseTextureCache   = {} ---@type table<string, integer>
    local baseTextureRects   = {} ---@type ss.Rectangle[]
    local tintTextureNames   = {} ---@type string[]
    local tintTextureCache   = {} ---@type table<string, integer>
    local tintTextureRects   = {} ---@type ss.Rectangle[]
    local detailTextureKeys  = {} ---@type string[]
    local detailTextureCache = {} ---@type table<string, ss.Rectangle>
    local detailTextureRects = {} ---@type ss.Rectangle[]
    local heightTextureNames = {} ---@type string[]
    local heightChannel      = {} ---@type string[]
    local parameters         = {} ---@type number[][][]
    local copyMaterial = Material "splashsweps/shaders/copy"
    copyMaterial:SetTexture("$basetexture", "color/black")
    local black = copyMaterial:GetTexture "$basetexture"
    copyMaterial:SetTexture("$basetexture", "color/white")
    local white = copyMaterial:GetTexture "$basetexture"
    local detailCopyMaterial = Material "splashsweps/shaders/copydetail"
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        assert(mat and not mat:IsError(), "One of ink type material is invalid!")
        materials[i] = mat

        copyMaterial:SetTexture("$basetexture", mat:GetString "$basetexture" or "???")
        local base = copyMaterial:GetTexture "$basetexture"
        if not base then
            ErrorNoHalt(string.format(
                "SplashSWEPs: $basetexture seems invalid for ink type '%s'\n",
                inktype.Identifier))
            base = white
        end
        baseTextureNames[i] = base:GetName()
        if not baseTextureCache[base:GetName()] then
            baseTextureCache[base:GetName()] = i
            baseTextureRects[#baseTextureRects + 1] = ss.MakeRectangle(
                base:Width() + MARGIN, base:Height() + MARGIN, 0, 0, inktype)
        end

        copyMaterial:SetTexture("$basetexture", mat:GetString "$tinttexture" or "???")
        local tint = copyMaterial:GetTexture "$basetexture"
        if not tint then
            local alpha = mat:GetFloat "$alpha" or 1
            local tintcolor = mat:GetVector "$tintcolor" or ss.vector_one
            local translucent = alpha < 1 or not tintcolor:IsEqualTol(ss.vector_one, ss.eps)
            tint = translucent and white or black
        end
        tintTextureNames[i] = tint:GetName()
        if not tintTextureCache[tint:GetName()] then
            tintTextureCache[tint:GetName()] = i
            tintTextureRects[#tintTextureRects + 1] = ss.MakeRectangle(
                tint:Width() + MARGIN, tint:Height() + MARGIN, 0, 0, inktype)
        end

        local detailMode = math.Clamp(
            mat:GetInt "$detailblendmode" or DETAIL_MODE.MATERIAL,
            DETAIL_MODE.MATERIAL, DETAIL_MODE.COLOR)
        local detailPath = mat:GetString "$detail"
        if detailPath and detailPath ~= "" then
            copyMaterial:SetTexture("$basetexture", detailPath)
            local detail = copyMaterial:GetTexture "$basetexture"
            if detail and not detail:IsError() and not detail:IsErrorTexture() then
                local normal = detailMode == DETAIL_MODE.MATERIAL or detailMode == DETAIL_MODE.NORMAL
                local key = detail:GetName() .. (normal and ":normal" or ":color")
                detailTextureKeys[i] = key
                if not detailTextureCache[key] then
                    local tag = { texture = detail, normal = normal } ---@type ss.InkDetailTransfer
                    local rect = ss.MakeRectangle(detail:Width() + MARGIN, detail:Height() + MARGIN, 0, 0, tag)
                    detailTextureCache[key] = rect
                    detailTextureRects[#detailTextureRects + 1] = rect
                end
            end
        end
        detailModes[i] = detailTextureKeys[i] and detailMode or DETAIL_MODE.NONE

        copyMaterial:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = copyMaterial:GetTexture "$basetexture"
        heightTextureNames[i] = height and height:GetName()
        heightChannel[i]      = mat:GetString "$heightchannel" or "R"

        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        baseAlphaHeight[i] = basealphaheightmap > 0 and HasAlphaChannel(baseTextureNames[i]) or nil
    end

    local shapeRects = {} ---@type ss.Rectangle[]
    for i, shape in ipairs(ss.InkShapes) do
        shapeRects[i] = ss.MakeRectangle(
            shape.Grid.Width + MARGIN, shape.Grid.Height + MARGIN, 0, 0, shape)
    end

    print "$basetexture"
    PrintTable(baseTextureNames)
    print "$tinttexture"
    PrintTable(tintTextureNames)
    print "$detail"
    PrintTable(detailTextureKeys)
    print "$heightmap"
    PrintTable(heightTextureNames)
    if #materials == 0 then return end

    if #detailTextureRects > 0 then
        ss.MakeRectanglePacker(detailTextureRects):packall()
    end
    for i, mat in ipairs(materials) do
        local detailRect = detailTextureCache[detailTextureKeys[i]]
        parameters[i] = EncodeMaterialParameters(mat, detailModes[i], detailRect)
    end

    -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
    -- Detail images use bilinear filtering; numeric rows are read at texel centers.
    local rtWidth = ss.RenderTarget.StaticTextures.Albedo:Width()
    local rtHeight = ss.RenderTarget.StaticTextures.Albedo:Height()
    ss.RenderTarget.StaticTextures.Details = GetRenderTargetEx(
        "splashsweps_details",
        math.max(rtWidth, #parameters), rtHeight + #parameters[1],
        RT_SIZE_NO_CHANGE,
        MATERIAL_RT_DEPTH_NONE,
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    Material "splashsweps/shaders/drawink" :SetFloat("$c3_w", rtHeight)

    ---@param tex ITexture|string
    ---@param rect ss.Rectangle
    ---@param drawcolor boolean
    ---@param drawalpha boolean
    local function draw(tex, rect, drawcolor, drawalpha)
        copyMaterial:SetTexture("$basetexture", tex)
        copyMaterial:SetInt("$c0_y", 0)
        render.SetMaterial(copyMaterial)
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

    timer.Simple(0, function()
        -- Packing albedo textures of all paint types
        local rt = ss.RenderTarget.StaticTextures.Albedo
        local packer = ss.MakeRectanglePacker(baseTextureRects):packall()
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            copyMaterial:SetInt("$c0_x", 3)
            draw(baseTextureNames[inktype.Index], rect, true, true)
            if heightTextureNames[inktype.Index] then
                copyMaterial:SetInt("$c0_x", CHANNEL_INDEX[heightChannel[inktype.Index]] or 0)
                draw(heightTextureNames[inktype.Index], rect, false, true)
            elseif not baseAlphaHeight[inktype.Index] then
                -- The alpha channel is used as the height map
                local tex = tintTextureNames[inktype.Index]
                if not HasAlphaChannel(tex) then
                    tex = "grey" -- $tinttexture with no alpha channel
                    copyMaterial:SetInt("$c0_x", 0)
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

        -- Packing detail textures of all paint types
        rt = ss.RenderTarget.StaticTextures.Details
        for _, rect in ipairs(detailTextureRects) do
            assert(rect.right <= rt:Width() and rect.top <= rtHeight, "Detail atlas overflow")
        end
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            for _, rect in ipairs(detailTextureRects) do
                local tag = rect.tag ---@type ss.InkDetailTransfer
                local width, height = rect.width - MARGIN, rect.height - MARGIN
                local transpose = width ~= tag.texture:Width() or height ~= tag.texture:Height()
                detailCopyMaterial:SetTexture("$basetexture", tag.texture)
                detailCopyMaterial:SetInt("$c0_x", transpose and 1 or 0)
                detailCopyMaterial:SetInt("$c0_y", tag.normal and 1 or 0)
                render.SetMaterial(detailCopyMaterial)
                mesh.Begin(MATERIAL_QUADS, 1)
                -- The extended UV rectangle covers one texel on every edge/corner.
                -- At pixel centers frac maps that border to opposite source texels.
                WriteQuad(rect.left, rect.bottom, rect.width, rect.height,
                    -1 / width, -1 / height, 1 + 1 / width, 1 + 1 / height)
                mesh.End()
            end
            render.OverrideBlend(false)
        cam.End2D()
        render.PopRenderTarget()

        -- Packing tint textures of all paint types
        rt = ss.RenderTarget.StaticTextures.Tint
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
            packer = ss.MakeRectanglePacker(tintTextureRects):packall()
            for _, rect in ipairs(packer.rects) do
                local inktype = rect.tag ---@type ss.InkType
                draw(tintTextureNames[inktype.Index], rect, true, false)
                inktype.TintUV = {
                    (rect.left   + HALF_MARGIN + 0.5) / rt:Width(),
                    (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                    (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                    (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
                }
            end

            -- Write shape atlas to the alpha channel
            packer = ss.MakeRectanglePacker(shapeRects):packall()
            for _, rect in ipairs(packer.rects) do
                local shape = rect.tag ---@type ss.InkShape
                copyMaterial:SetInt("$c0_x", CHANNEL_INDEX[shape.Channel] or 3)
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

        -- Writes material parameters to data texture so that they can be read in the shader
        rt = ss.RenderTarget.StaticTextures.Details
        render.PushRenderTarget(rt)
        cam.Start2D()
            copyMaterial:SetTexture("$basetexture", white)
            copyMaterial:SetInt("$c0_x", 3)
            copyMaterial:SetInt("$c0_y", 1)
            render.SetMaterial(copyMaterial)
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            -- Avoid driver-dependent point rasterization; each datum is a 1x1 quad.
            local rows = #parameters[1]
            local count = rows * #parameters
            local batchSize = math.floor(32768 / 4)
            for first = 0, count - 1, batchSize do
                local last = math.min(first + batchSize, count) - 1
                mesh.Begin(MATERIAL_QUADS, last - first + 1)
                for index = first, last do
                    local inkIndex = math.floor(index / rows) + 1
                    local rowIndex = index % rows + 1
                    WriteParameterPixel(inkIndex, rowIndex, rtHeight, parameters[inkIndex][rowIndex])
                end
                mesh.End()
            end
            render.OverrideBlend(false)

            -- Writes the average height of each ink type
            for i, inktype in ipairs(ss.InkTypes) do
                local heightbaseline = parameters[i][DATA_ROW.HEIGHT_MAXLAYERS][4]
                if heightbaseline < 0 then
                    copyMaterial:SetTexture("$basetexture", baseTextureNames[inktype.Index])
                    copyMaterial:SetInt("$c0_y", 0)
                    render.SetMaterial(copyMaterial)
                    render.OverrideBlend(true, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                    mesh.Begin(MATERIAL_QUADS, 1)
                    WriteQuad(i - 1, rtHeight + DATA_ROW.HEIGHT_MAXLAYERS - 1, 1, 1, 0, 0, 1, 1, { 1, 1, 1, 1 })
                    mesh.End()
                    render.OverrideBlend(false)
                end
            end
        cam.End2D()
        render.PopRenderTarget()

        -- Make sure all ink types have their own UV ranges (which may be shared)
        for _, inktype in ipairs(ss.InkTypes) do
            inktype.BaseUV = inktype.BaseUV
                or ss.InkTypes[baseTextureCache[baseTextureNames[inktype.Index]]].BaseUV
            inktype.TintUV = inktype.TintUV
                or ss.InkTypes[tintTextureCache[tintTextureNames[inktype.Index]]].TintUV
        end
    end)
end
