---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshTestFixtures
ss.InkmeshTestFixtures = ss.InkmeshTestFixtures or {}

---@class ss.InkmeshTestFixtures
local fixtures = ss.InkmeshTestFixtures
-- Real-VS capture now supports multi-draw fixtures.

---@class ss.InkmeshFixtureVertex
---@field pos Vector?
---@field normal Vector?
---@field color number[]?
---@field proxyU number?
---@field proxyV number?
---@field bumpProxyU number?
---@field bumpProxyV number?
---@field clipRange number[]?
---@field worldPosProjPosZ number[]?
---@field worldNormalTangentY number[]?
---@field inkTangentXYZWorldZ number[]?
---@field inkBinormalMeshLift number[]?
---@field projPosWMeshRole number[]?

---@class ss.InkmeshRealFixtureVertex
---@field pos Vector?
---@field normal Vector?
---@field color number[]?
---@field baseBumpUV number[]?
---@field lightmapUVOffset number[]?
---@field inkTangent number[]?
---@field inkBinormal number[]?
---@field tangent number[]?
---@field binormal number[]?
---@field surfaceClipRangeRaw number[]?

local support = ss.InkmeshTestSupport
---@type ss.RenderHarness
local rt = ss.RenderHarness
if not support or not rt or not rt.CaptureRT then return end

---@param target ITexture
---@param clear number[]|Color?
---@param draw fun(target: ITexture)
function fixtures.FillRT(target, clear, draw)
    render.PushRenderTarget(target)
    render.OverrideAlphaWriteEnable(true, true)
    local c = clear or { 0, 0, 0, 0 }
    render.Clear(c[1], c[2], c[3], c[4])
    cam.Start2D()
    draw(target)
    cam.End2D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
end

---@param baseName string
---@param stage string
---@return string
local function latestShaderName(baseName, stage)
    local files = file.Find(
        string.format("shaders/fxc/splashsweps/*_%s_%s30.vcs", baseName, stage),
        "GAME",
        "datedesc"
    )

    local bestName ---@type string?
    local bestVersion = -1
    for _, entry in ipairs(files or {}) do
        local version = tonumber(entry:match("^(%d+)_" .. baseName .. "_" .. stage .. "30%.vcs$"))
        if version and version > bestVersion then
            bestVersion = version
            bestName = entry
        end
    end

    if not bestName then
        return string.format("splashsweps/%s_%s30", baseName, stage)
    end

    local fileName = tostring(bestName:gsub("\\", "/"):match("([^/]+)$") or bestName)
    return "splashsweps/" .. fileName:gsub("%.vcs$", "")
end

---@param material IMaterial
---@param baseName string
local function syncHotloadShaderPair(material, baseName)
    material:SetString("$vertexshader", latestShaderName(baseName, "vs"))
    material:SetString("$pixshader", latestShaderName(baseName, "ps"))
end

---@return IMaterial
local function getCoreMaterial()
    local material = Material("splashsweps/shaders/inkmesh_core_test")
    syncHotloadShaderPair(material, "inkmesh_core_test")
    return material
end

---@return IMaterial
local function getDisplayMaterial()
    local material = Material("splashsweps/shaders/inkmesh_test")
    syncHotloadShaderPair(material, "inkmesh_test")
    return material
end

---@return IMaterial
local function getRealDisplayMaterial()
    local material = Material("splashsweps/shaders/inkmesh_realtest")
    syncHotloadShaderPair(material, "inkmesh_realtest")
    return material
end

---@param name string
---@param opts table
---@return table
function fixtures.ConfigureTextures(name, opts)
    local paramWidth = opts.paramWidth or 2
    local inkMap = rt.EnsureRT(
        name .. "_inkmap",
        support.FIXTURE_RT,
        support.FIXTURE_RT,
        MATERIAL_RT_DEPTH_NONE,
        128 + 256 + 512 + 32768
    )
    local params = rt.EnsureRT(name .. "_params", paramWidth, 8)
    local details = rt.EnsureRT(name .. "_details", 2, 2)
    local sceneDepth = rt.EnsureRT(name .. "_depth", support.FIXTURE_RT, support.FIXTURE_RT)
    local frameBuffer = rt.EnsureRT(name .. "_framebuffer", support.FIXTURE_RT, support.FIXTURE_RT)
    local wallAlbedo = rt.EnsureRT(name .. "_wallalbedo", 2, 2)
    local wallBump = rt.EnsureRT(name .. "_wallbump", 2, 2)
    local lightmap = rt.EnsureRT(name .. "_lightmap", 2, 2)
    local heightAlpha = opts.heightAlpha or 0
    local depthAlpha = opts.depthAlpha or 255
    local indexColor = opts.indexColor or { 255, 255, 255, 255 }

    fixtures.FillRT(inkMap, { 0, 0, 0, 0 }, function()
        if heightAlpha > 0 then
            surface.SetDrawColor(0, 0, 0, heightAlpha)
            surface.DrawRect(0, 0, support.FIXTURE_RT / 2, support.FIXTURE_RT)
        end

        surface.SetDrawColor(0, 0, 0, depthAlpha)
        surface.DrawRect(support.FIXTURE_RT / 2, 0, support.FIXTURE_RT / 2, support.FIXTURE_RT)

        surface.SetDrawColor(indexColor[1], indexColor[2], indexColor[3], indexColor[4])
        surface.DrawRect(0, support.FIXTURE_RT / 2, support.FIXTURE_RT / 2, support.FIXTURE_RT / 2)

        for _, write in ipairs(opts.inkMapWrites or {}) do
            local c = write.color
            surface.SetDrawColor(c[1], c[2], c[3], c[4])
            surface.DrawRect(write.x, write.y, write.w or 1, write.h or 1)
        end
    end)

    fixtures.FillRT(params, opts.paramsFill or { 255, 255, 255, 255 }, function()
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 4, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 5, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 6, 1, 1)
        surface.SetDrawColor(0, 0, 0, 0)
        surface.DrawRect(0, 7, 1, 1)

        for _, write in ipairs(opts.paramWrites or {}) do
            local c = write.color
            surface.SetDrawColor(c[1], c[2], c[3], c[4])
            surface.DrawRect(write.x, write.y, 1, 1)
        end
    end)

    fixtures.FillRT(details, opts.detailsFill or { 255, 255, 255, 255 }, function() end)
    fixtures.FillRT(sceneDepth, opts.sceneDepthFill or { 255, 255, 255, 255 }, function() end)
    fixtures.FillRT(frameBuffer, opts.frameBufferFill or { 255, 255, 255, 255 }, function() end)
    fixtures.FillRT(wallAlbedo, opts.wallAlbedoFill or { 255, 255, 255, 255 }, function() end)
    fixtures.FillRT(wallBump, opts.wallBumpFill or { 128, 128, 255, 255 }, function() end)
    fixtures.FillRT(lightmap, opts.lightmapFill or { 255, 255, 255, 255 }, function() end)

    return {
        inkMap = inkMap,
        params = params,
        details = details,
        sceneDepth = sceneDepth,
        frameBuffer = frameBuffer,
        wallAlbedo = wallAlbedo,
        wallBump = wallBump,
        lightmap = lightmap,
    }
end

---@param material IMaterial
---@param opts table
local function drawQuadSingle(material, opts)
    local width = support.FIXTURE_RT
    local height = support.FIXTURE_RT
    local clipRange = opts.clipRange or support.CLIP_FULL
    local proxyU = opts.proxyU or support.PROXY_U
    local proxyV = opts.proxyV or support.PROXY_V
    local bumpProxyU = opts.bumpProxyU or 0
    local bumpProxyV = opts.bumpProxyV or 0
    local worldPosProjPosZ = opts.worldPosProjPosZ
        or support.BuildWorldPosProjPosZ(opts.eyeNormalDistance, opts.projPosZ)
    local worldNormalTangentY = opts.worldNormalTangentY or { 1, 0, 0, 0 }
    local inkTangentXYZWorldZ = opts.inkTangentXYZWorldZ or { 0, 0, 0, 0 }
    local inkBinormalMeshLift = opts.inkBinormalMeshLift or { 0, 0, 0, 0 }
    local projPosWMeshRole = opts.projPosWMeshRole
        or support.BuildProjPosWMeshRole(opts.role, opts.projW)
    local defaultPositions = {
        Vector(0, 0, 0),
        Vector(0, height, 0),
        Vector(width, height, 0),
        Vector(width, 0, 0),
    }
    local defaultNormal = opts.normal or Vector(1, 0, 0)
    local vertices = opts.vertices or {} ---@type ss.InkmeshFixtureVertex[]

    render.SetMaterial(material)
    mesh.Begin(MATERIAL_QUADS, 1)
    for index = 1, 4 do
        local vertex = vertices[index] or {}
        local vertexClipRange = vertex.clipRange or clipRange
        local vertexBumpProxyU = vertex.bumpProxyU or bumpProxyU
        local vertexBumpProxyV = vertex.bumpProxyV or bumpProxyV
        local vertexWorldPosProjPosZ = vertex.worldPosProjPosZ or worldPosProjPosZ
        local vertexWorldNormalTangentY = vertex.worldNormalTangentY or worldNormalTangentY
        local vertexInkTangentXYZWorldZ = vertex.inkTangentXYZWorldZ or inkTangentXYZWorldZ
        local vertexInkBinormalMeshLift = vertex.inkBinormalMeshLift or inkBinormalMeshLift
        local vertexProjPosWMeshRole = vertex.projPosWMeshRole or projPosWMeshRole
        local vertexColor = vertex.color
        local vertexNormal = vertex.normal or defaultNormal

        mesh.Position(vertex.pos or defaultPositions[index])
        mesh.Normal(vertexNormal)
        if vertexColor then
            mesh.Color(vertexColor[1], vertexColor[2], vertexColor[3], vertexColor[4])
        else
            mesh.Color(255, 255, 255, 255)
        end
        mesh.TexCoord(0, vertex.proxyU or proxyU, vertex.proxyV or proxyV, vertexBumpProxyU, vertexBumpProxyV)
        mesh.TexCoord(1, vertexClipRange[1], vertexClipRange[2], vertexClipRange[3], vertexClipRange[4])
        mesh.TexCoord(2, vertexWorldPosProjPosZ[1], vertexWorldPosProjPosZ[2], vertexWorldPosProjPosZ[3], vertexWorldPosProjPosZ[4])
        mesh.TexCoord(3, vertexWorldNormalTangentY[1], vertexWorldNormalTangentY[2], vertexWorldNormalTangentY[3], vertexWorldNormalTangentY[4])
        mesh.TexCoord(4, vertexInkTangentXYZWorldZ[1], vertexInkTangentXYZWorldZ[2], vertexInkTangentXYZWorldZ[3], vertexInkTangentXYZWorldZ[4])
        mesh.TexCoord(5, vertexInkBinormalMeshLift[1], vertexInkBinormalMeshLift[2], vertexInkBinormalMeshLift[3], vertexInkBinormalMeshLift[4])
        mesh.TexCoord(6, vertexProjPosWMeshRole[1], vertexProjPosWMeshRole[2], vertexProjPosWMeshRole[3], vertexProjPosWMeshRole[4])
        mesh.AdvanceVertex()
    end
    mesh.End()
end

---@param material IMaterial
---@param opts table
local function drawQuadSingleRealVS(material, opts)
    local vertices = opts.vertices or {} ---@type ss.InkmeshRealFixtureVertex[]
    local primitiveType = opts.primitiveType or (#vertices == 4 and MATERIAL_QUADS or MATERIAL_TRIANGLES)
    local primitiveVertices = primitiveType == MATERIAL_QUADS and 4 or primitiveType == MATERIAL_TRIANGLES and 3 or nil
    if not primitiveVertices then
        error(string.format("Unsupported real-VS primitive type: %s", tostring(primitiveType)), 0)
    end
    if #vertices % primitiveVertices ~= 0 then
        error(string.format(
            "Real-VS fixture vertex count %d is not divisible by primitive size %d",
            #vertices,
            primitiveVertices
        ), 0)
    end

    render.SetMaterial(material)
    mesh.Begin(primitiveType, #vertices / primitiveVertices)
    for index = 1, #vertices do
        local vertex = vertices[index] or {}
        local color = vertex.color or { 255, 255, 255, 255 }
        local normal = vertex.normal or Vector(0, 0, 1)
        local baseBumpUV = vertex.baseBumpUV or { 0.5, 0.5, 0.25, 0.25 }
        local lightmapUVOffset = vertex.lightmapUVOffset or { 0, 0, 0, 0 }
        local inkTangent = vertex.inkTangent or { 0, 1 / 32, 0, 0 }
        local inkBinormal = vertex.inkBinormal or { 1 / 32, 0, 0, 0 }
        local tangent = vertex.tangent or { 1, 0, 0, 0 }
        local binormal = vertex.binormal or { 0, 1, 0, 0 }
        local surfaceClipRangeRaw = vertex.surfaceClipRangeRaw or { 0, 0, 1, 1 }

        mesh.Position(vertex.pos or Vector(0, 0, 0))
        mesh.Normal(normal)
        mesh.Color(color[1], color[2], color[3], color[4])
        mesh.TexCoord(0, baseBumpUV[1], baseBumpUV[2], baseBumpUV[3], baseBumpUV[4])
        mesh.TexCoord(1, lightmapUVOffset[1], lightmapUVOffset[2], lightmapUVOffset[3], lightmapUVOffset[4])
        mesh.TexCoord(2, inkTangent[1], inkTangent[2], inkTangent[3], inkTangent[4])
        mesh.TexCoord(3, inkBinormal[1], inkBinormal[2], inkBinormal[3], inkBinormal[4])
        mesh.TexCoord(4, tangent[1], tangent[2], tangent[3], tangent[4])
        mesh.TexCoord(5, binormal[1], binormal[2], binormal[3], binormal[4])
        mesh.TexCoord(6, surfaceClipRangeRaw[1], surfaceClipRangeRaw[2], surfaceClipRangeRaw[3], surfaceClipRangeRaw[4])
        mesh.AdvanceVertex()
    end
    mesh.End()
end

---@param base table
---@param override table
---@return table
local function mergeDrawOpts(base, override)
    local merged = {}
    for key, value in pairs(base) do
        if key ~= "draws" then
            merged[key] = value
        end
    end
    for key, value in pairs(override) do
        merged[key] = value
    end
    return merged
end

---@param material IMaterial
---@param opts table
local function drawQuad(material, opts)
    if istable(opts.draws) and #opts.draws > 0 then
        for _, drawOpts in ipairs(opts.draws) do
            drawQuadSingle(material, mergeDrawOpts(opts, drawOpts))
        end
        return
    end

    drawQuadSingle(material, opts)
end

---@param material IMaterial
---@param opts table
local function drawQuadRealVS(material, opts)
    if istable(opts.draws) and #opts.draws > 0 then
        for _, drawOpts in ipairs(opts.draws) do
            drawQuadSingleRealVS(material, mergeDrawOpts(opts, drawOpts))
        end
        return
    end

    drawQuadSingleRealVS(material, opts)
end

---@param material IMaterial
---@param textures table
---@param opts table
---@return integer[][]
local function captureFixture(material, textures, opts)
    material:SetTexture("$basetexture", textures.inkMap)
    material:SetTexture("$texture1", textures.params)
    material:SetTexture("$texture2", textures.sceneDepth)
    material:SetTexture("$texture3", textures.frameBuffer)
    material:SetTexture("$texture4", textures.details)
    material:SetTexture("$texture5", textures.wallAlbedo)
    material:SetTexture("$texture6", textures.wallBump)
    material:SetTexture("$texture7", textures.lightmap)
    material:SetInt("$c0_w", opts.debugMode or 1)
    material:SetFloat("$c1_x", opts.c1_x or 0)
    material:SetFloat("$c1_y", opts.c1_y or 0)
    material:SetFloat("$c1_w", opts.c1_w or 0)
    material:SetFloat("$c2_x", opts.c2_x or 0)
    material:SetFloat("$c2_y", opts.c2_y or 0)
    material:SetFloat("$c2_z", opts.c2_z or 0)
    material:SetFloat("$c3_x", opts.c3_x or 0)
    material:SetFloat("$c3_y", opts.c3_y or 0)
    material:SetFloat("$c3_z", opts.c3_z or 0)
    material:SetFloat("$c3_w", opts.c3_w or 0)
    material:Recompute()

    return rt.CaptureRT(
        support.FIXTURE_RT,
        support.FIXTURE_RT,
        function()
            local toneMapping = render.GetToneMappingScaleLinear()
            render.TurnOnToneMapping()
            render.SetGoalToneMappingScale(1)
            render.SetToneMappingScaleLinear(Vector(1, 1, 1))
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            local ok, err = pcall(function()
                drawQuad(material, opts)
            end)
            render.OverrideBlend(false)
            render.SetToneMappingScaleLinear(toneMapping)
            if not ok then error(err, 0) end
        end,
        opts.name .. "_capture",
        { 0, 0, 0, 0 }
    )
end

---@param opts table
---@return integer[][]
function fixtures.CaptureCoreDebug(opts)
    local textures = fixtures.ConfigureTextures(opts.name, opts)
    return captureFixture(getCoreMaterial(), textures, opts)
end

---@param opts table
---@return integer[][]
function fixtures.CaptureDisplayDebug(opts)
    local textures = fixtures.ConfigureTextures(opts.name, opts)
    return captureFixture(getDisplayMaterial(), textures, opts)
end

---@param opts table
---@return integer[][]
function fixtures.CaptureDisplayRealVS(opts)
    local textures = fixtures.ConfigureTextures(opts.name, opts)
    local material = getRealDisplayMaterial()
    material:SetTexture("$basetexture", textures.inkMap)
    material:SetTexture("$texture1", textures.params)
    material:SetTexture("$texture2", textures.sceneDepth)
    material:SetTexture("$texture3", textures.frameBuffer)
    material:SetTexture("$texture4", textures.details)
    material:SetTexture("$texture5", textures.wallAlbedo)
    material:SetTexture("$texture6", textures.wallBump)
    material:SetTexture("$texture7", textures.lightmap)
    material:SetInt("$c0_w", opts.debugMode or 1)
    material:SetFloat("$c1_x", opts.c1_x or 0)
    material:SetFloat("$c1_y", opts.c1_y or 0)
    material:SetFloat("$c1_w", opts.c1_w or 0)
    material:SetFloat("$c2_x", opts.c2_x or 0)
    material:SetFloat("$c2_y", opts.c2_y or 0)
    material:SetFloat("$c2_z", opts.c2_z or 0)
    material:SetFloat("$c3_x", opts.c3_x or 0)
    material:SetFloat("$c3_y", opts.c3_y or 0)
    material:SetFloat("$c3_z", opts.c3_z or 0)
    material:SetFloat("$c3_w", opts.c3_w or 0)
    material:Recompute()

    return rt.CaptureRT3D(
        support.FIXTURE_RT,
        support.FIXTURE_RT,
        function()
            local toneMapping = render.GetToneMappingScaleLinear()
            render.TurnOnToneMapping()
            render.SetGoalToneMappingScale(1)
            render.SetToneMappingScaleLinear(Vector(1, 1, 1))
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            local ok, err = pcall(function()
                drawQuadRealVS(material, opts)
            end)
            render.OverrideBlend(false)
            render.SetToneMappingScaleLinear(toneMapping)
            if not ok then error(err, 0) end
        end,
        opts.camera or {
            origin = EyePos(),
            angles = EyeAngles(),
            fov = 70,
            znear = 1,
            zfar = 4096,
        },
        opts.name .. "_capture",
        { 0, 0, 0, 0 },
        MATERIAL_RT_DEPTH_SEPARATE
    )
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
