---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshVisualSuite
---@field BuildCases fun(): ss.RenderHarness.Case[]
ss.InkmeshVisualSuite = ss.InkmeshVisualSuite or {}
local suite = ss.InkmeshVisualSuite

local support = ss.InkmeshTestSupport
local fixtures = ss.InkmeshTestFixtures
if not support or not fixtures then return end

local FULL_INKMAP_WRITE = {
    color = { 255, 255, 255, 255 },
    x = 0,
    y = 0,
    w = support.FIXTURE_RT,
    h = support.FIXTURE_RT,
}

local FACE_TEMPLATE = {
    normal = Vector(0, -1, 0),
    baseBumpUV = { 0.5, 0.5, 0.25, 0.25 },
    lightmapUVOffset = { 0, 0, 0, 0 },
    inkTangent = { 0, 0, 1 / 64, 0 },
    inkBinormal = { 1 / 64, 0, 0, 0 },
    tangent = { 1, 0, 0, 0 },
    binormal = { 0, 0, 1, 0 },
    surfaceClipRangeRaw = { 0, 0, 1, 1 },
}

---@param role ss.TRI_TYPE
---@param liftType ss.LIFT_TYPE
---@return table
local function buildFaceBase(role, liftType)
    local base = table.Copy(FACE_TEMPLATE)
    base.color = support.BuildRoleLiftColor(role, liftType)
    return base
end

---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@return Vector
---@return Vector
---@return Vector
---@return Vector
local function buildRectCorners(x0, x1, z0, z1)
    local p1 = Vector(x0, 0, z0)
    local p2 = Vector(x1, 0, z0)
    local p3 = Vector(x1, 0, z1)
    local p4 = Vector(x0, 0, z1)
    return p1, p2, p3, p4
end

---@param role ss.TRI_TYPE
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@param reverse? boolean
---@return table[]
local function buildTopFace(role, x0, x1, z0, z1, reverse)
    local p1, p2, p3, p4 = buildRectCorners(x0, x1, z0, z1)
    local positions = reverse
        and { p1, p3, p2, p1, p4, p3 }
        or { p1, p2, p3, p1, p3, p4 }
    return support.BuildRealVSVertices(
        buildFaceBase(role, support.LIFT_NONE),
        positions,
        support.BuildRealVSBaseBumpUVFromXZ(positions, x0, x1, z0, z1)
    )
end

---@param role ss.TRI_TYPE
---@param positions Vector[]
---@param lifts ss.LIFT_TYPE[]
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@return table[]
local function buildLiftedEdge(role, positions, lifts, x0, x1, z0, z1)
    local overrides = support.BuildRealVSBaseBumpUVFromXZ(positions, x0, x1, z0, z1)
    for i, liftType in ipairs(lifts) do
        overrides[i] = table.Merge(overrides[i] or {}, {
            color = support.BuildRoleLiftColor(role, liftType),
        })
    end

    return support.BuildRealVSVertices(table.Copy(FACE_TEMPLATE), positions, overrides)
end

---@param pI Vector
---@param pJ Vector
---@param role ss.TRI_TYPE
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@return table[]
local function buildSideInEdge(pI, pJ, role, x0, x1, z0, z1)
    return buildLiftedEdge(role, {
        pJ, pI, pJ,
        pI, pI, pJ,
    }, {
        support.LIFT_NONE,
        support.LIFT_NONE,
        support.LIFT_UP,
        support.LIFT_NONE,
        support.LIFT_UP,
        support.LIFT_UP,
    }, x0, x1, z0, z1)
end

---@param pI Vector
---@param pJ Vector
---@param role ss.TRI_TYPE
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@return table[]
local function buildSideOutEdge(pI, pJ, role, x0, x1, z0, z1)
    return buildLiftedEdge(role, {
        pJ, pI, pJ,
        pJ, pI, pI,
    }, {
        support.LIFT_UP,
        support.LIFT_NONE,
        support.LIFT_NONE,
        support.LIFT_UP,
        support.LIFT_UP,
        support.LIFT_NONE,
    }, x0, x1, z0, z1)
end

---@param pI Vector
---@param pJ Vector
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@return table[]
local function buildDepthEdge(pI, pJ, x0, x1, z0, z1)
    return buildLiftedEdge(ss.TRI_DEPTH, {
        pJ, pJ, pI,
        pI, pJ, pI,
    }, {
        support.LIFT_DOWN,
        support.LIFT_NONE,
        support.LIFT_DOWN,
        support.LIFT_DOWN,
        support.LIFT_NONE,
        support.LIFT_NONE,
    }, x0, x1, z0, z1)
end

---@return table[]
local function buildStraightSideInFixture()
    local p1, _, _, p4 = buildRectCorners(0, 64, 0, 64)
    return {
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildTopFace(ss.TRI_BASE, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideInEdge(p4, p1, ss.TRI_SIDE_IN, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p4, p1, 0, 64, 0, 64) },
    }
end

---@return table[]
local function buildStraightSideOutFixture()
    local p1, _, _, p4 = buildRectCorners(0, 64, 0, 64)
    return {
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildTopFace(ss.TRI_BASE, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideOutEdge(p4, p1, ss.TRI_SIDE_OUT, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p4, p1, 0, 64, 0, 64) },
    }
end

---@return table[]
local function buildCornerFixture()
    local p1, p2, _, p4 = buildRectCorners(0, 64, 0, 64)
    return {
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildTopFace(ss.TRI_BASE, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideInEdge(p4, p1, ss.TRI_SIDE_IN, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideInEdge(p1, p2, ss.TRI_SIDE_IN, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p4, p1, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p1, p2, 0, 64, 0, 64) },
    }
end

---@return table[]
local function buildSideWithoutCeilFixture()
    local p1, _, _, p4 = buildRectCorners(0, 64, 0, 64)
    return {
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideInEdge(p4, p1, ss.TRI_SIDE_IN, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p4, p1, 0, 64, 0, 64) },
    }
end

---@return table[]
local function buildSideWithCeilFixture()
    local p1, _, _, p4 = buildRectCorners(0, 64, 0, 64)
    return {
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildSideInEdge(p4, p1, ss.TRI_SIDE_IN, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildDepthEdge(p4, p1, 0, 64, 0, 64) },
        { primitiveType = MATERIAL_TRIANGLES, vertices = buildTopFace(ss.TRI_CEIL, 0, 64, 0, 64, true) },
    }
end

---@param origin Vector
---@param target Vector
---@return table
local function buildCamera(origin, target)
    return {
        origin = origin,
        angles = (target - origin):Angle(),
        fov = 50,
        znear = 1,
        zfar = 1024,
    }
end

local STRAIGHT_TARGET = Vector(8, -16, 32)
local CORNER_TARGET = Vector(8, -16, 8)

local STRAIGHT_CAMERAS = {
    high = buildCamera(Vector(96, -160, 48), STRAIGHT_TARGET),
    low = buildCamera(Vector(96, -20, 24), STRAIGHT_TARGET),
    shallow = buildCamera(Vector(160, -96, 16), STRAIGHT_TARGET),
}

local CORNER_CAMERAS = {
    high = buildCamera(Vector(96, -160, 96), CORNER_TARGET),
    low = buildCamera(Vector(96, -20, 64), CORNER_TARGET),
    shallow = buildCamera(Vector(160, -96, 64), CORNER_TARGET),
}

---@param name string
---@param camera table
---@param draws table[]
---@return table
local function buildVisualOpts(name, camera, draws)
    return {
        name = name,
        debugMode = 0,
        camera = table.Copy(camera),
        heightAlpha = 255,
        depthAlpha = 255,
        inkMapWrites = { FULL_INKMAP_WRITE },
        wallAlbedoFill = { 255, 255, 255, 255 },
        wallBumpFill = { 128, 128, 255, 255 },
        lightmapFill = { 255, 255, 255, 255 },
        draws = draws,
    }
end

---@param cases ss.RenderHarness.Case[]
---@param spec table
local function appendVisibilityCase(cases, spec)
    cases[#cases + 1] = {
        name = spec.name,
        run = function(t)
            local actual = fixtures.CaptureDisplayRealVS(spec.opts)
            support.AssertVisibilityContract(t, actual, spec.label, spec.contract)
        end,
    }
end

---@param cases ss.RenderHarness.Case[]
---@param spec table
local function appendVisibilityGainCase(cases, spec)
    cases[#cases + 1] = {
        name = spec.name,
        run = function(t)
            local beforePixels = fixtures.CaptureDisplayRealVS(spec.beforeOpts)
            local afterPixels = fixtures.CaptureDisplayRealVS(spec.afterOpts)
            support.AssertVisibilityGainContract(t, beforePixels, afterPixels, spec.label, spec.contract)
        end,
    }
end

local STRAIGHT_HIGH_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 5, y = 3, w = 2, h = 3 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local STRAIGHT_LOW_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 4, y = 2, w = 2, h = 5 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local STRAIGHT_SHALLOW_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 4, y = 3, w = 1, h = 3 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CORNER_HIGH_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 5, y = 2, w = 2, h = 3 },
        { x = 4, y = 4, w = 2, h = 1 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CORNER_LOW_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 4, y = 0, w = 2, h = 8 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CORNER_SHALLOW_CONTRACT = {
    requiredVisible = support.BuildMaskFromRects {
        { x = 4, y = 2, w = 1, h = 3 },
    },
    requiredHidden = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CEIL_HIGH_GAIN = {
    requiredGain = support.BuildMaskFromRects {
        { x = 5, y = 3, w = 3, h = 3 },
    },
    forbiddenGain = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CEIL_LOW_GAIN = {
    requiredGain = support.BuildMaskFromRects {
        { x = 6, y = 0, w = 2, h = 8 },
    },
    forbiddenGain = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

local CEIL_SHALLOW_GAIN = {
    requiredGain = support.BuildMaskFromRects {
        { x = 6, y = 2, w = 1, h = 1 },
        { x = 5, y = 3, w = 2, h = 3 },
    },
    forbiddenGain = support.BuildMaskFromRects {
        { x = 0, y = 6, w = 2, h = 2 },
    },
}

---@return ss.RenderHarness.Case[]
function suite.BuildCases()
    local cases = {} ---@type ss.RenderHarness.Case[]

    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_in.high_camera",
        label = "inkmesh visual straight side in high camera",
        contract = STRAIGHT_HIGH_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_in_high", STRAIGHT_CAMERAS.high, buildStraightSideInFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_in.low_camera",
        label = "inkmesh visual straight side in low camera",
        contract = STRAIGHT_LOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_in_low", STRAIGHT_CAMERAS.low, buildStraightSideInFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_in.shallow_oblique",
        label = "inkmesh visual straight side in shallow oblique",
        contract = STRAIGHT_SHALLOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_in_shallow", STRAIGHT_CAMERAS.shallow, buildStraightSideInFixture()),
    })

    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_out.high_camera",
        label = "inkmesh visual straight side out high camera",
        contract = STRAIGHT_HIGH_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_out_high", STRAIGHT_CAMERAS.high, buildStraightSideOutFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_out.low_camera",
        label = "inkmesh visual straight side out low camera",
        contract = STRAIGHT_LOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_out_low", STRAIGHT_CAMERAS.low, buildStraightSideOutFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.straight_side_out.shallow_oblique",
        label = "inkmesh visual straight side out shallow oblique",
        contract = STRAIGHT_SHALLOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_straight_side_out_shallow", STRAIGHT_CAMERAS.shallow, buildStraightSideOutFixture()),
    })

    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.corner_side_in.high_camera",
        label = "inkmesh visual corner side in high camera",
        contract = CORNER_HIGH_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_corner_side_in_high", CORNER_CAMERAS.high, buildCornerFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.corner_side_in.low_camera",
        label = "inkmesh visual corner side in low camera",
        contract = CORNER_LOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_corner_side_in_low", CORNER_CAMERAS.low, buildCornerFixture()),
    })
    appendVisibilityCase(cases, {
        name = "inkmesh.visual.contract.corner_side_in.shallow_oblique",
        label = "inkmesh visual corner side in shallow oblique",
        contract = CORNER_SHALLOW_CONTRACT,
        opts = buildVisualOpts("inkmesh_visual_contract_corner_side_in_shallow", CORNER_CAMERAS.shallow, buildCornerFixture()),
    })

    appendVisibilityGainCase(cases, {
        name = "inkmesh.visual.contract.ceil_gain.high_camera",
        label = "inkmesh visual ceil gain high camera",
        contract = CEIL_HIGH_GAIN,
        beforeOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_high_before", STRAIGHT_CAMERAS.high, buildSideWithoutCeilFixture()),
        afterOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_high_after", STRAIGHT_CAMERAS.high, buildSideWithCeilFixture()),
    })
    appendVisibilityGainCase(cases, {
        name = "inkmesh.visual.contract.ceil_gain.low_camera",
        label = "inkmesh visual ceil gain low camera",
        contract = CEIL_LOW_GAIN,
        beforeOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_low_before", STRAIGHT_CAMERAS.low, buildSideWithoutCeilFixture()),
        afterOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_low_after", STRAIGHT_CAMERAS.low, buildSideWithCeilFixture()),
    })
    appendVisibilityGainCase(cases, {
        name = "inkmesh.visual.contract.ceil_gain.shallow_oblique",
        label = "inkmesh visual ceil gain shallow oblique",
        contract = CEIL_SHALLOW_GAIN,
        beforeOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_shallow_before", STRAIGHT_CAMERAS.shallow, buildSideWithoutCeilFixture()),
        afterOpts = buildVisualOpts("inkmesh_visual_contract_ceil_gain_shallow_after", STRAIGHT_CAMERAS.shallow, buildSideWithCeilFixture()),
    })

    return cases
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
