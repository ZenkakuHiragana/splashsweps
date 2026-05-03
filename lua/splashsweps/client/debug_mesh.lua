-- Vertex-input probe for Screenspace_General_8tex
--
-- Goal:
--   Verify which vertex semantics arrive for IMesh:Draw() and
--   IMesh:DrawSkinned() using the existing debug shader pair.
--
-- Usage:
--   ss_debug_mesh_probe        : Toggle probe ON/OFF
--   ss_debug_mesh_probe_spawn  : Spawn or refresh the test meshes
--   ss_debug_mesh_probe_skin   : Toggle the skinned test mesh

---@class ss
local ss = SplashSWEPs
if not ss then return end

local enabled = false
local showSkinned = true
local probeMaterial = Material("splashsweps/shaders/debug_probe")

local hook3D = "SplashSWEPs: Debug Mesh Probe 3D"

local solidMesh ---@type IMesh?
local skinnedMesh ---@type IMesh?
local skinBones ---@type VMatrix[]

local function MakeMatrix(pos)
    local m = Matrix()
    m:Identity()
    m:SetTranslation(pos)
    return m
end

local function BuildSolidMesh()
    solidMesh = Mesh(probeMaterial)
    local verts = {
        { pos = Vector(-16, -16, 0), u = 0, v = 0, normal = Vector(0, 0, 1), color = Color(255, 64, 64), tangent = Vector(1, 0, 0) },
        { pos = Vector(16, -16, 0), u = 1, v = 0, normal = Vector(0, 0, 1), color = Color(64, 255, 64), tangent = Vector(1, 0, 0) },
        { pos = Vector(16, 16, 0), u = 1, v = 1, normal = Vector(0, 0, 1), color = Color(64, 64, 255), tangent = Vector(1, 0, 0) },
        { pos = Vector(-16, -16, 0), u = 0, v = 0, normal = Vector(0, 0, 1), color = Color(255, 64, 64), tangent = Vector(1, 0, 0) },
        { pos = Vector(16, 16, 0), u = 1, v = 1, normal = Vector(0, 0, 1), color = Color(64, 64, 255), tangent = Vector(1, 0, 0) },
        { pos = Vector(-16, 16, 0), u = 0, v = 1, normal = Vector(0, 0, 1), color = Color(255, 255, 64), tangent = Vector(1, 0, 0) },
    }
    mesh.Begin(solidMesh, MATERIAL_TRIANGLES, #verts / 3)
    for _, v in ipairs(verts) do
        mesh.Position(v.pos)
        mesh.Normal(v.normal)
        mesh.Color(v.color.r, v.color.g, v.color.b, 255)
        mesh.TexCoord(0, v.u, v.v)
        mesh.UserData(v.tangent.x, v.tangent.y, v.tangent.z, 1)
        mesh.AdvanceVertex()
    end
    mesh.End()
end

local function BuildSkinnedMesh()
    skinnedMesh = Mesh(probeMaterial, 2)
    local tris = {
        { Vector(-16, -16, 0), Vector(16, -16, 0), Vector(16, 16, 0) },
        { Vector(-16, -16, 0), Vector(16, 16, 0), Vector(-16, 16, 0) },
    }
    mesh.Begin(skinnedMesh, MATERIAL_TRIANGLES, 2)
    for ti, tri in ipairs(tris) do
        for vi, pos in ipairs(tri) do
            mesh.Position(pos)
            mesh.Normal(Vector(0, 0, 1))
            mesh.Color(255, 255 - ti * 80, 64 + vi * 64, 255)
            mesh.TexCoord(0, (vi == 2 or vi == 3) and 1 or 0, vi == 3 and 1 or 0)
            mesh.BoneData(0, 0, 0.5)
            mesh.BoneData(1, 1, 0.5)
            mesh.UserData(1, 0, 0, 1)
            mesh.AdvanceVertex()
        end
    end
    mesh.End()

    skinBones = {
        MakeMatrix(Vector(0, 0, 0)),
        MakeMatrix(Vector(0, 0, 24)),
    }
end

local function EnsureMeshes()
    if not solidMesh or not solidMesh:IsValid() then
        BuildSolidMesh()
    end
    if not skinnedMesh or not skinnedMesh:IsValid() then
        BuildSkinnedMesh()
    end
end

local function DrawProbe()
    if not enabled then return end
    EnsureMeshes()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local basePos = ply:GetPos() + Vector(0, 0, 96)

    render.SetMaterial(probeMaterial)
    local solidMat = Matrix()
    solidMat:SetTranslation(basePos)
    cam.PushModelMatrix(solidMat)
    if solidMesh then
        solidMesh:Draw()
    end
    cam.PopModelMatrix()

    if showSkinned and skinnedMesh and skinBones then
        local skinMat = Matrix()
        skinMat:Identity()
        skinMat:SetTranslation(basePos + Vector(96, 0, 0))
        cam.PushModelMatrix(skinMat)
        skinnedMesh:DrawSkinned(skinBones)
        cam.PopModelMatrix()
    end
end

local function Enable()
    enabled = true
    hook.Add("PostDrawOpaqueRenderables", hook3D, DrawProbe)
    print("[SplashSWEPs] Debug mesh probe: ON")
end

local function Disable()
    enabled = false
    hook.Remove("PostDrawOpaqueRenderables", hook3D)
    print("[SplashSWEPs] Debug mesh probe: OFF")
end

concommand.Add("ss_debug_mesh_probe", function()
    if enabled then Disable() else Enable() end
end)

concommand.Add("ss_debug_mesh_probe_spawn", function()
    BuildSolidMesh()
    BuildSkinnedMesh()
    print("[SplashSWEPs] Debug mesh probe meshes rebuilt")
end)

concommand.Add("ss_reload_shader", function(_, _, _)
    local vs = file.Find("shaders/fxc/splashsweps/*_inkmesh_vs30.vcs", "GAME", "datedesc")
    local ps = file.Find("shaders/fxc/splashsweps/*_inkmesh_ps30.vcs", "GAME", "datedesc")
    if not (vs and ps) then return end
    print(string.format("Reloading shader: %s, %s", vs[1], ps[1]))
    for _, batch in ipairs(ss.RenderBatches) do
        for _, model in ipairs(batch) do
            model.Material:SetString("$vertexshader", "splashsweps/" .. vs[1]:sub(1, -5))
            model.Material:SetString("$pixshader", "splashsweps/" .. ps[1]:sub(1, -5))
            model.Material:Recompute()
        end
    end
    ss.ClearAllInk()
end)

concommand.Add("ss_debug_mesh_probe_skin", function()
    showSkinned = not showSkinned
    print(string.format("[SplashSWEPs] Skinned probe mesh: %s", showSkinned and "ON" or "OFF"))
end)

print("[SplashSWEPs] Debug mesh probe loaded. Use ss_debug_mesh_probe.")
