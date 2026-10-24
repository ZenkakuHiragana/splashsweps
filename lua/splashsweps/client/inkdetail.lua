
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
-- Keep this state layout across Lua reloads; preparation replaces contents, not the field names.
if not locals.InkDetail then
    ---@class ss.Locals.InkDetail
    ---@field BaseTextureNames string[]                              $basetexture of each ink type, which also provides its average height
    ---@field AverageHeights   table<string, number>                 Mean alpha of each texture's smallest stored mipmap
    ---@field CellImages       table<integer, ITexture>              Image copied into each grid cell, nil for generated cells
    ---@field Slots            table<integer, integer>               Grid cell of each ink type, nil if the ink type has no detail image
    ---@field Animations       table<integer, ss.InkDetailAnimation> External frame variable and last copied frame, per animated cell
    ---@field CellMesh         IMesh?                                Periodic border mesh shared by all cells
    ---@field CellTransforms   VMatrix[]                             Placement of each cell's mesh
    ---@field ProxiedMaterials ss.ProxiedInkMaterial[]               Ink definitions with material proxies
    ---@field ParameterRows    table<integer, number[][]>            Last encoded inputs sent to WriteInkTypeRows
    ---@field Updaters         table<string, ss.InkDetailUpdater>    Functions registered for InkDetailUpdate
    ---@field GeneratedCells   table<string, integer>                Material name --> grid cell drawn by its InkDetailUpdate
    ---@field Requests         table<string, ss.InkDetailProxy>      Material name --> pending draw request; bind queues, atlas update consumes
    ---@field LastStates       table<string, table>                  Material name --> input snapshot from its last successful draw
    locals.InkDetail = {
        BaseTextureNames = {},
        AverageHeights = {},
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

local CELL_BORDER_TOTAL_PX = 2
local CELL_BORDER_PX       = CELL_BORDER_TOTAL_PX / 2
local copyMaterial         = Material "splashsweps/shaders/copy"
local detailCopyMaterial   = Material "splashsweps/shaders/copydetail"
local InkDetail            = locals.InkDetail

---@class ss.InkDetailAnimation
---@field Material IMaterial Lowest-index ink definition using this texture
---@field FrameVariable string Material parameter controlling the frame
---@field Frame integer Last frame copied to the cell

---@class ss.ProxiedInkMaterial
---@field Material IMaterial
---@field Index integer

---Draws the shared periodic-border mesh; the caller has set the cell transform and RT.
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

---Averages the smallest stored mipmap, including levels the engine may omit without ALL_MIPS.
---@param path string
---@return number
local function GetAverageHeight(path)
    if InkDetail.AverageHeights[path] then return InkDetail.AverageHeights[path] end
    local vtf = ss.ReadVTF(path)
    ss.assert(vtf, "Automatic height baseline has invalid texture (" .. path .. ")") ---@cast vtf -?
    local level = #vtf.Images
    local image = vtf.Images[level]
    local alpha = 0
    for y = 0, image.Height - 1 do
        for x = 0, image.Width - 1 do
            alpha = alpha + ss.ReadPixelFromVTF(vtf, x, y, level).a
        end
    end
    local average = alpha / (255 * image.Width * image.Height)
    InkDetail.AverageHeights[path] = average
    return average
end

---Reads VMT settings and encodes numeric RGBA rows shared with inkmesh_common.hlsl.
---Lua row j corresponds to shader row ID j - 1; image cell numbers are 1-based here.
---@param mat IMaterial The material of the ink type
---@param detailSlot integer? Grid cell of the detail image, nil if the ink type has none
---@param baseTextureName string Source of the automatic height baseline
---@return number[][] rows Data rows of four components each
local function EncodeInkTypeRows(mat, detailSlot, baseTextureName)
    local heightbaseline = mat:GetFloat "$heightbaseline" or -1
    if heightbaseline < 0 then heightbaseline = GetAverageHeight(baseTextureName) end
    local detailtexturetransform = mat:GetMatrix "$detailtexturetransform" or Matrix()
    local detailtransformscale   = detailtexturetransform:GetScale()
    local detailTranslationUV    = detailtexturetransform:GetTranslation()
    local detailRotationCosSin   = detailtexturetransform:GetForward():GetNormalized() -- (cos, sin, 0)
    local detailPeriodHU         = mat:GetFloat "$detailperiod" or 512
    local detailblendscale       = { mat:GetVector4D "$detailblendscale" }
    local detailheightsource     = math.Clamp(mat:GetInt "$detailheightsource" or 0, 0, 3)
    local detailheightinvert     = math.Clamp(mat:GetInt "$detailheightinvert" or 0, 0, 1)
    local heightLimitHU          = math.Clamp(mat:GetFloat "$detailheightmax" or 24, 0, 24)
    local heightLimitSqrtCode5   = math.Clamp(math.Round(math.sqrt(heightLimitHU / 24) * 32) - 1, 0, 31)
    local color                  = mat:GetVector "$color"     or ss.vector_one
    local tintcolor              = mat:GetVector "$tintcolor" or ss.vector_one
    local alpha                  = mat:GetFloat "$alpha" or 1
    local maxheight              = mat:GetFloat "$maxheight" or 1
    local normalBlendThicknessHU = mat:GetFloat "$bumpblendheight" or maxheight * 24
    return {
        { color.x,     color.y,     color.z,     alpha },
        { tintcolor.x, tintcolor.y, tintcolor.z, mat:GetFloat "$geometrypaintbias" or 0 },
        {
            (mat:GetInt "$maxlayers" or 1) / 255,
            maxheight,
            math.Remap(mat:GetFloat "$heightmapscale" or 1, -1, 1, 0, 1),
            heightbaseline,
        }, {
            mat:GetFloat "$erase"           or 0,
            mat:GetFloat "$flatten"         or 0,
            math.Clamp(normalBlendThicknessHU / 24, 0, 1),
            ((mat:GetInt "$nodig"      or 0) * 128 +
            (mat:GetInt  "$heightonly" or 0) * 64 +
            (mat:GetInt "$detaillocal" or 0) * 32) / 255,
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
            detailTranslationUV.x % 1,
            detailTranslationUV.y % 1,
            -- 127 / 255 represents zero
            (detailRotationCosSin.x + 1) * 127 / 255,
            (detailRotationCosSin.y + 1) * 127 / 255,
        }, {
            -- Image repeats per Hammer unit, log2 with 24 steps per octave from 2^-13
            (math.log(detailtransformscale.x / detailPeriodHU, 2) + 13) * 24 / 255,
            (math.log(detailtransformscale.y / detailPeriodHU, 2) + 13) * 24 / 255,
            ((detailSlot or 1) - 1) / 255, -- Grid index of the detail image
            -- bit 0: invert; bits 1..2: source (0 = off, 1 = thickness, 2 = height, 3 = depth).
            -- bits 3..7: sqrt-encode the height limit to give small limits finer steps within five bits.
            -- The 32 decoded levels stay above zero to avoid division by zero in the shader's height weight.
            (heightLimitSqrtCode5 * 8 + detailheightsource * 2 + detailheightinvert) / 255,
        },
    }
end

---Compares all drawing inputs with the snapshot saved after the last successful cell draw.
---Vector, Angle, and VMatrix compare their components with ==,
---while material and texture handles are compared by their names
---as getting the same resource again gives another handle.
---@param current any
---@param last any
---@return boolean
local function AreInputsEqual(current, last)
    if current == last then return true end
    local kind = TypeID(current)
    if kind ~= TypeID(last) then return false end
    if kind == TYPE_MATERIAL or kind == TYPE_TEXTURE then
        return current:GetName() == last:GetName()
    end
    if kind ~= TYPE_TABLE then return false end
    for key, value in pairs(current) do
        if not AreInputsEqual(value, last[key]) then return false end
    end
    for key in pairs(last) do
        if current[key] == nil then return false end
    end
    return true
end

---Draws the shared wrapping-border mesh in the caller's cell transform and RT context.
---@param material IMaterial
local function DrawCellMesh(material)
    render.SetMaterial(material)
    InkDetail.CellMesh:Draw()
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
        local animation = InkDetail.Animations[slot]
        local frame     = animation and (animation.Material:GetInt(animation.FrameVariable) or 0) or 0
        if animation then animation.Frame = frame end
        detailCopyMaterial:SetTexture("$basetexture", texture)
        detailCopyMaterial:SetInt("$frame", frame)
        cam.PushModelMatrix(InkDetail.CellTransforms[slot])
            DrawCellMesh(detailCopyMaterial)
        cam.PopModelMatrix()
    end
    for name, proxy in pairs(drawRequests) do
        cam.PushModelMatrix(InkDetail.CellTransforms[InkDetail.GeneratedCells[name]])
            -- An error in the drawing function must not leave the render target pushed.
            local drawn = ProtectedCall(proxy.Draw, proxy.State, DrawCellMesh)
        cam.PopModelMatrix()
        if drawn then InkDetail.LastStates[name] = ss.deepcopy(proxy.State) end
    end
    render.OverrideAlphaWriteEnable(false)
    render.OverrideBlend(false)
end

---Writes data rows of ink types below the grid cells so that they can be read in the shader.
---Automatic height baselines have already been resolved from the smallest stored mipmaps.
---The Details render target must be pushed and cam.Start2D() must be called beforehand.
---@param rowsByType table<integer, number[][]> Ink type index --> data rows from EncodeInkTypeRows()
local function WriteInkTypeRows(rowsByType)
    if not next(rowsByType) then return end
    local numRows = 0
    for i, rows in pairs(rowsByType) do
        numRows = numRows + #rows
        InkDetail.ParameterRows[i] = rows
    end

    copyMaterial:SetTexture("$basetexture", "color/white")
    copyMaterial:SetInt("$c0_x", 3)
    copyMaterial:SetInt("$c0_y", 1)
    render.SetMaterial(copyMaterial)
    render.OverrideBlend(true,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_POINTS, numRows)
    local imageAreaSizePx = ss.RenderTarget.DetailsImageSize
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
            local values  = proxies and proxies.Value ---@cast values ss.MaterialProxyKey[]?
            if inserts then
                values = values or {}
                MergeMaterialProxyKeys(values, inserts, false)
            end
            if values and replaces then MergeMaterialProxyKeys(values, replaces, true) end
            return values or {}
        end
        for _, action in ipairs { "insert", "replace" } do
            local section       = FindMaterialProxyKey(entries, action)
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
---@return boolean hasCellDrawProxy
local function ReadDetailProxyInfo(mat)
    local proxies          = ReadMaterialProxyKeys("materials/" .. mat:GetName() .. ".vmt")
    local frameVariable    = nil ---@type string?
    local hasCellDrawProxy = false
    for _, proxy in ipairs(proxies) do
        if proxy.Key == "animatedtexture" then
            local contents = proxy.Value ---@cast contents { Key: string, Value: string }[]
            local fields   = table.CollapseKeyValue(contents) ---@type table<string, string>
            if fields.animatedtexturevar and fields.animatedtexturevar:lower() == "$detail" then
                frameVariable = fields.animatedtextureframenumvar
            end
        elseif proxy.Key == "inkdetailupdate" then
            hasCellDrawProxy = true
        end
    end
    return #proxies > 0, frameVariable, hasCellDrawProxy
end

---Builds one reusable mesh containing a cell's center, edges, and corners.
---@param cellSizePx number Cell width in pixels, including both wrapping borders
local function BuildWrappedCellMesh(cellSizePx)
    if InkDetail.CellMesh then InkDetail.CellMesh:Destroy() end
    InkDetail.CellMesh = nil
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
    InkDetail.CellMesh = m
end

---Consumes the bind-time request queue, returning only requests with changed drawing inputs.
---@return table<string, ss.InkDetailProxy> drawRequests Changed drawing requests by material name
local function TakeChangedRequests()
    local drawRequests = {} ---@type table<string, ss.InkDetailProxy>
    for name, proxy in pairs(InkDetail.Requests) do
        if not AreInputsEqual(proxy.State, InkDetail.LastStates[name]) then
            drawRequests[name] = proxy
        end
        InkDetail.Requests[name] = nil
    end
    return drawRequests
end

---Consumes pending generated draws and writes selected images/encoded rows in one Details RT context.
---@param imageCells integer[]
---@param rowsByType table<integer, number[][]>
local function WriteAtlas(imageCells, rowsByType)
    local drawRequests = TakeChangedRequests()
    if #imageCells == 0 and not next(rowsByType) and not next(drawRequests) then return end
    local textures = {} ---@type table<integer, ITexture>
    for _, slot in ipairs(imageCells) do
        textures[slot] = InkDetail.CellImages[slot]
    end

    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
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
    for _, entry in ipairs(InkDetail.ProxiedMaterials) do
        render.SetMaterial(entry.Material) -- Ink definitions need an explicit bind to execute their proxies.
        local slot = InkDetail.Slots[entry.Index]
        local btstr = InkDetail.BaseTextureNames[entry.Index]
        local rows = EncodeInkTypeRows(entry.Material, slot, btstr)
        local changed = false
        for j, row in ipairs(rows) do
            for k, value in ipairs(row) do
                if value ~= InkDetail.ParameterRows[entry.Index][j][k] then changed = true end
            end
        end
        if changed then
            rowsByType[entry.Index] = rows
        end
    end
    local imageCells = {} ---@type integer[]
    for slot, animation in pairs(InkDetail.Animations) do
        if (animation.Material:GetInt(animation.FrameVariable) or 0) ~= animation.Frame then
            imageCells[#imageCells + 1] = slot
        end
    end
    WriteAtlas(imageCells, rowsByType)
end

---Lays out detail images of ink types, then creates the Details render target and the cell mesh.
---This also stops updating the render target until ss.WriteInitialInkDetailsRT() is called.
---@param baseTextureNames string[] $basetexture of each ink type, which also provides its average height
---@return number[][][]? rowsByType Data rows of each ink type, nil if there is no ink type
function ss.PrepareInkDetailsRT(baseTextureNames)
    hook.Remove("PreRender", "SplashSWEPs: Update ink materials")
    if #ss.InkTypes == 0 then return end

    local cellSizeSources  = {} ---@type ITexture[] Size source of every cell, including generated cells
    local cellImages       = {} ---@type table<integer, ITexture>
    local cache            = {} ---@type table<string, integer>
    local detailNames      = {} ---@type string[]
    local slots            = {} ---@type table<integer, integer>
    local animations       = {} ---@type table<integer, ss.InkDetailAnimation>
    local generatedCells   = {} ---@type table<string, integer>
    local proxiedMaterials = {} ---@type ss.ProxiedInkMaterial[]
    local rowsByType       = {} ---@type number[][][]
    for i, inktype in ipairs(ss.InkTypes) do
        local mat = Material(inktype.Identifier)
        local hasProxies, frameVariable, hasCellDrawProxy = ReadDetailProxyInfo(mat)
        copyMaterial:SetTexture("$basetexture", mat:GetString "$detail" or "???")
        local detail = copyMaterial:GetTexture "$basetexture"
        if detail then
            local name = detail:GetName()
            detailNames[i] = name
            inktype.DetailBlendMode = mat:GetInt "$detailblendmode" or 0
            if hasCellDrawProxy then
                -- The cell is owned by the material as its image differs from the source.
                cellSizeSources[#cellSizeSources + 1] = detail
                generatedCells[inktype.Identifier] = #cellSizeSources
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

        rowsByType[i] = EncodeInkTypeRows(mat, slots[i], baseTextureNames[i])
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
    ss.RenderTarget.DetailsImageSize = imageAreaSizePx
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
    local cellSizePx = gridColumns > 0 and imageAreaSizePx / gridColumns or 0
    BuildWrappedCellMesh(cellSizePx)
    for slot in ipairs(cellSizeSources) do
        local transform = Matrix()
        transform:SetTranslation(Vector(
            (slot - 1) % gridColumns * cellSizePx,
            math.floor((slot - 1) / gridColumns) * cellSizePx,
            0))
        InkDetail.CellTransforms[slot] = transform
    end
    ss.RenderTarget.StaticTextures.Details = GetRenderTargetEx(
        "splashsweps_details",
        atlasWidthPx, atlasHeightPx,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        -- NOLOD | ALL_MIPS | RENDERTARGET | NODEPTHBUFFER (RTs imply NOMIP).
        -- Detail images use bilinear filtering; numeric rows are read at texel centers.
        512 + 1024 + 32768 + 8388608, 0,
        IMAGE_FORMAT_RGBA8888)
    local drawInk         = Material "splashsweps/shaders/drawink"
    local inkMeshMaterial = Material "splashsweps/shaders/inkmesh"
    drawInk:SetFloat("$c3_w", imageAreaSizePx)
    inkMeshMaterial:SetFloat("$c3_w", imageAreaSizePx)
    inkMeshMaterial:SetFloat("$c1_x", gridColumns)
    inkMeshMaterial:SetFloat("$c1_z", 2 / ss.RenderTarget.HammerUnitsToUV)
    for _, materials in ipairs { ss.InkMeshMaterials, ss.StaticPropInkMaterials } do
        for material in pairs(materials) do
            material:SetFloat("$c3_w", imageAreaSizePx)
            material:SetFloat("$c1_x", gridColumns)
            material:SetFloat("$c1_z", 2 / ss.RenderTarget.HammerUnitsToUV)
        end
    end
    return rowsByType
end

---Writes the first contents of the Details render target prepared by ss.PrepareInkDetailsRT(),
---then starts updating it every frame if any ink type has material proxies or animated detail images.
---Generated cells are drawn by the first update.
---@param rowsByType number[][][] Data rows returned by ss.PrepareInkDetailsRT()
function ss.WriteInitialInkDetailsRT(rowsByType)
    render.PushRenderTarget(ss.RenderTarget.StaticTextures.Details)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
        WriteDetailCells(InkDetail.CellImages, {})
        WriteInkTypeRows(rowsByType)
    cam.End2D()
    render.PopRenderTarget()
    if #InkDetail.ProxiedMaterials > 0 or next(InkDetail.Animations) then
        hook.Add("PreRender", "SplashSWEPs: Update ink materials", UpdateFromMaterials)
    end
end

---Updates detail cells and ink type data.
---@param imageCells integer[] 1-based image cell numbers to copy
---@param inkTypes integer[] Ink type indices
function ss.WriteInkTypesRT(imageCells, inkTypes)
    local rowsByType = {} ---@type table<integer, number[][]>
    for _, i in ipairs(inkTypes) do
        rowsByType[i] = EncodeInkTypeRows(Material(ss.InkTypes[i].Identifier), InkDetail.Slots[i], InkDetail.BaseTextureNames[i])
    end
    WriteAtlas(imageCells, rowsByType)
end

---Registers a function called by InkDetailUpdate material proxy.
---The proxy block selects it by "updater" key, e.g.
---```
---"InkDetailUpdate"
---{
---    "updater" "myaddon/ripple"
---}
---```
---The updater records every drawing input in the state, which is kept per material,
---and returns the function to draw the cell.
---The cell is drawn only if the state differs from the one it was last drawn with.
---@param name string
---@param updater ss.InkDetailUpdater
function ss.RegisterInkDetailUpdate(name, updater)
    InkDetail.Updaters[name] = updater
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
    -- Bind collects inputs and queues work; drawing runs later in the Details RT context.
    bind = function(self, material)
        local name = material:GetName()
        if not InkDetail.GeneratedCells[name] then return end
        local updater = InkDetail.Updaters[self.Values.updater]
        if not updater then
            error(string.format("[SplashSWEPs] InkDetailUpdate: updater '%s' is not registered (%s)",
                tostring(self.Values.updater), name))
        end
        local draw = updater(self.State, material, self.Values)
        if draw then
            self.Draw = draw
            InkDetail.Requests[name] = self
        end
    end,
}
