
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkDetail then
    ---@class ss.Locals.InkDetail
    ---@field BaseTextureNames string[] $basetexture of each ink type, which also provides its average height
    ---@field CellImages table<integer, ITexture> Image copied into each grid cell, nil for generated cells
    ---@field Slots table<integer, integer> Grid cell of each ink type, nil if the ink type has no detail image
    ---@field Animations table<integer, ss.InkDetailAnimation> Frame control of animated cells
    ---@field CellMesh IMesh? Periodic border mesh shared by all cells
    ---@field CellTransforms VMatrix[] Placement of each cell's mesh
    ---@field ProxiedMaterials ss.ProxiedInkMaterial[] Ink definitions with material proxies
    ---@field ParameterRows table<integer, number[][]> Last encoded input rows written for each ink type
    ---@field Updaters table<string, ss.InkDetailUpdater> Functions registered for InkDetailUpdate
    ---@field GeneratedCells table<string, integer> Material name --> grid cell drawn by its InkDetailUpdate
    ---@field Requests table<string, ss.InkDetailProxy> Material name --> proxy which requested drawing
    ---@field LastStates table<string, table> Material name --> copy of the state its cell was drawn with
    locals.InkDetail = {
        BaseTextureNames = {},
        CellImages = {},
        Slots = {},
        Animations = {},
        CellTransforms = {},
        ProxiedMaterials = {},
        ParameterRows = {},
        Updaters = {},
        GeneratedCells = {},
        Requests = {},
        LastStates = {},
    }
end

local MARGIN = 2
local HALF_MARGIN = MARGIN / 2
local cp = Material "splashsweps/shaders/copy"
local detailCopyMaterial = Material "splashsweps/shaders/copydetail"
local InkDetail = locals.InkDetail

---@class ss.InkDetailAnimation
---@field Material IMaterial Lowest-index ink definition using this texture
---@field FrameVariable string Material parameter controlling the frame
---@field Frame integer Last frame copied to the cell

---@class ss.ProxiedInkMaterial
---@field Material IMaterial
---@field Index integer

---Draws a generated cell with the given material.
---@alias ss.InkDetailDrawCell fun(material: IMaterial)

---Draws a generated cell from the state, using drawCell for the actual drawing.
---@alias ss.InkDetailDraw fun(state: table, drawCell: ss.InkDetailDrawCell)

---Reads inputs into the state when the material is bound,
---and returns the function to draw its cell, or nil not to request drawing.
---@alias ss.InkDetailUpdater fun(state: table, material: IMaterial, values: table<string, any>): ss.InkDetailDraw?

---@class ss.InkDetailProxy
---@field Values table<string, any> Key values of the proxy block
---@field State table Inputs of drawing, kept per material
---@field Draw ss.InkDetailDraw? Function returned by the updater

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
    local detailheightsource         = math.Clamp(mat:GetInt "$detailheightsource" or 0, 0, 3)
    local detailheightinvert         = math.Clamp(mat:GetInt "$detailheightinvert" or 0, 0, 1)
    local detailheightmax            = math.Clamp(mat:GetFloat "$detailheightmax" or 24, 0, 24)
    local detailheightcode           = math.Clamp(math.Round(math.sqrt(detailheightmax / 24) * 32) - 1, 0, 31)
    local color                      = mat:GetVector "$color"     or ss.vector_one
    local tintcolor                  = mat:GetVector "$tintcolor" or ss.vector_one
    local alpha                      = mat:GetFloat "$alpha" or 1
    local maxheight                  = mat:GetFloat "$maxheight" or 1
    local bumpblendheight            = mat:GetFloat "$bumpblendheight" or maxheight * 24
    local detaillocal                = (mat:GetInt "$detaillocal" or 0) > 0 and 1 or 0
    return {
        { color.x,     color.y,     color.z,     alpha },
        { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
        {
            (mat:GetInt "$maxlayers" or 1) / 255,
            maxheight,
            math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
            mat:GetFloat "$heightbaseline" or -1,
        }, {
            mat:GetFloat "$erase"           or 0,
            mat:GetFloat "$flatten"         or 0,
            math.Clamp(bumpblendheight / 24, 0, 1),
            ((mat:GetInt "$nodig"      or 0) * 128 +
            (mat:GetInt  "$heightonly" or 0) * 64 + detaillocal * 32) / 255,
        }, {
            mat:GetFloat "$metallic"        or 0,
            mat:GetFloat "$roughness"       or 0,
            mat:GetFloat "$specularscale"   or 1,
            1 - 1 / (mat:GetFloat "$refractiveindex" or 1.33), -- Refraction strength for the shader
        },
        {
            0, 0, 0, -- Unused
            mat:GetFloat "$viscosity" or 1,
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
            -- bit 0: invert, bits 1..2: source, bits 3..7: sqrt(max HU / 24) * 32 - 1
            (detailheightcode * 8 + detailheightsource * 2 + detailheightinvert) / 255,
        },
    }
end

---Compares a state with the copy of the state a cell was drawn with.
---Vector, Angle, and VMatrix compare their components with ==,
---while material and texture handles are compared by their names
---as getting the same resource again gives another handle.
---@param current any
---@param last any
---@return boolean
local function IsSameState(current, last)
    if current == last then return true end
    local kind = TypeID(current)
    if kind ~= TypeID(last) then return false end
    if kind == TYPE_MATERIAL or kind == TYPE_TEXTURE then
        return current:GetName() == last:GetName()
    end
    if kind ~= TYPE_TABLE then return false end
    for key, value in pairs(current) do
        if not IsSameState(value, last[key]) then return false end
    end
    for key in pairs(last) do
        if current[key] == nil then return false end
    end
    return true
end

---Draws the cell mesh, including its borders, with the given material.
---@param material IMaterial
local function DrawCell(material)
    render.SetMaterial(material)
    InkDetail.CellMesh:Draw()
end

---Copies detail images into their grid cells with one-texel borders wrapping around the image,
---and draws generated cells by the functions returned from their updaters.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param textures table<integer, ITexture> Grid cell --> detail image
---@param generated table<string, ss.InkDetailProxy> Material name --> proxy to draw its cell
local function WriteDetailCells(textures, generated)
    if not next(textures) and not next(generated) then return end
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    render.OverrideAlphaWriteEnable(true, true)
    for slot, texture in pairs(textures) do
        local animation = InkDetail.Animations[slot]
        local frame = animation and (animation.Material:GetInt(animation.FrameVariable) or 0) or 0
        if animation then animation.Frame = frame end
        detailCopyMaterial:SetTexture("$basetexture", texture)
        detailCopyMaterial:SetInt("$frame", frame)
        cam.PushModelMatrix(InkDetail.CellTransforms[slot])
            DrawCell(detailCopyMaterial)
        cam.PopModelMatrix()
    end
    for name, proxy in pairs(generated) do
        cam.PushModelMatrix(InkDetail.CellTransforms[InkDetail.GeneratedCells[name]])
            -- An error in the drawing function must not leave the render target pushed.
            local drawn = ProtectedCall(proxy.Draw, proxy.State, DrawCell)
        cam.PopModelMatrix()
        if drawn then InkDetail.LastStates[name] = ss.deepcopy(proxy.State) end
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
        InkDetail.ParameterRows[i] = rows
        local heightbaseline = rows[3][4]
        if heightbaseline < 0 then
            ss.CopyTextureToRect(InkDetail.BaseTextureNames[i],
                ss.MakeRectangle(1, 1, i - 1, 3 - 1 + rtSize), false, true)
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

---Reads proxy presence, the output variable of AnimatedTexture applied to $detail,
---and whether InkDetailUpdate draws the detail cell.
---@param mat IMaterial
---@return boolean hasProxies
---@return string? detailFrameVariable
---@return boolean generated
local function ReadMaterialProxies(mat)
    local proxies = ReadMaterialProxyKeys("materials/" .. mat:GetName() .. ".vmt")
    local frameVariable = nil ---@type string?
    local generated = false
    for _, proxy in ipairs(proxies) do
        if proxy.Key == "animatedtexture" then
            local contents = proxy.Value ---@cast contents { Key: string, Value: string }[]
            local fields = table.CollapseKeyValue(contents) ---@type table<string, string>
            if fields.animatedtexturevar and fields.animatedtexturevar:lower() == "$detail" then
                frameVariable = fields.animatedtextureframenumvar
            end
        elseif proxy.Key == "inkdetailupdate" then
            generated = true
        end
    end
    return #proxies > 0, frameVariable, generated
end

---Builds one reusable mesh containing a cell's center, edges, and corners.
---@param cellSize number
local function BuildCellMesh(cellSize)
    if InkDetail.CellMesh then InkDetail.CellMesh:Destroy() end
    InkDetail.CellMesh = nil
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
    InkDetail.CellMesh = m
end

---Takes drawing requests whose state differs from the one their cell was last drawn with.
---@return table<string, ss.InkDetailProxy> generated Material name --> proxy to draw its cell
local function TakeGeneratedCells()
    local generated = {} ---@type table<string, ss.InkDetailProxy>
    for name, proxy in pairs(InkDetail.Requests) do
        if not IsSameState(proxy.State, InkDetail.LastStates[name]) then
            generated[name] = proxy
        end
        InkDetail.Requests[name] = nil
    end
    return generated
end

---Writes selected cells, generated cells, and encoded rows in one Details render context.
---@param cells integer[]
---@param parameters table<integer, number[][]>
local function UpdateDetailsAtlas(cells, parameters)
    local generated = TakeGeneratedCells()
    if #cells == 0 and not next(parameters) and not next(generated) then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(cells) do
        textures[slot] = InkDetail.CellImages[slot]
    end

    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
    cam.Start2D()
        WriteDetailCells(textures, generated)
        WriteInkTypeRows(parameters)
    cam.End2D()
    render.PopRenderTarget()
end

---Updates proxied definitions, copies cells whose selected frame changed,
---and draws generated cells whose state changed.
local function SyncDetailRT()
    local parameters = {} ---@type table<integer, number[][]>
    for _, entry in ipairs(InkDetail.ProxiedMaterials) do
        render.SetMaterial(entry.Material) -- Bind it so that material proxies work; usually it won't bind at any situation
        local rows = ReadParameters(entry.Material, InkDetail.Slots[entry.Index])
        local changed = false
        for j, row in ipairs(rows) do
            for k, value in ipairs(row) do
                if value ~= InkDetail.ParameterRows[entry.Index][j][k] then changed = true end
            end
        end
        if changed then
            parameters[entry.Index] = rows
        end
    end
    local cells = {} ---@type integer[]
    for slot, animation in pairs(InkDetail.Animations) do
        if (animation.Material:GetInt(animation.FrameVariable) or 0) ~= animation.Frame then
            cells[#cells + 1] = slot
        end
    end
    UpdateDetailsAtlas(cells, parameters)
end

---Lays out detail images of ink types, then creates the Details render target and the cell mesh.
---This also stops updating the render target until ss.WriteInitialInkDetailsRT() is called.
---@param baseTextureNames string[] $basetexture of each ink type, which also provides its average height
---@return number[][][]? parameters Data rows of each ink type, nil if there is no ink type
function ss.PrepareInkDetailsRT(baseTextureNames)
    hook.Remove("PreRender", "SplashSWEPs: Update ink materials")
    if #ss.InkTypes == 0 then return end

    local images           = {} ---@type ITexture[] Source image of each grid cell
    local cellImages       = {} ---@type table<integer, ITexture>
    local cache            = {} ---@type table<string, integer>
    local detailNames      = {} ---@type string[]
    local slots            = {} ---@type table<integer, integer>
    local animations       = {} ---@type table<integer, ss.InkDetailAnimation>
    local generatedCells   = {} ---@type table<string, integer>
    local proxiedMaterials = {} ---@type ss.ProxiedInkMaterial[]
    local parameters       = {} ---@type number[][][]
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        local hasProxies, frameVariable, generated = ReadMaterialProxies(mat)
        cp:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = cp:GetTexture "$basetexture"
        if detail then
            local name = detail:GetName()
            detailNames[i] = name
            inktype.DetailBlendMode = mat:GetInt "$detailblendmode" or 0
            if generated then
                -- The cell is owned by the material as its image differs from the source.
                images[#images + 1] = detail
                generatedCells[inktype.Identifier] = #images
                slots[i] = #images
            else
                if not cache[name] then
                    images[#images + 1] = detail
                    cellImages[#images] = detail
                    cache[name] = #images
                    if detail:GetNumAnimationFrames() > 1 then
                        animations[#images] = {
                            Material = mat,
                            FrameVariable = frameVariable or "$frame",
                            Frame = -1,
                        }
                    end
                end
                slots[i] = cache[name]
            end
        end

        parameters[i] = ReadParameters(mat, slots[i])
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
    local gridColumns = math.ceil(math.sqrt(#images))
    local detailSize, rtSize = 0, 0
    for _, texture in ipairs(images) do
        detailSize = math.max(detailSize, texture:Width(), texture:Height())
    end
    if #images > 0 then
        detailSize = math.min(detailSize, math.floor((16384 - #parameters[1]) / gridColumns) - MARGIN)
        rtSize = gridColumns * (detailSize + MARGIN)
    end

    local dataWidth, dataHeight = math.max(rtSize, #parameters), rtSize + #parameters[1]
    ss.RenderTarget.DetailsImageSize = rtSize
    ss.RenderTarget.DetailGridColumns = gridColumns
    InkDetail.BaseTextureNames = baseTextureNames
    InkDetail.CellImages = cellImages
    InkDetail.Slots = slots
    InkDetail.Animations = animations
    InkDetail.ProxiedMaterials = proxiedMaterials
    InkDetail.ParameterRows = {}
    InkDetail.GeneratedCells = generatedCells
    InkDetail.Requests = {}
    InkDetail.LastStates = {}
    InkDetail.CellTransforms = {}
    local cellSize = gridColumns > 0 and rtSize / gridColumns or 0
    BuildCellMesh(cellSize)
    for slot in ipairs(images) do
        local transform = Matrix()
        transform:SetTranslation(Vector(
            (slot - 1) % gridColumns * cellSize,
            math.floor((slot - 1) / gridColumns) * cellSize,
            0))
        InkDetail.CellTransforms[slot] = transform
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
    inkWater:SetFloat("$c1_z", 2 / ss.RenderTarget.HammerUnitsToUV)
    for material in pairs(ss.InkMeshMaterials) do
        material:SetFloat("$c3_w", rtSize)
        material:SetFloat("$c1_x", gridColumns)
        material:SetFloat("$c1_z", 2 / ss.RenderTarget.HammerUnitsToUV)
    end
    return parameters
end

---Writes the first contents of the Details render target prepared by ss.PrepareInkDetailsRT(),
---then starts updating it every frame if any ink type has material proxies or animated detail images.
---Generated cells are drawn by the first update.
---@param parameters number[][][] Data rows returned by ss.PrepareInkDetailsRT()
function ss.WriteInitialInkDetailsRT(parameters)
    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        WriteDetailCells(InkDetail.CellImages, {})
        WriteInkTypeRows(parameters)
    cam.End2D()
    render.PopRenderTarget()
    if #InkDetail.ProxiedMaterials > 0 or next(InkDetail.Animations) then
        hook.Add("PreRender", "SplashSWEPs: Update ink materials", SyncDetailRT)
    end
end

---Updates detail cells and ink type data.
---@param cells integer[] Detail cells
---@param inkTypes integer[] Ink type indices
function ss.WriteInkTypesRT(cells, inkTypes)
    local parameters = {} ---@type table<integer, number[][]>
    for _, i in ipairs(inkTypes) do
        parameters[i] = ReadParameters(Material(ss.InkTypes[i].Identifier), InkDetail.Slots[i])
    end
    UpdateDetailsAtlas(cells, parameters)
end

---Registers a function called by InkDetailUpdate material proxy.
---The proxy block selects it by "updater" key, e.g.
---```
---"InkDetailUpdate"
---{
---    "updater" "myaddon/ripple"
---}
---```
---The updater stores every input of drawing in the state, which is kept per material,
---and returns the function to draw the cell.
---The cell is drawn only if the state differs from the one it was last drawn with.
---@param name string
---@param update ss.InkDetailUpdater
function ss.RegisterInkDetailUpdate(name, update)
    InkDetail.Updaters[name] = update
    -- The new function may draw differently from the same state.
    InkDetail.LastStates = {}
end

matproxy.Add {
    name = "InkDetailUpdate",
    ---@param self ss.InkDetailProxy
    init = function(self)
        self.State = {}
    end,
    ---@param self ss.InkDetailProxy
    ---@param material IMaterial
    bind = function(self, material)
        local name = material:GetName()
        if not InkDetail.GeneratedCells[name] then return end
        local update = InkDetail.Updaters[self.Values.updater]
        if not update then
            error(string.format("[SplashSWEPs] InkDetailUpdate: updater '%s' is not registered (%s)",
                tostring(self.Values.updater), name))
        end
        local draw = update(self.State, material, self.Values)
        if draw then
            self.Draw = draw
            InkDetail.Requests[name] = self
        end
    end,
}
