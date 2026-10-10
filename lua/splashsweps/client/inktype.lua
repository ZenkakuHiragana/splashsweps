
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

function ss.LoadInkTypesRT()
    local baseAlphaHeight    = {} ---@type boolean[]
    local baseTextureNames   = {} ---@type string[]
    local baseTextureCache   = {} ---@type table<string, integer>
    local baseTextureRects   = {} ---@type ss.Rectangle[]
    local tintTextureNames   = {} ---@type string[]
    local tintTextureCache   = {} ---@type table<string, integer>
    local tintTextureRects   = {} ---@type ss.Rectangle[]
    local detailTextureNames = {} ---@type string[]
    local detailTextureCache = {} ---@type table<string, integer>
    local detailTextures     = {} ---@type ITexture[]
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

        local detailPath = mat:GetString "$detail"
        if detailPath and detailPath ~= "" then
            cp:SetTexture("$basetexture", detailPath)
            local detail = cp:GetTexture "$basetexture"
            local name = detail:GetName()
            detailTextureNames[i] = name
            if not detailTextureCache[name] then
                detailTextures[#detailTextures + 1] = detail
                detailTextureCache[name] = #detailTextures
            end
        end

        cp:SetTexture("$basetexture", mat:GetString "$heightmap" or "???")
        local height = cp:GetTexture "$basetexture"
        local basealphaheightmap = mat:GetInt "$basealphaheightmap" or 0
        heightTextureNames[i] = height and height:GetName()
        heightChannel[i]      = mat:GetString "$heightchannel" or "R"
        baseAlphaHeight[i]    = basealphaheightmap > 0 and HasAlphaChannel(baseTextureNames[i]) or nil

        local detailtexturetransform     = mat:GetMatrix "$detailtexturetransform" or Matrix()
        local detailtransformscale       = detailtexturetransform:GetScale()
        local detailtransformtranslation = detailtexturetransform:GetTranslation()
        local detailtransformrotation    = detailtexturetransform:GetAngles().yaw
        local detailperiod               = math.Clamp(mat:GetFloat "$detailperiod" or 512, 16, 4096)
        local detailblendscale           = { mat:GetVector4D "$detailblendscale" }
        local color                      = mat:GetVector "$color"     or ss.vector_one
        local tintcolor                  = mat:GetVector "$tintcolor" or ss.vector_one
        local edgecolor                  = mat:GetVector "$edgecolor" or ss.vector_one
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
                mat:GetFloat "$metallic"        or 0,
                mat:GetFloat "$roughness"       or 0,
                mat:GetFloat "$specularscale"   or 1,
                mat:GetFloat "$refractscale"    or 1,
            }, {
                mat:GetFloat "$erase"           or 0,
                mat:GetFloat "$flatten"         or 0,
                mat:GetFloat "$viscosity"       or 1,
                (mat:GetInt "$nodig"      or 0) * 0.5 +
                (mat:GetInt "$heightonly" or 0) * 0.125,
            }, {
                math.Remap(detailtransformscale.x, 0.5, 2, 0, 1),
                math.Remap(detailtransformscale.y, 0.5, 2, 0, 1),
                detailtransformrotation / 360,
                math.log(detailperiod / 16, 2) / 8,
            }, {
                mat:GetFloat "$edgehardness"    or 0,
                mat:GetFloat "$miscibility"     or 0,
                mat:GetFloat "$mixturetag"      or 0,
                mat:GetInt   "$developer"       or 0,
            }, {
                detailtransformtranslation.x,
                detailtransformtranslation.y,
                (mat:GetInt "$detailblendmode" or 255) / 255,
                mat:GetFloat "$bumpblendfactor" or 1,
            }, {
                math.Round(math.Clamp(detailblendscale[1], 0, 2) * 127) / 255,
                math.Round(math.Clamp(detailblendscale[2], 0, 2) * 127) / 255,
                math.Round(math.Clamp(detailblendscale[3], 0, 2) * 127) / 255,
                math.Round(math.Clamp(detailblendscale[4], 0, 2) * 127) / 255,
            },
            -- Grid coordinates and column count are filled after collecting the images.
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
    PrintTable(detailTextureNames)
    print "$heightmap"
    PrintTable(heightTextureNames)
    if #parameters == 0 then return end

    -- Calculating detail texture layout
    local gridColumns = math.ceil(math.sqrt(#detailTextures))
    local detailSize, rtSize = 0, 0
    for _, texture in ipairs(detailTextures) do
        detailSize = math.max(detailSize, texture:Width(), texture:Height())
    end
    if #detailTextures > 0 then
        detailSize = math.min(detailSize, math.floor((16384 - #parameters[1]) / gridColumns) - MARGIN)
        rtSize = gridColumns * (detailSize + MARGIN)
        for i, param in ipairs(parameters) do
            local slot = detailTextureCache[detailTextureNames[i]]
            if slot then
                param[11] = {
                    (slot - 1) % gridColumns / 255,
                    math.floor((slot - 1) / gridColumns) / 255,
                    gridColumns / 255,
                    0,
                }
            end
        end
    end

    -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
    -- Detail images use bilinear filtering; numeric rows are read at texel centers.
    local dataWidth, dataHeight = math.max(rtSize, #parameters), rtSize + #parameters[1]
    ss.RenderTarget.DetailsImageSize = rtSize
    ss.RenderTarget.StaticTextures.Details = GetRenderTargetEx(
        "splashsweps_details",
        dataWidth, dataHeight,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    local drawInk = Material "splashsweps/shaders/drawink"
    local inkWater = Material "splashsweps/shaders/inkmesh"
    drawInk:SetFloat("$c3_w", rtSize)
    inkWater:SetFloat("$c3_w", rtSize)
    for material in pairs(ss.InkMeshMaterials) do
        material:SetFloat("$c3_w", rtSize)
    end

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

        -- Copy detail images into equal-sized grid cells, preserving their orientation and channels.
        rt = ss.RenderTarget.StaticTextures.Details
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
            render.OverrideBlend(true,
                BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
                BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            surface.SetDrawColor(255, 255, 255, 255)
            for slot, texture in ipairs(detailTextures) do
                local cellSize = detailSize + MARGIN
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
            render.OverrideBlend(true,
                BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
                BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            mesh.Begin(MATERIAL_POINTS, #parameters[1] * #parameters)
            for i, param in ipairs(parameters) do
                for j, float4 in ipairs(param) do
                    mesh.Position(i, j + rtSize, 0)
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
                    draw(baseTextureNames[inktype.Index], ss.MakeRectangle(1, 1, i - 1, 4 - 1 + rtSize), false, true)
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
