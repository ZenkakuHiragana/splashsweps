
---@class ss
local ss = SplashSWEPs
if not ss then return end

local band = bit.band
local huge = math.huge
local huge_negative = -huge
local ipairs = ipairs
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

---Gets the dimension of the UV-unpacked rectangle for given AABB.
---
---```text
---  z
---  ^
---. |     y
---. |    /        +--- size = (maxs - mins)
---. |   /'''---___V
---. |  /         /|             |<------width------>|
---. | /    +z   / |       -.----+----+----+----+----+
---. |/         /  |        |    | -x | -z | +x | +z |
---. |'''---___/   |  ==> height +----+----+----+----+
---. |         |+x /        |    |    | -y |    | +y |
---. |   -y    |  /        -*----+----+----+----+----+
---. |         | /
---   '''---___|/
---            '''---> x
---```
---
---Width and height of each surface:
---
---* +z, -z: size.x, size.y
---* +x, -x: size.y, size.z
---* +y, -y: size.x, size.z
---
---There are three patterns of unpacking and the one with minimum wasted spaces is selected:
---
---(1) width = 2 * (size.x + size.y), height = size.x + size.z
---
---```text
---       sx   sy   sx   sy
---.    +----+----+----+----+
---. sz | -y | -x | +y | +x |
---.    +----+----+----+----+
---. sx | ^  | -z |    | +z |
---.    +-|--+----+----+----+
---.      |
---  area of wasted spaces = 2 * size.x^2
---```
---
---(2) width = 2 * (size.x + size.y), height = size.y + size.z
---
---```text
---       sy   sx   sy   sx
---.    +----+----+----+----+
---. sz | -x | -y | +x | +y |
---.    +----+----+----+----+
---. sy | ^  | -z |    | +z |
---.    +-|--+----+----+----+
---.      |
---  area of wasted spaces = 2 * size.y^2
---```
---
---(3) width = 2 * (size.x + size.z), height = size.y + size.z
---
---```text
---       sz   sx   sz   sx
---.    +----+----+----+----+
---. sy | -x | -z | +x | +z |
---.    +----+----+----+----+
---. sz | ^  | -y |    | +y |
---.    +-|--+----+----+----+
---.      |
---  area of wasted spaces = 2 * size.z^2
---```
---@param mins Vector
---@param maxs Vector
---@return number
---@return number
---@return integer
local function GetStaticPropUVSize(mins, maxs)
    local size = maxs - mins
    local sx, sy, sz = size:Unpack()

    -- Pattern 1
    local width1 = 2 * (sx + sy)
    local height1 = sx + sz
    local wasted1 = sx

    -- Pattern 2
    local width2 = 2 * (sx + sy)
    local height2 = sy + sz
    local wasted2 = sy

    -- Pattern 3
    local width3 = 2 * (sx + sz)
    local height3 = sy + sz
    local wasted3 = sz

    -- Find the pattern with the smallest area
    if wasted1 < wasted2 and wasted1 < wasted3 then
        return width1, height1, 1
    elseif wasted2 < wasted3 then
        return width2, height2, 2
    else
        return width3, height3, 3
    end
end

---Parses the BSP, collect valid brush surfaces,
---and prepare paintable surfaces.
---@return ss.PrecachedData?
function ss.BuildMapCache()
    local gcpause = collectgarbage("setpause", 0)
    collectgarbage "collect"
    local bsp = ss.LoadBSP()
    if not bsp then return end
    local cache = ss.new "PrecachedData"
    local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME") or "")
    cache.CacheVersion  = 1 -- TODO: Better versioning
    cache.MapCRC        = tonumber(mapCRC) or 0
    cache.MinimapBounds = BuildMinimapBounds(bsp)
    ss.BuildStaticPropCache(bsp, cache)
    ss.FindLightEnvironment(bsp, cache)
    for i = 1, #bsp.MODELS do
        cache.ModelsHDR[i] = ss.new "PrecachedData.ModelInfo"
        cache.ModelsLDR[i] = ss.new "PrecachedData.ModelInfo"
    end

    local staticPropRectangles = {} ---@type Vector[]
    for i, prop in ipairs(cache.StaticProps) do
        local w, h, layoutType = GetStaticPropUVSize(prop.BoundsMin, prop.BoundsMax)
        staticPropRectangles[i] = Vector(w, h)
        prop.UnwrapIndex = layoutType
    end

    do
        collectgarbage "collect"
        local hdr, whdr = ss.BuildSurfaceCache(bsp, cache.ModelsHDR, true)
        cache.SurfacesWaterHDR = whdr
        ss.BuildUVCache(hdr, cache.StaticPropHDR, staticPropRectangles)
        ss.BuildLightmapCache(bsp, hdr.Surfaces, true)
        ss.BuildDisplacementHash(hdr.Surfaces)
        ss.BuildSurfaceHash(hdr.Surfaces, cache.ModelsHDR[1].FaceIndices, hdr.SurfaceHash)
        file.Write(string.format("splashsweps/%s_hdr.json", game.GetMap()), util.Compress(util.TableToJSON(hdr)))
    end

    do
        collectgarbage "collect"
        local ldr, wldr = ss.BuildSurfaceCache(bsp, cache.ModelsLDR, false)
        cache.SurfacesWaterLDR = wldr
        ss.BuildUVCache(ldr, cache.StaticPropLDR, staticPropRectangles)
        ss.BuildLightmapCache(bsp, ldr.Surfaces, false)
        ss.BuildDisplacementHash(ldr.Surfaces)
        ss.BuildSurfaceHash(ldr.Surfaces, cache.ModelsLDR[1].FaceIndices, ldr.SurfaceHash)
        file.Write(string.format("splashsweps/%s_ldr.json", game.GetMap()), util.Compress(util.TableToJSON(ldr)))
    end

    collectgarbage "collect"
    collectgarbage("setpause", gcpause)
    return cache
end
