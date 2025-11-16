--!owner "Nanashi"
--!optimize 2
--!nocheck

---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band

-- From public/bspflags.h
local SURF_NOLIGHT = 0x0004

-- From public\materialsystem\imaterial.h
local FLAGS2_BUMPED_LIGHTMAP = 8 -- (1 << 3)

---@class ss.LightmapMaterial
---@field Name string
---@field EnumID integer
---@field NeedsBumpedLightmaps boolean
ss.struct "LightmapMaterial" {
    Name = "",
    EnumID = 0,
    NeedsBumpedLightmaps = false,
}

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.LightmapFace
---@field FaceIndex integer
---@field Face ss.Binary.BSP.FACES
---@field TexInfo ss.Binary.BSP.TEXINFO
---@field Material ss.LightmapMaterial
---@field HasLightmap boolean
---@field HasLightStyles boolean
---@field Area integer
ss.struct "LightmapFace" {
    FaceIndex = 0,
    Face = ss.new "Binary.BSP.FACES",
    TexInfo = ss.new "Binary.BSP.TEXINFO",
    Material = ss.new "LightmapMaterial",
    HasLightmap = false,
    HasLightStyles = false,
    Area = 0,
}

---@param faceIndex integer
---@param face ss.Binary.BSP.FACES
---@param texInfo ss.Binary.BSP.TEXINFO
---@param material ss.LightmapMaterial
---@return ss.LightmapFace
ss.ctor "LightmapFace" (function (self, faceIndex, face, texInfo, material)
    self.FaceIndex = faceIndex
    self.Face = face
    self.TexInfo = texInfo
    self.Material = material
    self.HasLightmap = band(texInfo.flags, SURF_NOLIGHT) == 0 and face.lightOffset >= 0
    self.HasLightStyles = false -- Check face.styles
    self.Area = face.lightmapTextureSizeInLuxels[1] * face.lightmapTextureSizeInLuxels[2]
    for i = 1, 4 do
        if face.styles[i] ~= 0 and face.styles[i] ~= 255 then
            self.HasLightStyles = true
            break
        end
    end
end)

---Sorts faces for lightmap packing, mimicking the engine's LightmapLess function.
---@param a ss.LightmapFace
---@param b ss.LightmapFace
---@return boolean
local function lightmapLess(a, b)
    -- 1. We want lightmapped surfaces to show up first
    if a.HasLightmap ~= b.HasLightmap then
        return a.HasLightmap
    end

    -- 2. Then sort by material enumeration ID
    if a.Material.EnumID ~= b.Material.EnumID then
        return a.Material.EnumID < b.Material.EnumID
    end

    -- 3. We want Lightstyled surfaces to show up first
    if a.HasLightStyles ~= b.HasLightStyles then
        return a.HasLightStyles
    end

    -- 4. Then sort by lightmap area for better packing... (big areas first)
    return a.Area > b.Area
end

---Generates lightmap packing information for all faces in a BSP.
---@param bsp ss.RawBSPResults
---@param isHDR boolean
---@param surfaces ss.PrecachedData.Surface[]
function ss.BuildLightmapInfo(bsp, isHDR, surfaces)
    print("    Generating lightmap info (" .. (isHDR and "HDR" or "LDR") .. ")...")
    local faces = isHDR and bsp.FACES_HDR or bsp.FACES
    if not faces or #faces == 0 then return {} end

    local texInfos = bsp.TEXINFO
    local texData = bsp.TEXDATA
    local texStringTable = bsp.TEXDATA_STRING_TABLE
    local texStrings = bsp.TEXDATA_STRING_DATA

    -- Create a lookup table for material enumeration IDs, sorted alphabetically
    -- to match the engine's CMaterialDict iteration.
    local materialNames = game.GetWorld():GetMaterials()
    table.sort(materialNames)
    local materialEnum = {} ---@type table<string, integer>
    for i, name in ipairs(materialNames) do
        materialEnum[name] = i
    end

    -- Pre-cache materials to avoid expensive lookups
    ---@type table<string, ss.LightmapMaterial>
    local materialsCache = {}
    local function getCachedMaterial(name)
        if not materialsCache[name] then
            local mat = Material(name)
            if not IsValid(mat) then return nil end
            local enumID = materialEnum[name] or 0
            local isBumped = band(mat:GetInt "$flags2", FLAGS2_BUMPED_LIGHTMAP) ~= 0
            materialsCache[name] = {
                Name = mat:GetName(),
                EnumID = enumID,
                NeedsBumpedLightmaps = isBumped,
            }
        end
        return materialsCache[name]
    end

    -- Create a list of face objects with all necessary info for sorting
    ---@type ss.LightmapFace[]
    local sortableFaces = {}
    for i = 1, #faces do
        local face = faces[i]
        local texinfo = texInfos[face.texInfo + 1]
        if texinfo then
            local texdata = texData[texinfo.texData + 1]
            local nameOffset = texStringTable[texdata.nameStringTableID + 1]
            if nameOffset and texStrings[nameOffset + 1] then
                local matName = texStrings[nameOffset + 1]
                local material = getCachedMaterial(matName)
                if material then
                    sortableFaces[#sortableFaces + 1] = ss.new "LightmapFace" (i, face, texinfo, material)
                end
            end
        end
    end

    -- Sort the faces
    table.sort(sortableFaces, lightmapLess)

    -- Initialize packers and result table
    local packers = { ss.MakeSkylinePacker(0, 512, 256) }
    ---@type table<integer, {page: integer, x: integer, y: integer, sortID: integer}>
    local faceLightmapInfo = {}
    local numSortIDs = 0
    local currentMaterialName = ""
    local firstMaterial = true

    -- Loop through sorted faces and pack them
    for _, faceInfo in ipairs(sortableFaces) do
        if faceInfo.HasLightmap then
            local face = faceInfo.Face
            local material = faceInfo.Material

            -- Material change logic from CMatLightmaps::AllocateLightmap
            if currentMaterialName ~= material.Name then
                -- When material changes, collapse all but the last packer
                for i = #packers - 1, 1, -1 do
                    table.remove(packers, i)
                end

                if not firstMaterial then
                    ---Increments the sort ID of the packer.
                    packers[1].SortID = packers[1].SortID + 1
                    numSortIDs = numSortIDs + 1
                end

                currentMaterialName = material.Name
                firstMaterial = false
            end

            -- Calculate allocation size
            local width = face.lightmapTextureSizeInLuxels[1] + 1
            local height = face.lightmapTextureSizeInLuxels[2] + 1
            local allocWidth = material.NeedsBumpedLightmaps and (width * 4) or width
            local allocHeight = height

            -- Try to pack into existing pages for this material group
            local packed = false
            local pageBaseIndex = numSortIDs
            for i, packer in ipairs(packers) do
                local success, x, y = packer:AddBlock(allocWidth, allocHeight)
                if success then
                    ---@cast x -?
                    ---@cast y -?
                    faceLightmapInfo[faceInfo.FaceIndex] = {
                        page = pageBaseIndex + i - 1,
                        x = x,
                        y = y,
                        sortID = packer.SortID
                    }
                    packed = true
                    break
                end
            end

            if not packed then
                -- Failed to fit, create a new page/packer for this material group
                local newPacker = ss.MakeSkylinePacker(packers[1].SortID, 512, 256)
                local success, x, y = newPacker:AddBlock(allocWidth, allocHeight)
                if success then
                    ---@cast x -?
                    ---@cast y -?
                    packers[#packers + 1] = newPacker
                    faceLightmapInfo[faceInfo.FaceIndex] = {
                        page = pageBaseIndex + #packers - 1,
                        x = x,
                        y = y,
                        sortID = newPacker.SortID
                    }
                else
                    -- This should not happen if the block is smaller than the page
                    print("WARNING: Lightmap block for material " .. material.Name .. " is too large to fit in a new page!")
                end
            end
        end
    end

    -- TODO: Handle last page resizing. For now, we assume all pages are max size.

    for _, surf in ipairs(surfaces) do
        local indexInLump = surf.FaceLumpIndex ---@cast indexInLump -?
        local info = faceLightmapInfo[indexInLump]
        if info then
            surf.LightmapPage = info.page
            surf.LightmapX = info.x
            surf.LightmapY = info.y
        end
    end
end
