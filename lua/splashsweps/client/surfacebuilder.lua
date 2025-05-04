
---@class ss
local ss = SplashSWEPs
if not ss then return end

-- local rt = ss.RenderTarget
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation

---Construct IMesh
---@param cache ss.PrecachedData
---@param surfaces ss.PrecachedData.Surface[]
---@param ishdr boolean
local function BuildInkMesh(cache, surfaces, ishdr)
    local NumMeshTriangles = ishdr and cache.NumTrianglesHDR or cache.NumTrianglesLDR
    print("SplashSWEPs: Total mesh triangles = ", NumMeshTriangles)

    local meshindex = 1
    for _ = 1, math.ceil(NumMeshTriangles / MAX_TRIANGLES) do
        ss.IMesh[#ss.IMesh + 1] = Mesh(ss.InkMeshMaterial)
    end

    -- Building MeshVertex
    if #ss.IMesh == 0 then return end
    mesh.Begin(ss.IMesh[meshindex], MATERIAL_TRIANGLES, math.min(NumMeshTriangles, MAX_TRIANGLES))
    local function ContinueMesh()
        if mesh.VertexCount() < MAX_TRIANGLES * 3 then return end
        mesh.End()
        mesh.Begin(ss.IMesh[meshindex + 1], MATERIAL_TRIANGLES,
        math.min(NumMeshTriangles - MAX_TRIANGLES * meshindex, MAX_TRIANGLES))
        meshindex = meshindex + 1
    end

    local worldToUV = Matrix()
    for _, surf in ipairs(surfaces) do
        local info = surf.UVInfo[#surf.UVInfo]
        local uvOrigin = info.Transform.Translation
        worldToUV:SetTranslation(uvOrigin)
        worldToUV:SetAngles(info.Transform.Angle)
        worldToUV:SetScale(info.Transform.Scale)
        worldToUV:Invert()
        for i, v in ipairs(surf.Vertices) do
            local position = v.Translation
            local normal = v.Angle:Up()
            local tangent = v.Angle:Forward()
            local binormal = -v.Angle:Right()
            local u0, v0 = v.TextureUV.x, v.TextureUV.y -- For displacement
            local s,  t  = v.LightmapUV.x, v.LightmapUV.y -- Lightmap UV
            local uv = worldToUV * position
            if u0 > 0 or v0 > 0 then
                uv = worldToUV * uvOrigin + Vector(u0 * info.Width, v0 * info.Height, 0)
            end
            mesh.Normal(normal)
            mesh.UserData(tangent.x, tangent.y, tangent.z, 1)
            mesh.TangentS(tangent)  -- These functions actually DO something
            mesh.TangentT(binormal) -- in terms of bumpmap for LightmappedGeneric
            mesh.Position(position)
            mesh.TexCoord(0, uv.x, uv.y)
            if t < 1 then
                mesh.TexCoord(1, s, t)
                mesh.Color(255, 255, 255, 255)
            else
                mesh.TexCoord(1, 1, 1)
                local sample = render.GetLightColor(position)
                local r = math.Round(sample.x ^ (1 / 2.2) / 2 * 255)
                local g = math.Round(sample.y ^ (1 / 2.2) / 2 * 255)
                local b = math.Round(sample.z ^ (1 / 2.2) / 2 * 255)
                mesh.Color(r, g, b, 255)
            end
            mesh.AdvanceVertex()
            if (i - 1) % 3 == 2 then
                ContinueMesh()
            end
        end
    end
    mesh.End()
end

local cachePath = string.format("splashsweps/%s.txt", game.GetMap())
function ss.PrepareInkSurface()
    util.TimerCycle()

    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(util.Decompress(file.Read(cachePath) or "") or "", true)
    if not cache then return end

    local minimapBounds = cache.MinimapBounds
    local pngldrPath = string.format("splashsweps/%s_ldr.png", game.GetMap())
    local pnghdrPath = string.format("splashsweps/%s_hdr.png", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.txt", game.GetMap())
    local hdrPath = string.format("splashsweps/%s_hdr.txt", game.GetMap())
    local pngldrExists = file.Exists(pngldrPath, "DATA")
    local pnghdrExists = file.Exists(pnghdrPath, "DATA")
    local ldrExists = file.Exists(ldrPath, "DATA")
    local hdrExists = file.Exists(hdrPath, "DATA")
    local isusinghdr = false
    if render.GetHDREnabled() then
        isusinghdr = hdrExists and pnghdrExists
    else
        isusinghdr = not (ldrExists and pngldrExists)
    end

    local surfacePath = isusinghdr and hdrPath or ldrPath
    local surfaces = util.JSONToTable(util.Decompress(file.Read(surfacePath) or "") or "", true) or {}
    local water    = isusinghdr and cache.SurfacesWaterHDR or cache.SurfacesWaterLDR
    ss.SURFACE_ID_BITS = select(2, math.frexp(#surfaces))

    -- if not lightmapmat:IsError() then
    --     rt.Lightmap = lightmapmat:GetTexture "$basetexture"
    --     rt.Lightmap:Download()
    -- end

    if isusinghdr then -- If HDR lighting computation has been done
        local intensity = 128
        if cache.Lightmap.DirectionalLightColor then -- If there is light_environment
            local lightIntensity = Vector(unpack(cache.Lightmap.DirectionalLightColor)):Dot(ss.GrayScaleFactor) / 255
            local brightness = cache.Lightmap.DirectionalLightColor.a
            local scale = cache.Lightmap.DirectionalLightScaleHDR
            intensity = intensity + lightIntensity * brightness * scale
        end
        local value = ss.vector_one * intensity / 4096
        ss.InkMeshMaterial:SetVector("$color", value)
        ss.InkMeshMaterial:SetVector("$envmaptint", value / 16)
    end

    -- ss.PrecachePaintTextures()
    -- ss.GenerateHashTable()
    BuildInkMesh(cache, surfaces, isusinghdr)
    -- ss.BuildWaterMesh()
    -- ss.ClearAllInk()
    -- ss.InitializeMoveEmulation(LocalPlayer())
    -- net.Start "SplashSWEPs: Ready to splat"
    -- net.WriteString(LocalPlayer():SteamID64() or "")
    -- net.SendToServer()
    -- ss.WeaponRecord[LocalPlayer()] = util.JSONToTable(
    -- util.Decompress(file.Read "splashsweps/record/stats.txt" or "") or "") or {
    --     Duration = {},
    --     Inked = {},
    --     Recent = {},
    -- }

    -- rt.Ready = true
    -- collectgarbage "collect"
    -- print("MAKE", util.TimerCycle())
end
