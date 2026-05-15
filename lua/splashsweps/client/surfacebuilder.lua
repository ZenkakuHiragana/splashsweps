
---@class ss
local ss = SplashSWEPs
if not ss then return end

local LightmapInfoMeta    = getmetatable(ss.new "PrecachedData.LightmapInfo")
local StaticPropMeta      = getmetatable(ss.new "PrecachedData.StaticProp")
local StaticPropUVMeta    = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
local SurfaceMeta         = getmetatable(ss.new "PrecachedData.Surface")
local UVInfoMeta          = getmetatable(ss.new "PrecachedData.UVInfo")
local VertexMeta          = getmetatable(ss.new "PrecachedData.Vertex")
local MAX_TRIANGLES       = math.floor(32768 / 3) -- mesh library limitation
local MIN_DRAW_RADIUS     = 0.01 * 0.01 -- Squared minimum draw radius for static props relative to ScrH()
local MAX_LIGHTMAP_WIDTH  = 512
local MAX_LIGHTMAP_HEIGHT = 256

---One vertex worth of packed data passed to inkmesh_vs30.
---@class ss.SurfaceBuilder.MeshVertex
---@field Position           Vector   World-space position written with mesh.Position.
---@field Color              number[] xyz: unused                      w: displacement vertex alpha
---@field UVRange            number[] xy:  min ink-map UV,            zw: max ink-map UV for surface clipping.
---@field WorldTangent_U     number[] xyz: world tangent,              w: geometry texture U.
---@field WorldBinormal_V    number[] xyz: world binormal,             w: geometry texture V.
---@field WorldNormal_dU     number[] xyz: world normal,               w: bumped-lightmap U offset.
---@field InkTangent_U       number[] xyz: world-to-ink-UV first row,  w: ink U.
---@field InkBinormal_V      number[] xyz: world-to-ink-UV second row, w: ink V.
---@field LightmapTangent_U  number[] xyz: world lightmap tangent,     w: packed lightmap U.
---@field LightmapBinormal_V number[] xyz: world lightmap binormal,    w: packed lightmap V.
---@field SurfaceIndex       integer? Source BSP face index, kept for debug mesh inspection.

---A draw-sized vertex list that maps one-to-one to a render batch entry.
---@class ss.SurfaceBuilder.MeshVertexBatch
---@field SortID   integer Lightmap/material group ID used to choose the render material.
---@field Vertices ss.SurfaceBuilder.MeshVertex[] Vertices written into one IMesh.

---Material metadata needed to reproduce world surface shading in inkmesh.
---@class ss.SurfaceBuilder.MaterialInfo
---@field Material             IMaterial The source material.
---@field ArrayIndex           integer   Index to material name array which is usually game.GetMap():GetMaterials().
---@field NeedsBumpedLightmaps boolean   Whether the material uses 3 directional lightmaps plus the base lightmap.
---@field NeedsFrameBuffer     boolean   Whether albedo should be reconstructed from the current framebuffer.
---@field BaseTexture          string?   Value of $basetexture.
---@field Bumpmap              string?   Value of $bumpmap.
---@field Detail               string?   Value of $detail.
---@field BumpTextureTransform VMatrix?  Value of $bumptransform.
---@field BaseTextureTransform VMatrix?  Value of $basetexturetransform.
---@field DetailBlendFactor    number?   Value of $detailblendfactor.
---@field DetailBlendMode      integer?  Value of $detailblendmode.
---@field DetailScale          Vector?   Value of $detailscale.
---@field DetailTint           Vector?   Value of $detailtint.
---@field Color                Vector?   Value of $color.
ss.struct "SurfaceBuilder.MaterialInfo" {
    Material             = Material "color",
    ArrayIndex           = 0,
    NeedsBumpedLightmaps = false,
    NeedsFrameBuffer     = false,
    BaseTexture          = nil,
    Bumpmap              = nil,
    Detail               = nil,
    BumpTextureTransform = nil,
    BaseTextureTransform = nil,
    DetailBlendFactor    = nil,
    DetailBlendMode      = nil,
    DetailScale          = nil,
    DetailTint           = nil,
    Color                = nil,
}

---Stores packed lightmap information for each SortID.
---@class ss.SurfaceBuilder.LightmapGroup
---@field FaceIndices    integer[] Array of index to surfaces that belong to this SortID.
---@field FaceLightmaps  Vector[]  Packed lightmap top-left positions corresponding to FaceIndices.
---@field LightmapPage   integer   Assigned lightmap page for this SortID.
---@field LightmapWidths integer[] Original lightmap width per face, before bumped-lightmap expansion.
---@field Material       ss.SurfaceBuilder.MaterialInfo The material bound to this surface.
---@field TriangleCount  integer   Total number of triangles of this SortID.
ss.struct "SurfaceBuilder.LightmapGroup" {
    FaceIndices = {},
    FaceLightmaps = {},
    LightmapPage = 0,
    LightmapWidths = {},
    Material = nil, ---@type ss.SurfaceBuilder.MaterialInfo
    TriangleCount = 0,
}

---Packed lightmap atlas description consumed by mesh grouping and render materials.
---@class ss.SurfaceBuilder.LightmapLayout
---@field Groups ss.SurfaceBuilder.LightmapGroup[] SortID-indexed packed lightmap/material groups.
---@field MaxLightmapIndex   integer Last allocated lightmap page index.
---@field LastLightmapWidth  integer Minimum actual width required for the last lightmap page.
---@field LastLightmapHeight integer Minimum actual height required for the last lightmap page.
ss.struct "SurfaceBuilder.LightmapLayout" {
    Groups = {},
    MaxLightmapIndex = 0,
    LastLightmapWidth = 0,
    LastLightmapHeight = 0,
}

---Faces that share one model and one lightmap/material SortID before IMesh splitting.
---@class ss.SurfaceBuilder.MeshGroup
---@field FaceIndices   integer[] BSP face indices included in this group.
---@field SortID        integer   LightmapGroup key used to find material and lightmap texture.
---@field TriangleCount integer   Total triangle count before splitting by MAX_TRIANGLES.
ss.struct "SurfaceBuilder.MeshGroup" {
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
                local baseTexture2 = mat:GetString "$basetexture2"
                materialInfo[enumerationID] = {
                    Material             = mat,
                    ArrayIndex           = enumerationIDToArrayIndex[enumerationID],
                    NeedsBumpedLightmaps = bit.band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0,
                    NeedsFrameBuffer     = tobool(baseTexture2),
                    BaseTexture          = mat:GetString "$basetexture",
                    Bumpmap              = mat:GetString "$bumpmap",
                    Detail               = baseTexture2 or mat:GetString "$detail",
                    BaseTextureTransform = mat:GetMatrix "$basetexturetransform",
                    BumpTextureTransform = mat:GetMatrix "$bumptransform",
                    DetailBlendFactor    = mat:GetFloat  "$detailblendfactor",
                    DetailBlendMode      = mat:GetInt    "$detailblendmode",
                    DetailScale          = mat:GetVector "$detailscale",
                    DetailTint           = baseTexture2 and ss.vector_one or mat:GetVector "$detailtint",
                    Color = (mat:GetVector "$color" or ss.vector_one)
                          * (mat:GetVector "$color2" or ss.vector_one),
                }
            end
        end
    end

    return materialInfo
end

---Packs surface lightmaps into SortID groups that mirror Source lightmap allocation order.
---@param surfaceInfo  ss.PrecachedData.SurfaceInfo     Cached BSP surface and lightmap metadata.
---@param materialInfo ss.SurfaceBuilder.MaterialInfo[] Enumeration-ID-indexed material metadata.
---@return ss.SurfaceBuilder.LightmapLayout lightmapLayout Packed lightmap pages and SortID groups.
local function packLightmaps(surfaceInfo, materialInfo)
    ---SortID --> packed lightmap group
    ---@type ss.SurfaceBuilder.LightmapLayout
    local lightmapLayout = {
        Groups = {},
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
                lightmapLayout.Groups[numSortIDs] = {
                    FaceIndices    = {},
                    FaceLightmaps  = {},
                    LightmapPage   = lightmapLayout.MaxLightmapIndex,
                    LightmapWidths = {},
                    Material       = mat,
                    TriangleCount  = 0,
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
                lightmapLayout.MaxLightmapIndex = lightmapLayout.MaxLightmapIndex + 1
                packers[#packers + 1] = ss.MakeSkylinePacker(
                    numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
                x, y = packers[#packers]:AddBlock(width, height)
                packedSortID = numSortIDs
                lightmapLayout.Groups[numSortIDs] = {
                    FaceIndices    = {},
                    FaceLightmaps  = {},
                    LightmapPage   = lightmapLayout.MaxLightmapIndex,
                    LightmapWidths = {},
                    Material       = mat,
                    TriangleCount  = 0,
                }
            end

            ---@cast x -?
            ---@cast y -?
            if faceInfo.FaceIndex then
                local faceIndices    = lightmapLayout.Groups[packedSortID].FaceIndices
                local faceLightmaps  = lightmapLayout.Groups[packedSortID].FaceLightmaps
                local lightmapWidths = lightmapLayout.Groups[packedSortID].LightmapWidths
                faceIndices   [#faceIndices    + 1] = faceInfo.FaceIndex
                faceLightmaps [#faceLightmaps  + 1] = Vector(x, y)
                lightmapWidths[#lightmapWidths + 1] = faceInfo.Width + 1
            end
        elseif not currentMaterialID and currentWhiteLightmapMaterialID ~= enumerationID then
            if not currentMaterialID and not currentWhiteLightmapMaterialID then
                numSortIDs = numSortIDs + 1
            end
            currentWhiteLightmapMaterialID = enumerationID
        end
    end

    lightmapLayout.LastLightmapWidth,
    lightmapLayout.LastLightmapHeight
        = packers[#packers]:GetMinimumDimensions()
    return lightmapLayout
end

---Retrieves the size of lightmap page that contains given face index i in luxels.
---@param lightmapLayout ss.SurfaceBuilder.LightmapLayout
---@param lightmapGroup  ss.SurfaceBuilder.LightmapGroup
---@return integer pageWidth  The width of the page in luxels.
---@return integer pageHeight The height of the page in luxels.
local function getLightmapPageSize(lightmapLayout, lightmapGroup)
    local maxLightmapIndex = lightmapLayout.MaxLightmapIndex
    local lastPageWidth    = lightmapLayout.LastLightmapWidth
    local lastPageHeight   = lightmapLayout.LastLightmapHeight
    local page             = lightmapGroup.LightmapPage
    local isLastPage       = page == maxLightmapIndex
    local pageWidth        = isLastPage and lastPageWidth  or MAX_LIGHTMAP_WIDTH
    local pageHeight       = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
    return pageWidth, pageHeight
end

---Groups packed faces by model and SortID, while applying packed lightmap UVs to vertices.
---@param surfaceInfo    ss.PrecachedData.SurfaceInfo     Cached BSP surface data to update in-place.
---@param lightmapLayout ss.SurfaceBuilder.LightmapLayout Packed lightmap layout from packLightmaps.
---@return ss.SurfaceBuilder.MeshGroup[][] meshGroupsByModel    Model-indexed mesh groups.
---@return number[]                        bumpmapOffsetsByFace Face-indexed lightmap U offsets for bumped lightmaps.
local function buildMeshGroupsAndApplyLightmapUVs(surfaceInfo, lightmapLayout)
    ---Model index ---> mesh groups for that model
    ---@type ss.SurfaceBuilder.MeshGroup[][]
    local meshGroupsByModel      = {}
    local bumpmapOffsetsByFace   = {} ---@type number[] faceIndex --> bumpmap offset
    local sortIDToMeshGroupIndex = {} ---@type integer[][]
    for sortID, lightmapGroup in ipairs(lightmapLayout.Groups) do
        local materialInfo = lightmapGroup.Material
        local pageWidth, pageHeight = getLightmapPageSize(lightmapLayout, lightmapGroup)
        for i, faceIndex in ipairs(lightmapGroup.FaceIndices) do
            local surf = setmetatable(surfaceInfo.Surfaces[faceIndex], SurfaceMeta)
            local lightmapWidth = lightmapGroup.LightmapWidths[i]
            local lightmapCoordinates = lightmapGroup.FaceLightmaps[i]
            bumpmapOffsetsByFace[faceIndex] = materialInfo.NeedsBumpedLightmaps and lightmapWidth / pageWidth or 0
            for _, v in ipairs(surf.Vertices) do
                setmetatable(v, VertexMeta)
                v.LightmapUV.x = (v.LightmapUV.x + lightmapCoordinates.x) / pageWidth
                v.LightmapUV.y = (v.LightmapUV.y + lightmapCoordinates.y) / pageHeight
            end

            if not meshGroupsByModel[surf.ModelIndex] then
                meshGroupsByModel[surf.ModelIndex] = {}
                sortIDToMeshGroupIndex[surf.ModelIndex] = {}
            end

            local meshGroups = meshGroupsByModel[surf.ModelIndex]
            local meshGroupIndex = sortIDToMeshGroupIndex[surf.ModelIndex][sortID]
            if not meshGroupIndex then
                meshGroups[#meshGroups + 1] = {
                    FaceIndices = {},
                    SortID = sortID,
                    TriangleCount = 0,
                }
                sortIDToMeshGroupIndex[surf.ModelIndex][sortID] = #meshGroups
                meshGroupIndex = #meshGroups
            end
            local meshGroup = meshGroups[meshGroupIndex]
            meshGroup.FaceIndices[#meshGroup.FaceIndices + 1] = faceIndex
            meshGroup.TriangleCount = meshGroup.TriangleCount + #surf.Vertices / 3
        end
    end

    for _, meshGroups in pairs(meshGroupsByModel) do
        table.sort(meshGroups, function(a, b) return a.SortID < b.SortID end)
    end

    return meshGroupsByModel, bumpmapOffsetsByFace
end

---Builds the shared key-values for dynamic inkmesh materials.
---@return table<string, string|number|Vector|VMatrix> baseParams Common Screenspace_General_8tex parameters.
local function buildBaseInkMeshMaterialParams()
    return {
        ["$vertexshader"]           = "splashsweps/inkmesh_vs30",
        ["$pixshader"]              = "splashsweps/inkmesh_ps30",
        ["$basetexture"]            = ss.RenderTarget.StaticTextures.InkMap:GetName(),
        ["$texture1"]               = ss.RenderTarget.StaticTextures.Params:GetName(),
        ["$texture2"]               = "_rt_fullframefb1",
        ["$texture7"]               = ss.RenderTarget.StaticTextures.Details:GetName(),
        ["$linearread_basetexture"] = "1",
        ["$linearread_texture1"]    = "1",
        ["$linearread_texture2"]    = "0",
        ["$linearread_texture3"]    = "0",
        ["$linearread_texture4"]    = "1",
        ["$linearread_texture5"]    = "1",
        ["$linearread_texture6"]    = render.GetHDREnabled() and "1" or "0",
        ["$linearread_texture7"]    = "1",
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
        ["$tcsize2"]                = "4",
        ["$tcsize3"]                = "4",
        ["$tcsize4"]                = "4",
        ["$tcsize5"]                = "4",
        ["$tcsize6"]                = "4",
        ["$tcsize7"]                = "4",
        ["$c0_x"]                   = 0,     -- Sun direction x
        ["$c0_y"]                   = 0.3,   -- Sun direction y
        ["$c0_z"]                   = 0.954, -- Sun direction z
        ["$c1_z"]                   = ss.RenderTarget.HammerUnitsToUV * 0.5,
        ["$c1_w"]                   = 0,
    }
end

---Creates render material and IMesh containers for each vertex batch.
---@param lightmapLayout ss.SurfaceBuilder.LightmapLayout    SortID-indexed material and lightmap data.
---@param vertexBatches  ss.SurfaceBuilder.MeshVertexBatch[] Draw-sized vertex batches to mirror.
---@param renderBatch    ss.RenderBatch                      Destination render batch owned by ss.RenderBatches.
---@return ss.RenderBatch renderBatch The same render batch after appending mesh entries.
local function buildRenderBatches(lightmapLayout, vertexBatches, renderBatch)
    local m = Matrix()
    for _, vertexBatch in ipairs(vertexBatches) do
        local sortID                = vertexBatch.SortID
        local lightmapGroup         = lightmapLayout.Groups[sortID]
        local pageWidth, pageHeight = getLightmapPageSize(lightmapLayout, lightmapGroup)
        local materialInfo          = lightmapGroup.Material
        local page                  = lightmapGroup.LightmapPage
        local lightmapTextureName   = page and string.format("\\[lightmap%d]", page) or "white"
        local materialParams        = buildBaseInkMeshMaterialParams()
        local hasDetail             = tobool(materialInfo.Detail)
        local detailBlendMode       = materialInfo.DetailBlendMode or 0
        materialParams["$texture3"] = materialInfo.BaseTexture or "white"
        materialParams["$texture4"] = materialInfo.Bumpmap or "null-bumpmap"
        materialParams["$texture5"] = materialInfo.Detail or "white"
        materialParams["$texture6"] = lightmapTextureName
        materialParams["$linearread_texture5"] = detailBlendMode == 1 and "0" or "1"
        materialParams["$c0_w"]     = detailBlendMode
        materialParams["$c1_x"]     = materialInfo.NeedsBumpedLightmaps and 1 or 0
        materialParams["$c1_y"]     = materialInfo.NeedsFrameBuffer and 1 or 0
        materialParams["$c2_x"]     = 1 / pageWidth
        materialParams["$c2_y"]     = 1 / pageHeight
        materialParams["$c2_z"]     = materialInfo.DetailScale and materialInfo.DetailScale.x or 4
        materialParams["$c2_w"]     = materialInfo.DetailScale and materialInfo.DetailScale.y or 4
        materialParams["$c3_x"]     = materialInfo.Color and materialInfo.Color.x or 1
        materialParams["$c3_y"]     = materialInfo.Color and materialInfo.Color.y or 1
        materialParams["$c3_z"]     = materialInfo.Color and materialInfo.Color.z or 1
        materialParams["$c3_w"]     = hasDetail and (materialInfo.DetailBlendFactor or 1) or 0

        local mat = CreateMaterial(
            string.format("splashsweps_mesh_%d_%s", sortID, game.GetMap()),
            "Screenspace_General_8tex", materialParams)
        m:SetUnpacked(
            materialInfo.BaseTextureTransform:GetField(1, 1),
            materialInfo.BaseTextureTransform:GetField(1, 2),
            materialInfo.BaseTextureTransform:GetField(1, 4),
            materialInfo.DetailTint and materialInfo.DetailTint.x or 1,
            materialInfo.BaseTextureTransform:GetField(2, 1),
            materialInfo.BaseTextureTransform:GetField(2, 2),
            materialInfo.BaseTextureTransform:GetField(2, 4),
            materialInfo.DetailTint and materialInfo.DetailTint.y or 1,
            materialInfo.BumpTextureTransform:GetField(1, 1),
            materialInfo.BumpTextureTransform:GetField(1, 2),
            materialInfo.BumpTextureTransform:GetField(1, 4),
            materialInfo.DetailTint and materialInfo.DetailTint.z or 1,
            materialInfo.BumpTextureTransform:GetField(2, 1),
            materialInfo.BumpTextureTransform:GetField(2, 2),
            materialInfo.BumpTextureTransform:GetField(2, 4),
            0)
        mat:SetMatrix("$viewprojmat", m)
        local matf = CreateMaterial(
            string.format("splashsweps_meshf_%d_%s", sortID, game.GetMap()),
            "LightmappedGeneric", {
                ["$basetexture"] = "white",
                ["$bumpmap"]     = materialInfo.Bumpmap or "null-bumpmap",
            })
        ss.InkMeshMaterials[mat] = materialInfo.Material
        renderBatch[#renderBatch + 1] = {
            Material           = mat,
            MaterialFlashlight = matf,
            Mesh               = Mesh(mat),
            MeshFlashlight     = Mesh(matf),
        }
    end

    return renderBatch
end

---Expands mesh groups into draw-sized vertex batches for mesh.Begin.
---@param surfaceInfo ss.PrecachedData.SurfaceInfo  Cached BSP surface data with packed lightmap UVs applied.
---@param meshGroups  ss.SurfaceBuilder.MeshGroup[] Mesh groups for one BSP model.
---@param bumpmapOffsetsByFace number[]             Face-indexed lightmap U offsets for bumped lightmaps.
---@return ss.SurfaceBuilder.MeshVertexBatch[] vertexBatches Draw-sized vertex data batches.
local function buildMeshVertexBatches(surfaceInfo, meshGroups, bumpmapOffsetsByFace)
    local rtIndex       = #ss.RenderTarget.Resolutions
    local rtSize        = ss.RenderTarget.Resolutions[rtIndex]
    local bilinearGuard = ss.RT_BILINEAR_GUARD_PIXELS / rtSize
    local scale         = surfaceInfo.UVScales[rtIndex]
    local worldToUV     = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    local vertexBatches = {} ---@type ss.SurfaceBuilder.MeshVertexBatch[]
    for _, meshGroup in ipairs(meshGroups) do
        local currentVertices = nil ---@type ss.SurfaceBuilder.MeshVertex[]?
        local function StartVertexBatch()
            currentVertices = {}
            vertexBatches[#vertexBatches + 1] = {
                SortID = meshGroup.SortID,
                Vertices = currentVertices,
            }
        end

        local function ContinueVertexBatch()
            if not currentVertices then StartVertexBatch() end
            if #currentVertices < MAX_TRIANGLES * 3 then return end
            StartVertexBatch()
        end

        for _, faceIndex in ipairs(meshGroup.FaceIndices) do
            local surf = surfaceInfo.Surfaces[faceIndex]
            local uvInfo = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
            worldToUV:SetAngles(uvInfo.Angle)
            for _, v in ipairs(surf.Vertices) do
                ContinueVertexBatch()
                local tr = v.DispPaintOrigin or v.Translation
                local uv = worldToUV * tr + uvInfo.Translation * scale
                currentVertices[#currentVertices + 1] = {
                    Position = v.Translation,
                    Color = { 0, 0, 0, math.Clamp(v.BumpmapUV.z, 0, 255) },
                    UVRange = {
                        uvInfo.OffsetU + bilinearGuard,
                        uvInfo.OffsetV + bilinearGuard,
                        uvInfo.OffsetU + uvInfo.Width  - bilinearGuard,
                        uvInfo.OffsetV + uvInfo.Height - bilinearGuard,
                    },
                    WorldTangent_U = {
                        v.Tangent.x,
                        v.Tangent.y,
                        v.Tangent.z,
                        v.BumpmapUV.x,
                    },
                    WorldBinormal_V = {
                        v.Binormal.x,
                        v.Binormal.y,
                        v.Binormal.z,
                        v.BumpmapUV.y,
                    },
                    WorldNormal_dU = {
                        v.Normal.x,
                        v.Normal.y,
                        v.Normal.z,
                        bumpmapOffsetsByFace[faceIndex],
                    },
                    InkTangent_U = {
                        worldToUV:GetField(1, 1),
                        worldToUV:GetField(1, 2),
                        worldToUV:GetField(1, 3),
                        uv.y,
                    },
                    InkBinormal_V = {
                        worldToUV:GetField(2, 1),
                        worldToUV:GetField(2, 2),
                        worldToUV:GetField(2, 3),
                        uv.x,
                    },
                    LightmapTangent_U = {
                        v.LightmapTangent.x,
                        v.LightmapTangent.y,
                        v.LightmapTangent.z,
                        v.LightmapUV.x,
                    },
                    LightmapBinormal_V = {
                        v.LightmapBinormal.x,
                        v.LightmapBinormal.y,
                        v.LightmapBinormal.z,
                        v.LightmapUV.y,
                    },
                    SurfaceIndex = faceIndex,
                }
            end
        end
    end

    return vertexBatches
end

---Copies vertex batches into ss.DebugMeshData without exposing batch metadata.
---@param debugMeshData ss.SurfaceBuilder.MeshVertex[][]    Destination debug vertex lists.
---@param vertexBatches ss.SurfaceBuilder.MeshVertexBatch[] Source draw-sized vertex batches.
local function storeDebugMeshData(debugMeshData, vertexBatches)
    for _, vertexBatch in ipairs(vertexBatches) do
        local dest = {}
        for _, v in ipairs(vertexBatch.Vertices) do table.insert(dest, v) end
        table.insert(debugMeshData, dest)
    end
end

---Writes each vertex batch into the matching normal and flashlight IMesh.
---@param renderBatch   ss.RenderBatch                      Render entries created from the same vertexBatches order.
---@param vertexBatches ss.SurfaceBuilder.MeshVertexBatch[] Vertex batches to write one-to-one with renderBatch.
local function writeMeshVertexBatches(renderBatch, vertexBatches)
    for i, vertexBatch in ipairs(vertexBatches) do
        local vertices = vertexBatch.Vertices
        mesh.Begin(renderBatch[i].Mesh, MATERIAL_TRIANGLES, #vertices / 3)
        for _, v in ipairs(vertices) do
            mesh.Color(unpack(v.Color))
            mesh.Position(v.Position)
            mesh.Normal(v.WorldNormal_dU[1], v.WorldNormal_dU[2], v.WorldNormal_dU[3])
            mesh.TexCoord(0, unpack(v.UVRange))
            mesh.TexCoord(1, unpack(v.WorldTangent_U))
            mesh.TexCoord(2, unpack(v.WorldBinormal_V))
            mesh.TexCoord(3, 0, 0, 0, v.WorldNormal_dU[4])
            mesh.TexCoord(4, unpack(v.InkTangent_U))
            mesh.TexCoord(5, unpack(v.InkBinormal_V))
            mesh.TexCoord(6, unpack(v.LightmapTangent_U))
            mesh.TexCoord(7, unpack(v.LightmapBinormal_V))
            mesh.AdvanceVertex()
        end
        mesh.End()

        mesh.Begin(renderBatch[i].MeshFlashlight, MATERIAL_TRIANGLES, #vertices / 3)
        for _, v in ipairs(vertices) do
            mesh.Normal(v.WorldNormal_dU[1], v.WorldNormal_dU[2], v.WorldNormal_dU[3])
            mesh.UserData(v.WorldTangent_U[1], v.WorldTangent_U[2], v.WorldTangent_U[3], 1)
            mesh.TangentS(v.WorldTangent_U[1], v.WorldTangent_U[2], v.WorldTangent_U[3])
            mesh.TangentT(v.WorldBinormal_V[1], v.WorldBinormal_V[2], v.WorldBinormal_V[3])
            mesh.Position(v.Position)
            mesh.TexCoord(0, v.WorldTangent_U[4], v.WorldBinormal_V[4]) -- Correctly bind geometry's bumpmap UV
            mesh.TexCoord(1, v.LightmapTangent_U[4], v.LightmapBinormal_V[4])
            mesh.TexCoord(2, v.WorldNormal_dU[4], 0)
            mesh.AdvanceVertex()
        end
        mesh.End()
    end
end

---Coordinates material enumeration, lightmap packing, batching, and final IMesh construction.
---@param surfaceInfo    ss.PrecachedData.SurfaceInfo Cached BSP surface data used to build ink meshes.
---@param materialsInMap string[]                     Map material names, usually from game.GetMap():GetMaterials().
local function BuildInkMesh(surfaceInfo, materialsInMap)
    local materialInfo = enumerateMaterials(materialsInMap)
    local lightmapLayout = packLightmaps(surfaceInfo, materialInfo)
    local meshGroupsByModel, bumpmapOffsetsByFace = buildMeshGroupsAndApplyLightmapUVs(surfaceInfo, lightmapLayout)
    ss.BuildMaterialWatchList(materialInfo)

    ss.DebugMeshData = {} ---@type ss.SurfaceBuilder.MeshVertex[][]
    for modelIndex, meshGroups in pairs(meshGroupsByModel) do
        local vertexBatches = buildMeshVertexBatches(surfaceInfo, meshGroups, bumpmapOffsetsByFace)
        local renderBatch = buildRenderBatches(lightmapLayout, vertexBatches, ss.RenderBatches[modelIndex])
        storeDebugMeshData(ss.DebugMeshData, vertexBatches)
        writeMeshVertexBatches(renderBatch, vertexBatches)
    end
end

---Reads through BSP models which includes the worldspawn and brush entities and constructs IMeshes from them.
---@param surfaceInfo   ss.PrecachedData.SurfaceInfo
---@param numModels     integer
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
---@param modelNames     string[]
---@param uvInfo         ss.PrecachedData.StaticProp.UVInfo[][]
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
