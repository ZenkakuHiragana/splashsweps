
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local gray = Material "grey" :GetTexture "$basetexture"
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local function DrawMesh()
    render.SetMaterial(ss.InkMeshMaterial)
    render.SetLightmapTexture(ss.RenderTarget.StaticTextures.Lightmap or gray) -- Set custom lightmap
    for _, model in ipairs(ss.IMesh) do -- Draw ink surface
        local ent = model.BrushEntity
        if not ent or IsValid(ent) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model) do
                m:Draw()
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
end

local function DrawMeshes(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingSkybox or CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    render.DepthRange(0, 65534 / 65535)
    DrawMesh()
    render.RenderFlashlights(DrawMesh)
    render.DepthRange(0, 1)
end

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(ss.SurfaceArray) do ss.ClearGrid(s) end

    local rt = ss.RenderTarget
    render.PushRenderTarget(rt.StaticTextures.Albedo)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(0, 0, 0, 0)
    render.OverrideAlphaWriteEnable(false)
    render.DrawTextureToScreen("splashsweps/debug/uvchecker")
    render.PopRenderTarget()

    render.PushRenderTarget(rt.StaticTextures.Normal)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(128, 128, 255, 255)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
end

hook.Add("PostDrawTranslucentRenderables", "SplashSWEPs: Draw ink", DrawMeshes)
