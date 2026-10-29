
-- Builds the map cache file from the BSP, and reads it.

---@class ss
local ss = SplashSWEPs
local BSP             = ss.import "splashsweps/shared/mapcache/bsploader"
local Hash            = ss.import "splashsweps/shared/hash"
local LightmapBuilder = ss.import "splashsweps/shared/mapcache/lightmapbuilder"
local PrecachedData   = ss.import "splashsweps/shared/typing/precachedata"
local SurfaceBuilder  = ss.import "splashsweps/shared/mapcache/surfacebuilder"
local UVBuilder       = ss.import "splashsweps/shared/mapcache/uvbuilder"

---@class ss.CacheBuilderModule
local CacheBuilder = ss.module "splashsweps/shared/mapcache/cachebuilder"

local band = bit.band
local huge = math.huge
local huge_negative = -huge
local max = math.max
local min = math.min
local ipairs = ipairs

---Finds light_environment entity in the ENTITIES lump and fetches directional light info.
---@param bsp ss.RawBSPResults
---@param cache ss.PrecachedData
local function findLightEnvironment(bsp, cache)
    for _, entities in ipairs(bsp.ENTITIES) do
        for k in entities:gmatch "{[^}]+}" do
            if k:find "light_environment" then
                local t = util.KeyValuesToTable("\"-\" " .. k)
                if t.classname == "light_environment" then
                    local lightScaleHDR = t._lightscalehdr
                    local lightColor    = t._light:Split " "
                    local lightColorHDR = t._lighthdr and t._lighthdr:Split " " or {}
                    local nlightColor = {} ---@type number[]
                    local nlightColorHDR = {} ---@type number[]
                    for i = 1, 4 do
                        nlightColor[i] = tonumber(lightColor[i])
                        nlightColorHDR[i] = tonumber(lightColorHDR[i])
                        if not nlightColorHDR[i] or nlightColorHDR[i] < 0 then
                            nlightColorHDR[i] = nlightColor[i]
                        end
                    end
                    print(string.format("    light_environment found:\n"
                        .. "        lightColor    = [%s %s %s %s]\n"
                        .. "        lightColorHDR = [%s %s %s %s]\n"
                        .. "        lightScaleHDR = %s",
                        lightColor[1], lightColor[2], lightColor[3], lightColor[4],
                        lightColorHDR[1], lightColorHDR[2], lightColorHDR[3], lightColorHDR[4],
                        lightScaleHDR))
                    cache.DirectionalLight.Color    = Color(unpack(nlightColor))
                    cache.DirectionalLight.ColorHDR = Color(unpack(nlightColorHDR))
                    cache.DirectionalLight.ScaleHDR = tonumber(lightScaleHDR) or 1
                    return
                end
            end
        end
    end
end

---Lists the material names of the map in the order of TEXDATA_STRING_DATA.
---@param bsp ss.RawBSPResults
---@return string[]
local function BuildMaterialNames(bsp)
    local names = {} ---@type string[]
    for i, texName in ipairs(bsp.TEXDATA_STRING_DATA) do
        names[i] = texName:lower():StripExtension():gsub("\\", "/")
    end

    return names
end

---Tests if LUMP_FACES_HDR has the same faces as LUMP_FACES except for their lighting,
---so that the surfaces built from LUMP_FACES can use the lightmaps of LUMP_FACES_HDR.
---@param bsp ss.RawBSPResults
---@return boolean
local function HasMatchingHDRFaces(bsp)
    local faces, hdrFaces = bsp.FACES, bsp.FACES_HDR
    if not hdrFaces or #hdrFaces == 0 then return false end
    local matches = #hdrFaces == #faces
    for i = 1, matches and #faces or 0 do
        local f, h = faces[i], hdrFaces[i]
        if f.planeNum ~= h.planeNum
        or f.firstEdge ~= h.firstEdge
        or f.numEdges ~= h.numEdges
        or f.texInfo ~= h.texInfo
        or f.dispInfo ~= h.dispInfo
        or f.lightmapTextureMinsInLuxels[1] ~= h.lightmapTextureMinsInLuxels[1]
        or f.lightmapTextureMinsInLuxels[2] ~= h.lightmapTextureMinsInLuxels[2]
        or f.lightmapTextureSizeInLuxels[1] ~= h.lightmapTextureSizeInLuxels[1]
        or f.lightmapTextureSizeInLuxels[2] ~= h.lightmapTextureSizeInLuxels[2] then
            matches = false
            break
        end
    end

    if not matches then
        print "    LUMP_FACES_HDR has faces other than LUMP_FACES, so the client uses the LDR lightmaps."
    end

    return matches
end

---Calculates playable areas from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@return ss.MinimapAreaBounds[]
local function BuildMinimapBounds(bsp)
    local bounds = {} ---@type ss.MinimapAreaBounds[]
    for _, leaf in ipairs(bsp.LEAFS) do
        local area = band(leaf.areaAndFlags, 0x01FF)
        if area > 0 then
            local b = bounds[area]
            if not b then
                b = PrecachedData.MinimapAreaBounds.new()
                b.MinX, b.MinY, b.MinZ = huge, huge, huge
                b.MaxX, b.MaxY, b.MaxZ = huge_negative, huge_negative, huge_negative
                bounds[area] = b
            end

            b.MinX, b.MinY, b.MinZ = min(b.MinX, leaf.minX), min(b.MinY, leaf.minY), min(b.MinZ, leaf.minZ)
            b.MaxX, b.MaxY, b.MaxZ = max(b.MaxX, leaf.maxX), max(b.MaxY, leaf.maxY), max(b.MaxZ, leaf.maxZ)
        end
    end

    return bounds
end

---Gets the dimension of the UV-unpacked rectangle for given AABB.
---
---```text
---  z
---  ^
---. |     y     size = (maxs - mins)
---. |    /        |
---. |   /'''---___V            <--height->
---. |  /         /|       -.---+----+----+
---. | /    +z   / |        |   | -x |    |
---. |/         /  |        |   +----+----+
---. |'''---___/   |        |   | -z | -y |
---. |         |+x /  ==> width +----+----+
---. |   -y    |  /         |   | +x |    |
---. |         | /          |   +----+----+
---   '''---___|/           |   | +z | +y |
---            '''---> x   -v---+----+----+
---```
---
---Width and height of each surface:
---
---* +z, -z: size.x, size.y
---* +x, -x: size.y, size.z
---* +y, -y: size.x, size.z
---
---There are three patterns of unpacking and the one with minimum wasted spaces is selected.
---Each face cell additionally has m = ss.MARGIN_HAMMER_UNITS on both sides.
---The figure below omits them, so the returned size has 8m in w (4 cells) and 4m in h (2 cells) in addition:
---
---```text
---.   (1)               (2)               (3)
---. w = 2 (sx + sy)       2 (sy + sz)       2 (sx + sz)
---. h =    sx + sz           sx + sy           sy + sz
---.        sz   sx           sx   sy           sy   sz
---.      +----+----+       +----+----+       +----+----+
---.   sx | -y |    |    sy | -z |    |    sz | -x |    |
---.      +----+----+       +----+----+       +----+----+
---.   sy | -x | -z |    sz | -y | -x |    sx | -z | -y |
---.      +----+----+       +----+----+       +----+----+
---.   sx | +y |    |    sy | +z |    |    sz | +x |    |
---.      +----+----+       +----+----+       +----+----+
---.   sy | +x | +z |    sz | +y | +x |    sx | +z | +y |
---.      +----+----+       +----+----+       +----+----+
---```
---@param prop ss.PrecachedData.StaticProp
---@return number # w including the margins.
---@return number # h including the margins.
---@return integer # The selected pattern.
local function GetStaticPropUVSize(prop)
    local sx = prop.BoundsMaxX - prop.BoundsMinX
    local sy = prop.BoundsMaxY - prop.BoundsMinY
    local sz = prop.BoundsMaxZ - prop.BoundsMinZ
    local margin = 2 * ss.MARGIN_HAMMER_UNITS -- Both sides of each face cell

    -- Pattern 1
    local width1 = 2 * (sx + sy) + 4 * margin
    local height1 = sx + sz + 2 * margin

    -- Pattern 2
    local width2 = 2 * (sy + sz) + 4 * margin
    local height2 = sx + sy + 2 * margin

    -- Pattern 3
    local width3 = 2 * (sx + sz) + 4 * margin
    local height3 = sy + sz + 2 * margin

    -- Find the pattern with the smallest area
    if sx < sy and sx < sz then
        return width1, height1, 1
    elseif sy < sx and sy < sz then
        return width2, height2, 2
    else
        return width3, height3, 3
    end
end

---Parses the BSP, collects valid brush surfaces, prepares paintable surfaces,
---and writes them to the file without compression.
---@param path string Path in the data folder.
---@return boolean # false if the BSP cannot be loaded.
local function WriteCache(path)
    local bsp = BSP.Load()
    if not bsp then return false end
    local cache = PrecachedData.new()
    cache.MaterialNames    = BuildMaterialNames(bsp)
    cache.NumMaterialNames = #cache.MaterialNames
    cache.MinimapBounds    = BuildMinimapBounds(bsp)
    cache.NumMinimapBounds = #cache.MinimapBounds
    cache.NumModels        = #bsp.MODELS
    SurfaceBuilder.BuildStaticPropCache(bsp, cache)
    findLightEnvironment(bsp, cache)
    for _, prop in ipairs(cache.StaticProps) do
        local rectangle = prop.InkMapRectangle
        rectangle.Width, rectangle.Height, prop.UnwrapIndex = GetStaticPropUVSize(prop)
    end

    collectgarbage "collect"
    SurfaceBuilder.BuildSurfaceCache(bsp, cache)
    local surfaces = cache.Surfaces ---@cast surfaces -? PrecachedData.new() creates the array.
    local rectangles = {} ---@type ss.PrecachedData.InkMapRectangle[]
    for _, surf in ipairs(surfaces) do
        rectangles[#rectangles + 1] = surf.InkMapRectangle
    end

    for _, prop in ipairs(cache.StaticProps) do
        rectangles[#rectangles + 1] = prop.InkMapRectangle
    end

    cache.HammerUnitsToUV = UVBuilder.Build(rectangles)
    Hash.BuildDisplacementHash(surfaces)
    cache.LightmapsLDR = LightmapBuilder.Build(bsp, bsp.FACES, bsp.LIGHTING, surfaces, cache.MaterialNames)
    cache.NumLightmapsLDR = #cache.LightmapsLDR
    if HasMatchingHDRFaces(bsp) then
        cache.LightmapsHDR = LightmapBuilder.Build(bsp, bsp.FACES_HDR, bsp.LIGHTING_HDR, surfaces, cache.MaterialNames)
        cache.NumLightmapsHDR = #cache.LightmapsHDR
    end

    cache.SurfaceHash = Hash.BuildSurfaceHash(surfaces, cache.StaticProps)
    PrecachedData.WriteFile(path, bsp.header.mapRevision, cache)
    return true
end

---Reads the map cache of the current map, building it from the BSP first
---if the file is missing, or built by another version of the cache or from another revision of the map.
---Each machine builds its own cache, as the server does not send it to the clients.
---@return ss.PrecachedData? # nil if the map file cannot be read.
function CacheBuilder.Load()
    local path = string.format("splashsweps/%s.dat", game.GetMap())
    local revision = BSP.ReadRevision()
    if not revision then return end
    local cache = PrecachedData.ReadFile(path, revision)
    if cache then return cache end

    file.CreateDir "splashsweps"
    collectgarbage "collect"
    if not WriteCache(path) then return end

    -- WriteCache has returned, so the BSP and the cache are released before the compression, which needs memory.
    collectgarbage "collect"
    PrecachedData.CompressFile(path)
    collectgarbage "collect"
    return PrecachedData.ReadFile(path, revision)
end

return CacheBuilder
