
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band
local huge = math.huge
local huge_negative = -huge
local ipairs = ipairs
local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap(), "GAME") or "")
local vector_one = ss.vector_one
local MaxVector = ss.MaxVector
local MinVector = ss.MinVector

---Calculates playable areas from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@return ss.MinimapAreaBounds[]
local function BuildMinimapBounds(bsp)
    local bounds = {} ---@type ss.MinimapAreaBounds[]
    for _, leaf in ipairs(bsp.LEAFS) do
        local area = band(leaf.areaAndFlags, 0x01FF)
        if area > 0 then
            if not bounds[area] then
                bounds[area] = {
                    maxs = vector_one * huge_negative,
                    mins = vector_one * huge,
                }
            end

            bounds[area].mins = MinVector(bounds[area].mins, leaf.mins)
            bounds[area].maxs = MaxVector(bounds[area].maxs, leaf.maxs)
        end
    end

    return bounds
end

---Parses the BSP, collect valid brush surfaces,
---and prepare paintable surfaces.
---@return ss.PrecachedData?
function ss.BuildMapCache()
    local bsp = ss.LoadBSP()
    if not bsp then return end
    local cache = ss.new "PrecachedData"
    cache.CacheVersion  = 1 -- TODO: Better versioning
    cache.MapCRC        = mapCRC
    cache.MinimapBounds = BuildMinimapBounds(bsp)
    cache.Lightmap.DirectionalLightColor,
    cache.Lightmap.DirectionalLightColorHDR,
    cache.Lightmap.DirectionalLightScaleHDR = ss.FindLightEnvironment(bsp)
    -- local surfaceDetails = ss.BuildFuncLODCache(bsp)

    do
        collectgarbage "collect"
        local hdr, whdr = ss.BuildSurfaceCache(bsp, true)
        -- table.Add(hdr, surfaceDetails)
        for _, s in ipairs(hdr) do
            cache.NumTrianglesHDR = cache.NumTrianglesHDR + #s.Vertices / 3
        end
        cache.SurfacesWaterHDR = whdr
        file.Write(string.format("splashsweps/%s_hdr.png", game.GetMap()), ss.BuildLightmapCache(bsp, hdr, true))
        file.Write(string.format("splashsweps/%s_hdr.txt", game.GetMap()), util.Compress(util.TableToJSON(hdr)))
        collectgarbage "collect"
        ss.BuildUVCache(hdr)
    end

    do
        collectgarbage "collect"
        local ldr, wldr = ss.BuildSurfaceCache(bsp, false)
        -- table.Add(ldr, surfaceDetails)
        for _, s in ipairs(ldr) do
            cache.NumTrianglesLDR = cache.NumTrianglesLDR + #s.Vertices / 3
        end
        cache.SurfacesWaterLDR = wldr
        file.Write(string.format("splashsweps/%s_ldr.png", game.GetMap()), ss.BuildLightmapCache(bsp, ldr, true))
        file.Write(string.format("splashsweps/%s_ldr.txt", game.GetMap()), util.Compress(util.TableToJSON(ldr)))
        collectgarbage "collect"
        ss.BuildUVCache(ldr)
    end

    collectgarbage "collect"
    return cache
end
