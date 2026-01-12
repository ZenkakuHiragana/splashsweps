
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
---@param isnormal boolean True this is NOT the flashlight rendering
local function DrawMesh(isnormal)
    local currentMaterial = nil ---@type IMaterial?
    for _, model in ipairs(ss.RenderBatches) do -- Draw ink surface
        local ent = model.BrushEntity
        if #model > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model) do
                local mat = isnormal and m.Material or m.MaterialFlashlight
                if currentMaterial ~= mat then
                    render.SetMaterial(mat)
                    currentMaterial = mat
                end
                (isnormal and m.Mesh or m.MeshFlashlight):Draw()
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
    DrawMesh(true)
    render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
    render.RenderFlashlights(DrawMesh)
    render.OverrideBlend(false)
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
    render.DrawTextureToScreen("grey")
    render.PopRenderTarget()

    render.PushRenderTarget(rt.StaticTextures.Normal)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(128, 128, 255, 255)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
end

hook.Add("PreDrawTranslucentRenderables", "SplashSWEPs: Draw ink", DrawMeshes)
