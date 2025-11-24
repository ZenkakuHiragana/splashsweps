
---@class ss
local ss = SplashSWEPs
if not ss then return end

ss.Lightmaps = ss.Lightmaps or {}
local LightmapInfoMeta = getmetatable(ss.new "PrecachedData.LightmapInfo")
local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation
local MIN_DRAW_RADIUS = 0.015 -- minimum draw radius for static props relative to ScrH()

---@class ss.SurfaceBuilder.MaterialInfo
---@field NeedsBumpedLightmaps boolean
---@field Bumpmap string? Value of $bumpmap
---@field Bumpmap2 string? Value of $bumpmap2
ss.struct "SurfaceBuilder.MaterialInfo" {
    NeedsBumpedLightmaps = false,
    Bumpmap = nil,
    Bumpmap2 = nil,
}

---Stores pakced lightmap information for each SortID.
---@class ss.SurfaceBuilder.LightmapPackDetails
---@field Bumpmap       string    $bumpmap  that this kind of surfaces uses.
---@field Bumpmap2      string    $bumpmap2 that this kind of surfaces uses (WorldVertexTransition).
---@field LightmapPage  integer   Assigned lightmap page for this SortID.
---@field TriangleCount integer   Total number of triangles of this SortID.
---@field FaceIndices   integer[] Array of index to surfaces that belong to this SortID.
---@field FaceLightmaps { x: integer, y: integer }[] Packed lightmap details for each face corresponding to FaceIndices.
ss.struct "SurfaceBuilder.LightmapPackDetails" {
    Bumpmap = "",
    Bumpmap2 = "",
    LightmapPage = 0,
    TriangleCount = 0,
    FaceIndices = {},
    FaceLightmaps = {},
}

---@class ss.SurfaceBuilder.LightmapPackResult
---@field Details ss.SurfaceBuilder.LightmapPackDetails[]
---@field MaxLightmapIndex integer
---@field LastLightmapWidth integer
---@field LastLightmapHeight integer
ss.struct "SurfaceBuilder.LightmapPackResult" {
    Details = {},
    MaxLightmapIndex = 0,
    LastLightmapWidth = 0,
    LastLightmapHeight = 0,
}

---@class ss.SurfaceBuilder.MeshConstructionInfo
---@field FaceIndices   integer[]
---@field SortID        integer
---@field TriangleCount integer
ss.struct "SurfaceBuilder.MeshConstructionInfo" {
    FaceIndices = {},
    SortID = 0,
    TriangleCount = 0,
}

---Construct IMesh
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param renderBatches ss.RenderBatch[]
---@param materialsInMap string[]
local function BuildInkMesh(surfaceInfo, renderBatches, materialsInMap)
    ---Sorts faces for lightmap packing, mimicking the engine's LightmapLess function.
    ---@param a ss.PrecachedData.LightmapInfo
    ---@param b ss.PrecachedData.LightmapInfo
    ---@return boolean
    local function lightmapLess(a, b)
        -- 1. We want lightmapped surfaces to show up first
        if a.HasLightmap ~= b.HasLightmap then
            return tobool(a.HasLightmap)
        end

        -- 2. Then sort by material enumeration ID
        if a.MaterialIndex ~= b.MaterialIndex then
            return a.MaterialIndex < b.MaterialIndex
        end

        -- 3. We want NON-lightstyled surfaces to show up first
        if a.HasLightStyles ~= b.HasLightStyles then
            return not tobool(a.HasLightStyles)
        end

        -- 4. Then sort by lightmap area for better packing... (big areas first)
        return (a.Width - 1) * (a.Height - 1) > (b.Width - 1) * (b.Height - 1)
    end

    ---Assigns enumeration ID to materials in the map,
    ---considering the global string table in the engine.
    ---@return string[] enumeratedMaterials
    ---@return integer[] enumerationIDToArrayIndex
    local function enumerateMaterials()
        local materialNames = materialsInMap ---@type string[]
        local enumerationIDToArrayIndex = {} ---@type integer[]
        if not ss.IsFirstRunInSession() then
            materialNames = util.JSONToTable( ---@type string[]
                file.Read("splashsweps/material-names.json", "DATA") or "") or {}
            local materialNameAsKey = table.Flip(materialNames)
            for _, str in ipairs(materialsInMap) do
                if not materialNameAsKey[str] then
                    materialNames[#materialNames + 1] = str
                end
            end
        end

        local materialsInMapFlip = table.Flip(materialsInMap)
        for enumerationID, str in ipairs(materialNames) do
            enumerationIDToArrayIndex[enumerationID] = materialsInMapFlip[str]
        end

        file.Write("splashsweps/material-names.json", util.TableToJSON(materialNames))
        return materialNames, enumerationIDToArrayIndex
    end

    local MAX_LIGHTMAP_WIDTH  = 512
    local MAX_LIGHTMAP_HEIGHT = 256
    ---@param materialInfo ss.SurfaceBuilder.MaterialInfo[]
    ---@param enumerationIDToArrayIndex integer[]
    ---@return ss.SurfaceBuilder.LightmapPackResult lightmapInfo
    local function packLightmaps(materialInfo, enumerationIDToArrayIndex)
        ---SortID --> Pakced lightmap details
        ---@type ss.SurfaceBuilder.LightmapPackResult
        local lightmapInfo = {
            Details = {{
                Bumpmap = "",
                Bumpmap2 = "",
                FaceIndices = {},
                FaceLightmaps = {},
                LightmapPage = 0,
                TriangleCount = 0,
            }},
            MaxLightmapIndex = 0,
            LastLightmapWidth = 0,
            LastLightmapHeight = 0,
        }

        local numSortIDs = 1
        local currentMaterialID = nil ---@type integer
        local currentWhiteLightmapMaterialID = nil ---@type integer
        local packers = {
            ss.MakeSkylinePacker(numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
        }

        -- Loop through sorted faces and pack them
        local sortableFaces = ss.CreateRBTree(lightmapLess)
        local arrayIndexToEnumerationID = table.Flip(enumerationIDToArrayIndex)
        for _, t in ipairs(surfaceInfo.Lightmaps) do
            setmetatable(t, LightmapInfoMeta)
            t.MaterialIndex = arrayIndexToEnumerationID[t.MaterialIndex]
            sortableFaces:Insert(t)
        end

        for faceInfo in sortableFaces:Pairs() do
            local enumerationID = faceInfo.MaterialIndex
            if faceInfo.HasLightmap then
                local width  = faceInfo.Width ---@cast width -?
                local height = faceInfo.Height ---@cast height -?
                local mat = materialInfo[enumerationID]
                if mat.NeedsBumpedLightmaps then width = width * 4 end

                -- Material change logic from CMatLightmaps::AllocateLightmap
                if currentMaterialID ~= enumerationID then
                    -- When material changes, collapse all but the last
                    packers = { packers[#packers] }
                    if currentMaterialID then
                        ---Increments the sort ID of the packer.
                        numSortIDs = numSortIDs + 1
                        packers[1].SortID = packers[1].SortID + 1
                        lightmapInfo.Details[numSortIDs] = {
                            Bumpmap = mat.Bumpmap,
                            Bumpmap2 = mat.Bumpmap2,
                            FaceIndices = {},
                            FaceLightmaps = {},
                            LightmapPage = lightmapInfo.MaxLightmapIndex,
                            TriangleCount = 0,
                        }
                    end

                    currentMaterialID = enumerationID
                end

                -- Try to pack into existing pages for this material group
                local x ---@type integer?
                local y ---@type integer?
                local packedSortID = nil ---@type integer?
                for _, packer in ipairs(packers) do
                    x, y = packer:AddBlock(width, height)
                    if x and y then
                        packedSortID = packer.SortID
                        break
                    end
                end

                -- Failed to fit, create a new page/packer for this material group
                if not packedSortID then
                    numSortIDs = numSortIDs + 1
                    lightmapInfo.MaxLightmapIndex = lightmapInfo.MaxLightmapIndex + 1
                    packers[#packers + 1] = ss.MakeSkylinePacker(
                        numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
                    x, y = packers[#packers]:AddBlock(width, height)
                    packedSortID = numSortIDs
                    lightmapInfo.Details[numSortIDs] = {
                        Bumpmap = mat.Bumpmap,
                        Bumpmap2 = mat.Bumpmap2,
                        FaceIndices = {},
                        FaceLightmaps = {},
                        LightmapPage = lightmapInfo.MaxLightmapIndex,
                        TriangleCount = 0,
                    }
                end

                ---@cast x -?
                ---@cast y -?
                if faceInfo.FaceIndex then
                    local faceIndices = lightmapInfo.Details[packedSortID].FaceIndices
                    local faceLightmaps = lightmapInfo.Details[packedSortID].FaceLightmaps
                    faceIndices[#faceIndices + 1] = faceInfo.FaceIndex
                    faceLightmaps[#faceLightmaps + 1] = { x = x, y = y }
                end
            elseif not currentMaterialID and currentWhiteLightmapMaterialID ~= enumerationID then
                if not currentMaterialID and not currentWhiteLightmapMaterialID then
                    numSortIDs = numSortIDs + 1
                end
                currentWhiteLightmapMaterialID = enumerationID
            end
        end

        lightmapInfo.LastLightmapWidth,
        lightmapInfo.LastLightmapHeight
            = packers[#packers]:GetMinimumDimensions()
        return lightmapInfo
    end

    local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)
    local materialNames, enumerationIDToArrayIndex = enumerateMaterials()
    ---Enumeration ID --> material information
    ---@type ss.SurfaceBuilder.MaterialInfo[]
    local materialInfo = {}
    for enumerationID, name in ipairs(materialNames) do
        if enumerationIDToArrayIndex[enumerationID] then
            local mat = Material(name)
            materialInfo[enumerationID] = {
                NeedsBumpedLightmaps = mat and not mat:IsError() and
                    bit.band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0,
                Bumpmap = mat and mat:GetString "$bumpmap",
                Bumpmap2 = mat and mat:GetString "$bumpmap2",
            }
        end
    end

    ---Model index ---> array of mesh construction info
    ---@type ss.SurfaceBuilder.MeshConstructionInfo[][]
    local meshConstructionInfo = {}
    local sortIDsToMeshInfoIndex = {} ---@type integer[][]
    local lightmapInfo = packLightmaps(materialInfo, enumerationIDToArrayIndex)
    local maxLightmapIndex = lightmapInfo.MaxLightmapIndex
    local lastPageWidth    = lightmapInfo.LastLightmapWidth
    local lastPageHeight   = lightmapInfo.LastLightmapHeight
    for sortID, info in ipairs(lightmapInfo.Details) do
        for i, faceIndex in ipairs(info.FaceIndices) do
            local surf = setmetatable(surfaceInfo.Surfaces[faceIndex], SurfaceMeta)
            local lightmapCoordinates = info.FaceLightmaps[i]
            local page = info.LightmapPage
            local isLastPage = page == maxLightmapIndex
            local pageWidth = isLastPage and lastPageWidth or MAX_LIGHTMAP_WIDTH
            local pageHeight = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
            for _, v in ipairs(surf.Vertices) do
                setmetatable(v, VertexMeta)
                v.LightmapUV.x = (v.LightmapUV.x + lightmapCoordinates.x) / pageWidth
                v.LightmapUV.y = (v.LightmapUV.y + lightmapCoordinates.y) / pageHeight
            end

            if not meshConstructionInfo[surf.ModelIndex] then
                meshConstructionInfo[surf.ModelIndex] = {}
                sortIDsToMeshInfoIndex[surf.ModelIndex] = {}
            end

            local meshInfoArray = meshConstructionInfo[surf.ModelIndex]
            local meshInfoIndex = sortIDsToMeshInfoIndex[surf.ModelIndex][sortID]
            if not meshInfoIndex then
                meshInfoArray[#meshInfoArray + 1] = {
                    FaceIndices = {},
                    SortID = sortID,
                    TriangleCount = 0,
                }
                sortIDsToMeshInfoIndex[surf.ModelIndex][sortID] = #meshInfoArray
                meshInfoIndex = #meshInfoArray
            end
            local meshInfo = meshInfoArray[meshInfoIndex]
            meshInfo.FaceIndices[#meshInfo.FaceIndices + 1] = faceIndex
            meshInfo.TriangleCount = meshInfo.TriangleCount + #surf.Vertices / 3
        end
    end

    for _, infoArray in ipairs(meshConstructionInfo) do
        table.sort(infoArray, function(a, b) return a.SortID < b.SortID end)
    end

    local rtIndex = #ss.RenderTarget.Resolutions
    local scale = surfaceInfo.UVScales[rtIndex]
    local worldToUV = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    for modelIndex, meshInfoArray in ipairs(meshConstructionInfo) do
        local meshIndex = 1
        local renderBatch = renderBatches[modelIndex]
        for _, meshInfo in ipairs(meshInfoArray) do
            local sortID = meshInfo.SortID
            local count = meshInfo.TriangleCount
            local numMeshesToAdd = math.ceil(count / MAX_TRIANGLES)
            if numMeshesToAdd > 0 then
                for _ = 1, numMeshesToAdd do
                    local page = lightmapInfo.Details[sortID].LightmapPage
                    local isLast = page == lightmapInfo.MaxLightmapIndex
                    local width = isLast and lastPageWidth or 512
                    local height = isLast and lastPageHeight or 256
                    local rt = page and ss.CreateLightmapRT(page, width, height)
                    local mat = page and CreateMaterial(
                        string.format("splashsweps_lightmap_%d_%s", page, game.GetMap()),
                        "UnlitGeneric", {
                            ["$basetexture"] = string.format("\\[lightmap%d]", page),
                        })
                    if page then
                        ss.Lightmaps[page] = {
                            RT = rt,
                            Tex = mat:GetTexture "$basetexture",
                        }
                    end
                    renderBatch[#renderBatch + 1] = {
                        LightmapTexture = page and mat:GetTexture "$basetexture",
                        LightmapTextureRT = rt,
                        BrushBumpmap = lightmapInfo.Details[sortID].Bumpmap,
                        Mesh = Mesh(ss.InkMeshMaterial),
                    }
                end

                mesh.Begin(renderBatch[meshIndex].Mesh, MATERIAL_TRIANGLES, math.min(count, MAX_TRIANGLES))
                local function ContinueMesh()
                    if mesh.VertexCount() < MAX_TRIANGLES * 3 then return end
                    mesh.End()
                    mesh.Begin(
                        renderBatch[meshIndex + 1].Mesh, MATERIAL_TRIANGLES,
                        math.min(count - MAX_TRIANGLES * meshIndex, MAX_TRIANGLES))
                    meshIndex = meshIndex + 1
                end

                for _, faceIndex in ipairs(meshInfo.FaceIndices) do
                    local surf = surfaceInfo.Surfaces[faceIndex]
                    local info = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
                    local uvOrigin = Vector(info.OffsetU, info.OffsetV)
                    worldToUV:SetAngles(info.Angle)
                    worldToUV:SetTranslation(info.Translation * scale + uvOrigin)
                    for i, v in ipairs(surf.Vertices) do
                        local position = v.Translation
                        local normal = v.Angle:Up()
                        local tangent = v.Angle:Forward()
                        local binormal = -v.Angle:Right()
                        local s,  t  = v.LightmapUV.x, v.LightmapUV.y -- Lightmap UV
                        local uv = worldToUV * position
                        local w = normal:Cross(tangent):Dot(binormal) >= 0 and 1 or -1
                        if v.DisplacementOrigin then
                            uv = worldToUV * v.DisplacementOrigin
                        end
                        mesh.Normal(normal)
                        mesh.UserData(tangent.x, tangent.y, tangent.z, w)
                        mesh.TangentS(tangent * w)  -- These functions actually DO something
                        mesh.TangentT(binormal) -- in terms of bumpmap for LightmappedGeneric
                        mesh.Position(position)
                        mesh.TexCoord(0, uv.y, uv.x)
                        if t < 1 then
                            mesh.TexCoord(1, s, t)
                            mesh.Color(255, 255, 255, 255)
                        else
                            mesh.TexCoord(1, 1, 1)
                            local sample = render.GetLightColor(position)
                            local r = math.Round(sample.x ^ (1 / 2.2) / 2 * 255)
                            local g = math.Round(sample.y ^ (1 / 2.2) / 2 * 255)
                            local b = math.Round(sample.z ^ (1 / 2.2) / 2 * 255)
                            mesh.Color(r, g, b, 255)
                        end
                        mesh.AdvanceVertex()
                        if (i - 1) % 3 == 2 then
                            ContinueMesh()
                        end
                    end
                end
                mesh.End()
                meshIndex = meshIndex + 1
            end
        end
    end
end

---Adjusts light intensity of ink mesh material from HDR info.
---@param cache ss.PrecachedData
function ss.SetupHDRLighting(cache)
    setmetatable(cache.DirectionalLight, getmetatable(ss.new "PrecachedData.DirectionalLight"))
    local intensity = 128
    local color = cache.DirectionalLight.Color
    if color then -- If there is light_environment
        local lightIntensity = Vector(color.r, color.g, color.b):Dot(ss.GrayScaleFactor) / 255
        local brightness = color.a
        local scale = cache.DirectionalLight.ScaleHDR
        intensity = intensity + lightIntensity * brightness * scale
    end

    local value = ss.vector_one * intensity / 4096
    -- ss.InkMeshMaterial:SetVector("$color", value)
    -- ss.InkMeshMaterial:SetVector("$envmaptint", value / 16)
end

---Reads through BSP models which includes the worldspawn and brush entities and constructs IMeshes from them.
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param numModels integer
---@param materialNames string[]
function ss.SetupModels(surfaceInfo, numModels, materialNames)
    local entities = {} ---@type Entity[]
    for _, e in ipairs(ents.GetAll()) do
        local modelName = e:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if e ~= game.GetWorld() and i and 0 < i and i <= numModels then
            entities[i] = e
        end
    end

    hook.Add("OnEntityCreated", "SplashSWEPs: Check brush entities", function (ent)
        local modelName = ent:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if i and 0 < i and i <= numModels then
            ss.RenderBatches[i + 1].BrushEntity = ent
        end
    end)

    for i = 1, numModels do
        ss.RenderBatches[i] = { BrushEntity = entities[i - 1] }
    end

    BuildInkMesh(surfaceInfo, ss.RenderBatches, materialNames)
end

---Builds render override functions of static props.
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param modelNames string[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function ss.SetupStaticProps(staticPropInfo, modelNames, uvInfo)
    local templateMaterial = Material "splashsweps/shaders/staticprop"
    local dynamiclight = Material "splashsweps/shaders/phong"
    local flashlight = Material "splashsweps/shaders/vertexlitgeneric"
    local drawStaticProps = GetConVar "r_drawstaticprops"
    local materialCache = {} ---@type table<string, IMaterial>
    local matKeyValues = templateMaterial:GetKeyValues()
    local view = Matrix()
    matKeyValues["$flags"] = nil
    matKeyValues["$flags2"] = nil
    matKeyValues["$flags_defined"] = nil
    matKeyValues["$flags_defined2"] = nil
    matKeyValues["$basetexture"] = "splashsweps_basetexture"
    matKeyValues["$texture1"] = "splashsweps_bumpmap"
    matKeyValues["$texture3"] = "effects/flashlight001"
    matKeyValues["$c1_y"] = ss.RenderTarget.HammerUnitsToUV

    ---@param self ss.PaintableCSEnt
    ---@param flags Enum.STUDIO
    local function RenderOverride(self, flags)
        if LocalPlayer():KeyDown(IN_RELOAD) then return end
        if not drawStaticProps:GetBool() then return end
        if self.FadeMaxSqr and self:GetPos():DistToSqr(EyePos()) > self.FadeMaxSqr then return end
        view:SetTranslation(EyePos())
        view:SetAngles(EyeAngles())
        view:InvertTR()
        local fov = math.rad(render.GetViewSetup().fov)
        local z = (view * self:GetPos()).x -- projected z-position
        local fp = ScrH() / (2 * math.tan(fov / 2)) -- focus distance in pixels
        local r = self:GetModelRadius() * fp / z -- draw radius on the screen in pixels
        if math.abs(r) < MIN_DRAW_RADIUS * ScrH() then return end
        render.MaterialOverride(dynamiclight)
        self:DrawModel(flags)
        render.MaterialOverride()
        render.OverrideDepthEnable(true, true)
        self:DrawModel(flags)
        render.OverrideDepthEnable(false)
        render.RenderFlashlights(function()
            render.MaterialOverride(flashlight)
            self:DrawModel(flags)
            render.MaterialOverride(self.FlashlightMaterials[1])
            for i, m in ipairs(self.FlashlightMaterials) do
                render.MaterialOverrideByIndex(i - 1, m)
            end
            render.OverrideDepthEnable(true, true)
            self:DrawModel(flags)
            render.OverrideDepthEnable(false)
            render.MaterialOverrideByIndex()
            render.MaterialOverride()
        end)
    end

    -- Matrix(X, Y, Z) * xyzTyzx = (Y, Z, X)
    local xyzTyzx = Matrix {
        { 0, 0, 1, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 0, 1 },
    }
    -- xyzTzxy = xyzTyzx * xyzTyzx
    -- xyzTzxy * Vector(X, Y, Z) = (Y, Z, X)
    local xyzTzxy = xyzTyzx:GetTransposed()
    for i, prop in ipairs(staticPropInfo or {}) do
        setmetatable(prop, StaticPropMeta)
        local uv = setmetatable(uvInfo[i][#ss.RenderTarget.Resolutions], StaticPropUVMeta)
        local modelName = modelNames[prop.ModelIndex]
        if modelName then
            ---@class ss.PaintableCSEnt : CSEnt
            local mdl = ClientsideModel(modelName)
            if mdl then
                mdl:SetPos(prop.Position or Vector())
                mdl:SetAngles(prop.Angles or Angle())
                mdl:SetKeyValue("fademindist", prop.FadeMin or -1)
                mdl:SetKeyValue("fademaxdist", prop.FadeMax or 0)
                mdl:SetModelScale(prop.Scale or 1)
                mdl.RenderOverride = RenderOverride
                local fadeMax = prop.FadeMax and prop.FadeMax > 0 and prop.FadeMax or false
                mdl.FadeMaxSqr = fadeMax and (fadeMax * fadeMax)
                local size = prop.BoundsMax - prop.BoundsMin
                local absoluteuvTlocaluv = Matrix()
                if uv.Offset.z > 0 then
                    -- +--------> v
                    -- |   v'
                    -- |   ^
                    -- v   +---> u'
                    -- u    \__local texture space
                    absoluteuvTlocaluv:SetUnpacked(
                        0, -1, 0, uv.Offset.x + uv.Width,
                        1,  0, 0, uv.Offset.y,
                        0,  0, 1, uv.Offset.z,
                        0,  0, 0, 1)
                else
                    -- +--------> v
                    -- | local texture space
                    -- |   +---> v'
                    -- v   |
                    -- u   u'
                    absoluteuvTlocaluv:SetUnpacked(
                        1, 0, 0, uv.Offset.x,
                        0, 1, 0, uv.Offset.y,
                        0, 0, 1, uv.Offset.z,
                        0, 0, 0, 1)
                end
                local localTworld = mdl:GetWorldTransformMatrix()
                localTworld:SetTranslation(localTworld * prop.BoundsMin)
                if prop.UnwrapIndex == 2 then
                    -- (X, Y, Z) * xyzTyzx = (Y, Z, X)
                    localTworld:Mul(xyzTyzx)
                    size:Mul(xyzTzxy)
                elseif prop.UnwrapIndex == 3 then
                    -- (X, Y, Z) * xyzTzxy = (Z, X, Y)
                    localTworld:Mul(xyzTzxy)
                    size:Mul(xyzTyzx)
                end
                localTworld:InvertTR()

                local params = table.Merge(matKeyValues, {
                    ["$c0_x"] = size.x,
                    ["$c0_y"] = size.y,
                    ["$c0_z"] = size.z,
                    ["$c0_w"] = prop.UnwrapIndex,
                })
                mdl.FlashlightMaterials = {} ---@type IMaterial[]
                for j, name in ipairs(mdl:GetMaterials()) do
                    local mdlmat = materialCache[name] or Material(name)
                    local basetexture = mdlmat:GetTexture "$basetexture"

                    params["$additive"] = "0"
                    params["$c1_x"] = "0"
                    local mat = CreateMaterial("splashsweps/sprp" .. i .. "-" .. j, "Screenspace_General", params)
                    mat:SetMatrix("$viewprojmat", localTworld)
                    mat:SetMatrix("$invviewprojmat", absoluteuvTlocaluv)
                    mat:SetTexture("$texture2", basetexture:IsErrorTexture() and "grey" or basetexture)
                    mdl:SetSubMaterial(j - 1, "!" .. mat:GetName())
                    materialCache[name] = mdlmat

                    params["$additive"] = "1"
                    params["$c1_x"] = "1"
                    mat = CreateMaterial("splashsweps/sprpf" .. i .. "-" .. j, "Screenspace_General", params)
                    mat:SetMatrix("$viewprojmat", localTworld)
                    mat:SetMatrix("$invviewprojmat", absoluteuvTlocaluv)
                    mat:SetTexture("$texture2", basetexture:IsErrorTexture() and "grey" or basetexture)
                    mdl.FlashlightMaterials[j] = mat
                end
            end
        end
    end
end

-- function ss.PrepareInkSurface()
--     local minimapBounds = cache.MinimapBounds
--     ss.BuildWaterMesh()
--     ss.ClearAllInk()
--     ss.InitializeMoveEmulation(LocalPlayer())
--     net.Start "SplashSWEPs: Ready to splat"
--     net.WriteString(LocalPlayer():SteamID64() or "")
--     net.SendToServer()
--     ss.WeaponRecord[LocalPlayer()] = util.JSONToTable(
--     util.Decompress(file.Read "splashsweps/record/stats.txt" or "") or "") or {
--         Duration = {},
--         Inked = {},
--         Recent = {},
--     }
--     rt.Ready = true
--     collectgarbage "collect"
-- end
