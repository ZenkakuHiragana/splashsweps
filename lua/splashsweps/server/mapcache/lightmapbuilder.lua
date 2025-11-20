
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
---@field Bumpmap string? Value of $bumpmap
---@field Bumpmap2 string? Value of $bumpmap2
ss.struct "SortableLightmapInfo.Material" {
    MaxLightmapPage = 0,
    MinLightmapPage = 0,
    NeedsBumpedLightmaps = false,
    Bumpmap = nil,
    Bumpmap2 = nil,
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

    -- 3. We want NON-lightstyled surfaces to show up first
    if a.HasLightStyles ~= b.HasLightStyles then
        return b.HasLightStyles
    end

    -- 4. Then sort by lightmap area for better packing... (big areas first)
    return a.Area > b.Area
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
---@param ishdr boolean
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
function ss.BuildLightmapInfo(bsp, ishdr, surfaceInfo)
    print("    Generating lightmap info (" .. (ishdr and "HDR" or "LDR") .. ")...")
    local faces = ishdr and bsp.FACES_HDR or bsp.FACES
    if not faces or #faces == 0 then return end

    local MAX_LIGHTMAP_WIDTH  = 512
    local MAX_LIGHTMAP_HEIGHT = 256
    local rawTexInfo   = bsp.TEXINFO
    local rawTexData   = bsp.TEXDATA
    local rawTexDict   = bsp.TEXDATA_STRING_TABLE
    local rawTexIndex  = bsp.TexDataStringTableToIndex
    local rawTexString = bsp.TEXDATA_STRING_DATA
    local rawSamples   = ishdr and bsp.LIGHTING_HDR or bsp.LIGHTING
    local power2 ---@type number[]

    -- FIXME: Enumeration IDs vary among sessions!!!
    --        Simulate the global symbol table to fix this!!!
    -- Create a lookup table for material enumeration IDs,
    -- which seems the same as the order in the BSP.
    local materialIDs = table.Flip(rawTexString)

    -- Create a list of material tied to min/max lightmap pages
    ---@type ss.SortableLightmapInfo.Material[]
    local materialInfo = {}
    for i, name in ipairs(rawTexString) do
        local mat = Material(name)
        if mat and not mat:IsError() then
            local isBumped = band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0
            materialInfo[i] = {
                MaxLightmapPage = -1,
                MinLightmapPage = -1,
                NeedsBumpedLightmaps = isBumped,
                Bumpmap = mat:GetString "$bumpmap",
                Bumpmap2 = mat:GetString "$bumpmap2",
            }
        end
    end

    -- Create a list of face objects with all necessary info for sorting
    local sortableFaces = ss.CreateRBTree(lightmapLess)
    for i, rawFace in ipairs(faces) do
        local texInfo     = rawTexInfo[rawFace.texInfo + 1]
        local texData     = rawTexData[texInfo.texData + 1]
        local texOffset   = rawTexDict[texData.nameStringTableID + 1]
        local texIndex    = rawTexIndex[texOffset]
        local texName     = rawTexString[texIndex]
        local materialID  = materialIDs[texName] or 0
        local lightOffset = rawFace.lightOffset + 1
        local lightStyles = rawFace.styles
        local width       = rawFace.lightmapTextureSizeInLuxels[1]
        local height      = rawFace.lightmapTextureSizeInLuxels[2]
        local area        = width * height
        local t = {
            Area = area,
            FaceIndex = i,
            HasLightmap = band(texInfo.flags, SURF_NOLIGHT) == 0 and
                          lightOffset > 0 and area > 0,
            HasLightStyles = lightStyles[1] ~= 0 and
                             lightStyles[1] ~= 255 or
                             lightStyles[2] ~= 255,
            MaterialID = materialID,
        }
        -- CheckSurfaceLighting
        if t.HasLightStyles then
            if not power2 then
                power2 = {}
                for exp = 0, 255 do
                    power2[exp] = math.pow(2, exp - 128)
                end
            end

            local minLightValue = 1 / 1023
            local maxLightmapIndex = 1
            local offset = (width + 1) * (height + 1)
            if materialInfo[materialID].NeedsBumpedLightmaps then
                offset = offset * 4
            end

            while lightStyles[maxLightmapIndex + 1] and lightStyles[maxLightmapIndex + 1] ~= 255 do
                maxLightmapIndex = maxLightmapIndex + 1
            end

            for j = maxLightmapIndex, 0, -1 do
                local maxLength = -1
                local maxR, maxG, maxB ---@type number, number, number
                for k = 0, offset - 1 do
                    local ptr = lightOffset + ((j - 1) * offset + k) * 4
                    local r, g, b, e = rawSamples:byte(ptr, ptr + 3)
                    local length = r * r + g * g + b * b
                    if length > maxLength then
                        maxLength = length
                        -- TexLightToLinear
                        maxR = r * power2[e]
                        maxG = g * power2[e]
                        maxB = b * power2[e]
                    end
                end
                if maxR < minLightValue and maxG < minLightValue and maxB < minLightValue then
                    maxLightmapIndex = maxLightmapIndex - 1
                end
            end

            t.HasLightStyles = maxLightmapIndex > 1
        end
        sortableFaces:Insert(t)
    end

    -- Initialize packers and result table
    local initialSortID = 1
    local packers = {
        ss.MakeSkylinePacker(
            initialSortID,
            MAX_LIGHTMAP_WIDTH,
            MAX_LIGHTMAP_HEIGHT)
    }

    ---Face lump index --> lightmap info
    ---@type { x: integer, y: integer, sortID: integer, mat: ss.SortableLightmapInfo.Material }[]
    local faceLightmapInfo = {}
    local numSortIDs = 1
    local numLightmapPages = 0
    local currentMaterialID = nil ---@type integer
    local currentWhiteLightmapMaterialID = nil ---@type integer
    surfaceInfo.LightmapPages[1] = 0

    -- Loop through sorted faces and pack them
    for faceInfo in sortableFaces:Pairs() do
        local face = faces[faceInfo.FaceIndex]
        local mat  = materialInfo[faceInfo.MaterialID]
        if faceInfo.HasLightmap then
            local width  = face.lightmapTextureSizeInLuxels[1] + 1
            local height = face.lightmapTextureSizeInLuxels[2] + 1
            if mat.NeedsBumpedLightmaps then width = width * 4 end

            -- Material change logic from CMatLightmaps::AllocateLightmap
            if currentMaterialID ~= faceInfo.MaterialID then
                -- When material changes, collapse all but the last packer
                packers = { packers[#packers] }
                if currentMaterialID then
                    ---Increments the sort ID of the packer.
                    numSortIDs = numSortIDs + 1
                    packers[1].SortID = packers[1].SortID + 1
                    surfaceInfo.LightmapPages[numSortIDs] = numLightmapPages
                    surfaceInfo.Bumpmaps[numSortIDs] = mat.Bumpmap
                    surfaceInfo.Bumpmaps2[numSortIDs] = mat.Bumpmap2
                end

                currentMaterialID = faceInfo.MaterialID
                mat.MaxLightmapPage = numLightmapPages
                mat.MinLightmapPage = numLightmapPages
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
                numLightmapPages = numLightmapPages + 1
                surfaceInfo.LightmapPages[numSortIDs] = numLightmapPages
                surfaceInfo.Bumpmaps[numSortIDs] = mat.Bumpmap
                surfaceInfo.Bumpmaps2[numSortIDs] = mat.Bumpmap2
                packers[#packers + 1] = ss.MakeSkylinePacker(
                    numSortIDs, MAX_LIGHTMAP_WIDTH, MAX_LIGHTMAP_HEIGHT)
                x, y = packers[#packers]:AddBlock(width, height)
                if x and y then
                    mat.MaxLightmapPage = numLightmapPages
                    packedSortID = packers[#packers].SortID
                end
            end

            faceLightmapInfo[faceInfo.FaceIndex] = {
                x = x or 0,
                y = y or 0,
                sortID = packedSortID or 0,
                mat = mat,
            }
        elseif not currentMaterialID and currentWhiteLightmapMaterialID ~= faceInfo.MaterialID then
            if not currentMaterialID and not currentWhiteLightmapMaterialID then
                numSortIDs = numSortIDs + 1
            end
            currentWhiteLightmapMaterialID = faceInfo.MaterialID
            -- mat.NeedsWhiteLightmap = true
        end
    end

    local lastPageWidth, lastPageHeight = GetMinimumDimensions(packers[#packers])
    for _, surf in ipairs(surfaceInfo.Surfaces) do
        local indexInLump = surf.FaceLumpIndex ---@cast indexInLump -?
        local info = faceLightmapInfo[indexInLump]
        surf.MeshSortID = info and info.sortID or 0
        if info then
            local face = faces[indexInLump]
            local texInfo = rawTexInfo[face.texInfo + 1]
            local width = face.lightmapTextureSizeInLuxels[1] + 1
            local height = face.lightmapTextureSizeInLuxels[2] + 1
            local page = surfaceInfo.LightmapPages[info.sortID]
            local isLastPage = page == numLightmapPages
            local pageWidth = isLastPage and lastPageWidth or MAX_LIGHTMAP_WIDTH
            local pageHeight = isLastPage and lastPageHeight or MAX_LIGHTMAP_HEIGHT
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

    surfaceInfo.NumLightmapPages = numLightmapPages
    surfaceInfo.LastLightmapPageWidth = lastPageWidth
    surfaceInfo.LastLightmapPageHeight = lastPageHeight
end
