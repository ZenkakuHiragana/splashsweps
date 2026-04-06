---@class ss
local ss = SplashSWEPs
if not ss then return end

local INKMESH_FIXTURE_RT = 8
local INKMESH_ROLE_BASE = ss.TRI_BASE / ss.TRI_MAX ---@type number
local INKMESH_PROXY_U = 0.25
local INKMESH_PROXY_V = 0.25
local INKMESH_CLIP_FULL = { 0.0, 0.0, 0.5, 0.5 }
local INKMESH_PROJ_POS_Z = 1.0
local INKMESH_PROJ_POS_W = 1.0
local COLOR_TRACE_BOX_MISS = { 255, 255, 0, 255 }
local COLOR_TRACE_NO_HIT = { 255, 0, 255, 255 }
local COLOR_TRACE_HIT_START = { 0, 255, 0, 255 }
local COLOR_TRACE_HIT_CROSSING = { 0, 128, 255, 255 }
local INKMESH_TEST_MATERIAL_NAME = "splashsweps_render_test_inkmesh_psonly"
local RT_FLAGS_INKMAP = 128 + 256 + 512 + 32768

---@type ss.RenderHarness
local rt = ss.RenderHarness
if not rt or not rt.CaptureRT or not rt.NewPixelMap or not rt.ClearTestPrefix then return end

---@param target ITexture
---@param clear number[]|Color?
---@param draw fun(target: ITexture)
local function fillRT(target, clear, draw)
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

---@return IMaterial
local function getInkmeshMaterial()
    local template = Material("splashsweps/shaders/inkmesh_test")
    local params = template:GetKeyValues() or {}
    params["$cull"] = "0"
    params["$c0_w"] = 1
    params["$c1_x"] = 0
    params["$c1_y"] = 0
    params["$c1_w"] = 0
    params["$c30_x"] = 1
    params["$c30_y"] = 1
    params["$c30_z"] = 1
    params["$c30_w"] = 1

    local material = CreateMaterial(
        INKMESH_TEST_MATERIAL_NAME,
        "Screenspace_General_8Tex",
        params
    )
    material:Recompute()
    return material
end

---@param name string
---@param heightAlpha integer
---@return { inkMap: ITexture, params: ITexture, details: ITexture, sceneDepth: ITexture, frameBuffer: ITexture }
local function configureInkmeshFixtureTextures(name, heightAlpha)
    local inkMap = rt.EnsureRT(
        name .. "_inkmap",
        INKMESH_FIXTURE_RT,
        INKMESH_FIXTURE_RT,
        MATERIAL_RT_DEPTH_NONE,
        128 + 256 + 512 + 32768
    )
    local params = rt.EnsureRT(name .. "_params", 2, 8)
    local details = rt.EnsureRT(name .. "_details", 2, 2)
    local sceneDepth = rt.EnsureRT(name .. "_depth", INKMESH_FIXTURE_RT, INKMESH_FIXTURE_RT)
    local frameBuffer = rt.EnsureRT(name .. "_framebuffer", INKMESH_FIXTURE_RT, INKMESH_FIXTURE_RT)

    fillRT(inkMap, { 0, 0, 0, 0 }, function()
        if heightAlpha > 0 then
            surface.SetDrawColor(0, 0, 0, heightAlpha)
            surface.DrawRect(0, 0, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT)
        end

        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawRect(INKMESH_FIXTURE_RT / 2, 0, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT)
    end)

    fillRT(params, { 255, 255, 255, 255 }, function()
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 4, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 5, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 6, 1, 1)
        surface.SetDrawColor(0, 0, 0, 0)
        surface.DrawRect(0, 7, 1, 1)
    end)

    fillRT(details, { 255, 255, 255, 255 }, function() end)
    fillRT(sceneDepth, { 255, 255, 255, 255 }, function() end)
    fillRT(frameBuffer, { 255, 255, 255, 255 }, function() end)

    return {
        inkMap = inkMap,
        params = params,
        details = details,
        sceneDepth = sceneDepth,
        frameBuffer = frameBuffer,
    }
end

---@param color number[]|Color
---@return integer[][]
local function buildInkmeshExpected(color)
    return rt.NewPixelMap(INKMESH_FIXTURE_RT, INKMESH_FIXTURE_RT, color)
end

---@param distance number?
---@param projPosZ number?
---@return Vector
local function buildWorldPosProjPosZ(distance, projPosZ)
    local eye = EyePos()
    local d = tonumber(distance) or 32
    return { eye.x - d, eye.y, eye.z, projPosZ or INKMESH_PROJ_POS_Z }
end

---@param role integer?
---@param projPosW number?
---@return number[]
local function buildProjPosWMeshRole(role, projPosW)
    return { projPosW or INKMESH_PROJ_POS_W, role or INKMESH_ROLE_BASE, 0, 0 }
end

---@param material IMaterial
---@param opts table
local function drawInkmeshQuad(material, opts)
    local width = INKMESH_FIXTURE_RT
    local height = INKMESH_FIXTURE_RT
    local clipRange = opts.clipRange or INKMESH_CLIP_FULL
    local proxyU = opts.proxyU or INKMESH_PROXY_U
    local proxyV = opts.proxyV or INKMESH_PROXY_V
    local worldPosProjPosZ = opts.worldPosProjPosZ
        or buildWorldPosProjPosZ(opts.eyeNormalDistance, opts.projPosZ)
    local worldNormalTangentY = opts.worldNormalTangentY or { 1, 0, 0, 0 }
    local inkTangentXYZWorldZ = opts.inkTangentXYZWorldZ or { 0, 0, 0, 0 }
    local inkBinormalMeshLift = opts.inkBinormalMeshLift or { 0, 0, 0, 0 }
    local projPosWMeshRole = opts.projPosWMeshRole
        or buildProjPosWMeshRole(opts.role, opts.projPosW)
    local vertices = {
        Vector(0, 0, 0),
        Vector(0, height, 0),
        Vector(width, height, 0),
        Vector(width, 0, 0),
    }

    render.SetMaterial(material)
    mesh.Begin(MATERIAL_QUADS, 1)
    for _, pos in ipairs(vertices) do
        mesh.Position(pos)
        mesh.TexCoord(0, proxyU, proxyV, 0, 0)
        mesh.TexCoord(1, clipRange[1], clipRange[2], clipRange[3], clipRange[4])
        mesh.TexCoord(2, worldPosProjPosZ[1], worldPosProjPosZ[2], worldPosProjPosZ[3], worldPosProjPosZ[4])
        mesh.TexCoord(3, worldNormalTangentY[1], worldNormalTangentY[2], worldNormalTangentY[3], worldNormalTangentY[4])
        mesh.TexCoord(4, inkTangentXYZWorldZ[1], inkTangentXYZWorldZ[2], inkTangentXYZWorldZ[3], inkTangentXYZWorldZ[4])
        mesh.TexCoord(5, inkBinormalMeshLift[1], inkBinormalMeshLift[2], inkBinormalMeshLift[3], inkBinormalMeshLift[4])
        mesh.TexCoord(6, projPosWMeshRole[1], projPosWMeshRole[2], projPosWMeshRole[3], projPosWMeshRole[4])
        mesh.AdvanceVertex()
    end
    mesh.End()
end

---@param opts { name: string, heightAlpha: integer?, clipRange: number[]?, eyeNormalDistance: number?, worldPosProjPosZ: number[]?, worldNormalTangentY: number[]?, inkTangentXYZWorldZ: number[]?, inkBinormalMeshLift: number[]?, projPosWMeshRole: number[]?, role: integer?, projPosW: number?, projPosZ: number?, proxyU: number?, proxyV: number? }
---@return integer[][]
local function captureInkmeshDebug(opts)
    local textures = configureInkmeshFixtureTextures(opts.name, opts.heightAlpha)
    local material = getInkmeshMaterial()
    material:SetTexture("$basetexture", textures.inkMap)
    material:SetTexture("$texture1", textures.params)
    material:SetTexture("$texture2", textures.sceneDepth)
    material:SetTexture("$texture3", textures.frameBuffer)
    material:SetTexture("$texture4", textures.details)
    material:SetTexture("$texture5", "white")
    material:SetTexture("$texture6", "null-bumpmap")
    material:SetTexture("$texture7", "white")
    material:SetInt("$c0_w", 1)
    material:SetFloat("$c1_x", 0)
    material:SetFloat("$c1_y", 0)
    material:SetFloat("$c1_w", 0)
    material:Recompute()

    return rt.CaptureRT(
        INKMESH_FIXTURE_RT,
        INKMESH_FIXTURE_RT,
        function()
            local toneMapping = render.GetToneMappingScaleLinear()
            render.TurnOnToneMapping()
            render.SetGoalToneMappingScale(1)
            render.SetToneMappingScaleLinear(Vector(1, 1, 1))
            local ok, err = pcall(function()
                drawInkmeshQuad(material, opts)
            end)
            render.SetToneMappingScaleLinear(toneMapping)
            if not ok then error(err, 0) end
        end,
        opts.name .. "_capture",
        { 0, 0, 0, 0 }
    )
end

ss.RenderHarness.ClearTestPrefix("inkmesh.")

---@type ss.RenderHarness.Case[]
local cases = {
    {
        name = "inkmesh.tracekind.hit_start",
        run = function(t)
            local actual = captureInkmeshDebug {
                name = "inkmesh_tracekind_hit_start",
                heightAlpha = 255,
                clipRange = INKMESH_CLIP_FULL,
                eyeNormalDistance = 32,
                worldPosProjPosZ = buildWorldPosProjPosZ(32, 1),
                inkBinormalMeshLift = { 0, 0, 0, 0 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_START),
                "inkmesh debug trace kind hit-start",
                4
            )
        end,
    },
    {
        name = "inkmesh.tracekind.hit_crossing",
        run = function(t)
            local actual = captureInkmeshDebug {
                name = "inkmesh_tracekind_hit_crossing",
                heightAlpha = 128,
                clipRange = INKMESH_CLIP_FULL,
                eyeNormalDistance = 32,
                worldPosProjPosZ = buildWorldPosProjPosZ(32, 1),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_CROSSING),
                "inkmesh debug trace kind hit-crossing",
                4
            )
        end,
    },
    {
        name = "inkmesh.tracekind.box_miss_visible",
        run = function(t)
            local actual = captureInkmeshDebug {
                name = "inkmesh_tracekind_box_miss",
                heightAlpha = 128,
                clipRange = { 0.0, 0.0, 0.1, 0.1 },
                eyeNormalDistance = 32,
                worldPosProjPosZ = buildWorldPosProjPosZ(32, 1),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_BOX_MISS),
                "inkmesh debug trace kind box-miss remains visible",
                4
            )
        end,
    },
    {
        name = "inkmesh.tracekind.no_hit_visible",
        run = function(t)
            local actual = captureInkmeshDebug {
                name = "inkmesh_tracekind_no_hit",
                heightAlpha = 0,
                clipRange = INKMESH_CLIP_FULL,
                eyeNormalDistance = 32,
                worldPosProjPosZ = buildWorldPosProjPosZ(32, 1),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_NO_HIT),
                "inkmesh debug trace kind no-hit remains visible",
                4
            )
        end,
    },
}

ss.RenderHarness.ScheduleTests(ss.RenderHarness.RegisterCases(cases))
