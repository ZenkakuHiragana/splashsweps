
-- Splits the surfaces of the world ink meshes into draw-sized batches,
-- and writes their vertices from the map cache into IMeshes.

---@class ss
local ss = SplashSWEPs

---@class ss.VertexBatchesModule
local VertexBatches = ss.module "splashsweps/client/mapload/vertexbatches"

local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation
local MAX_VERTICES  = MAX_TRIANGLES * 3
local floor = math.floor

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

---A draw-sized range of the triangles of the surfaces that maps one-to-one to a render batch entry.
---@class ss.VertexBatches.MeshVertexBatch
---@field SortID      integer   Lightmap/material group ID used to choose the render material.
---@field NumVertices integer   Number of vertices written into one IMesh.
---Face index, and the first and the last positions in VertexIndices of the surface, for each part in this batch, repeated.
---@field FaceRanges  integer[]

---Splits mesh groups into draw-sized vertex batches for mesh.Begin.
---A batch ends when it reaches the limit of the mesh library, even in the middle of the triangles of a surface.
---@param surfaceInfo ss.PrecachedData.SurfaceInfo Cached BSP surface data.
---@param meshGroups  ss.Lightmaps.MeshGroup[]     Mesh groups for one BSP model.
---@return ss.VertexBatches.MeshVertexBatch[] vertexBatches Draw-sized vertex batches.
function VertexBatches.Build(surfaceInfo, meshGroups)
    local vertexBatches = {} ---@type ss.VertexBatches.MeshVertexBatch[]
    for _, meshGroup in ipairs(meshGroups) do
        local vertexBatch = nil ---@type ss.VertexBatches.MeshVertexBatch?
        for _, faceIndex in ipairs(meshGroup.FaceIndices) do
            local numVertices = surfaceInfo.Surfaces[faceIndex].NumVertexIndices
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
---@param surfaceInfo       ss.PrecachedData.SurfaceInfo   Cached BSP surface data.
---@param placements        ss.InkMapLayout.Placement[]    Face-indexed placements in the ink map.
---@param faceLightmaps     ss.Lightmaps.FaceLightmap[]    Face-indexed lightmap placements.
---@param debugMeshData     ss.VertexBatches.MeshVertex[][]? Receives the vertices written into each IMesh if given.
function VertexBatches.WriteMeshes(renderBatch, vertexBatches, surfaceInfo, placements, faceLightmaps, debugMeshData)
    local scale = surfaceInfo.HammerUnitsToUV
    for i, vertexBatch in ipairs(vertexBatches) do
        local debugVertices = debugMeshData and {} ---@type ss.VertexBatches.MeshVertex[]?
        local faceRanges = vertexBatch.FaceRanges
        mesh.Begin(renderBatch[i].Mesh, MATERIAL_TRIANGLES, vertexBatch.NumVertices / 3)
        for r = 1, #faceRanges, 3 do
            local faceIndex = faceRanges[r]
            local surf      = surfaceInfo.Surfaces[faceIndex]
            local placement = placements[faceIndex]
            local lightmap  = faceLightmaps[faceIndex]
            local vertexIndices = surf.VertexIndices

            -- The values shared by the vertices of the surface.
            local row1, row2 = placement.WorldToUVRow1, placement.WorldToUVRow2
            local row1x, row1y, row1z, row1w = row1[1] * scale, row1[2] * scale, row1[3] * scale, row1[4] * scale
            local row2x, row2y, row2z, row2w = row2[1] * scale, row2[2] * scale, row2[3] * scale, row2[4] * scale
            local range = placement.UVRange
            local minU, minV, maxU, maxV = range[1], range[2], range[3], range[4]
            local bumpmapOffset = lightmap.BumpmapOffset
            local lightmapOffsetX, lightmapOffsetY = lightmap.OffsetX, lightmap.OffsetY
            local pageWidth, pageHeight = lightmap.PageWidth, lightmap.PageHeight

            for n = faceRanges[r + 1], faceRanges[r + 2] do
                local k = vertexIndices[n]
                local j = floor((n + 2) / 3) -- The triangle of the vertex
                local positionX, positionY, positionZ = surf.PositionX[k], surf.PositionY[k], surf.PositionZ[k]
                local normalX, normalY, normalZ = surf.NormalX[k], surf.NormalY[k], surf.NormalZ[k]
                local tangentX, tangentY, tangentZ = surf.TangentX[k], surf.TangentY[k], surf.TangentZ[k]
                local binormalX, binormalY, binormalZ = surf.BinormalX[k], surf.BinormalY[k], surf.BinormalZ[k]
                local lightmapTangentX, lightmapTangentY, lightmapTangentZ
                    = surf.LightmapTangentX[j], surf.LightmapTangentY[j], surf.LightmapTangentZ[j]
                local lightmapBinormalX, lightmapBinormalY, lightmapBinormalZ
                    = surf.LightmapBinormalX[j], surf.LightmapBinormalY[j], surf.LightmapBinormalZ[j]
                local bumpmapU, bumpmapV = surf.BumpmapU[k], surf.BumpmapV[k]
                local blend2, blend3, blend4 = surf.Blend2[k], surf.Blend3[k], surf.Blend4[k]
                local originX, originY, originZ = surf.PaintOriginX[k], surf.PaintOriginY[k], surf.PaintOriginZ[k]
                local uvX = row1x * originX + row1y * originY + row1z * originZ + row1w
                local uvY = row2x * originX + row2y * originY + row2z * originZ + row2w
                local lightmapU = (surf.LightmapU[k] + lightmapOffsetX) / pageWidth
                local lightmapV = (surf.LightmapV[k] + lightmapOffsetY) / pageHeight
                mesh.Color(blend2, blend3, blend4, 255)
                mesh.Position(positionX, positionY, positionZ)
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
                        Position           = Vector(positionX, positionY, positionZ),
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
            local surf = surfaceInfo.Surfaces[faceRanges[r]]
            local vertexIndices = surf.VertexIndices
            for n = faceRanges[r + 1], faceRanges[r + 2] do
                if numInMesh == meshSize then
                    local m = Mesh(flashlightMaterial)
                    renderBatch.FlashlightMeshes[#renderBatch.FlashlightMeshes + 1] = m
                    numInMesh, meshSize = 0, math.min(MAX_VERTICES, numRemaining)
                    mesh.Begin(m, MATERIAL_TRIANGLES, meshSize / 3)
                end

                local k = vertexIndices[n]
                mesh.Position(surf.PositionX[k], surf.PositionY[k], surf.PositionZ[k])
                mesh.Normal(surf.NormalX[k], surf.NormalY[k], surf.NormalZ[k])
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
