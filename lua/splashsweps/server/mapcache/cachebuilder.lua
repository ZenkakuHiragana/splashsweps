
---@class ss
local ss = SplashSWEPs
if not ss then return end

local assert = assert
local band = bit.band
local huge = math.huge
local huge_negative = -huge
local ipairs = ipairs
local mapCRC = util.CRC(file.Read("maps/" .. game.GetMap(), "GAME") or "")
local vector_one = ss.vector_one

local MatrixUnpack = Matrix().Unpack
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

---Since GMOD can't write VMatrix to JSON I have to serialize them manually.
---https://github.com/Facepunch/garrysmod-issues/issues/5150
---@param surfaces ss.PrecachedData.Surface[]
local function SerializeMatrices(surfaces)
    for _, surf in ipairs(surfaces) do
        local e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, eA, eB, eC, eD, eE, eF = MatrixUnpack(surf.TransformPaintGrid)
        assert(e0, "e0")
        assert(e1, "e1")
        assert(e2, "e2")
        assert(e3, "e3")
        assert(e4, "e4")
        assert(e5, "e5")
        assert(e6, "e6")
        assert(e7, "e7")
        assert(e8, "e8")
        assert(e9, "e9")
        assert(eA, "eA")
        assert(eB, "eB")
        assert(eC, "eC")
        assert(eD, "eD")
        assert(eE, "eE")
        assert(eF, "eF")
        surf.TransformPaintGridSerialized = {
            e0, e1, e2, e3,
            e4, e5, e6, e7,
            e8, e9, eA, eB,
            eC, eD, eE, eF,
        }
        for i, v in ipairs(surf.Vertices) do
            e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, eA, eB, eC, eD, eE, eF = MatrixUnpack(v)
            assert(e0, "e0")
            assert(e1, "e1")
            assert(e2, "e2")
            assert(e3, "e3")
            assert(e4, "e4")
            assert(e5, "e5")
            assert(e6, "e6")
            assert(e7, "e7")
            assert(e8, "e8")
            assert(e9, "e9")
            assert(eA, "eA")
            assert(eB, "eB")
            assert(eC, "eC")
            assert(eD, "eD")
            assert(eE, "eE")
            assert(eF, "eF")
            surf.VerticesSerialized[i] = {
                e0, e1, e2, e3,
                e4, e5, e6, e7,
                e8, e9, eA, eB,
                eC, eD, eE, eF,
            }
        end
        for _, info in ipairs(surf.UVInfo) do
            e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, eA, eB, eC, eD, eE, eF = MatrixUnpack(info.Transform)
            assert(e0, "e0")
            assert(e1, "e1")
            assert(e2, "e2")
            assert(e3, "e3")
            assert(e4, "e4")
            assert(e5, "e5")
            assert(e6, "e6")
            assert(e7, "e7")
            assert(e8, "e8")
            assert(e9, "e9")
            assert(eA, "eA")
            assert(eB, "eB")
            assert(eC, "eC")
            assert(eD, "eD")
            assert(eE, "eE")
            assert(eF, "eF")
            info.TransformSerialized = {
                e0, e1, e2, e3,
                e4, e5, e6, e7,
                e8, e9, eA, eB,
                eC, eD, eE, eF,
            }
        end
    end
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
    cache.SurfacesHDR   = ss.BuildSurfaceCache(bsp, true, cache.SurfacesWater)
    cache.SurfacesLDR   = ss.BuildSurfaceCache(bsp, false, cache.SurfacesWater)
    cache.Lightmap      = ss.BuildLightmapCache(bsp, cache.SurfacesHDR, cache.SurfacesLDR)

    local surfaceProps  = ss.BuildStaticPropCache(bsp)
    local surfacePropsHDR = ss.deepcopy(surfaceProps) or {}
    table.Add(cache.SurfacesHDR, surfacePropsHDR)
    table.Add(cache.SurfacesLDR, surfaceProps)
    cache.NumTrianglesHDR = ss.BuildUVCache(cache.SurfacesHDR)
    cache.NumTrianglesLDR = ss.BuildUVCache(cache.SurfacesLDR)
    SerializeMatrices(cache.SurfacesHDR)
    SerializeMatrices(cache.SurfacesLDR)
    SerializeMatrices(cache.SurfacesWater)
    collectgarbage "collect"
    return cache
end
