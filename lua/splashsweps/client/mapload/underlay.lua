
-- Packs the textures under the blended layers of WorldVertexTransition and Lightmapped_4WayBlend materials.

---@class ss
local ss = SplashSWEPs

---@class ss.UnderlayModule
local Underlay = ss.module "splashsweps/client/mapload/underlay"

---Creates render targets and packs textures used in WorldVertexTransition and Lightmapped_4WayBlend materials.
---@param mats table<integer, ss.MapMaterials.MaterialInfo> Sparse enumeration-ID-indexed materials.
function Underlay.Build(mats)
    local copy = Material "pp/copy"
    for _, m in pairs(mats) do
        local mat = m.Material
        local bt2str = mat:GetString "$basetexture2"
        local bt3str = mat:GetString "$basetexture3"
        local bt4str = mat:GetString "$basetexture4"
        local bmtstr = mat:GetString "$blendmodulatetexture"
        local bumpstr = mat:GetString "$bumpmap"
        local bumpstr2 = mat:GetString "$bumpmap2"
        local detailstr = mat:GetString "$detail"
        if bt2str then
            local bt2 = mat:GetTexture "$basetexture2"
            local bt3 = mat:GetTexture "$basetexture3"
            local bt4 = mat:GetTexture "$basetexture4"
            local bmt = mat:GetTexture "$blendmodulatetexture"
            local bumpmap2 = mat:GetTexture "$bumpmap2"
            local detail = mat:GetTexture "$detail"
            local numTextures = 1
                + (bt3str and 1 or 0)
                + (bt4str and 1 or 0)
                + (bmtstr and 1 or 0)
                + (bumpstr2 and 1 or 0)
                + (detailstr and 1 or 0)
            if numTextures > 0 then
                local meanWidth = (bt2:Width()
                    + (bt3str and bt3:Width() or 0)
                    + (bt4str and bt4:Width() or 0)
                    + (bmtstr and bmt:Width() or 0)
                    + (bumpstr2 and bumpmap2:Width() or 0)
                    + (detailstr and detail:Width() or 0)) / numTextures
                local meanHeight = (bt2:Height()
                    + (bt3str and bt3:Height() or 0)
                    + (bt4str and bt4:Height() or 0)
                    + (bmtstr and bmt:Height() or 0)
                    + (bumpstr2 and bumpmap2:Height() or 0)
                    + (detailstr and detail:Height() or 0)) / numTextures
                local size = math.min((meanWidth + meanHeight) / 2, 2048)
                local columns = bt3str and 3 or 2
                local name = string.format("splashsweps_texture_%s", mat:GetName())
                local rt = GetRenderTargetEx(name, size * columns, size * 2,
                    RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE,
                    256 + 512 + 32768, 0, IMAGE_FORMAT_DEFAULT)
                timer.Simple(0, function()
                    render.PushRenderTarget(rt)
                    cam.Start2D()
                    surface.SetMaterial(copy)
                    copy:SetTexture("$basetexture", detailstr or "grey")
                    surface.DrawTexturedRect(0, 0, size, size)
                    copy:SetTexture("$basetexture", bt2str)
                    surface.DrawTexturedRect(size, 0, size, size)
                    copy:SetTexture("$basetexture", bmtstr or "grey")
                    surface.DrawTexturedRect(0, size, size, size)
                    copy:SetTexture("$basetexture", bumpstr2 or bumpstr or "null-bumpmap")
                    surface.DrawTexturedRect(size, size, size, size)
                    if bt3str then
                        copy:SetTexture("$basetexture", bt3str)
                        surface.DrawTexturedRect(size * 2, 0, size, size)
                        copy:SetTexture("$basetexture", bt4str or "grey")
                        surface.DrawTexturedRect(size * 2, size, size, size)
                    end
                    cam.End2D()
                    render.PopRenderTarget()
                end)
                m.Detail = name
            end
        end
    end
end

return Underlay
