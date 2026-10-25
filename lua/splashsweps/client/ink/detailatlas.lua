
-- Atlas of the detail images of ink types and the data rows of their parameters.

---@class ss
local ss = SplashSWEPs
local DetailProxy   = ss.import "splashsweps/client/ink/detailproxy"
local DetailRows    = ss.import "splashsweps/client/ink/detailrows"
local InkType       = ss.import "splashsweps/shared/inktype"
local MaterialProxy = ss.import "splashsweps/client/ink/materialproxy"

---@class ss.DetailAtlasModule
local DetailAtlas = ss.module "splashsweps/client/ink/detailatlas"

---@class ss.DetailAtlasModule.State
---@field BaseTextureNames string[]                              $basetexture of each ink type, which also provides its average height
---@field CellImages       table<integer, ITexture>              Image copied into each grid cell, nil for generated cells
---@field Slots            table<integer, integer>               Grid cell of each ink type, nil if the ink type has no detail image
---@field Animations       table<integer, ss.InkDetailAnimation> External frame variable and last copied frame, per animated cell
---@field CellMesh         IMesh?                                Periodic border mesh shared by all cells
---@field CellTransforms   VMatrix[]                             Placement of each cell's mesh
---@field ProxiedMaterials ss.ProxiedInkMaterial[]               Ink definitions with material proxies
---@field ParameterRows    table<integer, number[][]>            Last encoded inputs sent to WriteInkTypeRows
---@field GeneratedCells   table<string, integer>                Material name --> grid cell drawn by its InkDetailUpdate
---@field RenderTarget     ITexture?                             The atlas
---@field ImageSize        number                                Side length of the square image area above the data rows
---@field GridColumns      number                                Number of columns in the detail image grid
---@field BlendModes       table<integer, integer>               $detailblendmode of each ink type with a detail image
-- Preparation replaces the contents, not the field names.
local state = ss.state("splashsweps/client/ink/detailatlas", {
    BaseTextureNames = {},
    CellImages = {},
    Slots = {},
    Animations = {},
    CellTransforms = {},
    ProxiedMaterials = {},
    ParameterRows = {},
    GeneratedCells = {},
    ImageSize = 0,
    GridColumns = 0,
    BlendModes = {},
}) ---@type ss.DetailAtlasModule.State

local CELL_BORDER_TOTAL_PX = 2
local CELL_BORDER_PX       = CELL_BORDER_TOTAL_PX / 2
local copyMaterial         = Material "splashsweps/shaders/copy"
local detailCopyMaterial   = Material "splashsweps/shaders/copydetail"

---@class ss.InkDetailAnimation
---@field Material IMaterial Lowest-index ink definition using this texture
---@field FrameVariable string Material parameter controlling the frame
---@field Frame integer Last frame copied to the cell

---@class ss.ProxiedInkMaterial
---@field Material IMaterial
---@field Index integer

---Draws the shared wrapping-border mesh in the caller's cell transform and RT context.
---@param material IMaterial
local function DrawCellMesh(material)
    render.SetMaterial(material)
    state.CellMesh:Draw()
end

---Copies detail images into their grid cells with one-texel borders wrapping around the image,
---and draws generated cells by the functions returned from their updaters.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param textures table<integer, ITexture> Grid cell --> detail image
---@param drawRequests table<string, ss.InkDetailProxy> Material name --> changed drawing request
local function WriteDetailCells(textures, drawRequests)
    if not next(textures) and not next(drawRequests) then return end
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    render.OverrideAlphaWriteEnable(true, true)
    for slot, texture in pairs(textures) do
        local animation = state.Animations[slot]
        local frame     = animation and (animation.Material:GetInt(animation.FrameVariable) or 0) or 0
        if animation then animation.Frame = frame end
        detailCopyMaterial:SetTexture("$basetexture", texture)
        detailCopyMaterial:SetInt("$frame", frame)
        cam.PushModelMatrix(state.CellTransforms[slot])
            DrawCellMesh(detailCopyMaterial)
        cam.PopModelMatrix()
    end
    for name, proxy in pairs(drawRequests) do
        cam.PushModelMatrix(state.CellTransforms[state.GeneratedCells[name]])
            -- An error in the drawing function must not leave the render target pushed.
            local drawn = ProtectedCall(proxy.Draw, proxy.State, DrawCellMesh)
        cam.PopModelMatrix()
        if drawn then DetailProxy.MarkDrawn(name, proxy) end
    end
    render.OverrideAlphaWriteEnable(false)
    render.OverrideBlend(false)
end

---Writes data rows of ink types below the grid cells so that they can be read in the shader.
---Automatic height baselines have already been resolved from the smallest stored mipmaps.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param rowsByType table<integer, number[][]> Ink type index --> data rows from DetailRows.Encode()
local function WriteInkTypeRows(rowsByType)
    if not next(rowsByType) then return end
    local numRows = 0
    for i, rows in pairs(rowsByType) do
        numRows = numRows + #rows
        state.ParameterRows[i] = rows
    end

    copyMaterial:SetTexture("$basetexture", "color/white")
    copyMaterial:SetInt("$c0_x", 3)
    copyMaterial:SetInt("$c0_y", 1)
    render.SetMaterial(copyMaterial)
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_POINTS, numRows)
    local imageAreaSizePx = state.ImageSize
    for i, rows in pairs(rowsByType) do
        for j, float4 in ipairs(rows) do
            mesh.Position(i, j + imageAreaSizePx, 0)
            mesh.TexCoord(0, 0.5, 0.5)
            mesh.TexCoord(1, unpack(float4))
            mesh.AdvanceVertex()
        end
    end
    mesh.End()
    render.OverrideBlend(false)
end

---Reads proxy presence, the output variable of AnimatedTexture applied to $detail,
---and the updater module of InkDetailUpdate drawing the detail cell.
---@param mat IMaterial
---@return boolean hasProxies
---@return string? detailFrameVariable
---@return string? updater Module name of the updater, nil if InkDetailUpdate does not draw the cell
local function ReadDetailProxyInfo(mat)
    local proxies          = MaterialProxy.Read("materials/" .. mat:GetName() .. ".vmt")
    local frameVariable    = nil ---@type string?
    local updater          = nil ---@type string?
    for _, proxy in ipairs(proxies) do
        if proxy.Key == "animatedtexture" then
            local contents = proxy.Value ---@cast contents { Key: string, Value: string }[]
            local fields   = table.CollapseKeyValue(contents) ---@type table<string, string>
            if fields.animatedtexturevar and fields.animatedtexturevar:lower() == "$detail" then
                frameVariable = fields.animatedtextureframenumvar
            end
        elseif proxy.Key == "inkdetailupdate" then
            local contents = proxy.Value ---@cast contents { Key: string, Value: string }[]
            updater = table.CollapseKeyValue(contents).updater
            if not updater then
                ErrorNoHalt(string.format("SplashSWEPs: InkDetailUpdate of '%s' has no updater\n", mat:GetName()))
            end
        end
    end
    return #proxies > 0, frameVariable, updater
end

---Builds one reusable mesh containing a cell's center, edges, and corners.
---@param cellSizePx number Cell width in pixels, including both wrapping borders
local function BuildWrappedCellMesh(cellSizePx)
    if state.CellMesh then state.CellMesh:Destroy() end
    state.CellMesh = nil
    if cellSizePx == 0 then return end
    local detailSize = cellSizePx - CELL_BORDER_TOTAL_PX
    local positions  = { 0, CELL_BORDER_PX, cellSizePx - CELL_BORDER_PX, cellSizePx }
    local uvs        = { { 1 - CELL_BORDER_PX / detailSize, 1 }, { 0, 1 }, { 0, CELL_BORDER_PX / detailSize } }
    local m          = Mesh()
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
    state.CellMesh = m
end

---Consumes pending generated draws and writes selected images/encoded rows in one Details RT context.
---@param imageCells integer[]
---@param rowsByType table<integer, number[][]>
local function WriteAtlas(imageCells, rowsByType)
    local drawRequests = DetailProxy.TakeChanged()
    if #imageCells == 0 and not next(rowsByType) and not next(drawRequests) then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(imageCells) do
        textures[slot] = state.CellImages[slot]
    end

    render.PushRenderTarget(state.RenderTarget)
    cam.Start2D()
        WriteDetailCells(textures, drawRequests)
        WriteInkTypeRows(rowsByType)
    cam.End2D()
    render.PopRenderTarget()
end

---Binds proxied materials, then reads their settings and externally selected animation frames.
---Only changed rows/frames and changed generated drawing inputs are written to the atlas.
local function UpdateFromMaterials()
    local rowsByType = {} ---@type table<integer, number[][]>
    for _, entry in ipairs(state.ProxiedMaterials) do
        render.SetMaterial(entry.Material) -- Ink definitions need an explicit bind to execute their proxies.
        local slot = state.Slots[entry.Index]
        local btstr = state.BaseTextureNames[entry.Index]
        local rows = DetailRows.Encode(entry.Material, slot, btstr)
        local changed = false
        for j, row in ipairs(rows) do
            for k, value in ipairs(row) do
                if value ~= state.ParameterRows[entry.Index][j][k] then changed = true end
            end
        end
        if changed then
            rowsByType[entry.Index] = rows
        end
    end
    local imageCells = {} ---@type integer[]
    for slot, animation in pairs(state.Animations) do
        if (animation.Material:GetInt(animation.FrameVariable) or 0) ~= animation.Frame then
            imageCells[#imageCells + 1] = slot
        end
    end
    WriteAtlas(imageCells, rowsByType)
end

---Lays out detail images of ink types, then creates the Details render target and the cell mesh.
---This also stops updating the render target until DetailAtlas.DrawInitial() is called.
---@param baseTextureNames string[] $basetexture of each ink type, which also provides its average height
---@return number[][][]? rowsByType Data rows of each ink type, nil if there is no ink type
function DetailAtlas.Prepare(baseTextureNames)
    hook.Remove("PreRender", "SplashSWEPs: Update ink materials")
    if #InkType.Types == 0 then return end

    local cellSizeSources  = {} ---@type ITexture[] Size source of every cell, including generated cells
    local cellImages       = {} ---@type table<integer, ITexture>
    local cache            = {} ---@type table<string, integer>
    local detailNames      = {} ---@type string[]
    local slots            = {} ---@type table<integer, integer>
    local animations       = {} ---@type table<integer, ss.InkDetailAnimation>
    local generatedCells   = {} ---@type table<string, integer>
    local updaters         = {} ---@type table<string, string>
    local proxiedMaterials = {} ---@type ss.ProxiedInkMaterial[]
    local rowsByType       = {} ---@type number[][][]
    local blendModes       = {} ---@type table<integer, integer>
    for i, inktype in ipairs(InkType.Types) do
        local mat = Material(inktype.Identifier)
        local hasProxies, frameVariable, updater = ReadDetailProxyInfo(mat)
        copyMaterial:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = copyMaterial:GetTexture "$basetexture"
        if detail then
            local name = detail:GetName()
            detailNames[i] = name
            blendModes[i] = mat:GetInt "$detailblendmode" or 0
            if updater then
                -- The cell is owned by the material as its image differs from the source.
                cellSizeSources[#cellSizeSources + 1] = detail
                generatedCells[inktype.Identifier] = #cellSizeSources
                updaters[inktype.Identifier] = updater
                slots[i] = #cellSizeSources
            else
                if not cache[name] then
                    cellSizeSources[#cellSizeSources + 1] = detail
                    cellImages[#cellSizeSources] = detail
                    cache[name] = #cellSizeSources
                    if detail:GetNumAnimationFrames() > 1 then
                        animations[#cellSizeSources] = {
                            Material = mat,
                            FrameVariable = frameVariable or "$frame",
                            Frame = -1,
                        }
                    end
                end
                slots[i] = cache[name]
            end
        end

        rowsByType[i] = DetailRows.Encode(mat, slots[i], baseTextureNames[i])
        if hasProxies then
            proxiedMaterials[#proxiedMaterials + 1] = {
                Material = mat,
                Index = i,
            }
        end
    end

    print "$detail"
    PrintTable(detailNames)

    -- Calculating detail texture layout
    local gridColumns = math.ceil(math.sqrt(#cellSizeSources))
    local detailSize, imageAreaSizePx = 0, 0
    for _, texture in ipairs(cellSizeSources) do
        detailSize = math.max(detailSize, texture:Width(), texture:Height())
    end
    if #cellSizeSources > 0 then
        detailSize = math.min(detailSize, math.floor((16384 - #rowsByType[1]) / gridColumns) - CELL_BORDER_TOTAL_PX)
        imageAreaSizePx = gridColumns * (detailSize + CELL_BORDER_TOTAL_PX)
    end

    local atlasWidthPx, atlasHeightPx = math.max(imageAreaSizePx, #rowsByType), imageAreaSizePx + #rowsByType[1]
    state.ImageSize = imageAreaSizePx
    state.GridColumns = gridColumns
    state.BlendModes = blendModes
    state.BaseTextureNames = baseTextureNames
    state.CellImages = cellImages
    state.Slots = slots
    state.Animations = animations
    state.ProxiedMaterials = proxiedMaterials
    state.ParameterRows = {}
    state.GeneratedCells = generatedCells
    DetailProxy.Reset(updaters)
    state.CellTransforms = {}
    local cellSizePx = gridColumns > 0 and imageAreaSizePx / gridColumns or 0
    BuildWrappedCellMesh(cellSizePx)
    for slot in ipairs(cellSizeSources) do
        local transform = Matrix()
        transform:SetTranslation(Vector(
            (slot - 1) % gridColumns * cellSizePx,
            math.floor((slot - 1) / gridColumns) * cellSizePx,
            0))
        state.CellTransforms[slot] = transform
    end
    state.RenderTarget = GetRenderTargetEx(
        "splashsweps_details",
        atlasWidthPx, atlasHeightPx,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
        -- Detail images use bilinear filtering; numeric rows are read at texel centers.
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    return rowsByType
end

---Writes the first contents of the Details render target prepared by DetailAtlas.Prepare(),
---then starts updating it every frame if any ink type has material proxies or animated detail images.
---Generated cells are drawn by the first update.
---Needs a rendering context, so call it from the next frame of DetailAtlas.Prepare().
---@param rowsByType number[][][] Data rows returned by DetailAtlas.Prepare()
function DetailAtlas.DrawInitial(rowsByType)
    render.PushRenderTarget(state.RenderTarget)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        WriteDetailCells(state.CellImages, {})
        WriteInkTypeRows(rowsByType)
    cam.End2D()
    render.PopRenderTarget()
    if #state.ProxiedMaterials > 0 or next(state.Animations) then
        hook.Add("PreRender", "SplashSWEPs: Update ink materials", UpdateFromMaterials)
    end
end

---Returns the atlas render target.
---@return ITexture
function DetailAtlas.GetRenderTarget()
    return state.RenderTarget
end

---Writes the layout of the atlas into a material reading it:
---the ink materials, and the material drawing paints into the ink map.
---The layout is fixed once the atlas is laid out in this Lua state,
---as the render target keeps the size it was first created with.
---@param mat IMaterial
function DetailAtlas.WriteLayout(mat)
    mat:SetFloat("$c3_w", state.ImageSize)
    mat:SetFloat("$c1_x", state.GridColumns)
end

---Returns $detailblendmode of an ink type, 0 if the detail is disabled.
---@param index integer Ink type index
---@return integer
function DetailAtlas.GetBlendMode(index)
    return state.BlendModes[index] or 0
end

return DetailAtlas
