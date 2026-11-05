
-- Ink meshes of the worldspawn and brush entities, built from the map cache.

---@class ss
local ss = SplashSWEPs
local InkMeshMaterial    = ss.import "splashsweps/client/mapload/inkmeshmaterial"
local Lightmaps          = ss.import "splashsweps/client/mapload/lightmaps"
local MapMaterials       = ss.import "splashsweps/client/mapload/materials"
local UnderlayBlendAtlas = ss.import "splashsweps/client/mapload/underlayblendatlas"
local UnderlaySync       = ss.import "splashsweps/client/render/underlaysync"
local VertexBatches      = ss.import "splashsweps/client/mapload/vertexbatches"

---@class ss.InkMeshModule
local InkMesh = ss.module "splashsweps/client/render/inkmesh"

---@class ss.InkMesh.Part
---@field EnvmapSource IMaterial? For some reason $envmap is not set at InitPostEntity so use this to fetch later.
---@field Material IMaterial The material to draw this mesh.
---@field Mesh IMesh The IMesh object to render this part of surfaces.

---@class ss.InkMesh.ModelMeshes
---@field BrushEntity Entity? The brush entity tied to this mesh, if any.
---@field FlashlightMeshes IMesh[] Positions and normals of all the surfaces in this model, for the flashlight pass.
---@field [integer] ss.InkMesh.Part List of meshes to render this model.


---@class ss.InkMeshModule.State
---@field ModelMeshes   ss.InkMesh.ModelMeshes[]        Ink meshes of each BSP model, indexed by 1-based model index.
---@field DebugMeshData ss.VertexBatches.MeshVertex[][] Vertices written into the meshes, kept for debug mesh inspection if InkMesh.Setup is asked to.
local state = ss.state("splashsweps/client/render/inkmesh", {
    ModelMeshes = {},
    DebugMeshData = {},
})

---Ink meshes of each BSP model, indexed by 1-based model index.
InkMesh.ModelMeshes = state.ModelMeshes

---Vertices written into the meshes, kept for debug mesh inspection if InkMesh.Setup is asked to.
InkMesh.DebugMeshData = state.DebugMeshData

---Reads through BSP models which includes the worldspawn and brush entities and constructs IMeshes from them.
---@param cache             ss.MapCache
---@param lightmaps         ss.MapCache.LightmapInfo[] Lightmap info of the faces the engine uses, LDR or HDR.
---@param placements        ss.InkMapLayout.Placement[] Placements in the ink map indexed by the surfaces of the cache.
---@param keepDebugMeshData boolean Keeps the vertices in InkMesh.DebugMeshData, which takes as much memory as the meshes.
function InkMesh.Setup(cache, lightmaps, placements, keepDebugMeshData)
    local numModels = cache.NumModels
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
            state.ModelMeshes[i + 1].BrushEntity = ent
        end
    end)

    for i = 1, numModels do
        state.ModelMeshes[i] = { BrushEntity = entities[i - 1], FlashlightMeshes = {} }
    end

    InkMeshMaterial.SetupWater()
    local materialInfo      = MapMaterials.Enumerate(cache.MaterialNames, cache.Cubemaps)
    local lightmapLayout    = Lightmaps.Pack(lightmaps, materialInfo)
    local meshGroupsByModel = Lightmaps.BuildMeshGroups(cache, lightmapLayout)
    local surfaceLightmaps  = Lightmaps.BuildSurfaceLightmaps(lightmapLayout)
    UnderlaySync.WatchUnderlays(materialInfo)
    UnderlayBlendAtlas.Build(materialInfo)

    table.Empty(state.DebugMeshData)
    local debugMeshData = keepDebugMeshData and state.DebugMeshData or nil
    for modelIndex, meshGroups in pairs(meshGroupsByModel) do
        local vertexBatches = VertexBatches.Build(cache, meshGroups)
        local modelMeshes   = state.ModelMeshes[modelIndex]
        for _, vertexBatch in ipairs(vertexBatches) do
            local mat = InkMeshMaterial.Create(lightmapLayout, vertexBatch.SortID)
            modelMeshes[#modelMeshes + 1] = {
                Material = mat,
                Mesh     = Mesh(mat),
            }
        end
        VertexBatches.WriteMeshes(modelMeshes, vertexBatches, cache, placements, surfaceLightmaps, debugMeshData)
        VertexBatches.WriteFlashlightMeshes(modelMeshes, vertexBatches, cache)
    end
end

---Draws the ink meshes of the worldspawn and brush entities by the handler.
---@param handler fun(m: ss.InkMesh.Part, ent: Entity?)
function InkMesh.Draw(handler)
    for _, model in ipairs(state.ModelMeshes) do -- Draw ink surface
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
    for _, model in ipairs(state.ModelMeshes) do
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
