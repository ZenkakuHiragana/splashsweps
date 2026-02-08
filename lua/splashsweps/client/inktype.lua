
---@class ss
local ss = SplashSWEPs
if not ss then return end

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
function ss.LoadInkTypesRT()
    local baseTextureCache   = {} ---@type table<string, integer>
    local tintTextureCache   = {} ---@type table<string, integer>
    local detailTextureCache = {} ---@type table<string, integer>
    local baseTextureRects   = {} ---@type ss.Rectangle[]
    local tintTextureRects   = {} ---@type ss.Rectangle[]
    local detailTextureRects = {} ---@type ss.Rectangle[]
    local parameters         = {} ---@type number[][][]
    local cp = Material "splashsweps/shaders/copy"
    cp:SetTexture("$basetexture", "null")
    local null = cp:GetTexture "$basetexture"
    cp:SetTexture("$basetexture", "white")
    local white = cp:GetTexture "$basetexture"
    cp:SetTexture("$basetexture", "null-bumpmap")
    local null_bumpmap = cp:GetTexture "$basetexture"
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        assert(mat and not mat:IsError(), "One of ink type material is invalid!")
        local base = mat:GetTexture "$basetexture" or white
        if not baseTextureCache[base:GetName()] then
            baseTextureCache[base:GetName()] = i
            baseTextureRects[#baseTextureRects + 1] = ss.MakeRectangle(
                base:Width() + MARGIN, base:Height() + MARGIN, 0, 0, inktype)
        end
        cp:SetTexture("$basetexture", mat:GetString "$tinttexture" or "null")
        local tint = cp:GetTexture "$basetexture" or null
        if not tintTextureCache[tint:GetName()] then
            tintTextureCache[tint:GetName()] = i
            tintTextureRects[#tintTextureRects + 1] = ss.MakeRectangle(
                tint:Width() + MARGIN, tint:Height() + MARGIN, 0, 0, inktype)
        end
        local detail = mat:GetTexture "$detail" or null_bumpmap
        if not detailTextureCache[detail:GetName()] then
            detailTextureCache[detail:GetName()] = i
            detailTextureRects[#detailTextureRects + 1] = ss.MakeRectangle(
                detail:Width() + MARGIN, detail:Height() + MARGIN, 0, 0, inktype)
        end

        local color = mat:GetVector "$color" or ss.vector_one
        local tintcolor = mat:GetVector "$tintcolor" or ss.vector_one
        local edgecolor = mat:GetVector "$edgecolor" or ss.vector_one
        parameters[i] = {
            { color.x,     color.y,     color.z,     mat:GetFloat "$alpha"             or 1 },
            { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
            { edgecolor.x, edgecolor.y, edgecolor.z, mat:GetFloat "$edgewidth"         or 1 },
            {
                mat:GetFloat "$maxheight"  or  1,
                mat:GetFloat "$meanheight" or -1,
                math.Remap(mat:GetFloat "$heightmapscale" or 1, -2, 2, 0, 1),
                (mat:GetInt "$maxlayers" or 1) / 255,
            }, {
                mat:GetFloat "$metallic"        or 0, mat:GetFloat "$roughness"        or 0,
                mat:GetFloat "$specularscale"   or 1, mat:GetFloat "$refractscale"     or 1,
            }, {
                mat:GetFloat "$erase"           or 0, mat:GetFloat "$flatten"          or 0,
                mat:GetFloat "$viscosity"       or 1, mat:GetInt   "$nodig"            or 0,
            }, {
                mat:GetInt   "$detailblendmode" or 0, mat:GetFloat "$detailblendscale" or 1,
                mat:GetFloat "$detailbumpscale" or 1, mat:GetFloat "$bumpblendfactor"  or 1,
            }, {
                mat:GetFloat "$edgehardness"    or 0, mat:GetFloat "$miscibility"      or 0,
                mat:GetFloat "$mixturetag"      or 0, mat:GetInt   "$developer"        or 0,
            },
        }

        inktype.BaseAlphaHeightmap = (mat:GetInt "$basealphaheightmap" or 0) > 0 or nil
    end

    local shapeRects = {} ---@type ss.Rectangle[]
    for i, shape in ipairs(ss.InkShapes) do
        shapeRects[i] = ss.MakeRectangle(
            shape.Grid.Width + MARGIN, shape.Grid.Height + MARGIN, 0, 0, shape)
    end

    -- 256 + 512 + 1024 + 32768 + 8388608
    -- = POINTSAMPLE | NOMIP | NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER
    -- GMOD can't change the size of render target without restart
    -- so I reserve twice the number of ink types.
    ss.RenderTarget.StaticTextures.Params = GetRenderTargetEx(
        "splashsweps_params",
        #parameters * 2, #parameters[1],
        RT_SIZE_NO_CHANGE,
        MATERIAL_RT_DEPTH_NONE,
        1 + 256 + 512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)

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
        cp:SetInt("$c0_x", 3)
        for _, rect in ipairs(packer.rects) do
            local inktype = rect.tag ---@type ss.InkType
            draw(inktype.BaseTexture, rect, true, true)
            if not inktype.BaseAlphaHeightmap then
                -- The alpha channel is used as the height map
                draw(inktype.TintTexture, rect, false, true)
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
        packer = ss.MakeRectanglePacker(detailTextureRects):packall()
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
            for _, rect in ipairs(packer.rects) do
                local inktype = rect.tag ---@type ss.InkType
                draw(inktype.DetailTexture, rect, true, true)
                inktype.DetailUV = {
                    (rect.left   + HALF_MARGIN + 0.5) / rt:Width(),
                    (rect.bottom + HALF_MARGIN + 0.5) / rt:Height(),
                    (rect.right  - HALF_MARGIN - 0.5) / rt:Width(),
                    (rect.top    - HALF_MARGIN - 0.5) / rt:Height(),
                }
            end
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
                draw(inktype.TintTexture, rect, true, false)
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
                local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }
                cp:SetInt("$c0_x", CHANNEL_INDEX[shape.Channel])
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
        rt = ss.RenderTarget.StaticTextures.Params
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 0)
        cam.Start2D()
            cp:SetTexture("$basetexture", white)
            cp:SetInt("$c0_x", 3)
            cp:SetInt("$c0_y", 1)
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            mesh.Begin(MATERIAL_POINTS, #parameters[1] * #parameters)
            for i, param in ipairs(parameters) do
                for j, float4 in ipairs(param) do
                    mesh.Position(i, j, 0)
                    mesh.TexCoord(0, 0.5, 0.5)
                    mesh.TexCoord(1, unpack(float4))
                    mesh.AdvanceVertex()
                end
            end
            mesh.End()
            render.OverrideBlend(false)

            -- Writes the average height of each ink type
            for i, inktype in ipairs(ss.InkTypes) do
                local meanheight = parameters[i][4][2]
                if meanheight >= 0 then
                    draw(inktype.TintTexture, ss.MakeRectangle(1, 1, i, 4), false, true)
                end
            end
        cam.End2D()
        render.PopRenderTarget()

        -- Make sure all ink types have their own UV ranges (which may be shared)
        for _, inktype in ipairs(ss.InkTypes) do
            inktype.BaseUV = inktype.BaseUV
                or ss.InkTypes[baseTextureCache[inktype.BaseTexture]].BaseUV
            inktype.TintUV = inktype.TintUV
                or ss.InkTypes[tintTextureCache[inktype.TintTexture]].TintUV
            inktype.DetailUV = inktype.DetailUV
                or ss.InkTypes[detailTextureCache[inktype.DetailTexture]].DetailUV
        end
    end)
end
