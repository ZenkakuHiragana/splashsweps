
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band

-- From public/bspflags.h
local SURF_NOLIGHT = 0x0400

-- From public\materialsystem\imaterial.h
local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.SortableLightmapInfo.Surface
---@field Area integer Area of the lightmap used in sorting.
---@field FaceIndex integer Index to the LUMP_FACE array.
---@field HasLightmap boolean
---@field HasLightStyles boolean
---@field MaterialID integer Each material is assigned a number that groups it with like materials for sorting in the application.
ss.struct "SortableLightmapInfo.Surface" {
    Area = 0,
    FaceIndex = 0,
    HasLightmap = false,
    HasLightStyles = false,
    MaterialID = 0,
}

---@class ss.SortableLightmapInfo.Material
---@field MaxLightmapPage integer
---@field MinLightmapPage integer
---@field NeedsBumpedLightmaps boolean
ss.struct "SortableLightmapInfo.Material" {
    MaxLightmapPage = 0,
    MinLightmapPage = 0,
    NeedsBumpedLightmaps = false,
}

---Sorts faces for lightmap packing, mimicking the engine's LightmapLess function.
---@param a ss.SortableLightmapInfo.Surface
---@param b ss.SortableLightmapInfo.Surface
---@return boolean
local function lightmapLess(a, b)
    -- 1. We want lightmapped surfaces to show up first
    if a.HasLightmap ~= b.HasLightmap then
        return a.HasLightmap
    end

    -- 2. Then sort by material enumeration ID
    if a.MaterialID ~= b.MaterialID then
        return a.MaterialID < b.MaterialID
    end

    -- 3. We want Lightstyled surfaces to show up first
    if a.HasLightStyles ~= b.HasLightStyles then
        return a.HasLightStyles
    end

    -- 4. Then sort by lightmap area for better packing... (big areas first)
    if a.Area ~= b.Area then
        return a.Area > b.Area
    end

    return a.FaceIndex < b.FaceIndex
end

---Gets the minimum required dimensions for the packed image.
---@param self ss.SkylinePacker
---@return integer width
---@return integer height
local function GetMinimumDimensions(self)
    ---@param n integer
    ---@return integer
    local function ceilPow2(n)
        n = n - 1
        n = bit.bor(n, bit.rshift(n, 1))
        n = bit.bor(n, bit.rshift(n, 2))
        n = bit.bor(n, bit.rshift(n, 4))
        n = bit.bor(n, bit.rshift(n, 8))
        n = bit.bor(n, bit.rshift(n, 16))
        return n + 1
    end

    -- In the source code, it seems to get aspect ratio from HardwareConfig()->MaxTextureAspectRatio()
    -- but I will just hardcode it to 8 for now.
    local MAX_ASPECT_RATIO = 8

    local width = ceilPow2(self.MaxWidth)
    local height = ceilPow2(self.MinHeight)

    local aspect = width / height
    if aspect > MAX_ASPECT_RATIO then
        height = width / MAX_ASPECT_RATIO
    end

    return width, height
end

---Generates lightmap packing information for all faces in a BSP.
---@param bsp ss.RawBSPResults
---@param isHDR boolean
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param modelCache ss.PrecachedData.ModelInfo[]
function ss.BuildLightmapInfo(bsp, isHDR, surfaceInfo, modelCache)
    print("    Generating lightmap info (" .. (isHDR and "HDR" or "LDR") .. ")...")
    local faces = isHDR and bsp.FACES_HDR or bsp.FACES
    if not faces or #faces == 0 then return end

    local MAX_LIGHTMAP_WIDTH  = 512
    local MAX_LIGHTMAP_HEIGHT = 256
    local rawTexInfo   = bsp.TEXINFO
    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA

    -- Create a lookup table for material enumeration IDs, sorted alphabetically
    -- to match the engine's CMaterialDict iteration.
    local materialNames = table.Copy(rawTexString)
    table.sort(materialNames)
    local materialIDs = table.Flip(materialNames)

    -- Create a list of material tied to min/max lightmap pages
    ---@type ss.SortableLightmapInfo.Material[]
    local materialInfo = {}
    for i, name in ipairs(materialNames) do
        local mat = Material(name)
        if mat and not mat:IsError() then
            local isBumped = band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0
            materialInfo[i] = {
                MaxLightmapPage = 0,
                MinLightmapPage = 0,
                NeedsBumpedLightmaps = isBumped,
            }
        end
    end

    -- Create a list of face objects with all necessary info for sorting
    ---@type ss.SortableLightmapInfo.Surface[]
    local sortableFaces = {}
    for i, rawFace in ipairs(faces) do
        local texInfo    = rawTexInfo[rawFace.texInfo + 1]
        local texData    = rawTexData[texInfo.texData + 1]
        local texOffset  = rawTexDict[texData.nameStringTableID + 1]
        local texIndex   = rawTexIndex[texOffset]
        local texName    = rawTexString[texIndex]
        local materialID = materialIDs[texName] or 0
        local t = { ---@type ss.SortableLightmapInfo.Surface
            Area = rawFace.lightmapTextureSizeInLuxels[1] * rawFace.lightmapTextureSizeInLuxels[2],
            FaceIndex = i,
            HasLightmap = band(texInfo.flags, SURF_NOLIGHT) == 0 and rawFace.lightOffset >= 0,
            HasLightStyles = false, -- Check face.styles
            MaterialID = materialID,
        }
        for j = 1, 4 do
            if rawFace.styles[j] ~= 0 and rawFace.styles[j] ~= 255 then
                t.HasLightStyles = true
                break
            end
        end
        sortableFaces[#sortableFaces + 1] = t
    end

    -- Sort the faces
    table.sort(sortableFaces, lightmapLess)

    -- Initialize packers and result table
    local initialSortID = 1
    local packers = { ss.MakeSkylinePacker(
        initialSortID, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT) }

    ---Face lump index --> lightmap info
    ---@type { x: integer, y: integer, sortID: integer }[]
    local faceLightmapInfo = {}
    ---Sort ID --> material, lightmap page
    ---@type integer[]
    local sortIDToLightmapPage = {}
    local numSortIDs = 1
    local numLightmapPages = 0
    local currentMaterialID = nil ---@type integer

    -- Loop through sorted faces and pack them
    for _, faceInfo in ipairs(sortableFaces) do
        if faceInfo.HasLightmap then
            local face = faces[faceInfo.FaceIndex]
            local mat = materialInfo[faceInfo.MaterialID]
            local width = face.lightmapTextureSizeInLuxels[1] + 1
            local height = face.lightmapTextureSizeInLuxels[2] + 1
            if mat.NeedsBumpedLightmaps then width = width * 4 end

            -- Material change logic from CMatLightmaps::AllocateLightmap
            if currentMaterialID ~= faceInfo.MaterialID then
                -- When material changes, collapse all but the last packer
                packers = { packers[#packers] }
                if currentMaterialID then
                    ---Increments the sort ID of the packer.
                    packers[1].SortID = packers[1].SortID + 1
                    numSortIDs = numSortIDs + 1
                end

                currentMaterialID = faceInfo.MaterialID
                mat.MaxLightmapPage = numLightmapPages
                mat.MinLightmapPage = numLightmapPages
            end

            -- Try to pack into existing pages for this material group
            local packed = false
            for _, packer in ipairs(packers) do
                local x, y = packer:AddBlock(width, height)
                if x and y then
                    packed = true
                    sortIDToLightmapPage[packer.SortID] = numLightmapPages
                    faceLightmapInfo[faceInfo.FaceIndex] = {
                        x = x,
                        y = y,
                        sortID = packer.SortID,
                    }
                    break
                end
            end

            if not packed then
                -- Failed to fit, create a new page/packer for this material group
                local newPacker = ss.MakeSkylinePacker(
                    packers[1].SortID + 1, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
                local x, y = newPacker:AddBlock(width, height)
                if x and y then
                    numSortIDs = numSortIDs + 1
                    numLightmapPages = numLightmapPages + 1
                    packers[#packers + 1] = newPacker
                    mat.MaxLightmapPage = numLightmapPages
                    sortIDToLightmapPage[newPacker.SortID] = numLightmapPages
                    faceLightmapInfo[faceInfo.FaceIndex] = {
                        x = x,
                        y = y,
                        sortID = newPacker.SortID,
                    }
                else
                    -- This should not happen if the block is smaller than the page
                    print("WARNING: Lightmap block for material "
                        .. materialNames[faceInfo.MaterialID]
                        .. " is too large to fit in a new page!")
                end
            end
        end
    end

    for _, surf in ipairs(surfaceInfo.Surfaces) do
        local indexInLump = surf.FaceLumpIndex ---@cast indexInLump -?
        local info = faceLightmapInfo[indexInLump]
        if info then
            local face = faces[indexInLump]
            local texInfo = rawTexInfo[face.texInfo + 1]
            local width = face.lightmapTextureSizeInLuxels[1] + 1
            local height = face.lightmapTextureSizeInLuxels[2] + 1
            surf.LightmapPage = sortIDToLightmapPage[info.sortID]
            surf.LightmapX = info.x
            surf.LightmapY = info.y
            surf.LightmapWidth = width
            surf.LightmapHeight = height
            surf.MeshID = info.sortID

            local pageWidth = MAX_LIGHTMAP_WIDTH
            local pageHeight = MAX_LIGHTMAP_WIDTH
            if surf.LightmapPage == numLightmapPages then
                pageWidth, pageHeight = GetMinimumDimensions(packers[#packers])
            end
            if face.dispInfo >= 0 then
                for _, v in ipairs(surf.Vertices) do
                    local s = v.LightmapSamplePoint.x * width
                    local t = v.LightmapSamplePoint.y * height
                    v.LightmapUV.x = (s + info.x) / pageWidth
                    v.LightmapUV.y = (t + info.y) / pageHeight
                end
            else
                for _, v in ipairs(surf.Vertices) do
                    v.LightmapUV.x
                        = (v.Translation:Dot(texInfo.lightmapVecS)
                        + texInfo.lightmapOffsetS
                        - face.lightmapTextureMinsInLuxels[1]
                        + 0.5 + info.x) / pageWidth
                    v.LightmapUV.y
                        = (v.Translation:Dot(texInfo.lightmapVecT)
                        + texInfo.lightmapOffsetT
                        - face.lightmapTextureMinsInLuxels[2]
                        + 0.5 + info.y) / pageHeight
                end
            end
        end
    end

    table.sort(surfaceInfo.Surfaces, function(a, b) return a.MeshID < b.MeshID end)
    local modelIndices = {} ---@type integer[] Face index --> model index
    for modelIndex, lump in ipairs(bsp.MODELS) do
        for i = 1, lump.numFaces do
            modelIndices[lump.firstFace + i] = modelIndex
        end
    end

    for i = 1, numSortIDs + 1 do surfaceInfo.VertexCounts[i] = 0 end
    for i, surf in ipairs(surfaceInfo.Surfaces) do
        local id = surf.MeshID + 1 -- 1 is reserved for non-lightmapped surfaces
        surfaceInfo.VertexCounts[id]
            = surfaceInfo.VertexCounts[id] + #surf.Vertices
        local modelIndex = modelIndices[surf.FaceLumpIndex]
        local modelInfo = modelCache[modelIndex]
        modelInfo.FaceIndices[#modelInfo.FaceIndices + 1] = i
        modelInfo.NumTriangles = modelInfo.NumTriangles + #surf.Vertices
    end
end
