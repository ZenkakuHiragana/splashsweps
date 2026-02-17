
---@class ss
local ss = SplashSWEPs
if not ss then return end

local LightmapInfoMeta = getmetatable(ss.new "PrecachedData.LightmapInfo")
local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation
local MIN_DRAW_RADIUS = 0.01 * 0.01 -- Squared minimum draw radius for static props relative to ScrH()

---@class ss.SurfaceBuilder.MaterialInfo
---@field ArrayIndex integer Index to material name array which is usually game.GetMap():GetMaterials()
---@field NeedsBumpedLightmaps boolean
---@field NeedsFrameBuffer boolean
---@field Envmap string? Value of $envmap
---@field Bumpmap string? Value of $bumpmap
---@field BaseTexture string? Value of $basetexture
---@field BumpTextureTransform string? Value of $bumptexturetransform
---@field BaseTextureTransform string? Value of $basetexturetransform
ss.struct "SurfaceBuilder.MaterialInfo" {
    ArrayIndex = 0,
    NeedsBumpedLightmaps = false,
    NeedsFrameBuffer = false,
    Envmap = nil,
    Bumpmap = nil,
    BaseTexture = nil,
    BumpTextureTransform = nil,
    BaseTextureTransform = nil,
}

---Stores pakced lightmap information for each SortID.
---@class ss.SurfaceBuilder.LightmapPackDetails
---@field FaceIndices    integer[] Array of index to surfaces that belong to this SortID.
---@field FaceLightmaps  Vector[]  Packed lightmap details for each face corresponding to FaceIndices.
---@field LightmapPage   integer   Assigned lightmap page for this SortID.
---@field LightmapWidths integer[] Array of width of lightmap corresponding to FaceIndices.
---@field Material       ss.SurfaceBuilder.MaterialInfo The material bound to this surface.
---@field TriangleCount  integer   Total number of triangles of this SortID.
ss.struct "SurfaceBuilder.LightmapPackDetails" {
    FaceIndices = {},
    FaceLightmaps = {},
    LightmapPage = 0,
    LightmapWidths = {},
    Material = nil, ---@type ss.SurfaceBuilder.MaterialInfo
    TriangleCount = 0,
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

---Sorts faces for lightmap packing, mimicking the engine's LightmapLess function.
---@param a ss.PrecachedData.LightmapInfo
---@param b ss.PrecachedData.LightmapInfo
---@return boolean
local function lightmapLess(a, b)
    -- 1. We want lightmapped surfaces to show up first
    local hasLightmapA = tobool(a.HasLightmap)
    local hasLightmapB = tobool(b.HasLightmap)
    if hasLightmapA ~= hasLightmapB then
        return hasLightmapA
    end

    -- 2. Then sort by material enumeration ID
    if a.MaterialIndex ~= b.MaterialIndex then
        return a.MaterialIndex < b.MaterialIndex
    end

    -- 3. We want NON-lightstyled surfaces to show up first
    local hasLightStylesA = a.HasLightmap and a.HasLightmap > 1 or false
    local hasLightStylesB = b.HasLightmap and b.HasLightmap > 1 or false
    if hasLightStylesA ~= hasLightStylesB then
        return not hasLightStylesA
    end

    -- 4. Then sort by lightmap area for better packing... (big areas first)
    local aArea = (a.Width or 0) * (a.Height or 0)
    local bArea = (b.Width or 0) * (b.Height or 0)
    return aArea > bArea
end

---Assigns enumeration ID to materials in the map,
---considering the global string table in the engine.
---@param materialsInMap string[]
---@return ss.SurfaceBuilder.MaterialInfo[] materialInfo
local function enumerateMaterials(materialsInMap)
    local materialNames = materialsInMap
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

    file.Write("splashsweps/material-names.json", util.TableToJSON(materialNames))
    local materialsInMapFlip = table.Flip(materialsInMap)
    for enumerationID, str in ipairs(materialNames) do
        enumerationIDToArrayIndex[enumerationID] = materialsInMapFlip[str]
    end

    ---Enumeration ID --> material information
    local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)
    local materialInfo = {} ---@type ss.SurfaceBuilder.MaterialInfo[]
    for enumerationID, name in ipairs(materialNames) do
        if enumerationIDToArrayIndex[enumerationID] then
            local mat = Material(name)
            if mat and not mat:IsError() then
                materialInfo[enumerationID] = {
                    ArrayIndex = enumerationIDToArrayIndex[enumerationID],
                    NeedsBumpedLightmaps = bit.band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0,
                    NeedsFrameBuffer = tobool(mat:GetString "$basetexture2"),
                    Envmap = mat:GetString "$envmap" or "shadertest/shadertest_env.hdr",
                    Bumpmap = mat:GetString "$bumpmap",
                    BaseTexture = mat:GetString "$basetexture",
                    BaseTextureTransform = mat:GetString "$basetexturetransform",
                    BumpTextureTransform = mat:GetString "$bumptransform",
                }
            end
        end
    end

    return materialInfo
end

local MAX_LIGHTMAP_WIDTH  = 512
local MAX_LIGHTMAP_HEIGHT = 256
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param materialInfo ss.SurfaceBuilder.MaterialInfo[]
---@return ss.SurfaceBuilder.LightmapPackResult lightmapInfo
local function packLightmaps(surfaceInfo, materialInfo)
    ---SortID --> Pakced lightmap details
    ---@type ss.SurfaceBuilder.LightmapPackResult
    local lightmapInfo = {
        Details = {},
        MaxLightmapIndex = 0,
        LastLightmapWidth = 0,
        LastLightmapHeight = 0,
    }

    local numSortIDs = 0
    local currentMaterialID = nil ---@type integer
    local currentWhiteLightmapMaterialID = nil ---@type integer
    local packers = {
        ss.MakeSkylinePacker(numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
    }

    -- Loop through sorted faces and pack them
    local sortableFaces = ss.CreateRBTree(lightmapLess)
    local arrayIndexToEnumerationID = {} ---@type table<integer, integer>
    for enumerationID, matInfo in pairs(materialInfo) do
        arrayIndexToEnumerationID[matInfo.ArrayIndex] = enumerationID
    end
    for _, t in ipairs(surfaceInfo.Lightmaps) do
        setmetatable(t, LightmapInfoMeta)
        t.MaterialIndex = arrayIndexToEnumerationID[t.MaterialIndex]
        sortableFaces:Insert(t)
    end

    for faceInfo in sortableFaces:Pairs() do
        local enumerationID = faceInfo.MaterialIndex
        if faceInfo.HasLightmap then
            local width  = faceInfo.Width + 1
            local height = faceInfo.Height + 1
            local mat    = materialInfo[enumerationID]
            if mat.NeedsBumpedLightmaps then width = width * 4 end

            -- Material change logic from CMatLightmaps::AllocateLightmap
            if currentMaterialID ~= enumerationID then
                -- When material changes, collapse all but the last
                packers = { packers[#packers] }
                ---Increments the sort ID of the packer.
                numSortIDs = numSortIDs + 1
                packers[1].SortID = packers[1].SortID + 1
                lightmapInfo.Details[numSortIDs] = {
                    FaceIndices = {},
                    FaceLightmaps = {},
                    LightmapPage = lightmapInfo.MaxLightmapIndex,
                    LightmapWidths = {},
                    Material = mat,
                    TriangleCount = 0,
                }

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
                    FaceIndices = {},
                    FaceLightmaps = {},
                    LightmapPage = lightmapInfo.MaxLightmapIndex,
                    LightmapWidths = {},
                    Material = mat,
                    TriangleCount = 0,
                }
            end

            ---@cast x -?
            ---@cast y -?
            if faceInfo.FaceIndex then
                local faceIndices = lightmapInfo.Details[packedSortID].FaceIndices
                local faceLightmaps = lightmapInfo.Details[packedSortID].FaceLightmaps
                local lightmapWidths = lightmapInfo.Details[packedSortID].LightmapWidths
                faceIndices[#faceIndices + 1] = faceInfo.FaceIndex
                faceLightmaps[#faceLightmaps + 1] = Vector(x, y)
                lightmapWidths[#lightmapWidths + 1] = faceInfo.Width + 1
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

---Construct IMesh
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param materialsInMap string[]
local function BuildInkMesh(surfaceInfo, materialsInMap)
    ---Model index ---> array of mesh construction info
    ---@type ss.SurfaceBuilder.MeshConstructionInfo[][]
    local meshInfoArrayOfArray   = {}
    local sortIDsToMeshInfoIndex = {} ---@type integer[][]
    local materialInfo           = enumerateMaterials(materialsInMap)
    local lightmapInfo           = packLightmaps(surfaceInfo, materialInfo)
    local maxLightmapIndex       = lightmapInfo.MaxLightmapIndex
    local lastPageWidth          = lightmapInfo.LastLightmapWidth
    local lastPageHeight         = lightmapInfo.LastLightmapHeight
    local bumpmapOffsets         = {} ---@type number[] faceIndex --> bumpmap offset
    for sortID, info in ipairs(lightmapInfo.Details) do
        local mat = info.Material
        for i, faceIndex in ipairs(info.FaceIndices) do
            local surf = setmetatable(surfaceInfo.Surfaces[faceIndex], SurfaceMeta)
            local lightmapWidth = info.LightmapWidths[i]
            local lightmapCoordinates = info.FaceLightmaps[i]
            local page = info.LightmapPage
            local isLastPage = page == maxLightmapIndex
            local pageWidth = isLastPage and lastPageWidth or MAX_LIGHTMAP_WIDTH
            local pageHeight = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
            bumpmapOffsets[faceIndex] = mat.NeedsBumpedLightmaps and lightmapWidth / pageWidth or 0
            for _, v in ipairs(surf.Vertices) do
                setmetatable(v, VertexMeta)
                v.LightmapUV.x = (v.LightmapUV.x + lightmapCoordinates.x) / pageWidth
                v.LightmapUV.y = (v.LightmapUV.y + lightmapCoordinates.y) / pageHeight
            end

            if not meshInfoArrayOfArray[surf.ModelIndex] then
                meshInfoArrayOfArray[surf.ModelIndex] = {}
                sortIDsToMeshInfoIndex[surf.ModelIndex] = {}
            end

            local meshInfoArray = meshInfoArrayOfArray[surf.ModelIndex]
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

    for _, infoArray in pairs(meshInfoArrayOfArray) do
        table.sort(infoArray, function(a, b) return a.SortID < b.SortID end)
    end

    local waterMaterial = Material "splashsweps/shader/inkmesh"
    local fbScale = ScrH() / (2 * math.tan(math.rad(LocalPlayer():GetFOV() * 0.5)))
    waterMaterial:SetFloat("$c1_y", fbScale)

    local rtIndex = #ss.RenderTarget.Resolutions
    local scale = surfaceInfo.UVScales[rtIndex]
    local worldToUV = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    for modelIndex, meshInfoArray in pairs(meshInfoArrayOfArray) do
        local meshIndex = 1
        local renderBatch = ss.RenderBatches[modelIndex]
        ---@class ss.SurfaceBuilder.MeshVertexPack
        ---@field Lift integer?
        ---@field Normal Vector
        ---@field TangentS    Vector
        ---@field TangentT    Vector
        ---@field Position    Vector
        ---@field U           number[]
        ---@field V           number[]
        ---@field UVRange     number[]
        ---@field InkTangent  number[]
        ---@field InkBinormal number[]
        local meshData = {} ---@type ss.SurfaceBuilder.MeshVertexPack[][]
        for _, meshInfo in ipairs(meshInfoArray) do
            local sortID = meshInfo.SortID
            local count = meshInfo.TriangleCount
            local numMeshesToAdd = math.ceil(count / MAX_TRIANGLES)
            if numMeshesToAdd > 0 then
                for _ = 1, numMeshesToAdd do
                    local info = lightmapInfo.Details[sortID]
                    local matinfo = info.Material
                    local page = info.LightmapPage
                    local lightmapTextureName = page and string.format("\\[lightmap%d]", page) or "white"
                    local envmapTextureName = matinfo.Envmap
                    local bumpmapTextureName = matinfo.Bumpmap
                    local baseTextureName = matinfo.NeedsFrameBuffer
                        and render.GetScreenEffectTexture(1):GetName() or matinfo.BaseTexture
                    local bump = matinfo.NeedsBumpedLightmaps and 1 or 0
                    local fb = fbScale * (matinfo.NeedsFrameBuffer and 1 or 0)
                    local uvScale = ss.RenderTarget.HammerUnitsToUV * 0.5
                    local params = {
                        ["$vertexshader"]           = "splashsweps/inkmesh_vs30",
                        ["$pixshader"]              = "splashsweps/inkmesh_ps30",
                        ["$basetexture"]            = ss.RenderTarget.StaticTextures.InkMap:GetName(),
                        ["$texture1"]               = ss.RenderTarget.StaticTextures.Details:GetName(),
                        ["$texture2"]               = ss.RenderTarget.StaticTextures.Params:GetName(),
                        ["$texture3"]               = baseTextureName,
                        ["$texture4"]               = bumpmapTextureName,
                        ["$texture5"]               = lightmapTextureName,
                        ["$texture6"]               = envmapTextureName,
                        ["$linearread_basetexture"] = "1",
                        ["$linearread_texture1"]    = "1",
                        ["$linearread_texture2"]    = "1",
                        ["$linearread_texture3"]    = "0",
                        ["$linearread_texture4"]    = "1",
                        ["$linearread_texture5"]    = "1",
                        ["$linearread_texture6"]    = "1",
                        ["$alpha_blend"]            = "1",
                        ["$alphablend"]             = "1",
                        ["$alphatested"]            = "0",
                        ["$cull"]                   = "1",
                        ["$depthtest"]              = "1",
                        ["$vertexalpha"]            = "1",
                        ["$vertexcolor"]            = "1",
                        ["$vertexnormal"]           = "1",
                        ["$tcsize0"]                = "4",
                        ["$tcsize1"]                = "4",
                        ["$tcsize2"]                = "3",
                        ["$tcsize3"]                = "3",
                        ["$tcsize4"]                = "3",
                        ["$tcsize5"]                = "3",
                        ["$tcsize6"]                = "4",
                        ["$c0_x"]                   = 0,     -- Sun direction x
                        ["$c0_y"]                   = 0.3,   -- Sun direction y
                        ["$c0_z"]                   = 0.954, -- Sun direction z
                        ["$c1_x"]                   = bump,  -- Indicates if having bumped lightmaps
                        ["$c1_y"]                   = fb,    -- Indicates if it needs frame buffer
                        ["$c1_z"]                   = uvScale,
                        ["$c1_w"]                   = 0,
                        ["$viewprojmat"]            = matinfo.BaseTextureTransform,
                        ["$invviewprojmat"]         = matinfo.BumpTextureTransform,
                    }
                    local mat = CreateMaterial(
                        string.format("splashsweps_mesh_%d_%s", sortID, game.GetMap()),
                        "Screenspace_General_8tex", params)
                    local matf = CreateMaterial(
                        string.format("splashsweps_meshf_%d_%s", sortID, game.GetMap()),
                        "LightmappedGeneric", {
                            ["$basetexture"] = "white",
                            ["$bumpmap"]     = bumpmapTextureName,
                        })
                    renderBatch[#renderBatch + 1] = {
                        Material = mat,
                        MaterialFlashlight = matf,
                        Mesh = Mesh(mat),
                        MeshFlashlight = Mesh(matf),
                    }
                end

                meshData[meshIndex] = {}
                local vertIndex = 1
                local function ContinueMesh()
                    if vertIndex - 1 < MAX_TRIANGLES * 3 then return end
                    meshIndex = meshIndex + 1
                    vertIndex = 1
                    meshData[meshIndex] = {}
                end

                for _, faceIndex in ipairs(meshInfo.FaceIndices) do
                    local surf = surfaceInfo.Surfaces[faceIndex]
                    local info = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
                    worldToUV:SetAngles(info.Angle)
                    for i, v in ipairs(surf.Vertices) do
                        local position = v.Translation
                        local normal = v.Normal
                        local tangent = v.Tangent
                        local binormal = v.Binormal
                        local s, t = v.LightmapUV.x, v.LightmapUV.y -- Lightmap UV
                        local uv = worldToUV * position
                        if v.DisplacementOrigin then
                            uv = worldToUV * v.DisplacementOrigin
                        end

                        -- I think I have to avoid constructing a temporary Vector just for this purpose
                        uv.x = uv.x + info.Translation.x * scale
                        uv.y = uv.y + info.Translation.y * scale
                        meshData[meshIndex][vertIndex] = {
                            Lift = math.Remap(v.LiftThisVertex or 2, 0, 3, 0, 1),
                            Normal = normal,
                            TangentS = tangent,
                            TangentT = binormal,
                            Position = position,
                            U = { uv.y, s, bumpmapOffsets[faceIndex], v.BumpmapUV.x },
                            V = { uv.x, t, 0,                         v.BumpmapUV.y },
                            UVRange = {
                                info.OffsetU,
                                info.OffsetV,
                                info.OffsetU + info.Width,
                                info.OffsetV + info.Height,
                            },
                            InkTangent = {
                                worldToUV:GetField(1, 1),
                                worldToUV:GetField(1, 2),
                                worldToUV:GetField(1, 3),
                                worldToUV:GetField(1, 4),
                            },
                            InkBinormal = {
                                worldToUV:GetField(2, 1),
                                worldToUV:GetField(2, 2),
                                worldToUV:GetField(2, 3),
                                worldToUV:GetField(2, 4),
                            },
                        }
                        vertIndex = vertIndex + 1
                        if (i - 1) % 3 == 2 then
                            ContinueMesh()
                        end
                    end
                end
                meshIndex = meshIndex + 1
            end
        end

        for i, vertices in ipairs(meshData) do
            mesh.Begin(renderBatch[i].Mesh, MATERIAL_TRIANGLES, #vertices / 3)
            for _, v in ipairs(vertices) do
                mesh.Normal(v.Normal)
                mesh.UserData(v.TangentS.x, v.TangentS.y, v.TangentS.z, 1)
                mesh.Position(v.Position)
                mesh.TexCoord(0, v.U[1], v.V[1], v.U[4], v.V[4])
                mesh.TexCoord(1, v.U[2], v.V[2], v.U[3], v.V[3])
                mesh.TexCoord(2, v.InkTangent[1], v.InkTangent[2], v.InkTangent[3], v.InkTangent[4])
                mesh.TexCoord(3, v.InkBinormal[1], v.InkBinormal[2], v.InkBinormal[3], v.InkBinormal[4])
                mesh.TexCoord(4, v.TangentS.x, v.TangentS.y, v.TangentS.z)
                mesh.TexCoord(5, v.TangentT.x, v.TangentT.y, v.TangentT.z)
                mesh.TexCoord(6, unpack(v.UVRange))
                mesh.Color(0, 0, 0, v.Lift * 255)
                mesh.AdvanceVertex()
            end
            mesh.End()

            mesh.Begin(renderBatch[i].MeshFlashlight, MATERIAL_TRIANGLES, #vertices / 3)
            for _, v in ipairs(vertices) do
                mesh.Normal(v.Normal)
                mesh.UserData(v.TangentS.x, v.TangentS.y, v.TangentS.z, 1)
                mesh.TangentS(v.TangentS)
                mesh.TangentT(v.TangentT)
                mesh.Position(v.Position)
                mesh.TexCoord(0, v.U[4], v.V[4]) -- Correctly bind geometry's bumpmap UV
                mesh.TexCoord(1, v.U[2], v.V[2])
                mesh.TexCoord(2, v.U[3], v.V[3])
                mesh.AdvanceVertex()
            end
            mesh.End()
        end
    end
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

    hook.Add("OnEntityCreated", "SplashSWEPs: Check brush entities", function(ent)
        local modelName = ent:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if i and 0 < i and i <= numModels then
            ss.RenderBatches[i + 1].BrushEntity = ent
        end
    end)

    for i = 1, numModels do
        ss.RenderBatches[i] = { BrushEntity = entities[i - 1] }
    end

    BuildInkMesh(surfaceInfo, materialNames)
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
    local matKeyValues = templateMaterial:GetKeyValues() ---@type table<string, string|number>
    local view = Matrix()
    matKeyValues["$flags"] = nil
    matKeyValues["$flags2"] = nil
    matKeyValues["$flags_defined"] = nil
    matKeyValues["$flags_defined2"] = nil
    matKeyValues["$basetexture"] = "splashsweps_inkmap"
    matKeyValues["$texture1"] = "splashsweps_params"
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
        local z = (view * self:GetPos()).x          -- projected z-position
        local fp = ScrH() / (2 * math.tan(fov / 2)) -- focus distance in pixels
        local r = self.ModelLengthSqr * fp * fp / (z * z)     -- draw radius on the screen in pixels
        local minRadius = MIN_DRAW_RADIUS * ScrH() * ScrH()
        if r < minRadius then return end
        render.MaterialOverride(dynamiclight)
        self:DrawModel(flags)
        render.MaterialOverride()
        render.OverrideDepthEnable(true, true)
        render.DepthRange(0, 65534 / 65535)
        self:DrawModel(flags)
        render.OverrideDepthEnable(false)
        render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD)
        render.MaterialOverride(flashlight)
        render.RenderFlashlights(function() self:DrawModel(flags) end)
        render.OverrideBlend(false)
        render.MaterialOverride()
        render.DepthRange(0, 1)
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
                local mins, maxs = mdl:GetModelBounds()
                mdl.FadeMaxSqr = fadeMax and (fadeMax * fadeMax)
                mdl.ModelLengthSqr = mins:DistToSqr(maxs)
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
                    ["$c1_x"] = 0,
                    ["$c0_w"] = prop.UnwrapIndex,
                })
                for j, name in ipairs(mdl:GetMaterials()) do
                    local mdlmat = materialCache[name] or Material(name)
                    local basetexture = mdlmat:GetTexture "$basetexture"
                    local mat = CreateMaterial("splashsweps/sprp" .. i .. "-" .. j, "Screenspace_General", params)
                    mat:SetMatrix("$viewprojmat", localTworld)
                    mat:SetMatrix("$invviewprojmat", absoluteuvTlocaluv)
                    mat:SetTexture("$texture2", basetexture:IsErrorTexture() and "grey" or basetexture)
                    mdl:SetSubMaterial(j - 1, "!" .. mat:GetName())
                    materialCache[name] = mdlmat
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
