
-- Draws the ink meshes of the world and static props in each view and composes reflections on them.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local RenderTargets      = ss.import "splashsweps/client/render/rendertargets"
local StaticPropRenderer = ss.import "splashsweps/client/render/staticproprenderer"
local WorldMesh          = ss.import "splashsweps/client/render/worldmesh"

local FullFrameFb1 = render.GetScreenEffectTexture(1)
local SceneCopyMaterial = Material "splashsweps/shaders/scene_copy"
local InkColorInitMaterial = Material "splashsweps/shaders/gbuf_inkcolor_init"
local FlashlightInitMaterial = Material "splashsweps/shaders/flashlight_init"
local FlashlightBakeMaterial = Material "splashsweps/shaders/lightmappedgeneric"
local SSRTraceMaterial = Material "splashsweps/shaders/inkssr"
local SSRCompositeMaterial = Material "splashsweps/shaders/inkssr_compose"
local SSRDownsampleMaterial = Material "splashsweps/shaders/inkssr_downsample"
local InkWaterMaterial = Material "splashsweps/shaders/inkmesh"
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"

local ScreenQuadCorners = { Vector(0, 0, 0), Vector(1, 0, 0), Vector(1, 1, 0), Vector(0, 1, 0) }

local currentNormalMaterial = nil ---@type IMaterial?
local function DrawNormalMesh(m, _)
    local mat = m.Material
    if currentNormalMaterial ~= mat then
        render.SetMaterial(mat)
        currentNormalMaterial = mat
    end
    m.Mesh:Draw()
end

---Draws the mesh with the material already set.
local function DrawMeshOnly(m, _)
    m.Mesh:Draw()
end

local function DrawNormalMeshes()
    currentNormalMaterial = nil
    WorldMesh.Draw(DrawNormalMesh)
end

local SSRViewMatrix = Matrix()
local function UpdateViewParameters()
    local view = render.GetViewSetup()
    local origin = view.origin
    local angles = view.angles
    local aspect = view.aspect
    local tanHalfFovX = math.tan(math.rad(view.fov) * 0.5)
    local tanHalfFovY = tanHalfFovX / aspect
    local right = angles:Right() * tanHalfFovX
    local up = angles:Up() * tanHalfFovY
    local forward = angles:Forward()
    SSRViewMatrix:SetUnpacked(
        right.x, right.y, right.z, 0,
        up.x, up.y, up.z, 0,
        forward.x, forward.y, forward.z, 0,
        origin.x, origin.y, origin.z, 1)
    SSRTraceMaterial:SetMatrix("$viewprojmat", SSRViewMatrix)

    -- Maps the view depth to the depth buffer value of the current projection.
    local znear, zfar = view.znear, view.zfar
    FlashlightInitMaterial:SetFloat("$c0_x", zfar / (zfar - znear))
    FlashlightInitMaterial:SetFloat("$c0_y", -znear * zfar / (zfar - znear))
end

-- IMAGE_FORMAT_R32F = 27, Single-channel 32-bit floating point
hook.Add("NeedsDepthPass", "SplashSWEPs: Needs depth pass", function() return true end)
GetRenderTargetEx("_rt_resolvedfullframedepth", ScrW(), ScrH(),
    RT_SIZE_FULL_FRAME_BUFFER,
    MATERIAL_RT_DEPTH_SHARED,
    bit.bor(4, 8, 256, 512, 65536), 0, 27)

hook.Add("PreDrawTranslucentRenderables", "SplashSWEPs: Draw ink",
function(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingDepth or bDrawingSkybox then return end
    if CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    local rt = render.GetRenderTarget()
    local isDrawingWater = rt and rt:GetName():find "_rt_waterref"
    if isDrawingWater then
        render.SetMaterial(InkWaterMaterial)
        WorldMesh.Draw(DrawMeshOnly)
        return
    end

    -- Frame buffer copy for SSR reflection and underlay sampling
    UpdateViewParameters()
    render.CopyRenderTargetToTexture(FullFrameFb1)
    render.PushRenderTarget(RenderTargets.Frame.InkColor)
    render.ClearDepth(false)
    render.SetMaterial(InkColorInitMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.PopRenderTarget()

    -- Upper half of SceneAndFlashlight: frame buffer color and view depth.
    -- Lower half: light the ink meshes receive from flashlights, behind the scene depth.
    local w, h = ScrW(), ScrH()
    render.PushRenderTarget(RenderTargets.Frame.SceneAndFlashlight, 0, 0, w, h)
    render.SetMaterial(SceneCopyMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.SetViewPort(0, h, w, h)
    render.SetMaterial(FlashlightInitMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.RenderFlashlights(function()
        render.SetMaterial(FlashlightBakeMaterial)
        WorldMesh.DrawFlashlight()
    end)
    render.PopRenderTarget()

    if StaticPropRenderer.HasQueued() then
        render.PushRenderTarget(RenderTargets.Frame.StaticPropFlashlight)
        if RenderTargets.IsStaticPropFlashlightSharingDepth() then
            render.Clear(0, 0, 0, 0)
        else
            render.SetMaterial(FlashlightInitMaterial)
            render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
        end
        render.RenderFlashlights(StaticPropRenderer.DrawFlashlight)
        render.PopRenderTarget()
    end

    render.PushRenderTarget(RenderTargets.Frame.InkColor)
    render.SetRenderTargetEx(1, RenderTargets.Frame.InkNormals)
    render.SetRenderTargetEx(2, RenderTargets.Frame.Reflection)
    render.SetRenderTargetEx(3, RenderTargets.Frame.Envmap)
    render.OverrideDepthEnable(true, true)
    DrawNormalMeshes()
    StaticPropRenderer.DrawInk()
    render.OverrideDepthEnable(false)
    render.PopRenderTarget()

    -- Shrunk copy of InkColor, blurred reflections on rough surfaces read it
    render.PushRenderTarget(RenderTargets.Frame.InkColorBlur)
    render.SetMaterial(SSRDownsampleMaterial)
    render.DrawScreenQuad()
    render.PopRenderTarget()

    render.PushRenderTarget(RenderTargets.Frame.SSRResult)
    render.Clear(0, 0, 0, 0)
    render.SetMaterial(SSRTraceMaterial)
    render.DrawScreenQuad()
    render.PopRenderTarget()

    render.SetMaterial(SSRCompositeMaterial)
    render.DrawScreenQuad()
end)
