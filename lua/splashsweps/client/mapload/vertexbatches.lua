
-- Builds the vertices of the world ink meshes from the map cache and writes them into IMeshes.

---@class ss
local ss = SplashSWEPs
local PrecachedData = ss.import "splashsweps/shared/typing/precachedata"
local Util          = ss.import "splashsweps/shared/util"

---@class ss.VertexBatchesModule
local VertexBatches = ss.module "splashsweps/client/mapload/vertexbatches"

local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation

---One vertex worth of packed data passed to inkmesh_vs30.
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
---@field SurfaceIndex       integer? Source BSP face index, kept for debug mesh inspection.

---A draw-sized vertex list that maps one-to-one to a render batch entry.
---@class ss.VertexBatches.MeshVertexBatch
---@field SortID   integer Lightmap/material group ID used to choose the render material.
---@field Vertices ss.VertexBatches.MeshVertex[] Vertices written into one IMesh.

---Expands mesh groups into draw-sized vertex batches for mesh.Begin.
---@param surfaceInfo ss.PrecachedData.SurfaceInfo  Cached BSP surface data with packed lightmap UVs applied.
---@param meshGroups  ss.Lightmaps.MeshGroup[] Mesh groups for one BSP model.
---@param bumpmapOffsetsByFace number[]             Face-indexed lightmap U offsets for bumped lightmaps.
---@return ss.VertexBatches.MeshVertexBatch[] vertexBatches Draw-sized vertex data batches.
function VertexBatches.Build(surfaceInfo, meshGroups, bumpmapOffsetsByFace)
    local rtIndex       = #PrecachedData.InkMapResolutions
    local rtSize        = PrecachedData.InkMapResolutions[rtIndex]
    local bilinearGuard = ss.RT_BILINEAR_GUARD_PIXELS / rtSize
    local scale         = surfaceInfo.UVScales[rtIndex]
    local worldToUV     = Matrix()
    worldToUV:SetScale(Util.vector_one * scale)
    local vertexBatches = {} ---@type ss.VertexBatches.MeshVertexBatch[]
    for _, meshGroup in ipairs(meshGroups) do
        local currentVertices = nil ---@type ss.VertexBatches.MeshVertex[]?
        local function StartVertexBatch()
            currentVertices = {}
            vertexBatches[#vertexBatches + 1] = {
                SortID = meshGroup.SortID,
                Vertices = currentVertices,
            }
        end

        local function ContinueVertexBatch()
            if not currentVertices then StartVertexBatch() end
            if #currentVertices < MAX_TRIANGLES * 3 then return end
            StartVertexBatch()
        end

        for _, faceIndex in ipairs(meshGroup.FaceIndices) do
            local surf = surfaceInfo.Surfaces[faceIndex]
            local uvInfo = surf.UVInfo[rtIndex]
            worldToUV:SetAngles(uvInfo.Angle)
            for _, v in ipairs(surf.Vertices) do
                ContinueVertexBatch()
                local tr = v.DispPaintOrigin or v.Translation
                local uv = worldToUV * tr + uvInfo.Translation * scale
                local blend = v.BumpmapUV.z
                currentVertices[#currentVertices + 1] = {
                    Position = v.Translation,
                    Color = {
                        bit.band(blend, 255),
                        bit.band(bit.rshift(blend, 8), 255),
                        bit.rshift(blend, 16),
                        255,
                    },
                    UVRange = {
                        uvInfo.OffsetU + bilinearGuard,
                        uvInfo.OffsetV + bilinearGuard,
                        uvInfo.OffsetU + uvInfo.Width  - bilinearGuard,
                        uvInfo.OffsetV + uvInfo.Height - bilinearGuard,
                    },
                    WorldTangent_U = {
                        v.Tangent.x,
                        v.Tangent.y,
                        v.Tangent.z,
                        v.BumpmapUV.x,
                    },
                    WorldBinormal_V = {
                        v.Binormal.x,
                        v.Binormal.y,
                        v.Binormal.z,
                        v.BumpmapUV.y,
                    },
                    WorldNormal_dU = {
                        v.Normal.x,
                        v.Normal.y,
                        v.Normal.z,
                        bumpmapOffsetsByFace[faceIndex],
                    },
                    InkTangent_U = {
                        worldToUV:GetField(1, 1),
                        worldToUV:GetField(1, 2),
                        worldToUV:GetField(1, 3),
                        uv.y,
                    },
                    InkBinormal_V = {
                        worldToUV:GetField(2, 1),
                        worldToUV:GetField(2, 2),
                        worldToUV:GetField(2, 3),
                        uv.x,
                    },
                    LightmapTangent_U = {
                        v.LightmapTangent.x,
                        v.LightmapTangent.y,
                        v.LightmapTangent.z,
                        v.LightmapUV.x,
                    },
                    LightmapBinormal_V = {
                        v.LightmapBinormal.x,
                        v.LightmapBinormal.y,
                        v.LightmapBinormal.z,
                        v.LightmapUV.y,
                    },
                    SurfaceIndex = faceIndex,
                }
            end
        end
    end

    return vertexBatches
end

---Writes each vertex batch into the matching ink IMesh.
---@param renderBatch   ss.RenderBatch                      Render entries created from the same vertexBatches order.
---@param vertexBatches ss.VertexBatches.MeshVertexBatch[] Vertex batches to write one-to-one with renderBatch.
function VertexBatches.WriteMeshes(renderBatch, vertexBatches)
    for i, vertexBatch in ipairs(vertexBatches) do
        local vertices = vertexBatch.Vertices
        mesh.Begin(renderBatch[i].Mesh, MATERIAL_TRIANGLES, #vertices / 3)
        for _, v in ipairs(vertices) do
            mesh.Color(unpack(v.Color))
            mesh.Position(v.Position)
            mesh.Normal(v.WorldNormal_dU[1], v.WorldNormal_dU[2], v.WorldNormal_dU[3])
            mesh.TexCoord(0, unpack(v.UVRange))
            mesh.TexCoord(1, unpack(v.WorldTangent_U))
            mesh.TexCoord(2, unpack(v.WorldBinormal_V))
            mesh.TexCoord(3, 0, 0, 0, v.WorldNormal_dU[4])
            mesh.TexCoord(4, unpack(v.InkTangent_U))
            mesh.TexCoord(5, unpack(v.InkBinormal_V))
            mesh.TexCoord(6, unpack(v.LightmapTangent_U))
            mesh.TexCoord(7, unpack(v.LightmapBinormal_V))
            mesh.AdvanceVertex()
        end
        mesh.End()
    end
end

---Writes the positions and normals of all vertex batches into as few IMeshes as possible.
---The flashlight pass draws them with a single material, so the batches need no split by material.
---@param renderBatch   ss.RenderBatch                      Render batch to store the meshes.
---@param vertexBatches ss.VertexBatches.MeshVertexBatch[] Vertex batches of the model.
function VertexBatches.WriteFlashlightMeshes(renderBatch, vertexBatches)
    local flashlightMaterial = Material "splashsweps/shaders/lightmappedgeneric"
    local vertices = {} ---@type ss.VertexBatches.MeshVertex[]
    local function flush()
        if #vertices == 0 then return end
        local m = Mesh(flashlightMaterial)
        mesh.Begin(m, MATERIAL_TRIANGLES, #vertices / 3)
        for _, v in ipairs(vertices) do
            mesh.Position(v.Position)
            mesh.Normal(v.WorldNormal_dU[1], v.WorldNormal_dU[2], v.WorldNormal_dU[3])
            mesh.AdvanceVertex()
        end
        mesh.End()
        renderBatch.FlashlightMeshes[#renderBatch.FlashlightMeshes + 1] = m
        vertices = {}
    end

    -- Each batch holds whole triangles, so a full mesh never splits one.
    for _, vertexBatch in ipairs(vertexBatches) do
        for _, v in ipairs(vertexBatch.Vertices) do
            if #vertices >= MAX_TRIANGLES * 3 then flush() end
            vertices[#vertices + 1] = v
        end
    end
    flush()
end

return VertexBatches
