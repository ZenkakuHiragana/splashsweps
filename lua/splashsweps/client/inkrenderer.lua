
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local pngldrPath = string.format("../data/splashsweps/%s_ldr.png", game.GetMap())
local pnghdrPath = string.format("../data/splashsweps/%s_hdr.png", game.GetMap())
local pngPath = render.GetHDREnabled() and pnghdrPath or pngldrPath
local lightmapTexture ---@type ITexture
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local greyMat = Material "grey"
local grey = greyMat:GetTexture "$basetexture"
local function DrawMesh()
    render.SetMaterial(ss.InkMeshMaterial)
    render.SetLightmapTexture(lightmapTexture) -- Set custom lightmap
    for _, model in ipairs(ss.IMesh) do -- Draw ink surface
        if not model.BrushEntity or IsValid(model.BrushEntity) then
            if IsValid(model.BrushEntity) then
                local matrix = model.BrushEntity:GetWorldTransformMatrix()
                cam.PushModelMatrix(matrix)
            end

            for _, m in ipairs(model) do
                m:Draw()
            end

            if IsValid(model.BrushEntity) then
                cam.PopModelMatrix()
            end
        end
    end
end
local function DrawMeshes(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingSkybox or CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    if not lightmapTexture then
        local mat = Material(pngPath, "smooth")
        if not mat:IsError() then
            print "downloading!!"
            mat:GetTexture "$basetexture":Download()
        end
        lightmapTexture = mat:IsError() and grey or mat:GetTexture "$basetexture"
    end
    render.DepthRange(0, 65534 / 65535)
    DrawMesh()
    render.RenderFlashlights(DrawMesh)
    render.DepthRange(0, 1)
end

hook.Add("PostDrawTranslucentRenderables", "SplashSWEPs: Draw ink", DrawMeshes)
