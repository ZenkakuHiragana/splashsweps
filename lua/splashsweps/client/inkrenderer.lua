
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local gray = Material "grey" :GetTexture "$basetexture"
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local function DrawMesh()
    local currentBumpmap = nil ---@type ITexture
    local currentLightmap = nil ---@type string
    for _, model in ipairs(ss.RenderBatches) do -- Draw ink surface
        local ent = model.BrushEntity
        if #model > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model) do
                -- if m.BrushBumpmap and currentBumpmap ~= m.BrushBumpmap then
                --     currentBumpmap = m.BrushBumpmap
                --     -- ss.InkMeshMaterial:SetTexture("$texture3", m.BrushBumpmap)
                -- end
                if m.LightmapTexture and currentLightmap ~= m.LightmapTexture:GetName() then
                    currentLightmap = m.LightmapTexture:GetName() ---@cast currentLightmap -?
                    render.SetLightmapTexture(m.LightmapTextureRT)
                end
                m.Mesh:Draw()
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
    render.SetLightmapTexture(gray)
end

local function DrawMeshes(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingSkybox or CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    for i, t in pairs(ss.Lightmaps) do
        if t.RT and t.Tex then
            render.PushRenderTarget(t.RT)
            render.DrawTextureToScreen(t.Tex)
            render.PopRenderTarget()
        end
    end
    render.SetMaterial(ss.InkMeshMaterial)
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

hook.Add("PreDrawTranslucentRenderables", "SplashSWEPs: Draw ink", DrawMeshes)

-- local m = Matrix()
-- local meshHint = Material "debug/debuglightmap"
-- hook.Add("PostDrawTranslucentRenderables", "test", function()
--     m:SetAngles(EyeAngles())
--     m:Rotate(Angle(0, 180, 0))
--     for i, v in pairs(ss.Lightmaps) do
--         m:SetTranslation(EyePos() + EyeAngles():Forward() * 400 + EyeAngles():Right() * 200 + EyeAngles():Up() * (230 - i * 102))
--         cam.PushModelMatrix(m)
--         render.SetMaterial(meshHint)
--         render.SetLightmapTexture(v.RT)
--         ss.GlobalMesh:Draw()
--         cam.PopModelMatrix()
--     end
-- end)
