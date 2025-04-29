
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Calculates playable areas from parsed BSP structures.
---@param bsp ss.RawBSPResults
---@return ss.MinimapAreaBounds[]
local function BuildMinimapBounds(bsp)
    local bounds = {} ---@type ss.MinimapAreaBounds[]
    for _, leaf in ipairs(bsp.LEAFS) do
        local area = bit.band(leaf.areaAndFlags, 0x01FF)
        if area > 0 then
            if not bounds[area] then
                bounds[area] = {
                    maxs = ss.vector_one * -math.huge,
                    mins = ss.vector_one * math.huge,
                }
            end

            bounds[area].mins = ss.MinVector(bounds[area].mins, leaf.mins)
            bounds[area].maxs = ss.MaxVector(bounds[area].maxs, leaf.maxs)
        end
    end

    return bounds
end

local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap(), "GAME") or "")

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
    cache.SurfacesHDR   = ss.BuildSurfaceCache(bsp, true, cache.SurfacesWater)
    cache.SurfacesLDR   = ss.BuildSurfaceCache(bsp, false, cache.SurfacesWater)
    cache.Lightmap      = ss.BuildLightmapCache(bsp, cache.SurfacesHDR, cache.SurfacesLDR)

    local surfaceProps  = ss.BuildStaticPropCache(bsp)
    local surfacePropsHDR = ss.deepcopy(surfaceProps) or {}
    table.Add(cache.SurfacesHDR, surfacePropsHDR)
    table.Add(cache.SurfacesLDR, surfaceProps)
    cache.NumTrianglesHDR = ss.BuildUVCache(cache.SurfacesHDR)
    -- cache.NumTrianglesLDR = ss.BuildUVCache(cache.SurfacesLDR)
    return cache
end
