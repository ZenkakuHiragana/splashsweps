
---@class ss
local ss = SplashSWEPs
if not ss then return end

ss.Lightmaps = ss.Lightmaps or {}
local ModelInfoMeta = getmetatable(ss.new "PrecachedData.ModelInfo")
local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation
local MIN_DRAW_RADIUS = 0.015 -- minimum draw radius for static props relative to ScrH()

---Construct IMesh
---@param surfInfo ss.PrecachedData.SurfaceInfo
---@param modelInfo ss.PrecachedData.ModelInfo
---@param meshTable ss.RenderBatch
local function BuildInkMesh(surfInfo, modelInfo, meshTable)
    local meshIndex = 1
    local rtIndex = #ss.RenderTarget.Resolutions
    local scale = surfInfo.UVScales[rtIndex]
    local worldToUV = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    for indexToMeshID, count in ipairs(modelInfo.TriangleCounts) do
        local meshID = modelInfo.MeshSortIDs[indexToMeshID] - 1
        local numMeshesToAdd = math.ceil(count / MAX_TRIANGLES)
        if numMeshesToAdd > 0 then
            for _ = 1, numMeshesToAdd do
                local page = surfInfo.LightmapPages[meshID]
                local isLast = page == surfInfo.NumLightmapPages
                local width = isLast and surfInfo.LastLightmapPageWidth or 512
                local height = isLast and surfInfo.LastLightmapPageHeight or 256
                local rt = page and ss.CreateLightmapRT(page, width, height)
                local mat = page and CreateMaterial(
                    string.format("splashsweps_lightmap_%d_%s", page, game.GetMap()),
                    "UnlitGeneric", {
                        ["$basetexture"] = string.format("\\[lightmap%d]", page),
                    })
                if page then
                    ss.Lightmaps[page] = {
                        RT = rt,
                        Tex = mat:GetTexture "$basetexture",
                    }
                end
                meshTable[#meshTable + 1] = {
                    LightmapTexture = page and mat:GetTexture "$basetexture",
                    LightmapTextureRT = rt,
                    BrushBumpmap = surfInfo.Bumpmaps[meshID],
                    Mesh = Mesh(ss.InkMeshMaterial),
                }
            end

            mesh.Begin(meshTable[meshIndex].Mesh, MATERIAL_TRIANGLES, math.min(count, MAX_TRIANGLES))
            local function ContinueMesh()
                if mesh.VertexCount() < MAX_TRIANGLES * 3 then return end
                mesh.End()
                mesh.Begin(
                    meshTable[meshIndex + 1].Mesh, MATERIAL_TRIANGLES,
                    math.min(count - MAX_TRIANGLES * meshIndex, MAX_TRIANGLES))
                meshIndex = meshIndex + 1
            end

            for _, faceIndex in ipairs(modelInfo.FaceIndices[indexToMeshID]) do
                local surf = setmetatable(surfInfo.Surfaces[faceIndex], SurfaceMeta)
                local info = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
                local uvOrigin = Vector(info.OffsetU, info.OffsetV)
                worldToUV:SetAngles(info.Angle)
                worldToUV:SetTranslation(info.Translation * scale + uvOrigin)
                for i, v in ipairs(surf.Vertices) do
                    setmetatable(v, VertexMeta)
                    local position = v.Translation
                    local normal = v.Angle:Up()
                    local tangent = v.Angle:Forward()
                    local binormal = -v.Angle:Right()
                    local s,  t  = v.LightmapUV.x, v.LightmapUV.y -- Lightmap UV
                    local uv = worldToUV * position
                    local w = normal:Cross(tangent):Dot(binormal) >= 0 and 1 or -1
                    if v.DisplacementOrigin then
                        uv = worldToUV * v.DisplacementOrigin
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
            meshIndex = meshIndex + 1
        end
    end
end

---Adjusts light intensity of ink mesh material from HDR info.
---@param cache ss.PrecachedData
function ss.SetupHDRLighting(cache)
    setmetatable(cache.DirectionalLight, getmetatable(ss.new "PrecachedData.DirectionalLight"))
    local intensity = 128
    local color = cache.DirectionalLight.Color
    if color then -- If there is light_environment
        local lightIntensity = Vector(color.r, color.g, color.b):Dot(ss.GrayScaleFactor) / 255
        local brightness = color.a
        local scale = cache.DirectionalLight.ScaleHDR
        intensity = intensity + lightIntensity * brightness * scale
    end

    local value = ss.vector_one * intensity / 4096
    -- ss.InkMeshMaterial:SetVector("$color", value)
    -- ss.InkMeshMaterial:SetVector("$envmaptint", value / 16)
end

---Reads through BSP models which includes the worldspawn and brush entities and constructs IMeshes from them.
---@param modelInfo ss.PrecachedData.ModelInfo[]
---@param surfInfo ss.PrecachedData.SurfaceInfo
function ss.SetupModels(modelInfo, surfInfo)
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
            ss.RenderBatches[i + 1].BrushEntity = ent
        end
    end)

    for i, info in ipairs(modelInfo) do
        ss.RenderBatches[i] = { BrushEntity = entities[i - 1] }
        setmetatable(info, ModelInfoMeta)
        BuildInkMesh(surfInfo, info, ss.RenderBatches[i])
    end

    -- local width = 200
    -- local height = 100
    -- local meshVertices = {
    --     {
    --         pos = Vector( 0,   0,    0 ),
    --         u  = 0, v  = 0,
    --         u1 = 0, v1 = 0,
    --         u2 = 0.125, v2 = -0.125,
    --         u3 = 0, v3 = 0,
    --         u4 = 0, v4 = 0,
    --         u5 = 0, v5 = 0,
    --         u6 = 0, v6 = 0,
    --         u7 = 0, v7 = 0,
    --         normal   = Vector(1, 0, 0),
    --         tangent  = Vector(0, 1, 0),
    --         binormal = Vector(0, 0, 1),
    --         color    = (Vector(1, 1, 1) * 0.25):ToColor(),
    --     },
    --     {
    --         pos = Vector( 0, width,    0 ),
    --         u  = 1, v  = 0,
    --         u1 = 1, v1 = 0,
    --         u2 = -0.125, v2 = -0.125,
    --         u3 = 1, v3 = 0,
    --         u4 = 1, v4 = 0,
    --         u5 = 1, v5 = 0,
    --         u6 = 1, v6 = 0,
    --         u7 = 1, v7 = 0,
    --         normal   = Vector(1, 0, 0),
    --         tangent  = Vector(0, 1, 0),
    --         binormal = Vector(0, 0, 1),
    --         color    = (Vector(1, 2, 1) * 0.25):ToColor(),
    --     },
    --     {
    --         pos = Vector( 0, width, -height ),
    --         u  = 1, v  = 1,
    --         u1 = 1, v1 = 1,
    --         u2 = -0.125, v2 = 0.125,
    --         u3 = 1, v3 = 1,
    --         u4 = 1, v4 = 1,
    --         u5 = 1, v5 = 1,
    --         u6 = 1, v6 = 1,
    --         u7 = 1, v7 = 1,
    --         normal   = Vector(1, 0, 0),
    --         tangent  = Vector(0, 1, 0),
    --         binormal = Vector(0, 0, 1),
    --         color    = (Vector(1, 2, 2) * 0.25):ToColor(),
    --     },
    --     {
    --         pos = Vector( 0,   0, -height ),
    --         u  = 0, v  = 1,
    --         u1 = 0, v1 = 1,
    --         u2 = 0.125, v2 = 0.125,
    --         u3 = 0, v3 = 1,
    --         u4 = 0, v4 = 1,
    --         u5 = 0, v5 = 1,
    --         u6 = 0, v6 = 1,
    --         u7 = 0, v7 = 1,
    --         normal   = Vector(1, 0, 0),
    --         tangent  = Vector(0, 1, 0),
    --         binormal = Vector(0, 0, 1),
    --         color    = (Vector(1, 1, 2) * 0.25):ToColor(),
    --     },
    -- }

    -- local meshTriangles = {
    --     meshVertices[1],
    --     meshVertices[2],
    --     meshVertices[3],
    --     meshVertices[1],
    --     meshVertices[3],
    --     meshVertices[4],

    --     meshVertices[1 + 4],
    --     meshVertices[2 + 4],
    --     meshVertices[3 + 4],
    --     meshVertices[1 + 4],
    --     meshVertices[3 + 4],
    --     meshVertices[4 + 4],

    --     meshVertices[1 + 8],
    --     meshVertices[2 + 8],
    --     meshVertices[3 + 8],
    --     meshVertices[1 + 8],
    --     meshVertices[3 + 8],
    --     meshVertices[4 + 8],
    -- }
    -- local meshHint = Material "debug/debuglightmap"
    -- if GlobalMesh then GlobalMesh:Destroy() end
    -- ss.GlobalMesh = Mesh(meshHint)
    -- mesh.Begin( ss.GlobalMesh, MATERIAL_TRIANGLES, #meshTriangles / 3 )
    --     for _, vertex in pairs( meshTriangles ) do
    --         mesh.Position( vertex.pos or vector_origin )
    --         -- Texture coordinates go to channel 0
    --         mesh.TexCoord( 0, vertex.u or 0, vertex.v or 0 )
    --         -- Lightmap texture coordinates go to channel 1
    --         mesh.TexCoord( 1, vertex.u1 or 0, vertex.v1 or 0 )
    --         mesh.TexCoord( 2, vertex.u2 or 0, vertex.v2 or 0 )
    --         mesh.TexCoord( 3, vertex.u3 or 0, vertex.v3 or 0 )
    --         mesh.TexCoord( 4, vertex.u4 or 0, vertex.v4 or 0 )
    --         mesh.TexCoord( 5, vertex.u5 or 0, vertex.v5 or 0 )
    --         mesh.TexCoord( 6, vertex.u6 or 0, vertex.v6 or 0 )
    --         mesh.TexCoord( 7, vertex.u7 or 0, vertex.v7 or 0 )
    --         mesh.Normal( vertex.normal or Vector(0, 0, 1) )
    --         mesh.TangentS( vertex.tangent or Vector(1, 0, 0) )
    --         mesh.TangentT( vertex.binormal or Vector(0, 1, 0) )
    --         mesh.Specular( 192 / 255, 168 / 255, 0, 1.0 )
    --         mesh.UserData( 0.2, 0.8, 0.9, 1.0 )
    --         mesh.AdvanceVertex()
    --     end
    -- mesh.End()
end

---Builds render override functions of static props.
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param modelNames string[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function ss.SetupStaticProps(staticPropInfo, modelNames, uvInfo)
    local templateMaterial = Material "splashsweps/shaders/staticprop"
    local dynamiclight = Material "splashsweps/shaders/phong"
    local flashlight = Material "splashsweps/shaders/vertexlitgeneric"
    local drawStaticProps = GetConVar "r_drawstaticprops"
    local materialCache = {} ---@type table<string, IMaterial>
    local matKeyValues = templateMaterial:GetKeyValues()
    local view = Matrix()
    matKeyValues["$flags"] = nil
    matKeyValues["$flags2"] = nil
    matKeyValues["$flags_defined"] = nil
    matKeyValues["$flags_defined2"] = nil
    matKeyValues["$basetexture"] = "splashsweps_basetexture"
    matKeyValues["$texture1"] = "splashsweps_bumpmap"
    matKeyValues["$texture3"] = "effects/flashlight001"
    matKeyValues["$c1_y"] = ss.RenderTarget.HammerUnitsToUV

    ---@param self ss.PaintableCSEnt
    ---@param flags Enum.STUDIO
    local function RenderOverride(self, flags)
        if LocalPlayer():KeyDown(IN_RELOAD) then return end
        if not drawStaticProps:GetBool() then return end
        if self.FadeMaxSqr and self:GetPos():DistToSqr(EyePos()) > self.FadeMaxSqr then return end
        view:SetTranslation(EyePos())
        view:SetAngles(EyeAngles())
        view:InvertTR()
        local fov = math.rad(render.GetViewSetup().fov)
        local z = (view * self:GetPos()).x -- projected z-position
        local fp = ScrH() / (2 * math.tan(fov / 2)) -- focus distance in pixels
        local r = self:GetModelRadius() * fp / z -- draw radius on the screen in pixels
        if math.abs(r) < MIN_DRAW_RADIUS * ScrH() then return end
        render.MaterialOverride(dynamiclight)
        self:DrawModel(flags)
        render.MaterialOverride()
        render.OverrideDepthEnable(true, true)
        self:DrawModel(flags)
        render.OverrideDepthEnable(false)
        render.RenderFlashlights(function()
            render.MaterialOverride(flashlight)
            self:DrawModel(flags)
            render.MaterialOverride(self.FlashlightMaterials[1])
            for i, m in ipairs(self.FlashlightMaterials) do
                render.MaterialOverrideByIndex(i - 1, m)
            end
            render.OverrideDepthEnable(true, true)
            self:DrawModel(flags)
            render.OverrideDepthEnable(false)
            render.MaterialOverrideByIndex()
            render.MaterialOverride()
        end)
    end

    -- Matrix(X, Y, Z) * xyzTyzx = (Y, Z, X)
    local xyzTyzx = Matrix {
        { 0, 0, 1, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 0, 1 },
    }
    -- xyzTzxy = xyzTyzx * xyzTyzx
    -- xyzTzxy * Vector(X, Y, Z) = (Y, Z, X)
    local xyzTzxy = xyzTyzx:GetTransposed()
    for i, prop in ipairs(staticPropInfo or {}) do
        setmetatable(prop, StaticPropMeta)
        local uv = setmetatable(uvInfo[i][#ss.RenderTarget.Resolutions], StaticPropUVMeta)
        local modelName = modelNames[prop.ModelIndex]
        if modelName then
            ---@class ss.PaintableCSEnt : CSEnt
            local mdl = ClientsideModel(modelName)
            if mdl then
                mdl:SetPos(prop.Position or Vector())
                mdl:SetAngles(prop.Angles or Angle())
                mdl:SetKeyValue("fademindist", prop.FadeMin or -1)
                mdl:SetKeyValue("fademaxdist", prop.FadeMax or 0)
                mdl:SetModelScale(prop.Scale or 1)
                mdl.RenderOverride = RenderOverride
                local fadeMax = prop.FadeMax and prop.FadeMax > 0 and prop.FadeMax or false
                mdl.FadeMaxSqr = fadeMax and (fadeMax * fadeMax)
                local size = prop.BoundsMax - prop.BoundsMin
                local absoluteuvTlocaluv = Matrix()
                if uv.Offset.z > 0 then
                    -- +--------> v
                    -- |   v'
                    -- |   ^
                    -- v   +---> u'
                    -- u    \__local texture space
                    absoluteuvTlocaluv:SetUnpacked(
                        0, -1, 0, uv.Offset.x + uv.Width,
                        1,  0, 0, uv.Offset.y,
                        0,  0, 1, uv.Offset.z,
                        0,  0, 0, 1)
                else
                    -- +--------> v
                    -- | local texture space
                    -- |   +---> v'
                    -- v   |
                    -- u   u'
                    absoluteuvTlocaluv:SetUnpacked(
                        1, 0, 0, uv.Offset.x,
                        0, 1, 0, uv.Offset.y,
                        0, 0, 1, uv.Offset.z,
                        0, 0, 0, 1)
                end
                local localTworld = mdl:GetWorldTransformMatrix()
                localTworld:SetTranslation(localTworld * prop.BoundsMin)
                if prop.UnwrapIndex == 2 then
                    -- (X, Y, Z) * xyzTyzx = (Y, Z, X)
                    localTworld:Mul(xyzTyzx)
                    size:Mul(xyzTzxy)
                elseif prop.UnwrapIndex == 3 then
                    -- (X, Y, Z) * xyzTzxy = (Z, X, Y)
                    localTworld:Mul(xyzTzxy)
                    size:Mul(xyzTyzx)
                end
                localTworld:InvertTR()

                local params = table.Merge(matKeyValues, {
                    ["$c0_x"] = size.x,
                    ["$c0_y"] = size.y,
                    ["$c0_z"] = size.z,
                    ["$c0_w"] = prop.UnwrapIndex,
                })
                mdl.FlashlightMaterials = {} ---@type IMaterial[]
                for j, name in ipairs(mdl:GetMaterials()) do
                    local mdlmat = materialCache[name] or Material(name)
                    local basetexture = mdlmat:GetTexture "$basetexture"

                    params["$additive"] = "0"
                    params["$c1_x"] = "0"
                    local mat = CreateMaterial("splashsweps/sprp" .. i .. "-" .. j, "Screenspace_General", params)
                    mat:SetMatrix("$viewprojmat", localTworld)
                    mat:SetMatrix("$invviewprojmat", absoluteuvTlocaluv)
                    mat:SetTexture("$texture2", basetexture:IsErrorTexture() and "grey" or basetexture)
                    mdl:SetSubMaterial(j - 1, "!" .. mat:GetName())
                    materialCache[name] = mdlmat

                    params["$additive"] = "1"
                    params["$c1_x"] = "1"
                    mat = CreateMaterial("splashsweps/sprpf" .. i .. "-" .. j, "Screenspace_General", params)
                    mat:SetMatrix("$viewprojmat", localTworld)
                    mat:SetMatrix("$invviewprojmat", absoluteuvTlocaluv)
                    mat:SetTexture("$texture2", basetexture:IsErrorTexture() and "grey" or basetexture)
                    mdl.FlashlightMaterials[j] = mat
                end
            end
        end
    end
end

-- function ss.PrepareInkSurface()
--     local minimapBounds = cache.MinimapBounds
--     ss.BuildWaterMesh()
--     ss.ClearAllInk()
--     ss.InitializeMoveEmulation(LocalPlayer())
--     net.Start "SplashSWEPs: Ready to splat"
--     net.WriteString(LocalPlayer():SteamID64() or "")
--     net.SendToServer()
--     ss.WeaponRecord[LocalPlayer()] = util.JSONToTable(
--     util.Decompress(file.Read "splashsweps/record/stats.txt" or "") or "") or {
--         Duration = {},
--         Inked = {},
--         Recent = {},
--     }
--     rt.Ready = true
--     collectgarbage "collect"
-- end
