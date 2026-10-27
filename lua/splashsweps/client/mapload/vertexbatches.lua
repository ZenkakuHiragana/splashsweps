
-- Splits the surfaces of the world ink meshes into draw-sized batches,
-- and writes their vertices from the map cache into IMeshes.

---@class ss
local ss = SplashSWEPs
local PrecachedData = ss.import "splashsweps/shared/typing/precachedata"
local Util          = ss.import "splashsweps/shared/util"

---@class ss.VertexBatchesModule
local VertexBatches = ss.module "splashsweps/client/mapload/vertexbatches"

local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation
local MAX_VERTICES  = MAX_TRIANGLES * 3

---One vertex worth of packed data passed to inkmesh_vs30, kept only for debug mesh inspection.
---@class ss.VertexBatches.MeshVertex
---@field Position           Vector   World-space position written with mesh.Position.
---@field Color              number[] xyz: blend toward $basetexture2, 3, and 4, w: unused.
---@field UVRange            number[] xy:  min ink-map UV,            zw: max ink-map UV for surface clipping.
---@field WorldTangent_U     number[] xyz: world tangent,              w: geometry texture U.
---@field WorldBinormal_V    number[] xyz: world binormal,             w: geometry texture V.
---@field WorldNormal_dU     number[] xyz: world normal,               w: bumped-lightmap U offset.
---@field InkTangent_U       number[] xyz: world-to-ink-UV first row,  w: ink U.
---@field InkBinormal_V      number[] xyz: world-to-ink-UV second row, w: ink V.
---@field LightmapTangent_U  number[] xyz: world lightmap tangent,     w: packed lightmap U.
---@field LightmapBinormal_V number[] xyz: world lightmap binormal,    w: packed lightmap V.
---@field SurfaceIndex       integer  Source BSP face index.

---A draw-sized range of the vertices of the surfaces that maps one-to-one to a render batch entry.
---@class ss.VertexBatches.MeshVertexBatch
---@field SortID      integer   Lightmap/material group ID used to choose the render material.
---@field NumVertices integer   Number of vertices written into one IMesh.
---Face index, first vertex, and last vertex of each part of the vertices of a surface in this batch, repeated.
---@field FaceRanges  integer[]

---Splits mesh groups into draw-sized vertex batches for mesh.Begin.
---A batch ends when it reaches the limit of the mesh library, even in the middle of the vertices of a surface.
---@param surfaceInfo ss.PrecachedData.SurfaceInfo Cached BSP surface data.
---@param meshGroups  ss.Lightmaps.MeshGroup[]     Mesh groups for one BSP model.
---@return ss.VertexBatches.MeshVertexBatch[] vertexBatches Draw-sized vertex batches.
function VertexBatches.Build(surfaceInfo, meshGroups)
    local vertexBatches = {} ---@type ss.VertexBatches.MeshVertexBatch[]
    for _, meshGroup in ipairs(meshGroups) do
        local vertexBatch = nil ---@type ss.VertexBatches.MeshVertexBatch?
        for _, faceIndex in ipairs(meshGroup.FaceIndices) do
            local numVertices = #surfaceInfo.Surfaces[faceIndex].Vertices
            local first = 1
            while first <= numVertices do
                if not vertexBatch or vertexBatch.NumVertices >= MAX_VERTICES then
                    vertexBatch = { SortID = meshGroup.SortID, NumVertices = 0, FaceRanges = {} }
                    vertexBatches[#vertexBatches + 1] = vertexBatch
                end

                local last = math.min(numVertices, first + MAX_VERTICES - vertexBatch.NumVertices - 1)
                local faceRanges = vertexBatch.FaceRanges
                faceRanges[#faceRanges + 1] = faceIndex
                faceRanges[#faceRanges + 1] = first
                faceRanges[#faceRanges + 1] = last
                vertexBatch.NumVertices = vertexBatch.NumVertices + last - first + 1
                first = last + 1
            end
        end
    end

    return vertexBatches
end

---Writes the vertices of each vertex batch into the matching ink IMesh.
---@param renderBatch   ss.RenderBatch                     Render entries created from the same vertexBatches order.
---@param vertexBatches ss.VertexBatches.MeshVertexBatch[] Vertex batches to write one-to-one with renderBatch.
---@param surfaceInfo   ss.PrecachedData.SurfaceInfo       Cached BSP surface data.
---@param faceLightmaps ss.Lightmaps.FaceLightmap[]        Face-indexed lightmap placements.
---@param debugMeshData ss.VertexBatches.MeshVertex[][]?   Receives the vertices written into each IMesh if given.
function VertexBatches.WriteMeshes(renderBatch, vertexBatches, surfaceInfo, faceLightmaps, debugMeshData)
    local rtIndex       = #PrecachedData.InkMapResolutions
    local rtSize        = PrecachedData.InkMapResolutions[rtIndex]
    local bilinearGuard = ss.RT_BILINEAR_GUARD_PIXELS / rtSize
    local scale         = surfaceInfo.UVScales[rtIndex]
    local worldToUV     = Matrix()
    worldToUV:SetScale(Util.vector_one * scale)
    for i, vertexBatch in ipairs(vertexBatches) do
        local debugVertices = debugMeshData and {} ---@type ss.VertexBatches.MeshVertex[]?
        local faceRanges = vertexBatch.FaceRanges
        mesh.Begin(renderBatch[i].Mesh, MATERIAL_TRIANGLES, vertexBatch.NumVertices / 3)
        for r = 1, #faceRanges, 3 do
            local faceIndex = faceRanges[r]
            local surf      = surfaceInfo.Surfaces[faceIndex]
            local vertices  = surf.Vertices
            local uvInfo    = surf.UVInfo[rtIndex]
            local lightmap  = faceLightmaps[faceIndex]

            -- The values shared by the vertices of the surface, read from C functions once per surface.
            worldToUV:SetAngles(uvInfo.Angle)
            local row1x, row1y, row1z, row1w =
                worldToUV:GetField(1, 1), worldToUV:GetField(1, 2), worldToUV:GetField(1, 3), worldToUV:GetField(1, 4)
            local row2x, row2y, row2z, row2w =
                worldToUV:GetField(2, 1), worldToUV:GetField(2, 2), worldToUV:GetField(2, 3), worldToUV:GetField(2, 4)
            local translationX, translationY = uvInfo.Translation:Unpack()
            row1w = row1w + translationX * scale
            row2w = row2w + translationY * scale
            local minU = uvInfo.OffsetU + bilinearGuard
            local minV = uvInfo.OffsetV + bilinearGuard
            local maxU = uvInfo.OffsetU + uvInfo.Width  - bilinearGuard
            local maxV = uvInfo.OffsetV + uvInfo.Height - bilinearGuard
            local bumpmapOffset = lightmap.BumpmapOffset
            local lightmapOffsetX, lightmapOffsetY = lightmap.OffsetX, lightmap.OffsetY
            local pageWidth, pageHeight = lightmap.PageWidth, lightmap.PageHeight

            for k = faceRanges[r + 1], faceRanges[r + 2] do
                local v = vertices[k]
                local normalX, normalY, normalZ = v.Normal:Unpack()
                local tangentX, tangentY, tangentZ = v.Tangent:Unpack()
                local binormalX, binormalY, binormalZ = v.Binormal:Unpack()
                local lightmapTangentX, lightmapTangentY, lightmapTangentZ = v.LightmapTangent:Unpack()
                local lightmapBinormalX, lightmapBinormalY, lightmapBinormalZ = v.LightmapBinormal:Unpack()
                local bumpmapU, bumpmapV, blend = v.BumpmapUV:Unpack()
                local lightmapU, lightmapV = v.LightmapUV:Unpack()
                local originX, originY, originZ = v.DispPaintOrigin:Unpack()
                local uvX = row1x * originX + row1y * originY + row1z * originZ + row1w
                local uvY = row2x * originX + row2y * originY + row2z * originZ + row2w
                local blend2 = bit.band(blend, 255)
                local blend3 = bit.band(bit.rshift(blend, 8), 255)
                local blend4 = bit.rshift(blend, 16)
                lightmapU = (lightmapU + lightmapOffsetX) / pageWidth
                lightmapV = (lightmapV + lightmapOffsetY) / pageHeight
                mesh.Color(blend2, blend3, blend4, 255)
                mesh.Position(v.Translation)
                mesh.Normal(normalX, normalY, normalZ)
                mesh.TexCoord(0, minU, minV, maxU, maxV)
                mesh.TexCoord(1, tangentX, tangentY, tangentZ, bumpmapU)
                mesh.TexCoord(2, binormalX, binormalY, binormalZ, bumpmapV)
                mesh.TexCoord(3, 0, 0, 0, bumpmapOffset)
                mesh.TexCoord(4, row1x, row1y, row1z, uvY)
                mesh.TexCoord(5, row2x, row2y, row2z, uvX)
                mesh.TexCoord(6, lightmapTangentX, lightmapTangentY, lightmapTangentZ, lightmapU)
                mesh.TexCoord(7, lightmapBinormalX, lightmapBinormalY, lightmapBinormalZ, lightmapV)
                mesh.AdvanceVertex()

                if debugVertices then
                    debugVertices[#debugVertices + 1] = {
                        Position           = v.Translation,
                        Color              = { blend2, blend3, blend4, 255 },
                        UVRange            = { minU, minV, maxU, maxV },
                        WorldTangent_U     = { tangentX, tangentY, tangentZ, bumpmapU },
                        WorldBinormal_V    = { binormalX, binormalY, binormalZ, bumpmapV },
                        WorldNormal_dU     = { normalX, normalY, normalZ, bumpmapOffset },
                        InkTangent_U       = { row1x, row1y, row1z, uvY },
                        InkBinormal_V      = { row2x, row2y, row2z, uvX },
                        LightmapTangent_U  = { lightmapTangentX, lightmapTangentY, lightmapTangentZ, lightmapU },
                        LightmapBinormal_V = { lightmapBinormalX, lightmapBinormalY, lightmapBinormalZ, lightmapV },
                        SurfaceIndex       = faceIndex,
                    }
                end
            end
        end

        mesh.End()
        if debugMeshData then
            debugMeshData[#debugMeshData + 1] = debugVertices
        end
    end
end

---Writes the positions and normals of all vertex batches into as few IMeshes as possible.
---The flashlight pass draws them with a single material, so the batches need no split by material.
---@param renderBatch   ss.RenderBatch                     Render batch to store the meshes.
---@param vertexBatches ss.VertexBatches.MeshVertexBatch[] Vertex batches of the model.
---@param surfaceInfo   ss.PrecachedData.SurfaceInfo       Cached BSP surface data.
function VertexBatches.WriteFlashlightMeshes(renderBatch, vertexBatches, surfaceInfo)
    local flashlightMaterial = Material "splashsweps/shaders/lightmappedgeneric"
    local numRemaining = 0
    for _, vertexBatch in ipairs(vertexBatches) do
        numRemaining = numRemaining + vertexBatch.NumVertices
    end

    -- Each batch holds whole triangles, so a full mesh never splits one.
    local numInMesh, meshSize = 0, 0
    for _, vertexBatch in ipairs(vertexBatches) do
        local faceRanges = vertexBatch.FaceRanges
        for r = 1, #faceRanges, 3 do
            local vertices = surfaceInfo.Surfaces[faceRanges[r]].Vertices
            for k = faceRanges[r + 1], faceRanges[r + 2] do
                if numInMesh == meshSize then
                    local m = Mesh(flashlightMaterial)
                    renderBatch.FlashlightMeshes[#renderBatch.FlashlightMeshes + 1] = m
                    numInMesh, meshSize = 0, math.min(MAX_VERTICES, numRemaining)
                    mesh.Begin(m, MATERIAL_TRIANGLES, meshSize / 3)
                end

                local v = vertices[k]
                mesh.Position(v.Translation)
                mesh.Normal(v.Normal)
                mesh.AdvanceVertex()
                numInMesh = numInMesh + 1
                numRemaining = numRemaining - 1
                if numInMesh == meshSize then
                    mesh.End()
                end
            end
        end
    end
end

return VertexBatches
