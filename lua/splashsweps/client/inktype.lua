
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkTypeRT then
    ---@class ss.Locals.InkTypeRT
    ---@field BaseTextureNames string[] $basetexture of each ink type, which also provides its average height
    ---@field DetailTextures ITexture[] Detail image of each grid cell
    ---@field DetailSlots table<integer, integer> Grid cell of each ink type, nil if the ink type has no detail image
    ---@field DetailAnimations table<integer, ss.InkDetailAnimation> Frame control of animated cells
    ---@field DetailMesh IMesh? Periodic border mesh shared by all cells
    ---@field DetailTransforms VMatrix[] Placement of each cell's mesh
    ---@field ProxiedMaterials ss.ProxiedInkMaterial[] Ink definitions with material proxies
    ---@field ParameterRows table<integer, number[][]> Last encoded input rows written for each ink type
    locals.InkTypeRT = {
        BaseTextureNames = {},
        DetailTextures = {},
        DetailSlots = {},
        DetailAnimations = {},
        DetailTransforms = {},
        ProxiedMaterials = {},
        ParameterRows = {},
    }
end

local InkTypeRT = locals.InkTypeRT

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local CHANNEL_INDEX = { R = 0, G = 1, B = 2, A = 3 }
local cp = Material "splashsweps/shaders/copy"
local detailCopyMaterial = Material "splashsweps/shaders/copydetail"

---@class ss.InkDetailAnimation
---@field Material IMaterial Lowest-index ink definition using this texture
---@field FrameVariable string Material parameter controlling the frame
---@field Frame integer Last frame copied to the cell

---@class ss.ProxiedInkMaterial
---@field Material IMaterial
---@field Index integer

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
            ((mat:GetInt "$nodig"      or 0) * 128 +
            (mat:GetInt "$heightonly" or 0) * 64) / 255,
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
    if not next(textures) then return end
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    render.OverrideAlphaWriteEnable(true, true)
    for slot, texture in pairs(textures) do
        local animation = InkTypeRT.DetailAnimations[slot]
        local frame = animation and (animation.Material:GetInt(animation.FrameVariable) or 0) or 0
        if animation then animation.Frame = frame end
        detailCopyMaterial:SetTexture("$basetexture", texture)
        detailCopyMaterial:SetInt("$frame", frame)
        render.SetMaterial(detailCopyMaterial)
        cam.PushModelMatrix(InkTypeRT.DetailTransforms[slot])
            InkTypeRT.DetailMesh:Draw()
        cam.PopModelMatrix()
    end
    render.OverrideAlphaWriteEnable(false)
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
        InkTypeRT.ParameterRows[i] = rows
        local heightbaseline = rows[3][4]
        if heightbaseline < 0 then
            draw(InkTypeRT.BaseTextureNames[i], ss.MakeRectangle(1, 1, i - 1, 3 - 1 + rtSize), false, true)
        end
    end
end

---@class ss.MaterialProxyKey
---@field Key string
---@field Value string|number|ss.MaterialProxyKey[]

---Finds the first named entry in an ordered KeyValues list.
---@param entries ss.MaterialProxyKey[]
---@param name string
---@return ss.MaterialProxyKey?
local function FindMaterialProxyKey(entries, name)
    for _, entry in ipairs(entries) do
        if entry.Key == name then return entry end
    end
end

---Merges ordered proxy keys using Source's insert/replace rules.
---@param destination ss.MaterialProxyKey[]
---@param source ss.MaterialProxyKey[]
---@param existingOnly boolean
local function MergeMaterialProxyKeys(destination, source, existingOnly)
    for _, entry in ipairs(source) do
        local target = FindMaterialProxyKey(destination, entry.Key)
        if target or not existingOnly then
            if not target then
                target = { Key = entry.Key, Value = {} }
                destination[#destination + 1] = target
            end
            if istable(entry.Value) then
                if not istable(target.Value) then target.Value = {} end
                local targetValues, sourceValues = target.Value, entry.Value
                    ---@cast targetValues ss.MaterialProxyKey[]
                    ---@cast sourceValues ss.MaterialProxyKey[]
                MergeMaterialProxyKeys(targetValues, sourceValues, existingOnly)
            else
                target.Value = entry.Value
            end
        end
    end
    if existingOnly then
        for _, target in ipairs(destination) do
            local entry = FindMaterialProxyKey(source, target.Key)
            if istable(target.Value) and entry and istable(entry.Value) then
                local targetValues, sourceValues = target.Value, entry.Value
                    ---@cast targetValues ss.MaterialProxyKey[]
                    ---@cast sourceValues ss.MaterialProxyKey[]
                MergeMaterialProxyKeys(targetValues, sourceValues, true)
            end
        end
    end
end

---Reads the proxy block after resolving Source's Patch include chain.
---@param path string
---@return ss.MaterialProxyKey[]
local function ReadMaterialProxyKeys(path)
    local inserts, replaces ---@type ss.MaterialProxyKey[]?, ss.MaterialProxyKey[]?
    -- Source accumulates patches from outermost to innermost, up to ten includes.
    for _ = 0, 10 do
        local vmt = file.Read(path, "GAME")
        if not vmt then return {} end
        local root = util.KeyValuesToTablePreserveOrder('"vmt" {\n' .. vmt .. '\n}')[1]
            ---@cast root ss.MaterialProxyKey
        local entries = root.Value ---@cast entries ss.MaterialProxyKey[]
        if root.Key ~= "patch" then
            local proxies = FindMaterialProxyKey(entries, "proxies")
            local values = proxies and proxies.Value ---@cast values ss.MaterialProxyKey[]?
            if inserts then
                values = values or {}
                MergeMaterialProxyKeys(values, inserts, false)
            end
            if values and replaces then MergeMaterialProxyKeys(values, replaces, true) end
            return values or {}
        end
        for _, action in ipairs { "insert", "replace" } do
            local section = FindMaterialProxyKey(entries, action)
            local sectionValues = section and section.Value
                ---@cast sectionValues ss.MaterialProxyKey[]?
            local proxies = sectionValues and FindMaterialProxyKey(sectionValues, "proxies")
            if proxies then
                local values = proxies.Value ---@cast values ss.MaterialProxyKey[]
                if action == "insert" then
                    inserts = inserts or {}
                    MergeMaterialProxyKeys(inserts, values, false)
                else
                    replaces = replaces or {}
                    MergeMaterialProxyKeys(replaces, values, false)
                end
            end
        end
        local include = FindMaterialProxyKey(entries, "include")
        if not include then return {} end
        local includePath = include.Value ---@cast includePath string
        path = includePath
    end
    return {}
end

---Reads proxy presence and the output variable of AnimatedTexture applied to $detail.
---@param mat IMaterial
---@return boolean hasProxies
---@return string? detailFrameVariable
local function ReadMaterialProxies(mat)
    local proxies = ReadMaterialProxyKeys("materials/" .. mat:GetName() .. ".vmt")
    local frameVariable = nil ---@type string?
    for _, proxy in ipairs(proxies) do
        if proxy.Key == "animatedtexture" then
            local contents = proxy.Value ---@cast contents { Key: string, Value: string }[]
            local fields = table.CollapseKeyValue(contents) ---@type table<string, string>
            if fields.animatedtexturevar and fields.animatedtexturevar:lower() == "$detail" then
                frameVariable = fields.animatedtextureframenumvar
            end
        end
    end
    return #proxies > 0, frameVariable
end

---Collects textures and packing rectangles, and encodes ink type parameters.
---@return ss.InkTypeAtlasSources sources
---@return number[][][] parameters
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
        DetailNames      = {}, ---@type string[]
        DetailCache      = {}, ---@type table<string, integer>
        DetailTextures   = {}, ---@type ITexture[]
        DetailSlots      = {}, ---@type table<integer, integer>
        DetailAnimations = {}, ---@type table<integer, ss.InkDetailAnimation>
        ProxiedMaterials = {}, ---@type ss.ProxiedInkMaterial[]
    }
    local parameters = {} ---@type number[][][]
    cp:SetTexture("$basetexture", "color/black")
    local black = cp:GetTexture "$basetexture"
    cp:SetTexture("$basetexture", "color/white")
    local white = cp:GetTexture "$basetexture"
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        local hasProxies, frameVariable = ReadMaterialProxies(mat)

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

        cp:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = cp:GetTexture "$basetexture"
        if detail then
            local name = detail:GetName()
            sources.DetailNames[i] = name
            inktype.DetailBlendMode = mat:GetInt "$detailblendmode" or 0
            if not sources.DetailCache[name] then
                sources.DetailTextures[#sources.DetailTextures + 1] = detail
                sources.DetailCache[name] = #sources.DetailTextures
                if detail:GetNumAnimationFrames() > 1 then
                    sources.DetailAnimations[#sources.DetailTextures] = {
                        Material = mat,
                        FrameVariable = frameVariable or "$frame",
                        Frame = -1,
                    }
                end
            end
            sources.DetailSlots[i] = sources.DetailCache[name]
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

        parameters[i] = ReadParameters(mat, sources.DetailSlots[i])
        if hasProxies then
            sources.ProxiedMaterials[#sources.ProxiedMaterials + 1] = {
                Material = mat,
                Index = i,
            }
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
    print "$detail"
    PrintTable(sources.DetailNames)
    print "$heightmap"
    PrintTable(sources.HeightNames)
    return sources, parameters
end

---Builds one reusable mesh containing a cell's center, edges, and corners.
---@param cellSize number
local function BuildDetailCellMesh(cellSize)
    if InkTypeRT.DetailMesh then InkTypeRT.DetailMesh:Destroy() end
    InkTypeRT.DetailMesh = nil
    if cellSize == 0 then return end
    local detailSize = cellSize - MARGIN
    local positions = { 0, HALF_MARGIN, cellSize - HALF_MARGIN, cellSize }
    local uvs = { { 1 - HALF_MARGIN / detailSize, 1 }, { 0, 1 }, { 0, HALF_MARGIN / detailSize } }
    local m = Mesh()
    mesh.Begin(m, MATERIAL_QUADS, 9)
    for y = 1, 3 do
        for x = 1, 3 do
            local vertices = {
                { positions[x],     positions[y],     uvs[x][1], uvs[y][1] },
                { positions[x + 1], positions[y],     uvs[x][2], uvs[y][1] },
                { positions[x + 1], positions[y + 1], uvs[x][2], uvs[y][2] },
                { positions[x],     positions[y + 1], uvs[x][1], uvs[y][2] },
            }
            for _, v in ipairs(vertices) do
                mesh.Position(v[1], v[2], 0)
                mesh.TexCoord(0, v[3], v[4])
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
        end
    end
    mesh.End()
    InkTypeRT.DetailMesh = m
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
    InkTypeRT.DetailAnimations = sources.DetailAnimations
    InkTypeRT.ProxiedMaterials = sources.ProxiedMaterials
    InkTypeRT.ParameterRows = {}
    InkTypeRT.DetailTransforms = {}
    local cellSize = gridColumns > 0 and rtSize / gridColumns or 0
    BuildDetailCellMesh(cellSize)
    for slot in ipairs(sources.DetailTextures) do
        local transform = Matrix()
        transform:SetTranslation(Vector(
            (slot - 1) % gridColumns * cellSize,
            math.floor((slot - 1) / gridColumns) * cellSize,
            0))
        InkTypeRT.DetailTransforms[slot] = transform
    end
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
            draw(sources.TintNames[inktype.Index], rect, true, false)
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
            draw(shape.MaskTexture:StripExtension(), rect, false, true)
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

---Writes selected cells and encoded rows in one Details render context.
---@param cells integer[]
---@param parameters table<integer, number[][]>
local function UpdateDetailsAtlas(cells, parameters)
    if #cells == 0 and not next(parameters) then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(cells) do
        textures[slot] = InkTypeRT.DetailTextures[slot]
    end

    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
    cam.Start2D()
        WriteDetailCells(textures)
        WriteInkTypeRows(parameters)
    cam.End2D()
    render.PopRenderTarget()
end

---Updates proxied definitions and copies cells whose selected frame changed.
local function SyncDetailRT()
    local parameters = {} ---@type table<integer, number[][]>
    for _, entry in ipairs(InkTypeRT.ProxiedMaterials) do
        render.SetMaterial(entry.Material) -- Bind it so that material proxies work; usually it won't bind at any situation
        local rows = ReadParameters(entry.Material, InkTypeRT.DetailSlots[entry.Index])
        local changed = false
        for j, row in ipairs(rows) do
            for k, value in ipairs(row) do
                if value ~= InkTypeRT.ParameterRows[entry.Index][j][k] then changed = true end
            end
        end
        if changed then
            parameters[entry.Index] = rows
        end
    end
    local cells = {} ---@type integer[]
    for slot, animation in pairs(InkTypeRT.DetailAnimations) do
        if (animation.Material:GetInt(animation.FrameVariable) or 0) ~= animation.Frame then
            cells[#cells + 1] = slot
        end
    end
    UpdateDetailsAtlas(cells, parameters)
end

---Updates detail cells and ink type data.
---@param cells integer[] Detail cells
---@param inkTypes integer[] Ink type indices
function ss.WriteInkTypesRT(cells, inkTypes)
    local parameters = {} ---@type table<integer, number[][]>
    for _, i in ipairs(inkTypes) do
        parameters[i] = ReadParameters(Material(ss.InkTypes[i].Identifier), InkTypeRT.DetailSlots[i])
    end
    UpdateDetailsAtlas(cells, parameters)
end

function ss.LoadInkTypesRT()
    hook.Remove("PreRender", "SplashSWEPs: Update ink materials")
    local sources, parameters = ReadInkTypeSources()
    if #parameters == 0 then return end
    SetupDetailAtlas(sources, parameters)

    timer.Simple(0, function()
        BuildAlbedoAtlas(sources)
        BuildTintAtlas(sources)
        BuildDetailsAtlas(sources.DetailTextures, parameters)
        if #InkTypeRT.ProxiedMaterials > 0 or next(InkTypeRT.DetailAnimations) then
            hook.Add("PreRender", "SplashSWEPs: Update ink materials", SyncDetailRT)
        end
    end)
end
