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
local COLOR_TRACE_HIT_CENTER = { 64, 64, 128, 255 }
local COLOR_TRACE_HIT_FRACTION = { 92, 32, 0, 255 }
local COLOR_TRACE_SAMPLE_FETCH = { 255, 255, 0, 255 }
local COLOR_DISPLAY_TRACE_HIT_CROSSING = COLOR_TRACE_HIT_CROSSING

---@type ss.RenderHarness
local rt = ss.RenderHarness
if not rt or not rt.CaptureRT or not rt.NewPixelMap or not rt.RegisterSuite then return end

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
local function getInkmeshCoreMaterial()
    local material = Material("splashsweps/shaders/inkmesh_core_test")
    return material
end

---@return IMaterial
local function getInkmeshDisplayMaterial()
    local material = Material("splashsweps/shaders/inkmesh_test")
    return material
end

---@param name string
---@param opts { heightAlpha?: integer, depthAlpha?: integer, indexColor?: number[]|Color, paramsFill?: number[]|Color?, detailsFill?: number[]|Color?, sceneDepthFill?: number[]|Color?, frameBufferFill?: number[]|Color? }
---@return { inkMap: ITexture, params: ITexture, details: ITexture, sceneDepth: ITexture, frameBuffer: ITexture }
local function configureInkmeshFixtureTextures(name, opts)
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
    local heightAlpha = opts.heightAlpha or 0
    local depthAlpha = opts.depthAlpha or 255
    local indexColor = opts.indexColor or { 255, 255, 255, 255 }

    fillRT(inkMap, { 0, 0, 0, 0 }, function()
        if heightAlpha > 0 then
            surface.SetDrawColor(0, 0, 0, heightAlpha)
            surface.DrawRect(0, 0, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT)
        end

        surface.SetDrawColor(0, 0, 0, depthAlpha)
        surface.DrawRect(INKMESH_FIXTURE_RT / 2, 0, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT)

        surface.SetDrawColor(indexColor[1], indexColor[2], indexColor[3], indexColor[4])
        surface.DrawRect(0, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT / 2, INKMESH_FIXTURE_RT / 2)
    end)

    fillRT(params, opts.paramsFill or { 255, 255, 255, 255 }, function()
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 4, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 5, 1, 1)
        surface.SetDrawColor(0, 255, 255, 255)
        surface.DrawRect(0, 6, 1, 1)
        surface.SetDrawColor(0, 0, 0, 0)
        surface.DrawRect(0, 7, 1, 1)
    end)

    fillRT(details, opts.detailsFill or { 255, 255, 255, 255 }, function() end)
    fillRT(sceneDepth, opts.sceneDepthFill or { 255, 255, 255, 255 }, function() end)
    fillRT(frameBuffer, opts.frameBufferFill or { 255, 255, 255, 255 }, function() end)

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
---@return number[]
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

---@param lift number?
---@param proxyU number?
---@param proxyV number?
---@param eyeHeight number?
---@return number[]
local function buildCoreEyeUV(lift, proxyU, proxyV, eyeHeight)
    return {
        proxyU or INKMESH_PROXY_U,
        proxyV or INKMESH_PROXY_V,
        (lift or 0) + (eyeHeight or 1),
        0,
    }
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

---@param material IMaterial
---@param textures { inkMap: ITexture, params: ITexture, details: ITexture, sceneDepth: ITexture, frameBuffer: ITexture }
---@param opts table
---@return integer[][]
local function captureInkmeshFixture(material, textures, opts)
    material:SetTexture("$basetexture", textures.inkMap)
    material:SetTexture("$texture1", textures.params)
    material:SetTexture("$texture2", textures.sceneDepth)
    material:SetTexture("$texture3", textures.frameBuffer)
    material:SetTexture("$texture4", textures.details)
    material:SetTexture("$texture5", "white")
    material:SetTexture("$texture6", "null-bumpmap")
    material:SetTexture("$texture7", "white")
    material:SetInt("$c0_w", opts.debugMode or 1)
    material:SetFloat("$c1_x", opts.c1_x or 0)
    material:SetFloat("$c1_y", opts.c1_y or 0)
    material:SetFloat("$c1_w", opts.c1_w or 0)
    material:Recompute()

    return rt.CaptureRT(
        INKMESH_FIXTURE_RT,
        INKMESH_FIXTURE_RT,
        function()
            local toneMapping = render.GetToneMappingScaleLinear()
            render.TurnOnToneMapping()
            render.SetGoalToneMappingScale(1)
            render.SetToneMappingScaleLinear(Vector(1, 1, 1))
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
            local ok, err = pcall(function()
                drawInkmeshQuad(material, opts)
            end)
            render.OverrideBlend(false)
            render.SetToneMappingScaleLinear(toneMapping)
            if not ok then error(err, 0) end
        end,
        opts.name .. "_capture",
        { 0, 0, 0, 0 }
    )
end

---@param opts { name: string, debugMode?: integer, heightAlpha?: integer, depthAlpha?: integer, indexColor?: number[]|Color, clipRange?: number[], eyeNormalDistance?: number, worldPosProjPosZ?: number[], worldNormalTangentY?: number[], inkTangentXYZWorldZ?: number[], inkBinormalMeshLift?: number[], projPosWMeshRole?: number[], role?: integer, projPosW?: number, projPosZ?: number, proxyU?: number, proxyV?: number, c1_x?: number, c1_y?: number, c1_w?: number }
---@return integer[][]
local function captureInkmeshCoreDebug(opts)
    local textures = configureInkmeshFixtureTextures(opts.name, opts)
    local material = getInkmeshCoreMaterial()
    return captureInkmeshFixture(material, textures, opts)
end

---@param opts { name: string, debugMode?: integer, heightAlpha?: integer, depthAlpha?: integer, indexColor?: number[]|Color, clipRange?: number[], eyeNormalDistance?: number, worldPosProjPosZ?: number[], worldNormalTangentY?: number[], inkTangentXYZWorldZ?: number[], inkBinormalMeshLift?: number[], projPosWMeshRole?: number[], role?: integer, projPosW?: number, projPosZ?: number, proxyU?: number, proxyV?: number, c1_x?: number, c1_y?: number, c1_w?: number }
---@return integer[][]
local function captureInkmeshDisplayDebug(opts)
    local textures = configureInkmeshFixtureTextures(opts.name, opts)
    local material = getInkmeshDisplayMaterial()
    return captureInkmeshFixture(material, textures, opts)
end

rt.ClearTestPrefix("inkmesh.")

---@type ss.RenderHarness.Case[]
local cases = {
    {
        name = "inkmesh.core.tracekind.hit_start",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_tracekind_hit_start",
                debugMode = 1,
                heightAlpha = 255,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildCoreEyeUV(0),
                inkBinormalMeshLift = { 0, 0, 0, 0 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_START),
                "inkmesh core trace kind hit-start",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.tracekind.hit_crossing",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_tracekind_hit_crossing",
                debugMode = 1,
                heightAlpha = 128,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildCoreEyeUV(-0.75),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_CROSSING),
                "inkmesh core trace kind hit-crossing",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.tracekind.box_miss_visible",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_tracekind_box_miss",
                debugMode = 1,
                heightAlpha = 128,
                clipRange = { 0.0, 0.0, 0.1, 0.1 },
                worldPosProjPosZ = buildCoreEyeUV(-0.75),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_BOX_MISS),
                "inkmesh core trace kind box-miss",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.tracekind.no_hit_visible",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_tracekind_no_hit",
                debugMode = 1,
                heightAlpha = 0,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = { INKMESH_PROXY_U, 0.75, 0.25, 0 },
                inkBinormalMeshLift = { 0, 0, 0, 0.25 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_NO_HIT),
                "inkmesh core trace kind no-hit",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.hit_uv_encoding.center",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_hit_uv_center",
                debugMode = 2,
                heightAlpha = 128,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildCoreEyeUV(-0.75),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
                worldNormalTangentY = { 1, 0, 0, 0 },
                inkTangentXYZWorldZ = { 0, 1, 0, 0 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_CENTER),
                "inkmesh core hit UV encoding",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.trace_fraction_and_steps",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_trace_fraction_steps",
                debugMode = 3,
                heightAlpha = 128,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildCoreEyeUV(-0.75),
                inkBinormalMeshLift = { 0, 0, 0, -0.75 },
                worldNormalTangentY = { 1, 0, 0, 0 },
                inkTangentXYZWorldZ = { 0, 1, 0, 0 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_HIT_FRACTION),
                "inkmesh core trace fraction and steps",
                4
            )
        end,
    },
    {
        name = "inkmesh.core.height_depth_fetch",
        run = function(t)
            local actual = captureInkmeshCoreDebug {
                name = "inkmesh_core_height_depth_fetch",
                debugMode = 4,
                heightAlpha = 255,
                depthAlpha = 255,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildCoreEyeUV(0),
                inkBinormalMeshLift = { 0, 0, 0, 0 },
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_TRACE_SAMPLE_FETCH),
                "inkmesh core height/depth fetch",
                4
            )
        end,
    },
    {
        name = "inkmesh.display.tracekind.hit_crossing",
        run = function(t)
            local actual = captureInkmeshDisplayDebug {
                name = "inkmesh_display_tracekind_hit_crossing",
                debugMode = 1,
                heightAlpha = 255,
                clipRange = INKMESH_CLIP_FULL,
                worldPosProjPosZ = buildWorldPosProjPosZ(32, 1),
                inkBinormalMeshLift = { 0, 0, 0, 0 },
                eyeNormalDistance = 32,
            }

            t.assertPixelsEqual(
                INKMESH_FIXTURE_RT,
                INKMESH_FIXTURE_RT,
                actual,
                buildInkmeshExpected(COLOR_DISPLAY_TRACE_HIT_CROSSING),
                "inkmesh display trace kind hit-crossing",
                4
            )
        end,
    },
}

rt.RegisterSuite("inkmesh", cases)
