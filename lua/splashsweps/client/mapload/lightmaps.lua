
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
---@field SurfaceIndices  integer[] Indices to the surfaces of the map cache that belong to this SortID.
---@field LightmapOffsets Vector[]  Packed lightmap top-left positions corresponding to SurfaceIndices.
---@field LightmapPage    integer   Assigned lightmap page for this SortID.
---@field LightmapWidths  integer[] Original lightmap width per surface, before bumped-lightmap expansion.
---@field Material        ss.MapMaterials.MaterialInfo The material bound to this surface.
---@field TriangleCount   integer   Total number of triangles of this SortID.

---Packed lightmap atlas description consumed by mesh grouping and render materials.
---@class ss.Lightmaps.Layout
---@field Groups ss.Lightmaps.LightmapGroup[] SortID-indexed packed lightmap/material groups.
---@field LastPageIndex  integer              Last allocated lightmap page index.
---@field LastPageWidth  integer              Minimum actual width required for the last lightmap page.
---@field LastPageHeight integer              Minimum actual height required for the last lightmap page.

---Surfaces that share one model and one lightmap/material SortID before IMesh splitting.
---@class ss.Lightmaps.MeshGroup
---@field SurfaceIndices integer[] Indices to the surfaces of the map cache included in this group.
---@field SortID         integer   LightmapGroup key used to find material and lightmap texture.
---@field TriangleCount  integer   Total triangle count before splitting by MAX_TRIANGLES.

---A face to sort for lightmap packing.
---The engine sorts the faces by the enumeration ID of their materials in the material system.
---@class ss.Lightmaps.SortableFace
---@field Lightmap      ss.MapCache.LightmapInfo
---@field EnumerationID integer The enumeration ID of the material of the face.

---Sorts faces for lightmap packing, mimicking the engine's LightmapLess function.
---@param a ss.Lightmaps.SortableFace
---@param b ss.Lightmaps.SortableFace
---@return boolean
local function lightmapLess(a, b)
    local lightmapA, lightmapB = a.Lightmap, b.Lightmap

    -- 1. We want lightmapped surfaces to show up first
    local hasLightmapA = tobool(lightmapA.HasLightmap)
    local hasLightmapB = tobool(lightmapB.HasLightmap)
    if hasLightmapA ~= hasLightmapB then
        return hasLightmapA
    end

    -- 2. Then sort by material enumeration ID
    if a.EnumerationID ~= b.EnumerationID then
        return a.EnumerationID < b.EnumerationID
    end

    -- 3. We want NON-lightstyled surfaces to show up first
    local hasLightStylesA = lightmapA.HasLightmap and lightmapA.HasLightmap > 1 or false
    local hasLightStylesB = lightmapB.HasLightmap and lightmapB.HasLightmap > 1 or false
    if hasLightStylesA ~= hasLightStylesB then
        return not hasLightStylesA
    end

    -- 4. Then sort by lightmap area for better packing... (big areas first)
    local aArea = (lightmapA.Width or 0) * (lightmapA.Height or 0)
    local bArea = (lightmapB.Width or 0) * (lightmapB.Height or 0)
    return aArea > bArea
end

---Packs surface lightmaps into SortID groups that mirror Source lightmap allocation order.
---@param lightmaps    ss.MapCache.LightmapInfo[] Lightmap info of the faces the engine uses.
---@param materialInfo table<integer, ss.MapMaterials.MaterialInfo>
---@return ss.Lightmaps.Layout lightmapLayout Packed lightmap pages and SortID groups.
function Lightmaps.Pack(lightmaps, materialInfo)
    ---@type ss.Lightmaps.Layout
    local lightmapLayout = {
        Groups = {},
        LastPageIndex = 0,
        LastPageWidth = 0,
        LastPageHeight = 0,
    }

    local numSortIDs = 0
    local currentMaterialID = nil ---@type integer
    local currentWhiteLightmapMaterialID = nil ---@type integer
    local packers = {
        SkylinePacker.new(numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
    }

    -- Loop through sorted faces and pack them
    local arrayIndexToEnumerationID = {} ---@type table<integer, integer>
    for enumerationID, matInfo in pairs(materialInfo) do
        for _, arrayIndex in ipairs(matInfo.ArrayIndices) do
            arrayIndexToEnumerationID[arrayIndex] = enumerationID
        end
    end

    local sortableFaces = RBTree.new(lightmapLess)
    for _, t in ipairs(lightmaps) do
        ---@type ss.Lightmaps.SortableFace
        local face = { Lightmap = t, EnumerationID = arrayIndexToEnumerationID[t.MaterialIndex] }
        sortableFaces:Insert(face)
    end

    for face in sortableFaces:Pairs() do ---@cast face ss.Lightmaps.SortableFace
        local faceInfo = face.Lightmap
        local enumerationID = face.EnumerationID
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
                    SurfaceIndices  = {},
                    LightmapOffsets = {},
                    LightmapPage    = lightmapLayout.LastPageIndex,
                    LightmapWidths  = {},
                    Material        = mat,
                    TriangleCount   = 0,
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
                lightmapLayout.LastPageIndex = lightmapLayout.LastPageIndex + 1
                packers[#packers + 1] = SkylinePacker.new(
                    numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
                x, y = packers[#packers]:AddBlock(width, height)
                packedSortID = numSortIDs
                lightmapLayout.Groups[numSortIDs] = {
                    SurfaceIndices  = {},
                    LightmapOffsets = {},
                    LightmapPage    = lightmapLayout.LastPageIndex,
                    LightmapWidths  = {},
                    Material        = mat,
                    TriangleCount   = 0,
                }
            end

            ---@cast x -?
            ---@cast y -?
            if faceInfo.SurfaceIndex > 0 then
                local surfaceIndices  = lightmapLayout.Groups[packedSortID].SurfaceIndices
                local lightmapOffsets = lightmapLayout.Groups[packedSortID].LightmapOffsets
                local lightmapWidths  = lightmapLayout.Groups[packedSortID].LightmapWidths
                surfaceIndices [#surfaceIndices  + 1] = faceInfo.SurfaceIndex
                lightmapOffsets[#lightmapOffsets + 1] = Vector(x, y)
                lightmapWidths [#lightmapWidths  + 1] = faceInfo.Width + 1
            end
        elseif not currentMaterialID and currentWhiteLightmapMaterialID ~= enumerationID then
            if not currentMaterialID and not currentWhiteLightmapMaterialID then
                numSortIDs = numSortIDs + 1
            end
            currentWhiteLightmapMaterialID = enumerationID
        end
    end

    lightmapLayout.LastPageWidth,
    lightmapLayout.LastPageHeight
        = packers[#packers]:GetMinimumDimensions()
    return lightmapLayout
end

---Retrieves the size of the lightmap page of a lightmap group in luxels.
---@param lightmapLayout ss.Lightmaps.Layout
---@param lightmapGroup  ss.Lightmaps.LightmapGroup
---@return integer pageWidth
---@return integer pageHeight
function Lightmaps.GetPageSize(lightmapLayout, lightmapGroup)
    local lastPageIndex    = lightmapLayout.LastPageIndex
    local lastPageWidth    = lightmapLayout.LastPageWidth
    local lastPageHeight   = lightmapLayout.LastPageHeight
    local page             = lightmapGroup.LightmapPage
    local isLastPage       = page == lastPageIndex
    local pageWidth        = isLastPage and lastPageWidth  or MAX_LIGHTMAP_WIDTH
    local pageHeight       = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
    return pageWidth, pageHeight
end

---Groups packed surfaces by model and SortID.
---@param cache          ss.MapCache         The map cache.
---@param lightmapLayout ss.Lightmaps.Layout Packed lightmap layout from Lightmaps.Pack.
---@return ss.Lightmaps.MeshGroup[][] meshGroupsByModel    Model-indexed mesh groups.
function Lightmaps.BuildMeshGroups(cache, lightmapLayout)
    ---Model index ---> mesh groups for that model
    ---@type ss.Lightmaps.MeshGroup[][]
    local meshGroupsByModel      = {}
    local sortIDToMeshGroupIndex = {} ---@type integer[][]
    for sortID, lightmapGroup in ipairs(lightmapLayout.Groups) do
        for _, surfaceIndex in ipairs(lightmapGroup.SurfaceIndices) do
            local surf = cache.Surfaces[surfaceIndex]
            if not meshGroupsByModel[surf.ModelIndex] then
                meshGroupsByModel[surf.ModelIndex] = {}
                sortIDToMeshGroupIndex[surf.ModelIndex] = {}
            end

            local meshGroups = meshGroupsByModel[surf.ModelIndex]
            local meshGroupIndex = sortIDToMeshGroupIndex[surf.ModelIndex][sortID]
            if not meshGroupIndex then
                meshGroups[#meshGroups + 1] = {
                    SurfaceIndices = {},
                    SortID = sortID,
                    TriangleCount = 0,
                }
                sortIDToMeshGroupIndex[surf.ModelIndex][sortID] = #meshGroups
                meshGroupIndex = #meshGroups
            end
            local meshGroup = meshGroups[meshGroupIndex]
            meshGroup.SurfaceIndices[#meshGroup.SurfaceIndices + 1] = surfaceIndex
            meshGroup.TriangleCount = meshGroup.TriangleCount + surf.NumVertexIndices / 3
        end
    end

    for _, meshGroups in pairs(meshGroupsByModel) do
        table.sort(meshGroups, function(a, b) return a.SortID < b.SortID end)
    end

    return meshGroupsByModel
end

---Where the lightmap of a surface is in its lightmap page.
---The lightmap UV of a vertex in the page is (LightmapUV + (OffsetX, OffsetY)) / (PageWidth, PageHeight).
---@class ss.Lightmaps.SurfaceLightmap
---@field OffsetX       number  Left of the lightmap of the surface in the page in luxels.
---@field OffsetY       number  Top of the lightmap of the surface in the page in luxels.
---@field PageWidth     integer Width of the page in luxels.
---@field PageHeight    integer Height of the page in luxels.
---@field BumpmapOffset number  Lightmap U offset between bumped lightmaps, or 0 if the material has no bumped lightmaps.

---@param lightmapLayout ss.Lightmaps.Layout Packed lightmap layout from Lightmaps.Pack.
---@return ss.Lightmaps.SurfaceLightmap[] surfaceLightmaps Lightmap placements indexed by the surfaces of the map cache.
function Lightmaps.BuildSurfaceLightmaps(lightmapLayout)
    local surfaceLightmaps = {} ---@type ss.Lightmaps.SurfaceLightmap[]
    for _, lightmapGroup in ipairs(lightmapLayout.Groups) do
        local materialInfo = lightmapGroup.Material
        local pageWidth, pageHeight = Lightmaps.GetPageSize(lightmapLayout, lightmapGroup)
        for i, surfaceIndex in ipairs(lightmapGroup.SurfaceIndices) do
            local lightmapCoordinates = lightmapGroup.LightmapOffsets[i]
            local lightmapWidth = lightmapGroup.LightmapWidths[i]
            surfaceLightmaps[surfaceIndex] = {
                OffsetX       = lightmapCoordinates.x,
                OffsetY       = lightmapCoordinates.y,
                PageWidth     = pageWidth,
                PageHeight    = pageHeight,
                BumpmapOffset = materialInfo.NeedsBumpedLightmaps and lightmapWidth / pageWidth or 0,
            }
        end
    end

    return surfaceLightmaps
end

return Lightmaps
