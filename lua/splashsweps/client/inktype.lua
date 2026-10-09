
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

function ss.LoadInkTypesRT()
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
    local cp = Material "splashsweps/shaders/copy"
    cp:SetTexture("$basetexture", "color/black")
    local black = cp:GetTexture "$basetexture"
    cp:SetTexture("$basetexture", "color/white")
    local white = cp:GetTexture "$basetexture"
    local detailCopyMaterial = Material "splashsweps/shaders/copydetail"
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        assert(mat and not mat:IsError(), "One of ink type material is invalid!")

        cp:SetTexture("$basetexture", mat:GetString "$basetexture" or "???")
        local base = cp:GetTexture "$basetexture"
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

        cp:SetTexture("$basetexture", mat:GetString "$tinttexture" or "???")
        local tint = cp:GetTexture "$basetexture"
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
            cp:SetTexture("$basetexture", detailPath)
            local detail = cp:GetTexture "$basetexture"
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
        detailMode = detailTextureKeys[i] and detailMode or DETAIL_MODE.NONE

        cp:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = cp:GetTexture "$basetexture"
        heightTextureNames[i] = height and height:GetName()
        heightChannel[i]      = mat:GetString "$heightchannel" or "R"

        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        baseAlphaHeight[i] = basealphaheightmap > 0 and HasAlphaChannel(baseTextureNames[i]) or nil

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

        local color = mat:GetVector "$color" or ss.vector_one
        local tintcolor = mat:GetVector "$tintcolor" or ss.vector_one
        local edgecolor = mat:GetVector "$edgecolor" or ss.vector_one
        parameters[i] = {
            { color.x,     color.y,     color.z,     mat:GetFloat "$alpha"             or 1 },
            { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
            { edgecolor.x, edgecolor.y, edgecolor.z, mat:GetFloat "$edgewidth"         or 1 },
            {
                (mat:GetInt "$maxlayers" or 1) / 255,
                mat:GetFloat "$maxheight" or 1,
                math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
                mat:GetFloat "$heightbaseline" or -1,
            }, {
                mat:GetFloat "$metallic"        or 0, mat:GetFloat "$roughness"        or 0,
                mat:GetFloat "$specularscale"   or 1, mat:GetFloat "$refractscale"     or 1,
            }, {
                mat:GetFloat "$erase"           or 0,
                mat:GetFloat "$flatten"         or 0,
                mat:GetFloat "$viscosity"       or 1,
                (mat:GetInt "$nodig"      or 0) * 0.5 +
                (mat:GetInt "$heightonly" or 0) * 0.125,
            }, {
                EncodeByte(math.Remap(scaleX, 0.5, 2, 0, 1)),
                EncodeByte(math.Remap(scaleY, 0.5, 2, 0, 1)),
                EncodeTurn(rotationTurns),
                EncodeByte(math.log(period / 16, 2) / 8),
            }, {
                mat:GetFloat "$edgehardness"    or 0, mat:GetFloat "$miscibility"      or 0,
                mat:GetFloat "$mixturetag"      or 0, mat:GetInt   "$developer"        or 0,
            }, {
                EncodeTurn(translationU), EncodeTurn(translationV),
                detailMode / 255, mat:GetFloat "$bumpblendfactor" or 1,
            }, {
                EncodeDetailStrength(strengthX), EncodeDetailStrength(strengthY),
                EncodeDetailStrength(strengthZ), EncodeDetailStrength(strengthW),
            },
            -- Atlas origin and size are filled after packing; see ID_DETAIL_* in inkmesh_common.hlsl.
            { 0, 0, 0, 0 },
            { 0, 0, 0, 0 },
        }
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
    if #parameters == 0 then return end

    if #detailTextureRects > 0 then
        ss.MakeRectanglePacker(detailTextureRects):packall()
    end
    for i, param in ipairs(parameters) do
        local rect = detailTextureCache[detailTextureKeys[i]]
        if rect then
            param[11] = EncodeAtlasXY(rect.left + HALF_MARGIN, rect.bottom + HALF_MARGIN)
            param[12] = EncodeAtlasXY(rect.width - MARGIN, rect.height - MARGIN)
        end
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

    timer.Simple(0, function()
        -- Packing albedo textures of all paint types
        local rt = ss.RenderTarget.StaticTextures.Albedo
        local packer = ss.MakeRectanglePacker(baseTextureRects):packall()
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            cp:SetInt("$c0_x", 3)
            draw(baseTextureNames[inktype.Index], rect, true, true)
            if heightTextureNames[inktype.Index] then
                cp:SetInt("$c0_x", CHANNEL_INDEX[heightChannel[inktype.Index]] or 0)
                draw(heightTextureNames[inktype.Index], rect, false, true)
            elseif not baseAlphaHeight[inktype.Index] then
                -- The alpha channel is used as the height map
                local tex = tintTextureNames[inktype.Index]
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
                for corner = 0, 3 do
                    local right = corner >= 2
                    local bottom = corner == 1 or corner == 2
                    -- copydetail's VS does not compensate for D3D9's half-pixel offset.
                    mesh.Position(rect.left + (right and rect.width or 0) - 0.5,
                        rect.bottom + (bottom and rect.height or 0) - 0.5, 0)
                    mesh.TexCoord(0, right and 1 + 1 / width or -1 / width,
                        bottom and 1 + 1 / height or -1 / height)
                    mesh.AdvanceVertex()
                end
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

        -- Writes material parameters to data texture so that they can be read in the shader
        rt = ss.RenderTarget.StaticTextures.Details
        render.PushRenderTarget(rt)
        cam.Start2D()
            cp:SetTexture("$basetexture", white)
            cp:SetInt("$c0_x", 3)
            cp:SetInt("$c0_y", 1)
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            mesh.Begin(MATERIAL_POINTS, #parameters[1] * #parameters)
            for i, param in ipairs(parameters) do
                for j, float4 in ipairs(param) do
                    mesh.Position(i, j + rtHeight, 0)
                    mesh.TexCoord(0, 0.5, 0.5)
                    mesh.TexCoord(1, unpack(float4))
                    mesh.AdvanceVertex()
                end
            end
            mesh.End()
            render.OverrideBlend(false)

            -- Writes the average height of each ink type
            for i, inktype in ipairs(ss.InkTypes) do
                local heightbaseline = parameters[i][4][4]
                if heightbaseline < 0 then
                    draw(baseTextureNames[inktype.Index], ss.MakeRectangle(1, 1, i - 1, 4 - 1 + rtHeight), false, true)
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
