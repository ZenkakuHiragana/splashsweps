
---@class ss
local ss = SplashSWEPs
if not ss then return end

-- local rt = ss.RenderTarget
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation

---Construct IMesh
---@param surfaces ss.PrecachedData.SurfaceInfo
---@param modelInfo ss.PrecachedData.ModelInfo
---@param modelIndex integer
local function BuildInkMesh(surfaces, modelInfo, modelIndex)
    local NumMeshTriangles = modelInfo.NumTriangles
    print("SplashSWEPs: Total mesh triangles = ", NumMeshTriangles)

    local meshindex = 1
    local meshTable = ss.IMesh[modelIndex]
    for _ = 1, math.ceil(NumMeshTriangles / MAX_TRIANGLES) do
        meshTable[#meshTable + 1] = Mesh(ss.InkMeshMaterial)
    end

    -- Building MeshVertex
    if #meshTable == 0 then return end
    mesh.Begin(meshTable[meshindex], MATERIAL_TRIANGLES, math.min(NumMeshTriangles, MAX_TRIANGLES))
    local function ContinueMesh()
        if mesh.VertexCount() < MAX_TRIANGLES * 3 then return end
        mesh.End()
        mesh.Begin(meshTable[meshindex + 1], MATERIAL_TRIANGLES,
        math.min(NumMeshTriangles - MAX_TRIANGLES * meshindex, MAX_TRIANGLES))
        meshindex = meshindex + 1
    end

    local rtIndex = #surfaces.UVScales
    local scale = surfaces.UVScales[rtIndex]
    local worldToUV = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    for _, faceIndex in ipairs(modelInfo.FaceIndices) do
        local surf = surfaces[faceIndex]
        local info = surf.UVInfo[rtIndex]
        local uvOrigin = Vector(info.OffsetU, info.OffsetV)
        worldToUV:SetAngles(info.Angle)
        worldToUV:SetTranslation(info.Translation * scale)
        for i, v in ipairs(surf.Vertices) do
            local position = v.Translation
            local normal = v.Angle:Up()
            local tangent = v.Angle:Forward()
            local binormal = -v.Angle:Right()
            local u0, v0 = v.TextureUV.x, v.TextureUV.y -- For displacement
            local s,  t  = v.LightmapUV.x, v.LightmapUV.y -- Lightmap UV
            local uv = worldToUV * position
            local w = normal:Cross(tangent):Dot(binormal) >= 0 and 1 or -1
            if u0 >= 0 or v0 >= 0 then
                uv = uvOrigin + Vector(u0 * info.Width, v0 * info.Height, 0)
            end
            mesh.Normal(normal)
            mesh.UserData(tangent.x, tangent.y, tangent.z, w)
            mesh.TangentS(tangent * w)  -- These functions actually DO something
            mesh.TangentT(binormal) -- in terms of bumpmap for LightmappedGeneric
            mesh.Position(position)
            mesh.TexCoord(0, uv.y, uv.x)
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

local cachePath = string.format("splashsweps/%s.json", game.GetMap())
function ss.PrepareInkSurface()
    util.TimerCycle()

    ---@type ss.PrecachedData?
    local cache = util.JSONToTable(file.Read(cachePath) or "", true)
    if not cache then return end

    local minimapBounds = cache.MinimapBounds
    local pngldrPath = string.format("splashsweps/%s_ldr.png", game.GetMap())
    local pnghdrPath = string.format("splashsweps/%s_hdr.png", game.GetMap())
    local ldrPath = string.format("splashsweps/%s_ldr.json", game.GetMap())
    local hdrPath = string.format("splashsweps/%s_hdr.json", game.GetMap())
    local pngldrExists = file.Exists(pngldrPath, "DATA")
    local pnghdrExists = file.Exists(pnghdrPath, "DATA")
    local ldrExists = file.Exists(ldrPath, "DATA")
    local hdrExists = file.Exists(hdrPath, "DATA")
    local ishdr = false
    if render.GetHDREnabled() then
        ishdr = hdrExists and pnghdrExists
    else
        ishdr = not (ldrExists and pngldrExists)
    end

    local surfacePath = ishdr and hdrPath or ldrPath
    local surfaces = util.JSONToTable(file.Read(surfacePath) or "", true) or {}
    local water    = ishdr and cache.SurfacesWaterHDR or cache.SurfacesWaterLDR
    ss.SURFACE_ID_BITS = select(2, math.frexp(#surfaces))

    -- if not lightmapmat:IsError() then
    --     rt.Lightmap = lightmapmat:GetTexture "$basetexture"
    --     rt.Lightmap:Download()
    -- end

    if ishdr then -- If HDR lighting computation has been done
        local intensity = 128
        local color = cache.DirectionalLight.Color
        if color then -- If there is light_environment
            local lightIntensity = Vector(color.r, color.g, color.b):Dot(ss.GrayScaleFactor) / 255
            local brightness = color.a
            local scale = cache.DirectionalLight.ScaleHDR
            intensity = intensity + lightIntensity * brightness * scale
        end
        local value = ss.vector_one * intensity / 4096
        ss.InkMeshMaterial:SetVector("$color", value)
        ss.InkMeshMaterial:SetVector("$envmaptint", value / 16)
    end

    -- ss.PrecachePaintTextures()
    -- ss.GenerateHashTable()
    local modelInfo = ishdr and cache.ModelsHDR or cache.ModelsLDR
    local entities = {} ---@type Entity[]
    for _, e in ipairs(ents.GetAll()) do
        local modelName = e:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if e ~= game.GetWorld() and i and 0 < i and i <= #modelInfo then
            entities[i] = e
        end
    end
    hook.Add("OnEntityCreated", "SplashSWEPs: Check brush entities", function (ent)
        local modelName = ent:GetModel() or ""
        local i = tonumber(modelName:sub(2))
        if i and 0 < i and i <= #modelInfo then
            ss.IMesh[i + 1].BrushEntity = ent
        end
    end)
    for i, info in ipairs(modelInfo) do
        ss.IMesh[i] = { BrushEntity = entities[i - 1] }
        BuildInkMesh(surfaces, info, i)
    end

    local copy = Material "pp/copy"
    local function RenderOverride(self, flags)
        if LocalPlayer():KeyDown(IN_RELOAD) then return end
        copy:SetTexture("$basetexture", "uvchecker")
        render.MaterialOverride(copy)
        render.DepthRange(0, 65534 / 65535)
        self:DrawModel(flags)
        render.DepthRange(0, 1)
        render.MaterialOverride()
    end
    
    for _, prop in ipairs(cache.StaticProps or {}) do
        local mdl = ClientsideModel(prop.ModelName)
        mdl:SetPos(prop.Position or Vector())
        mdl:SetAngles(prop.Angles or Angle())
        mdl:SetKeyValue("fademindist", prop.FadeMin or -1)
        mdl:SetKeyValue("fademaxdist", prop.FadeMax or 0)
        mdl:SetModelScale(prop.Scale or 1)
        mdl.RenderOverride = RenderOverride
    end

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

-- local cache = util.JSONToTable(util.Decompress(file.Read(cachePath) or "") or "", true)
-- if not cache then return end
-- ss.test = cache ---@type ss.PrecachedData

-- timer.Simple(1, function()
--     for _, s in ipairs(ss.test.SurfacesHDR) do
--         for i = 1, #s.Vertices, 3 do
--             -- debugoverlay.Line(s.Vertices[i].Translation,     s.Vertices[i + 1].Translation, 5, Color(0, 255, 0), true)
--             -- debugoverlay.Line(s.Vertices[i + 1].Translation, s.Vertices[i + 2].Translation, 5, Color(0, 255, 0), true)
--             -- debugoverlay.Line(s.Vertices[i + 2].Translation, s.Vertices[i].    Translation, 5, Color(0, 255, 0), true)
--             debugoverlay.Triangle(
--                 s.Vertices[i].Translation,
--                 s.Vertices[i + 1].Translation,
--                 s.Vertices[i + 2].Translation,
--                 5, Color(0, 255, 0, 255))
--         end
--     end
-- end)
