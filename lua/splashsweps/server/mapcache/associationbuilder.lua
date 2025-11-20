
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Compares surfaces with their sort ID.
---@param a ss.PrecachedData.Surface
---@param b ss.PrecachedData.Surface
---@return boolean
local function MeshSortIDLess(a, b)
    return a.MeshSortID < b.MeshSortID
end

---Binds paintable surfaces to corresponding model.
---@param bsp ss.RawBSPResults
---@param surfaceInfo ss.PrecachedData.SurfaceInfo
---@param modelInfoArray ss.PrecachedData.ModelInfo[]
function ss.BuildModelSurfaceAssociation(bsp, surfaceInfo, modelInfoArray)
    table.sort(surfaceInfo.Surfaces, MeshSortIDLess)
    local meshSortIDToIndex = {} ---@type table<integer, integer>[]
    local modelIndices = {} ---@type integer[] Face index --> model index
    for modelIndex, lump in ipairs(bsp.MODELS) do
        meshSortIDToIndex[modelIndex] = {}
        for i = 1, lump.numFaces do
            modelIndices[lump.firstFace + i] = modelIndex
        end
    end

    for i, surf in ipairs(surfaceInfo.Surfaces) do
        local id = surf.MeshSortID + 1 -- 1 is reserved for non-lightmapped surfaces
        local modelIndex = modelIndices[surf.FaceLumpIndex]
        local modelInfo = modelInfoArray[modelIndex]
        if not meshSortIDToIndex[modelIndex][id] then
            meshSortIDToIndex[modelIndex][id] = #modelInfo.MeshSortIDs + 1
            modelInfo.MeshSortIDs[#modelInfo.MeshSortIDs + 1] = id
            modelInfo.TriangleCounts[#modelInfo.TriangleCounts + 1] = 0
            modelInfo.FaceIndices[#modelInfo.FaceIndices + 1] = {}
        end
        local faceIndices = modelInfo.FaceIndices[meshSortIDToIndex[modelIndex][id]]
        faceIndices[#faceIndices + 1] = i
        modelInfo.TriangleCounts[#modelInfo.TriangleCounts]
            = modelInfo.TriangleCounts[#modelInfo.TriangleCounts] + #surf.Vertices / 3

        -- Remove these entries as it's no longer needed
        surf.FaceLumpIndex = nil
        surf.MeshSortID = nil
    end
end
