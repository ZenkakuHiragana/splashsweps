
-- Builds the map cache files from the BSP.

---@class ss
local ss = SplashSWEPs
local BSP             = ss.import "splashsweps/server/mapcache/bsploader"
local Hash            = ss.import "splashsweps/shared/hash"
local LightmapBuilder = ss.import "splashsweps/server/mapcache/lightmapbuilder"
local PrecachedData   = ss.import "splashsweps/shared/typing/precachedata"
local SurfaceBuilder  = ss.import "splashsweps/server/mapcache/surfacebuilder"
local UVBuilder       = ss.import "splashsweps/server/mapcache/uvbuilder"

---@class ss.CacheBuilderModule
local CacheBuilder = ss.module "splashsweps/server/mapcache/cachebuilder"

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

            b.MinX, b.MinY, b.MinZ = min(b.MinX, leaf.mins.x), min(b.MinY, leaf.mins.y), min(b.MinZ, leaf.mins.z)
            b.MaxX, b.MaxY, b.MaxZ = max(b.MaxX, leaf.maxs.x), max(b.MaxY, leaf.maxs.y), max(b.MaxZ, leaf.maxs.z)
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

---Parses the BSP, collect valid brush surfaces,
---and prepare paintable surfaces.
---@return ss.PrecachedData?
function CacheBuilder.Build()
    collectgarbage "collect"
    local bsp = BSP.Load()
    if not bsp then return end
    local cache = PrecachedData.new()
    cache.Revision         = bsp.header.mapRevision
    cache.MinimapBounds    = BuildMinimapBounds(bsp)
    cache.NumMinimapBounds = #cache.MinimapBounds
    cache.NumModels        = #bsp.MODELS
    SurfaceBuilder.BuildStaticPropCache(bsp, cache)
    findLightEnvironment(bsp, cache)

    local staticPropRectangles = {} ---@type Vector[]
    for i, prop in ipairs(cache.StaticProps) do
        local w, h, layoutType = GetStaticPropUVSize(prop)
        staticPropRectangles[i] = Vector(w, h)
        prop.UnwrapIndex = layoutType
    end

    local hdrPath = string.format("splashsweps/%s_hdr.dat", game.GetMap())
    do
        collectgarbage "collect"
        local hdr, whdr = SurfaceBuilder.BuildSurfaceCache(bsp, true)
        cache.SurfacesWaterHDR = whdr
        cache.NumSurfacesWaterHDR = #whdr
        UVBuilder.Build(hdr, cache.StaticPropHDR, staticPropRectangles)
        Hash.BuildDisplacementHash(hdr.Surfaces)
        LightmapBuilder.Build(bsp, true, hdr, cache)
        hdr.SurfaceHash = Hash.BuildSurfaceHash(hdr.Surfaces, cache.StaticProps)
        PrecachedData.WriteFile(hdrPath, "PrecachedData.SurfaceInfo", hdr)
    end

    collectgarbage "collect"
    PrecachedData.CompressFile(hdrPath)

    local ldrPath = string.format("splashsweps/%s_ldr.dat", game.GetMap())
    do
        collectgarbage "collect"
        local ldr, wldr = SurfaceBuilder.BuildSurfaceCache(bsp, false)
        cache.SurfacesWaterLDR = wldr
        cache.NumSurfacesWaterLDR = #wldr
        UVBuilder.Build(ldr, cache.StaticPropLDR, staticPropRectangles)
        Hash.BuildDisplacementHash(ldr.Surfaces)
        LightmapBuilder.Build(bsp, false, ldr, cache)
        ldr.SurfaceHash = Hash.BuildSurfaceHash(ldr.Surfaces, cache.StaticProps)
        PrecachedData.WriteFile(ldrPath, "PrecachedData.SurfaceInfo", ldr)
    end

    collectgarbage "collect"
    PrecachedData.CompressFile(ldrPath)
    collectgarbage "collect"
    return cache
end

return CacheBuilder
