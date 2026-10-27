
-- Packs the lightmaps of the map surfaces in the same layout as the engine does.

---@class ss
local ss = SplashSWEPs
local RBTree        = ss.import "splashsweps/client/mapload/rbtree"
local SkylinePacker = ss.import "splashsweps/client/mapload/skylinepacker"

---@class ss.LightmapsModule
local Lightmaps = ss.module "splashsweps/client/mapload/lightmaps"

local MAX_LIGHTMAP_WIDTH  = 512
local MAX_LIGHTMAP_HEIGHT = 256

---Stores packed lightmap information for each SortID.
---@class ss.Lightmaps.LightmapGroup
---@field FaceIndices    integer[] Array of index to surfaces that belong to this SortID.
---@field FaceLightmaps  Vector[]  Packed lightmap top-left positions corresponding to FaceIndices.
---@field LightmapPage   integer   Assigned lightmap page for this SortID.
---@field LightmapWidths integer[] Original lightmap width per face, before bumped-lightmap expansion.
---@field Material       ss.MapMaterials.MaterialInfo The material bound to this surface.
---@field TriangleCount  integer   Total number of triangles of this SortID.

---Packed lightmap atlas description consumed by mesh grouping and render materials.
---@class ss.Lightmaps.LightmapLayout
---@field Groups ss.Lightmaps.LightmapGroup[] SortID-indexed packed lightmap/material groups.
---@field MaxLightmapIndex   integer Last allocated lightmap page index.
---@field LastLightmapWidth  integer Minimum actual width required for the last lightmap page.
---@field LastLightmapHeight integer Minimum actual height required for the last lightmap page.

---Faces that share one model and one lightmap/material SortID before IMesh splitting.
---@class ss.Lightmaps.MeshGroup
---@field FaceIndices   integer[] BSP face indices included in this group.
---@field SortID        integer   LightmapGroup key used to find material and lightmap texture.
---@field TriangleCount integer   Total triangle count before splitting by MAX_TRIANGLES.

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

---Packs surface lightmaps into SortID groups that mirror Source lightmap allocation order.
---@param lightmaps    ss.PrecachedData.LightmapInfo[] Lightmap info of the faces the engine uses.
---@param materialInfo table<integer, ss.MapMaterials.MaterialInfo> Sparse enumeration-ID-indexed material metadata.
---@return ss.Lightmaps.LightmapLayout lightmapLayout Packed lightmap pages and SortID groups.
function Lightmaps.Pack(lightmaps, materialInfo)
    ---SortID --> packed lightmap group
    ---@type ss.Lightmaps.LightmapLayout
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
        SkylinePacker.new(numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
    }

    -- Loop through sorted faces and pack them
    local sortableFaces = RBTree.new(lightmapLess)
    local arrayIndexToEnumerationID = {} ---@type table<integer, integer>
    for enumerationID, matInfo in pairs(materialInfo) do
        arrayIndexToEnumerationID[matInfo.ArrayIndex] = enumerationID
    end
    for _, t in ipairs(lightmaps) do
        t.MaterialIndex = arrayIndexToEnumerationID[t.MaterialIndex]
        sortableFaces:Insert(t)
    end

    for faceInfo in sortableFaces:Pairs() do ---@cast faceInfo ss.PrecachedData.LightmapInfo
        local enumerationID = faceInfo.MaterialIndex
        if faceInfo.HasLightmap > 0 then
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
                packers[#packers + 1] = SkylinePacker.new(
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
            if faceInfo.FaceIndex > 0 then
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
---@param lightmapLayout ss.Lightmaps.LightmapLayout
---@param lightmapGroup  ss.Lightmaps.LightmapGroup
---@return integer pageWidth  The width of the page in luxels.
---@return integer pageHeight The height of the page in luxels.
function Lightmaps.GetPageSize(lightmapLayout, lightmapGroup)
    local maxLightmapIndex = lightmapLayout.MaxLightmapIndex
    local lastPageWidth    = lightmapLayout.LastLightmapWidth
    local lastPageHeight   = lightmapLayout.LastLightmapHeight
    local page             = lightmapGroup.LightmapPage
    local isLastPage       = page == maxLightmapIndex
    local pageWidth        = isLastPage and lastPageWidth  or MAX_LIGHTMAP_WIDTH
    local pageHeight       = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
    return pageWidth, pageHeight
end

---Groups packed faces by model and SortID.
---@param surfaceInfo    ss.PrecachedData.SurfaceInfo Cached BSP surface data.
---@param lightmapLayout ss.Lightmaps.LightmapLayout Packed lightmap layout from Lightmaps.Pack.
---@return ss.Lightmaps.MeshGroup[][] meshGroupsByModel    Model-indexed mesh groups.
function Lightmaps.BuildMeshGroups(surfaceInfo, lightmapLayout)
    ---Model index ---> mesh groups for that model
    ---@type ss.Lightmaps.MeshGroup[][]
    local meshGroupsByModel      = {}
    local sortIDToMeshGroupIndex = {} ---@type integer[][]
    for sortID, lightmapGroup in ipairs(lightmapLayout.Groups) do
        for _, faceIndex in ipairs(lightmapGroup.FaceIndices) do
            local surf = surfaceInfo.Surfaces[faceIndex]
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
            meshGroup.TriangleCount = meshGroup.TriangleCount + surf.NumVertexIndices / 3
        end
    end

    for _, meshGroups in pairs(meshGroupsByModel) do
        table.sort(meshGroups, function(a, b) return a.SortID < b.SortID end)
    end

    return meshGroupsByModel
end

---Where the lightmap of a face is in its lightmap page.
---The lightmap UV of a vertex in the page is (LightmapUV + (OffsetX, OffsetY)) / (PageWidth, PageHeight).
---@class ss.Lightmaps.FaceLightmap
---@field OffsetX       number  Left of the lightmap of the face in the page in luxels.
---@field OffsetY       number  Top of the lightmap of the face in the page in luxels.
---@field PageWidth     integer Width of the page in luxels.
---@field PageHeight    integer Height of the page in luxels.
---@field BumpmapOffset number  Lightmap U offset between bumped lightmaps, or 0 if the material has no bumped lightmaps.

---@param lightmapLayout ss.Lightmaps.LightmapLayout Packed lightmap layout from Lightmaps.Pack.
---@return ss.Lightmaps.FaceLightmap[] faceLightmaps Face-indexed lightmap placements.
function Lightmaps.BuildFaceLightmaps(lightmapLayout)
    local faceLightmaps = {} ---@type ss.Lightmaps.FaceLightmap[]
    for _, lightmapGroup in ipairs(lightmapLayout.Groups) do
        local materialInfo = lightmapGroup.Material
        local pageWidth, pageHeight = Lightmaps.GetPageSize(lightmapLayout, lightmapGroup)
        for i, faceIndex in ipairs(lightmapGroup.FaceIndices) do
            local lightmapCoordinates = lightmapGroup.FaceLightmaps[i]
            local lightmapWidth = lightmapGroup.LightmapWidths[i]
            faceLightmaps[faceIndex] = {
                OffsetX       = lightmapCoordinates.x,
                OffsetY       = lightmapCoordinates.y,
                PageWidth     = pageWidth,
                PageHeight    = pageHeight,
                BumpmapOffset = materialInfo.NeedsBumpedLightmaps and lightmapWidth / pageWidth or 0,
            }
        end
    end

    return faceLightmaps
end

return Lightmaps
