
---@class ss
local ss = SplashSWEPs
if not ss then return end

-- local rt = ss.RenderTarget
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation

---Construct IMesh
---@param cache ss.PrecachedData
---@param ishdr boolean
local function BuildInkMesh(cache, ishdr)
    local rects = {} ---@type ss.Rectangle[]
    local surfaces = ishdr and cache.SurfacesHDR or cache.SurfacesLDR
    local NumMeshTriangles = ishdr and cache.NumTrianglesHDR or cache.NumTrianglesLDR
    print("SplashSWEPs: Total mesh triangles = ", NumMeshTriangles)

    local meshindex = 1
    for _ = 1, math.ceil(NumMeshTriangles / MAX_TRIANGLES) do
        ss.IMesh[#ss.IMesh + 1] = Mesh()
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

    for _, surf in ipairs(surfaces) do
        local info = surf.UVInfo[#surf.UVInfo]
        local worldToUV = info.Transform
        for i, v in ipairs(surf.Vertices) do
            local position = v:GetTranslation()
            local normal = v:GetUp()
            local tangent = v:GetForward()
            local binormal = -v:GetRight()
            local u0, v0 = v:GetField(4, 1), v:GetField(4, 2) -- For displacement
            local s,  t  = v:GetField(4, 3), v:GetField(4, 4) -- Lightmap UV
            local uv = worldToUV * position
            if u0 > 0 or v0 > 0 then
                uv = worldToUV * -worldToUV:GetTranslation()
                   + Vector(u0 * info.Width, v0 * info.Height, 0)
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

---Since GMOD can't read VMatrix from JSON I have to deserialize them manually.
---https://github.com/Facepunch/garrysmod-issues/issues/5150
---@param surfaces ss.PrecachedData.Surface[]
local function DeserializeMatrices(surfaces)
    for _, surf in ipairs(surfaces) do
        assert(surf.TransformPaintGridSerialized and #surf.TransformPaintGridSerialized > 0)
        surf.TransformPaintGrid = Matrix()
        ---@diagnostic disable-next-line: missing-parameter
        surf.TransformPaintGrid:SetUnpacked(unpack(surf.TransformPaintGridSerialized))
        for i, v in ipairs(surf.VerticesSerialized) do
            surf.Vertices[i] = Matrix()
            ---@diagnostic disable-next-line: missing-parameter
            surf.Vertices[i]:SetUnpacked(unpack(v))
        end
        for _, info in ipairs(surf.UVInfo) do
            info.Transform = Matrix()
            ---@diagnostic disable-next-line: missing-parameter
            info.Transform:SetUnpacked(unpack(info.TransformSerialized))
        end
    end
end

local cachePath = string.format("splashsweps/%s.txt", game.GetMap())
function ss.PrepareInkSurface()
    util.TimerCycle()

    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(util.Decompress(file.Read(cachePath) or "") or "", true)
    if not cache then return end

    local minimapBounds = cache.MinimapBounds
    local pngldr = cache.Lightmap.PNGLDR
    local pnghdr = cache.Lightmap.PNGHDR
    local ldr = cache.SurfacesLDR
    local hdr = cache.SurfacesHDR
    local isusinghdr = false
    if render.GetHDREnabled() then
        isusinghdr = #hdr > 0 and pnghdr and #pnghdr > 0 or false
    else
        isusinghdr = not (#ldr > 0 and pngldr and #pngldr > 0)
    end

    local surfaces = isusinghdr and hdr or ldr
    local water    = cache.SurfacesWater
    ss.SURFACE_ID_BITS = select(2, math.frexp(#surfaces))
    DeserializeMatrices(surfaces)
    DeserializeMatrices(water)

    local lightmap = isusinghdr and pnghdr or pngldr or ""
    local lightpng = "splashsweps/" .. game.GetMap() .. ".png"
    file.Write(lightpng, lightmap)

    -- if not lightmapmat:IsError() then
    --     rt.Lightmap = lightmapmat:GetTexture "$basetexture"
    --     rt.Lightmap:Download()
    -- end

    -- if rt.Lightmap and isusinghdr then -- If HDR lighting computation has been done
    --     local intensity = 128
    --     if cache.Lightmap.DirectionalLightColor then -- If there is light_environment
    --         local lightIntensity = Vector(unpack(cache.Lightmap.DirectionalLightColor)):Dot(ss.GrayScaleFactor) / 255
    --         local brightness = cache.Lightmap.DirectionalLightColor.a
    --         local scale = cache.Lightmap.DirectionalLightScaleHDR
    --         intensity = intensity + lightIntensity * brightness * scale
    --     end
    --     local value = ss.vector_one * intensity / 4096
    --     rt.Material:SetVector("$color", value)
    --     rt.Material:SetVector("$envmaptint", value / 16)
    -- end

    -- ss.PrecachePaintTextures()
    -- ss.GenerateHashTable()
    BuildInkMesh(cache, isusinghdr)
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
