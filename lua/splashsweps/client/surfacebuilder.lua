
---@class ss
local ss = SplashSWEPs
if not ss then return end

local ModelInfoMeta = getmetatable(ss.new "PrecachedData.ModelInfo")
local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
local MAX_TRIANGLES = math.floor(32768 / 3) -- mesh library limitation

---Construct IMesh
---@param surfInfo ss.PrecachedData.SurfaceInfo
---@param modelInfo ss.PrecachedData.ModelInfo
---@param modelIndex integer
local function BuildInkMesh(surfInfo, modelInfo, modelIndex)
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

    local rtIndex = #ss.RenderTarget.Resolutions
    local scale = surfInfo.UVScales[rtIndex]
    local worldToUV = Matrix()
    worldToUV:SetScale(ss.vector_one * scale)
    for _, faceIndex in ipairs(modelInfo.FaceIndices) do
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
    ss.InkMeshMaterial:SetVector("$color", value)
    ss.InkMeshMaterial:SetVector("$envmaptint", value / 16)
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
            ss.IMesh[i + 1].BrushEntity = ent
        end
    end)

    for i, info in ipairs(modelInfo) do
        ss.IMesh[i] = { BrushEntity = entities[i - 1] }
        setmetatable(info, ModelInfoMeta)
        BuildInkMesh(surfInfo, info, i)
    end
end

---Builds render override functions of static props.
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param modelNames string[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function ss.SetupStaticProps(staticPropInfo, modelNames, uvInfo)
    local mat = Material "splashsweps/shaders/staticprop"
    local dynamiclight = Material "splashsweps/shaders/phong"
    local flashlight = Material "splashsweps/shaders/vertexlitgeneric"

    ---@param self Entity
    ---@param flags Enum.STUDIO
    local function RenderOverrideInternal(self, flags)
        render.MaterialOverride(dynamiclight)
        render.SetBlend(0)
        self:DrawModel(flags)
        render.SetBlend(1)
        render.MaterialOverride()
        render.OverrideDepthEnable(true, true)
        render.DepthRange(0, 65534 / 65535)
        self:DrawModel(flags)
        render.DepthRange(0, 1)
        render.OverrideDepthEnable(false)
    end

    ---@param self ss.PaintableCSEnt
    ---@param flags Enum.STUDIO
    local function RenderOverride(self, flags)
        if LocalPlayer():KeyDown(IN_RELOAD) then return end
        mat:SetFloat("$c0_x", self.Size.x)
        mat:SetFloat("$c0_y", self.Size.y)
        mat:SetFloat("$c0_z", self.Size.z)
        mat:SetFloat("$c0_w", self.UnwrapIndex)
        mat:SetMatrix("$viewprojmat", self.WorldMatrix)
        mat:SetMatrix("$invviewprojmat", self.UVMatrix)
        RenderOverrideInternal(self, flags)
        render.RenderFlashlights(function()
            mat:SetFloat("$c1_x", 1)
            render.MaterialOverride(flashlight)
            render.SetBlend(0)
            self:DrawModel(flags)
            render.SetBlend(1)
            render.MaterialOverride()
            render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ONE, BLENDFUNC_MAX)
            render.DepthRange(0, 65534 / 65535)
            self:DrawModel(flags)
            render.DepthRange(0, 1)
            render.OverrideBlend(false)
            mat:SetFloat("$c1_x", 0)
        end)
    end

    local uvScale = ss.RenderTarget.HammerUnitsToUV
    for i, prop in ipairs(staticPropInfo or {}) do
        setmetatable(prop, StaticPropMeta)
        local uv = setmetatable(uvInfo[i][#ss.RenderTarget.Resolutions], StaticPropUVMeta)
        local modelName = modelNames[prop.ModelIndex]
        if modelName then
            ---@class ss.PaintableCSEnt : CSEnt
            local mdl = ClientsideModel(modelName)
            if mdl then
                local x ---@type number
                local u, v ---@type Vector, Vector
                if uv.Offset.z > 0 then
                    x = uv.Offset.x + uv.Width
                    u = Vector(0, 1, 0)
                    v = Vector(-1, 0, 0)
                else
                    x = uv.Offset.x
                    u = Vector(1, 0, 0)
                    v = Vector(0, 1, 0)
                end
                mdl:SetPos(prop.Position or Vector())
                mdl:SetAngles(prop.Angles or Angle())
                mdl:SetKeyValue("fademindist", prop.FadeMin or -1)
                mdl:SetKeyValue("fademaxdist", prop.FadeMax or 0)
                mdl:SetModelScale(prop.Scale or 1)
                mdl:SetMaterial(mat:GetName())
                mdl.RenderOverride = RenderOverride
                mdl.UnwrapIndex = prop.UnwrapIndex
                mdl.WorldMatrix = mdl:GetWorldTransformMatrix()
                mdl.WorldMatrix:SetTranslation(mdl.WorldMatrix * prop.BoundsMin)
                mdl.WorldMatrix:InvertTR()
                mdl.UVMatrix = Matrix()
                mdl.UVMatrix:SetForward(u)
                mdl.UVMatrix:SetRight(-v)
                mdl.UVMatrix:SetTranslation(Vector(x, uv.Offset.y, uv.Offset.z))
                mdl.UVMatrix:SetScale(Vector(uvScale, uvScale, 1))
                mdl.Size = prop.BoundsMax - prop.BoundsMin
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
