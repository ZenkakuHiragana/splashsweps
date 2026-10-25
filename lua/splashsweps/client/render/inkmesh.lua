
-- Ink meshes of the worldspawn and brush entities, built from the map cache.

---@class ss
local ss = SplashSWEPs
local InkMeshMaterial = ss.import "splashsweps/client/mapload/inkmeshmaterial"
local Lightmaps       = ss.import "splashsweps/client/mapload/lightmaps"
local MapMaterials    = ss.import "splashsweps/client/mapload/materials"
local Underlay        = ss.import "splashsweps/client/mapload/underlay"
local UnderlaySync    = ss.import "splashsweps/client/render/underlaysync"
local VertexBatches   = ss.import "splashsweps/client/mapload/vertexbatches"

---@class ss.InkMeshModule
local InkMesh = ss.module "splashsweps/client/render/inkmesh"

---@class ss.MeshData
---@field EnvmapSource IMaterial? For some reason $envmap is not set at InitPostEntity so use this to fetch later.
---@field Material IMaterial The material to draw this mesh.
---@field Mesh IMesh The IMesh object to render this part of surfaces.

---@class ss.RenderBatch
---@field BrushEntity Entity? The brush entity tied to this mesh, if any.
---@field FlashlightMeshes IMesh[] Positions and normals of all the surfaces in this model, for the flashlight pass.
---@field [integer] ss.MeshData List of meshes to render this model.


---@class ss.InkMeshModule.State
---@field Batches       ss.RenderBatch[] Ink meshes of each BSP model, indexed by 1-based model index.
---@field DebugMeshData ss.VertexBatches.MeshVertex[][] Vertices written into the meshes, kept for debug mesh inspection.
local state = ss.state("splashsweps/client/render/inkmesh", {
    Batches = {},
    DebugMeshData = {},
}) ---@type ss.InkMeshModule.State

---Ink meshes of each BSP model, indexed by 1-based model index.
InkMesh.Batches = state.Batches

---Vertices written into the meshes, kept for debug mesh inspection.
InkMesh.DebugMeshData = state.DebugMeshData

---Copies vertex batches into InkMesh.DebugMeshData without exposing batch metadata.
---@param debugMeshData ss.VertexBatches.MeshVertex[][]    Destination debug vertex lists.
---@param vertexBatches ss.VertexBatches.MeshVertexBatch[] Source draw-sized vertex batches.
local function storeDebugMeshData(debugMeshData, vertexBatches)
    for _, vertexBatch in ipairs(vertexBatches) do
        local dest = {}
        for _, v in ipairs(vertexBatch.Vertices) do table.insert(dest, v) end
        table.insert(debugMeshData, dest)
    end
end

---Reads through BSP models which includes the worldspawn and brush entities and constructs IMeshes from them.
---@param surfaceInfo   ss.PrecachedData.SurfaceInfo
---@param numModels     integer
---@param materialNames string[]
function InkMesh.Setup(surfaceInfo, numModels, materialNames)
    local entities = {} ---@type Entity[]
    for _, e in ipairs(ents.GetAll()) do
        local modelName = e:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if e ~= game.GetWorld() and i and 0 < i and i <= numModels then
            entities[i] = e
        end
    end

    hook.Add("OnEntityCreated", "SplashSWEPs: Check brush entities", function(ent)
        local modelName = ent:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if i and 0 < i and i <= numModels then
            state.Batches[i + 1].BrushEntity = ent
        end
    end)

    for i = 1, numModels do
        state.Batches[i] = { BrushEntity = entities[i - 1], FlashlightMeshes = {} }
    end

    InkMeshMaterial.SetupWater()
    local materialInfo      = MapMaterials.Enumerate(materialNames, surfaceInfo.Cubemaps)
    local lightmapLayout    = Lightmaps.Pack(surfaceInfo, materialInfo)
    local meshGroupsByModel = Lightmaps.BuildMeshGroups(surfaceInfo, lightmapLayout)
    local bumpmapOffsets    = Lightmaps.BuildBumpmapOffsets(lightmapLayout)
    UnderlaySync.WatchUnderlays(materialInfo)
    Underlay.Build(materialInfo)

    table.Empty(state.DebugMeshData)
    for modelIndex, meshGroups in pairs(meshGroupsByModel) do
        local vertexBatches = VertexBatches.Build(surfaceInfo, meshGroups, bumpmapOffsets)
        local renderBatch = state.Batches[modelIndex]
        for _, vertexBatch in ipairs(vertexBatches) do
            local mat = InkMeshMaterial.Create(lightmapLayout, vertexBatch.SortID)
            renderBatch[#renderBatch + 1] = {
                Material = mat,
                Mesh     = Mesh(mat),
            }
        end
        storeDebugMeshData(state.DebugMeshData, vertexBatches)
        VertexBatches.WriteMeshes(renderBatch, vertexBatches)
        VertexBatches.WriteFlashlightMeshes(renderBatch, vertexBatches)
    end
end

---Draws the ink meshes of the worldspawn and brush entities by the handler.
---@param handler fun(m: ss.MeshData, ent: Entity?)
function InkMesh.Draw(handler)
    for _, model in ipairs(state.Batches) do -- Draw ink surface
        local ent = model.BrushEntity
        if #model > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model) do
                handler(m, ent)
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
end

---Draws the meshes for the flashlight pass with the material already set.
function InkMesh.DrawFlashlight()
    for _, model in ipairs(state.Batches) do
        local ent = model.BrushEntity
        if #model.FlashlightMeshes > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model.FlashlightMeshes) do
                m:Draw()
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
end

return InkMesh
