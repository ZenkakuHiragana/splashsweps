
-- Ink detail atlas: the detail images of ink materials, and the ink data below them.

---@class ss
local ss = SplashSWEPs
local InkData        = ss.import "splashsweps/client/ink/inkdata"
local InkDetailProxy = ss.import "splashsweps/client/ink/inkdetailproxy"
local InkType        = ss.import "splashsweps/shared/inktype"
local MaterialProxy  = ss.import "splashsweps/client/ink/materialproxy"

---@class ss.InkDetailAtlasModule
local InkDetailAtlas = ss.module "splashsweps/client/ink/inkdetailatlas"

---@class ss.InkDetailAtlasModule.State
---@field BaseTextureNames string[]                   $basetexture of each ink type, which also provides its average height
---@field CellImages       table<integer, ITexture>   Image copied into each grid cell, nil for generated cells
---@field Slots            table<integer, integer>    Grid cell of each ink type, nil if the ink type has no detail image
---@field Animations       table<integer, ss.InkDetailAnimation> External frame variable and last copied frame, per animated cell
---@field CellMesh         IMesh?                     Periodic border mesh shared by all cells
---@field CellTransforms   VMatrix[]                  Placement of each cell's mesh
---@field ProxiedMaterials ss.ProxiedInkMaterial[]    Ink materials with material proxies
---@field LastInkData      table<integer, number[][]> Last encoded inputs sent to WriteInkData
---@field GeneratedCells   table<string, integer>     Material name --> grid cell drawn by its InkDetailUpdate
---@field RenderTarget     ITexture?                  The atlas
---@field ImageSize        number                     Side length of the square image area above the ink data
---@field GridColumns      number                     Number of columns in the detail image grid
---@field BlendModes       table<integer, integer>    $detailblendmode of each ink type, 0 if the detail is disabled
-- Preparation replaces the contents, not the field names.
local state = ss.state("splashsweps/client/ink/inkdetailatlas", {
    BaseTextureNames = {},
    CellImages = {},
    Slots = {},
    Animations = {},
    CellTransforms = {},
    ProxiedMaterials = {},
    LastInkData = {},
    GeneratedCells = {},
    ImageSize = 0,
    GridColumns = 0,
    BlendModes = {},
}) ---@type ss.InkDetailAtlasModule.State

---$detailblendmode of each ink type, 0 if the detail is disabled.
InkDetailAtlas.BlendModes = state.BlendModes

local CELL_BORDER_TOTAL_PX = 2
local CELL_BORDER_PX       = CELL_BORDER_TOTAL_PX / 2
local copyMaterial         = Material "splashsweps/shaders/copy"
local detailCopyMaterial   = Material "splashsweps/shaders/copydetail"

---@class ss.InkDetailAnimation
---@field Material IMaterial Lowest-index ink material using this texture
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
---@param drawRequests table<string, ss.InkDetailProxyInstance> Material name --> changed drawing request
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
        if drawn then InkDetailProxy.MarkDrawn(name, proxy) end
    end
    render.OverrideAlphaWriteEnable(false)
    render.OverrideBlend(false)
end

---Writes the ink data of ink types below the grid cells so that they can be read in the shader.
---Automatic height baselines have already been resolved from the smallest stored mipmaps.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param inkDataByType table<integer, number[][]> Ink type index --> ink data from InkData.Encode()
local function WriteInkData(inkDataByType)
    if not next(inkDataByType) then return end
    local numTexels = 0
    for i, inkData in pairs(inkDataByType) do
        numTexels = numTexels + #inkData
        state.LastInkData[i] = inkData
    end

    copyMaterial:SetTexture("$basetexture", "color/white")
    copyMaterial:SetInt("$c0_x", 3)
    copyMaterial:SetInt("$c0_y", 1)
    render.SetMaterial(copyMaterial)
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_POINTS, numTexels)
    local imageAreaSizePx = state.ImageSize
    for i, inkData in pairs(inkDataByType) do
        for j, float4 in ipairs(inkData) do
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
    local proxies       = MaterialProxy.Read("materials/" .. mat:GetName() .. ".vmt")
    local frameVariable = nil ---@type string?
    local updater       = nil ---@type string?
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

---Consumes pending generated draws and writes selected images/ink data in one ink detail atlas context.
---@param imageCells integer[]
---@param inkDataByType table<integer, number[][]>
local function WriteAtlas(imageCells, inkDataByType)
    local drawRequests = InkDetailProxy.TakeChanged()
    if #imageCells == 0 and not next(inkDataByType) and not next(drawRequests) then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(imageCells) do
        textures[slot] = state.CellImages[slot]
    end

    render.PushRenderTarget(state.RenderTarget)
    cam.Start2D()
        WriteDetailCells(textures, drawRequests)
        WriteInkData(inkDataByType)
    cam.End2D()
    render.PopRenderTarget()
end

---Binds proxied materials, then reads their settings and externally selected animation frames.
---Only changed ink data/frames and changed generated drawing inputs are written to the atlas.
local function UpdateFromMaterials()
    local inkDataByType = {} ---@type table<integer, number[][]>
    for _, entry in ipairs(state.ProxiedMaterials) do
        render.SetMaterial(entry.Material) -- Ink materials need an explicit bind to execute their proxies.
        local slot = state.Slots[entry.Index]
        local btstr = state.BaseTextureNames[entry.Index]
        local inkData = InkData.Encode(entry.Material, slot, btstr)
        local changed = false
        for j, texel in ipairs(inkData) do
            for k, value in ipairs(texel) do
                if value ~= state.LastInkData[entry.Index][j][k] then changed = true end
            end
        end
        if changed then
            inkDataByType[entry.Index] = inkData
        end
    end
    local imageCells = {} ---@type integer[]
    for slot, animation in pairs(state.Animations) do
        if (animation.Material:GetInt(animation.FrameVariable) or 0) ~= animation.Frame then
            imageCells[#imageCells + 1] = slot
        end
    end
    WriteAtlas(imageCells, inkDataByType)
end

---Lays out detail images of ink types, then creates the Details render target and the cell mesh.
---This also stops updating the render target until InkDetailAtlas.DrawInitial() is called.
---@param baseTextureNames string[] $basetexture of each ink type, which also provides its average height
---@return number[][][]? inkDataByType Ink data of each ink type, nil if there is no ink type
function InkDetailAtlas.Prepare(baseTextureNames)
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
    local inkDataByType    = {} ---@type number[][][]
    local blendModes       = {} ---@type table<integer, integer>
    for i, inktype in ipairs(InkType.Types) do
        local mat = Material(inktype.Identifier)
        local hasProxies, frameVariable, updater = ReadDetailProxyInfo(mat)
        copyMaterial:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = copyMaterial:GetTexture "$basetexture"
        blendModes[i] = detail and mat:GetInt "$detailblendmode" or 0
        if detail then
            local name = detail:GetName()
            detailNames[i] = name
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

        inkDataByType[i] = InkData.Encode(mat, slots[i], baseTextureNames[i])
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
        detailSize = math.min(detailSize, math.floor((16384 - #inkDataByType[1]) / gridColumns) - CELL_BORDER_TOTAL_PX)
        imageAreaSizePx = gridColumns * (detailSize + CELL_BORDER_TOTAL_PX)
    end

    local atlasWidthPx, atlasHeightPx = math.max(imageAreaSizePx, #inkDataByType), imageAreaSizePx + #inkDataByType[1]
    state.ImageSize = imageAreaSizePx
    state.GridColumns = gridColumns
    table.CopyFromTo(blendModes, state.BlendModes)
    state.BaseTextureNames = baseTextureNames
    state.CellImages = cellImages
    state.Slots = slots
    state.Animations = animations
    state.ProxiedMaterials = proxiedMaterials
    state.LastInkData = {}
    state.GeneratedCells = generatedCells
    InkDetailProxy.Reset(updaters)
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
        -- Detail images use bilinear filtering; ink data is read at texel centers.
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    return inkDataByType
end

---Writes the first contents of the Details render target prepared by InkDetailAtlas.Prepare(),
---then starts updating it every frame if any ink type has material proxies or animated detail images.
---Generated cells are drawn by the first update.
---Needs a rendering context, so call it from the next frame of InkDetailAtlas.Prepare().
---@param inkDataByType number[][][] Ink data returned by InkDetailAtlas.Prepare()
function InkDetailAtlas.DrawInitial(inkDataByType)
    render.PushRenderTarget(state.RenderTarget)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        WriteDetailCells(state.CellImages, {})
        WriteInkData(inkDataByType)
    cam.End2D()
    render.PopRenderTarget()
    if #state.ProxiedMaterials > 0 or next(state.Animations) then
        hook.Add("PreRender", "SplashSWEPs: Update ink materials", UpdateFromMaterials)
    end
end

---Returns the atlas render target.
---@return ITexture
function InkDetailAtlas.GetRenderTarget()
    return state.RenderTarget
end

---Writes the layout of the atlas into a material reading it:
---ink mesh materials, ink sprp materials, and the paint material drawing paints into the ink map.
---The layout is fixed once the atlas is laid out in this Lua state,
---as the render target keeps the size it was first created with.
---@param mat IMaterial
function InkDetailAtlas.WriteLayout(mat)
    mat:SetFloat("$c3_w", state.ImageSize)
    mat:SetFloat("$c1_x", state.GridColumns)
end

return InkDetailAtlas
