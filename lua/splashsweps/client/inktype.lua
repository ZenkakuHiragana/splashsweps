
---@class ss
local ss = SplashSWEPs
if not ss then return end

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }

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
---@field texture ITexture Exact source retained through packing.
---@field normal boolean Whether transposition also exchanges RG.

---@param value number
---@return number
local function EncodeTurn(value)
    return math.Round(value * 256) % 256 / 255
end

---@param mat IMaterial
---@return number[] mapping
---@return number[] translation
---@return number[] strength
local function DetailSettings(mat)
    local sx, sy, rotation, tx, ty = 1, 1, 0, 0, 0
    local transform = mat:GetMatrix "$detailtexturetransform"
    if transform then
        -- The supported transform is positive XY scale and Z-axis rotation.
        -- Translation already includes the rotation-center adjustment.
        local scale = transform:GetScale()
        local translation = transform:GetTranslation()
        sx, sy = scale.x, scale.y
        rotation = transform:GetAngles().y / 360
        tx, ty = translation.x, translation.y
    end
    local period = math.Clamp(mat:GetFloat "$detailperiod" or 512, 16, 4096)
    local x, y, z, w = 1, 1, 1, 1
    if mat:GetVector "$detailblendscale" then
        x, y, z, w = mat:GetVector4D "$detailblendscale"
    end
    local strength = { x, y, z, w }
    for i = 1, 4 do
        strength[i] = math.Round(math.Clamp(strength[i], 0, 2) * 127) / 255
    end
    return {
        math.Round((math.Clamp(sx, 0.5, 2) - 0.5) / 1.5 * 255) / 255,
        math.Round((math.Clamp(sy, 0.5, 2) - 0.5) / 1.5 * 255) / 255,
        EncodeTurn(rotation),
        math.Round(math.log(period / 16) / math.log(2) / 8 * 255) / 255,
    }, { EncodeTurn(tx), EncodeTurn(ty) }, strength
end

---@param x integer
---@param y integer
---@return number[]
local function EncodeUInt16Pair(x, y)
    assert(x >= 0 and x <= 65535 and y >= 0 and y <= 65535, "Detail atlas range exceeds uint16")
    return { x % 256 / 255, math.floor(x / 256) / 255,
        y % 256 / 255, math.floor(y / 256) / 255 }
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

function ss.LoadInkTypesRT()
    local baseAlphaHeight    = {} ---@type boolean[]
    local baseTextureNames   = {} ---@type string[]
    local baseTextureCache   = {} ---@type table<string, integer>
    local baseTextureRects   = {} ---@type ss.Rectangle[]
    local tintTextureNames   = {} ---@type string[]
    local tintTextureCache   = {} ---@type table<string, integer>
    local tintTextureRects   = {} ---@type ss.Rectangle[]
    local detailTextureNames = {} ---@type string[]
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
    local detailCopy = Material "splashsweps/shaders/inkdetail_copy"
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

        local detailMode = math.Clamp(mat:GetInt "$detailblendmode" or 0, 0, 3)
        local detailPath = mat:GetString "$detail"
        if detailPath and detailPath ~= "" then
            cp:SetTexture("$basetexture", detailPath)
            local detail = cp:GetTexture "$basetexture"
            if detail and not detail:IsError() and not detail:IsErrorTexture() then
                local normal = detailMode <= 1
                local key = detail:GetName() .. (normal and ":normal" or ":color")
                detailTextureNames[i] = key
                if not detailTextureCache[key] then
                    local tag = { texture = detail, normal = normal } ---@type ss.InkDetailTransfer
                    local rect = ss.MakeRectangle(detail:Width() + MARGIN, detail:Height() + MARGIN, 0, 0, tag)
                    detailTextureCache[key] = rect
                    detailTextureRects[#detailTextureRects + 1] = rect
                end
            end
        end
        if not detailTextureNames[i] then detailMode = 255 end
        local mapping, translation, strength = DetailSettings(mat)

        cp:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = cp:GetTexture "$basetexture"
        heightTextureNames[i] = height and height:GetName()
        heightChannel[i]      = mat:GetString "$heightchannel" or "R"

        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        baseAlphaHeight[i] = basealphaheightmap > 0 and HasAlphaChannel(baseTextureNames[i]) or nil

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
                unpack(mapping)
            }, {
                mat:GetFloat "$edgehardness"    or 0, mat:GetFloat "$miscibility"      or 0,
                mat:GetFloat "$mixturetag"      or 0, mat:GetInt   "$developer"        or 0,
            }, {
                translation[1], translation[2], detailMode / 255, mat:GetFloat "$bumpblendfactor" or 1,
            }, strength,
            { 0, 0, 0, 0 }, -- Interior origin, uint16 little-endian XY (row 10).
            { 0, 0, 0, 0 }, -- Interior size, uint16 little-endian XY (row 11).
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
    PrintTable(detailTextureNames)
    print "$heightmap"
    PrintTable(heightTextureNames)
    if #parameters == 0 then return end

    -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
    -- No POINTSAMPLE: detail images require bilinear filtering. Numeric rows
    -- are fetched at exact texel centers, so their byte codes remain separate.
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
        if #detailTextureRects > 0 then
            ss.MakeRectanglePacker(detailTextureRects):packall()
        end
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
                detailCopy:SetTexture("$basetexture", tag.texture)
                detailCopy:SetInt("$c0_x", transpose and 1 or 0)
                detailCopy:SetInt("$c0_y", tag.normal and 1 or 0)
                render.SetMaterial(detailCopy)
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
        for i in ipairs(parameters) do
            local rect = detailTextureCache[detailTextureNames[i]]
            if rect then
                parameters[i][11] = EncodeUInt16Pair(rect.left + HALF_MARGIN, rect.bottom + HALF_MARGIN)
                parameters[i][12] = EncodeUInt16Pair(rect.width - MARGIN, rect.height - MARGIN)
            end
        end

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
            render.SetMaterial(cp)
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            -- Avoid driver-dependent point rasterization; each datum is a 1x1 quad.
            local rows = #parameters[1]
            local count = rows * #parameters
            local batchSize = math.floor(32768 / 4)
            for first = 0, count - 1, batchSize do
                local last = math.min(first + batchSize, count) - 1
                mesh.Begin(MATERIAL_QUADS, last - first + 1)
                for index = first, last do
                    local i, j = math.floor(index / rows) + 1, index % rows + 1
                    WriteQuad(i - 1, rtHeight + j - 1, 1, 1, 0.5, 0.5, 0.5, 0.5, parameters[i][j])
                end
                mesh.End()
            end
            render.OverrideBlend(false)

            -- Writes the average height of each ink type
            for i, inktype in ipairs(ss.InkTypes) do
                local heightbaseline = parameters[i][4][4]
                if heightbaseline < 0 then
                    cp:SetTexture("$basetexture", baseTextureNames[inktype.Index])
                    cp:SetInt("$c0_y", 0)
                    render.SetMaterial(cp)
                    render.OverrideBlend(true, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                    mesh.Begin(MATERIAL_QUADS, 1)
                    WriteQuad(i - 1, rtHeight + 3, 1, 1, 0, 0, 1, 1, { 1, 1, 1, 1 })
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
