
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
---There are three patterns of unpacking and the one with minimum wasted spaces is selected:
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

    -- Pattern 2
    local width2 = 2 * (sy + sz)
    local height2 = sx + sy

    -- Pattern 3
    local width3 = 2 * (sx + sz)
    local height3 = sy + sz

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
    cache.NumModels     = #bsp.MODELS
    ss.BuildStaticPropCache(bsp, cache)
    findLightEnvironment(bsp, cache)

    local staticPropRectangles = {} ---@type Vector[]
    for i, prop in ipairs(cache.StaticProps) do
        local w, h, layoutType = GetStaticPropUVSize(prop.BoundsMin, prop.BoundsMax)
        staticPropRectangles[i] = Vector(w, h)
        prop.UnwrapIndex = layoutType
    end

    do
        collectgarbage "collect"
        local hdr, whdr = ss.BuildSurfaceCache(bsp, true)
        cache.SurfacesWaterHDR = whdr
        ss.BuildUVCache(hdr, cache.StaticPropHDR, staticPropRectangles)
        ss.BuildDisplacementHash(hdr.Surfaces)
        ss.BuildLightmapInfo(bsp, true, hdr, cache)
        ss.BuildSurfaceHash(hdr.Surfaces, cache.StaticProps, hdr.SurfaceHash)
        file.Write(string.format("splashsweps/%s_hdr.json", game.GetMap()), util.Compress(util.TableToJSON(hdr)))
    end

    do
        collectgarbage "collect"
        local ldr, wldr = ss.BuildSurfaceCache(bsp, false)
        cache.SurfacesWaterLDR = wldr
        ss.BuildUVCache(ldr, cache.StaticPropLDR, staticPropRectangles)
        ss.BuildDisplacementHash(ldr.Surfaces)
        ss.BuildLightmapInfo(bsp, false, ldr, cache)
        ss.BuildSurfaceHash(ldr.Surfaces, cache.StaticProps, ldr.SurfaceHash)
        file.Write(string.format("splashsweps/%s_ldr.json", game.GetMap()), util.Compress(util.TableToJSON(ldr)))
    end

    collectgarbage "collect"
    collectgarbage("setpause", gcpause)
    return cache
end
