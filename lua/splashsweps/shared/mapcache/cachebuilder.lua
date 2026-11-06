
-- Builds the map cache file from the BSP, and reads it.

---@class ss
local ss = SplashSWEPs
local BSP             = ss.import "splashsweps/shared/mapcache/bsploader"
local LightmapBuilder = ss.import "splashsweps/shared/mapcache/lightmapbuilder"
local MapCache        = ss.import "splashsweps/shared/mapcache/mapcache"
local SpatialIndex    = ss.import "splashsweps/shared/spatialindex"
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

---Lists the material names of the map in the order of TEXDATA_STRING_DATA.
---@param bsp ss.BSP.Lumps
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
---@param bsp ss.BSP.Lumps
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
---@param bsp ss.BSP.Lumps
---@return ss.MapCache.MinimapAreaBounds[]
local function BuildMinimapBounds(bsp)
    local bounds = {} ---@type ss.MapCache.MinimapAreaBounds[]
    for _, leaf in ipairs(bsp.LEAFS) do
        local area = band(leaf.areaAndFlags, 0x01FF)
        if area > 0 then
            local b = bounds[area]
            if not b then
                b = MapCache.MinimapAreaBounds.new()
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

---Parses the BSP, collects valid brush surfaces, prepares paintable surfaces,
---and writes them to the temporary file.
---@param path string Path of the temporary file in the data folder.
---@return boolean # false if the BSP cannot be loaded.
local function WriteCache(path)
    local bsp = BSP.Load()
    if not bsp then return false end
    local cache = MapCache.new()
    cache.MaterialNames    = BuildMaterialNames(bsp)
    cache.NumMaterialNames = #cache.MaterialNames
    cache.MinimapBounds    = BuildMinimapBounds(bsp)
    cache.NumMinimapBounds = #cache.MinimapBounds
    cache.NumModels        = #bsp.MODELS
    SurfaceBuilder.BuildStaticPropCache(bsp, cache)

    collectgarbage "collect"
    SurfaceBuilder.BuildSurfaceCache(bsp, cache)
    local surfaces = cache.Surfaces ---@cast surfaces -? MapCache.new() creates the array.
    local rectangles = {} ---@type ss.MapCache.InkMapRectangle[]
    for _, surf in ipairs(surfaces) do
        rectangles[#rectangles + 1] = surf.InkMapRectangle
    end

    for _, prop in ipairs(cache.StaticProps) do
        rectangles[#rectangles + 1] = prop.InkMapRectangle
    end

    cache.HammerUnitsToUV = UVBuilder.Build(rectangles)
    SpatialIndex.BuildDisplacementHash(surfaces)
    cache.LightmapsLDR = LightmapBuilder.Build(bsp, bsp.FACES, bsp.LIGHTING, surfaces, cache.MaterialNames)
    cache.NumLightmapsLDR = #cache.LightmapsLDR
    if HasMatchingHDRFaces(bsp) then
        cache.LightmapsHDR = LightmapBuilder.Build(bsp, bsp.FACES_HDR, bsp.LIGHTING_HDR, surfaces, cache.MaterialNames)
        cache.NumLightmapsHDR = #cache.LightmapsHDR
    end

    MapCache.WriteFile(path, bsp.header.mapRevision, cache)
    return true
end

---Reads the map cache of the current map, building it from the BSP first
---if the file is missing, or built by another version of the cache or from another revision of the map.
---Each machine builds its own cache, as the server does not send it to the clients.
---@return ss.MapCache? # nil if the map file cannot be read.
function CacheBuilder.Load()
    local path = string.format("splashsweps/%s.dat", game.GetMap())
    local tempPath = string.format("splashsweps/%s.tmp.dat", game.GetMap())
    local revision = BSP.ReadRevision()
    if not revision then return end
    local cache = MapCache.ReadFile(path, revision)
    if cache then return cache end

    file.CreateDir "splashsweps"
    collectgarbage "collect"
    if not WriteCache(tempPath) then return end

    -- WriteCache has returned, so the BSP and the cache are released.
    collectgarbage "collect"
    MapCache.CompressFile(tempPath, path)
    collectgarbage "collect"
    return MapCache.ReadFile(path, revision)
end

return CacheBuilder
