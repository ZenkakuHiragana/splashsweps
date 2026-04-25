---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshTransportSuite
---@field BuildCases fun(): ss.RenderHarness.Case[]
ss.InkmeshTransportSuite = ss.InkmeshTransportSuite or {}
local suite = ss.InkmeshTransportSuite

local support = ss.InkmeshTestSupport
if not support then return end

local function encodeRoleByte(role)
    return math.floor((role / ss.TRI_MAX) * 255 + 0.5)
end

local BASE_CAMERA = {
    origin = Vector(32, -64, 32),
    angles = Angle(0, 90, 0),
    fov = 50,
    znear = 1,
    zfar = 512,
}

local function buildBaseVertex(role, alpha)
    return {
        normal = Vector(0, 0, 1),
        color = { 0, 0, encodeRoleByte(role or ss.TRI_BASE), alpha or 191 },
        baseBumpUV = { 0.5, 0.25, 0.25, 0.25 },
        lightmapUVOffset = { 0, 0, 0, 0 },
        inkTangent = { 0, 0.5, 0, 0.5 },
        inkBinormal = { 0.5, 0, 0, -0.25 },
        tangent = { 1, 0, 0, -0.5 },
        binormal = { 0, 1, 0, 0.25 },
        surfaceClipRangeRaw = { 0, 0, 1, 1 },
    }
end

local function mergeVertex(base, overrides)
    local vertex = table.Copy(base)
    for key, value in pairs(overrides or {}) do
        vertex[key] = value
    end
    return vertex
end

local function buildQuad(base, overrides)
    return support.BuildRealVSQuadXZFacingNegativeY(base, 0, 64, 0, 64, 0, overrides)
end

local FULL_INKMAP_WRITE = {
    color = { 255, 255, 255, 255 },
    x = 0,
    y = 0,
    w = support.FIXTURE_RT,
    h = support.FIXTURE_RT,
}

---@return ss.RenderHarness.Case[]
function suite.BuildCases()
    local cases = {} ---@type ss.RenderHarness.Case[]

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.role_encoding.side_in",
        label = "inkmesh transport role encoding side in",
        expected = support.BuildExpectedUnit(0.75, 0.75, 0.0),
        opts = {
            name = "inkmesh_transport_role_encoding_side_in",
            debugMode = 11,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(buildBaseVertex(ss.TRI_SIDE_IN, 191)),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.role_encoding.side_out",
        label = "inkmesh transport role encoding side out",
        expected = support.BuildExpectedUnit(1.0, 1.0, 0.0),
        opts = {
            name = "inkmesh_transport_role_encoding_side_out",
            debugMode = 11,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(buildBaseVertex(ss.TRI_SIDE_OUT, 191)),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.role_encoding.depth",
        label = "inkmesh transport role encoding depth",
        expected = support.BuildExpectedUnit(0.25, 0.25, 0.0),
        opts = {
            name = "inkmesh_transport_role_encoding_depth",
            debugMode = 11,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(buildBaseVertex(ss.TRI_DEPTH, 191)),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.surface_clip_range",
        label = "inkmesh transport surface clip range",
        expected = support.BuildExpectedUnit(0.125, 0.25, 0.5, 0.375),
        opts = {
            name = "inkmesh_transport_surface_clip_range",
            debugMode = 15,
            c2_x = 1,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                surfaceClipRangeRaw = { 0.5, 0.25, 0.75, 1.0 },
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.ink_uv_and_lift",
        label = "inkmesh transport ink uv and lift",
        expected = support.BuildExpectedUnit(0.25, 0.125, 128 / 255, 1.0),
        opts = {
            name = "inkmesh_transport_ink_uv_and_lift",
            debugMode = 15,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_CEIL, 128), {
                baseBumpUV = { 0.5, 0.25, 0.75, 1.0 },
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.ink_tangent_xyz_world_z",
        label = "inkmesh transport ink tangent xyz world z",
        expected = support.BuildExpectedSigned(0.25, -0.25, 0.0),
        opts = {
            name = "inkmesh_transport_ink_tangent_xyz_world_z",
            debugMode = 16,
            c2_x = 1,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                inkBinormal = { 0.5, -0.5, 0.0, 0.0 },
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.ink_binormal_mesh_lift",
        label = "inkmesh transport ink binormal mesh lift",
        expected = support.BuildExpectedSigned(-0.25, 0.125, 0.25),
        opts = {
            name = "inkmesh_transport_ink_binormal_mesh_lift",
            debugMode = 16,
            c2_y = 1,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                inkTangent = { -0.5, 0.25, 0.5, 0.0 },
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.world_normal_passthrough",
        label = "inkmesh transport world normal passthrough",
        expected = support.BuildExpectedSigned(0.25, -0.5, 0.5),
        opts = {
            name = "inkmesh_transport_world_normal_passthrough",
            debugMode = 16,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                normal = Vector(0.25, -0.5, 0.5),
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.jacobian_row0",
        label = "inkmesh transport jacobian row zero",
        expected = support.BuildExpectedUnit(0.75, 0.375, 0.0),
        opts = {
            name = "inkmesh_transport_jacobian_row0",
            debugMode = 17,
            c2_x = 1,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                tangent = { 1, 0, 0, 0.5 },
                binormal = { 0, 1, 0, -0.25 },
            })),
        },
    })

    support.AppendDisplayRealVSCase(cases, {
        name = "inkmesh.transport.jacobian_row1",
        label = "inkmesh transport jacobian row one",
        expected = support.BuildExpectedUnit(0.625, 0.25, 0.0),
        opts = {
            name = "inkmesh_transport_jacobian_row1",
            debugMode = 17,
            camera = table.Copy(BASE_CAMERA),
            heightAlpha = 255,
            depthAlpha = 255,
            inkMapWrites = { FULL_INKMAP_WRITE },
            vertices = buildQuad(mergeVertex(buildBaseVertex(ss.TRI_SIDE_IN, 191), {
                inkTangent = { 0, 0, 0, 0.25 },
                inkBinormal = { 0, 0, 0, -0.5 },
            })),
        },
    })

    return cases
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
