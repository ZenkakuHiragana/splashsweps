
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end

local lightmapTexture ---@type ITexture
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local greyMat = Material "grey"
local grey = greyMat:GetTexture "$basetexture"
local function DrawMeshes(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    -- if not rt.Ready then return end
    if bDrawingSkybox or CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    if not lightmapTexture then
        local mat = Material("../data/" .. "splashsweps/" .. game.GetMap() .. ".png", "smooth")
        lightmapTexture = mat:IsError() and grey or mat:GetTexture "$basetexture"
    end
    render.SetMaterial(greyMat)
    render.SetLightmapTexture(lightmapTexture) -- Set custom lightmap
    render.DepthRange(0, 65534 / 65535)
    for _, m in ipairs(ss.IMesh) do m:Draw() end    -- Draw ink surface
    render.RenderFlashlights(function()
        render.SetMaterial(greyMat)
        render.SetLightmapTexture(lightmapTexture)
        for _, m in ipairs(ss.IMesh) do m:Draw() end
    end)
    render.DepthRange(0, 1)
end

hook.Add("PostDrawTranslucentRenderables", "SplashSWEPs: Draw ink", DrawMeshes)
