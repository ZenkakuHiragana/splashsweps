---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshTestSupport
ss.InkmeshTestSupport = ss.InkmeshTestSupport or {}

---@class ss.InkmeshTestSupport
local support = ss.InkmeshTestSupport

---@type ss.RenderHarness
local rt = ss.RenderHarness
if not rt or not rt.NewPixelMap then return end

support.FIXTURE_RT = 8
support.ROLE_BASE = ss.TRI_BASE / ss.TRI_MAX ---@type number
support.LIFT_DOWN = ss.LIFT_DOWN
support.LIFT_NONE = ss.LIFT_NONE
support.LIFT_UP = ss.LIFT_UP
support.PROXY_U = 0.25
support.PROXY_V = 0.25
support.CLIP_FULL = { 0.0, 0.0, 0.5, 0.5 }
support.PROJ_POS_Z = 1.0
support.PROJ_POS_W = 1.0
support.COLORS = {
    trace_box_miss = { 255, 255, 0, 255 },
    trace_no_hit = { 255, 0, 255, 255 },
    trace_hit_start = { 0, 255, 0, 255 },
    trace_hit_crossing = { 0, 128, 255, 255 },
    display_visible = { 255, 255, 255, 255 },
    display_empty_ink = { 255, 128, 0, 255 },
    display_negative_thickness = { 128, 0, 255, 255 },
    trace_hit_fraction = { 92, 32, 0, 255 },
    trace_sample_fetch = { 255, 255, 0, 255 },
    geometry_white = { 255, 255, 255, 255 },
    geometry_red = { 255, 0, 0, 255 },
}
support.MidHeightSigned = (128 / 255) * 2 - 1
support.MidHeightUnit = support.MidHeightSigned * 0.5 + 0.5

---@param value number
---@return number
function support.SignedToUnit(value)
    return math.Clamp((tonumber(value) or 0) * 0.5 + 0.5, 0, 1)
end

---@class ss.InkmeshTestCaseSpec
---@field name string
---@field label string
---@field expected integer[][]
---@field tolerance? integer
---@field capture fun(opts: table): integer[][]
---@field transformActual? fun(actual: integer[][]): integer[][]
---@field opts table

---@class ss.InkmeshSuiteCaseSpec
---@field name string
---@field label string
---@field expected integer[][]
---@field tolerance? integer
---@field transformActual? fun(actual: integer[][]): integer[][]
---@field opts table

---@param value number
---@return integer
local function unitToByte(value)
    return math.floor(math.Clamp(value, 0, 1) * 255 + 0.5)
end

---@param role ss.TRI_TYPE
---@return integer
function support.EncodeRoleByte(role)
    return unitToByte((tonumber(role) or ss.TRI_BASE) / ss.TRI_MAX)
end

---@param liftType ss.LIFT_TYPE
---@return integer
function support.EncodeLiftByte(liftType)
    return unitToByte((tonumber(liftType) or ss.LIFT_NONE) * 0.5)
end

---@param role ss.TRI_TYPE
---@param liftType ss.LIFT_TYPE
---@return integer[]
function support.BuildRoleLiftColor(role, liftType)
    return { 0, 0, support.EncodeRoleByte(role), support.EncodeLiftByte(liftType) }
end

---@param color number[]|Color
---@return integer[]
local function normalizeColorBytes(color)
    return {
        math.floor(math.Clamp(color[1] or color.r or 0, 0, 255) + 0.5),
        math.floor(math.Clamp(color[2] or color.g or 0, 0, 255) + 0.5),
        math.floor(math.Clamp(color[3] or color.b or 0, 0, 255) + 0.5),
        math.floor(math.Clamp(color[4] or color.a or 255, 0, 255) + 0.5),
    }
end

---@param color number[]|Color
---@return integer[][]
function support.BuildExpected(color)
    return rt.NewPixelMap(support.FIXTURE_RT, support.FIXTURE_RT, color)
end

---@param leftColor number[]|Color
---@param rightColor number[]|Color
---@param splitX integer?
---@return integer[][]
function support.BuildExpectedVerticalSplit(leftColor, rightColor, splitX)
    local pixels = support.BuildExpected(rightColor)
    local left = normalizeColorBytes(leftColor)
    local boundary = math.Clamp(math.floor(tonumber(splitX) or (support.FIXTURE_RT / 2)), 0, support.FIXTURE_RT)

    for y = 0, support.FIXTURE_RT - 1 do
        for x = 0, boundary - 1 do
            pixels[y * support.FIXTURE_RT + x + 1] = { left[1], left[2], left[3], left[4] }
        end
    end

    return pixels
end

---@param leftColor number[]|Color
---@param middleColor number[]|Color
---@param rightColor number[]|Color
---@param split1 integer?
---@param split2 integer?
---@return integer[][]
function support.BuildExpectedThreeWayVerticalSplit(leftColor, middleColor, rightColor, split1, split2)
    local pixels = support.BuildExpected(rightColor)
    local left = normalizeColorBytes(leftColor)
    local middle = normalizeColorBytes(middleColor)
    local boundary1 = math.Clamp(math.floor(tonumber(split1) or 0), 0, support.FIXTURE_RT)
    local boundary2 = math.Clamp(math.floor(tonumber(split2) or support.FIXTURE_RT), boundary1, support.FIXTURE_RT)

    for y = 0, support.FIXTURE_RT - 1 do
        for x = 0, boundary1 - 1 do
            pixels[y * support.FIXTURE_RT + x + 1] = { left[1], left[2], left[3], left[4] }
        end
        for x = boundary1, boundary2 - 1 do
            pixels[y * support.FIXTURE_RT + x + 1] = { middle[1], middle[2], middle[3], middle[4] }
        end
    end

    return pixels
end

---@param x number
---@param y number
---@param z number?
---@param a number?
---@return integer[][]
function support.BuildExpectedXY(x, y, z, a)
    return support.BuildExpectedUnit(x, y, z or 0, a)
end

---@param r number
---@param g number
---@param b number
---@param a number?
---@return integer[][]
function support.BuildExpectedUnit(r, g, b, a)
    return support.BuildExpected {
        unitToByte(r),
        unitToByte(g),
        unitToByte(b),
        unitToByte(a or 1),
    }
end

---@param r number
---@param g number
---@param b number
---@param a number?
---@return integer[][]
function support.BuildExpectedSigned(r, g, b, a)
    return support.BuildExpectedUnit(
        support.SignedToUnit(r),
        support.SignedToUnit(g),
        support.SignedToUnit(b),
        a or 1
    )
end

---@param gray number
---@return integer[][]
function support.BuildExpectedGray(gray)
    return support.BuildExpectedUnit(gray, gray, gray, 1)
end

---@param value number
---@return integer[][]
function support.BuildExpectedSignedGray(value)
    local unit = support.SignedToUnit(value)
    return support.BuildExpectedGray(unit)
end

---@param actual integer[]
---@param expected integer[]
---@param tolerance integer
---@return boolean
local function isColorWithinTolerance(actual, expected, tolerance)
    return math.abs(actual[1] - expected[1]) <= tolerance
        and math.abs(actual[2] - expected[2]) <= tolerance
        and math.abs(actual[3] - expected[3]) <= tolerance
        and math.abs(actual[4] - expected[4]) <= tolerance
end

---@param pixels integer[][]
---@param tolerance integer?
---@return integer[][]
function support.TraceKindToHitMask(pixels, tolerance)
    local mask = support.BuildExpectedGray(0)
    local hitStart = support.COLORS.trace_hit_start
    local hitCrossing = support.COLORS.trace_hit_crossing
    local tol = math.max(0, math.floor(tonumber(tolerance) or 4))

    for i, pixel in ipairs(pixels) do
        local isHit = isColorWithinTolerance(pixel, hitStart, tol)
            or isColorWithinTolerance(pixel, hitCrossing, tol)
        mask[i] = isHit and { 255, 255, 255, 255 } or { 0, 0, 0, 255 }
    end

    return mask
end

---@param pixels integer[][]
---@param tolerance integer?
---@return integer[][]
function support.VisibilityMask(pixels, tolerance)
    local mask = support.BuildExpected { 0, 0, 0, 0 }
    local tol = math.max(0, math.floor(tonumber(tolerance) or 4))

    for i, pixel in ipairs(pixels) do
        local visible = (pixel[4] or 0) > tol
            or (pixel[1] or 0) > tol
            or (pixel[2] or 0) > tol
            or (pixel[3] or 0) > tol
        mask[i] = visible and { 255, 255, 255, 255 } or { 0, 0, 0, 0 }
    end

    return mask
end

---@param leftU number
---@param rightU number
---@param proxyV number?
---@return table[]
function support.BuildHorizontalProxyGradient(leftU, rightU, proxyV)
    local v = proxyV or support.PROXY_V
    return {
        { proxyU = leftU, proxyV = v },
        { proxyU = leftU, proxyV = v },
        { proxyU = rightU, proxyV = v },
        { proxyU = rightU, proxyV = v },
    }
end

---@param leftLift number
---@param rightLift number
---@return table[]
function support.BuildVerticalLiftGradient(leftLift, rightLift)
    return {
        { inkBinormalMeshLift = { 0, 0, 0, leftLift } },
        { inkBinormalMeshLift = { 0, 0, 0, leftLift } },
        { inkBinormalMeshLift = { 0, 0, 0, rightLift } },
        { inkBinormalMeshLift = { 0, 0, 0, rightLift } },
    }
end

---@param base table?
---@param positions Vector[]
---@param overrides table[]?
---@return table[]
local function buildRealVSQuad(base, positions, overrides)
    local vertices = {} ---@type table[]
    local baseVertex = table.Copy(base or {})
    local perVertex = overrides or {}

    for i = 1, #(positions or {}) do
        local vertex = table.Copy(baseVertex)
        if perVertex[i] then
            table.Merge(vertex, table.Copy(perVertex[i]))
        end
        vertex.pos = positions[i]
        vertices[i] = vertex
    end

    return vertices
end

---@param base table?
---@param positions Vector[]
---@param overrides table[]?
---@return table[]
function support.BuildRealVSVertices(base, positions, overrides)
    return buildRealVSQuad(base, positions, overrides)
end

---@param positions Vector[]
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@param bumpU number?
---@param bumpV number?
---@return table[]
function support.BuildRealVSBaseBumpUVFromXZ(positions, x0, x1, z0, z1, bumpU, bumpV)
    local spanX = tonumber(x1) - tonumber(x0)
    local spanZ = tonumber(z1) - tonumber(z0)
    local denomX = math.abs(spanX) > 1.0e-6 and spanX or 1
    local denomZ = math.abs(spanZ) > 1.0e-6 and spanZ or 1
    local overrides = {} ---@type table[]

    for i, pos in ipairs(positions or {}) do
        local u = (pos.x - x0) / denomX
        local v = (pos.z - z0) / denomZ
        overrides[i] = {
            baseBumpUV = { u, v, bumpU or 0.25, bumpV or 0.25 },
        }
    end

    return overrides
end

---@param positions Vector[]
---@param x0 number
---@param x1 number
---@param y0 number
---@param y1 number
---@param bumpU number?
---@param bumpV number?
---@return table[]
function support.BuildRealVSBaseBumpUVFromXY(positions, x0, x1, y0, y1, bumpU, bumpV)
    local spanX = tonumber(x1) - tonumber(x0)
    local spanY = tonumber(y1) - tonumber(y0)
    local denomX = math.abs(spanX) > 1.0e-6 and spanX or 1
    local denomY = math.abs(spanY) > 1.0e-6 and spanY or 1
    local overrides = {} ---@type table[]

    for i, pos in ipairs(positions or {}) do
        local u = (pos.x - x0) / denomX
        local v = (pos.y - y0) / denomY
        overrides[i] = {
            baseBumpUV = { v, u, bumpU or 0.25, bumpV or 0.25 },
        }
    end

    return overrides
end

---@param base table?
---@param x0 number
---@param x1 number
---@param z0 number
---@param z1 number
---@param y number?
---@param overrides table[]?
---@return table[]
function support.BuildRealVSQuadXZFacingNegativeY(base, x0, x1, z0, z1, y, overrides)
    return buildRealVSQuad(base, {
        Vector(x0, y or 0, z0),
        Vector(x1, y or 0, z0),
        Vector(x1, y or 0, z1),
        Vector(x0, y or 0, z1),
    }, overrides)
end

---@param base table?
---@param y0 number
---@param y1 number
---@param z0 number
---@param z1 number
---@param x number?
---@param overrides table[]?
---@return table[]
function support.BuildRealVSQuadYZFacingNegativeX(base, y0, y1, z0, z1, x, overrides)
    return buildRealVSQuad(base, {
        Vector(x or 0, y0, z0),
        Vector(x or 0, y0, z1),
        Vector(x or 0, y1, z1),
        Vector(x or 0, y1, z0),
    }, overrides)
end

---@param fill boolean?
---@return boolean[]
function support.NewBoolMask(fill)
    local mask = {} ---@type boolean[]
    local value = fill == true
    for i = 1, support.FIXTURE_RT * support.FIXTURE_RT do
        mask[i] = value
    end
    return mask
end

---@param mask boolean[]
---@param x integer
---@param y integer
---@param w integer
---@param h integer
function support.FillMaskRect(mask, x, y, w, h)
    local x0 = math.max(0, math.floor(tonumber(x) or 0))
    local y0 = math.max(0, math.floor(tonumber(y) or 0))
    local x1 = math.min(support.FIXTURE_RT, x0 + math.max(0, math.floor(tonumber(w) or 0)))
    local y1 = math.min(support.FIXTURE_RT, y0 + math.max(0, math.floor(tonumber(h) or 0)))

    for py = y0, y1 - 1 do
        for px = x0, x1 - 1 do
            mask[py * support.FIXTURE_RT + px + 1] = true
        end
    end
end

---@param rects table[]?
---@return boolean[]
function support.BuildMaskFromRects(rects)
    local mask = support.NewBoolMask(false)
    for _, rect in ipairs(rects or {}) do
        support.FillMaskRect(mask, rect.x, rect.y, rect.w, rect.h)
    end
    return mask
end

---@param mask boolean[]
---@param visibleColor number[]|Color?
---@param hiddenColor number[]|Color?
---@return integer[][]
function support.BuildExpectedFromMask(mask, visibleColor, hiddenColor)
    local pixels = support.BuildExpected(hiddenColor or { 0, 0, 0, 0 })
    local visible = normalizeColorBytes(visibleColor or { 255, 255, 255, 255 })

    for i, state in ipairs(mask or {}) do
        if state then
            pixels[i] = { visible[1], visible[2], visible[3], visible[4] }
        end
    end

    return pixels
end

---@param pixel integer[]
---@param tolerance integer
---@return boolean
local function pixelIsVisible(pixel, tolerance)
    local tol = math.max(0, math.floor(tonumber(tolerance) or 4))
    return (pixel[4] or 0) > tol
        or (pixel[1] or 0) > tol
        or (pixel[2] or 0) > tol
        or (pixel[3] or 0) > tol
end

---@param pixels integer[][]
---@return integer[][]
local function clonePixels(pixels)
    local copy = {} ---@type integer[][]
    for i, pixel in ipairs(pixels or {}) do
        copy[i] = { pixel[1], pixel[2], pixel[3], pixel[4] }
    end
    return copy
end

---@param t ss.RenderHarness.Context
---@param actualPixels integer[][]
---@param label string
---@param contract table
function support.AssertVisibilityContract(t, actualPixels, label, contract)
    local tolerance = math.max(0, math.floor(tonumber(contract.tolerance) or 4))
    local requiredVisible = contract.requiredVisible or support.NewBoolMask(false)
    local requiredHidden = contract.requiredHidden or support.NewBoolMask(false)
    local actualMask = support.VisibilityMask(actualPixels, tolerance)
    local expectedMask = clonePixels(actualMask)

    for i = 1, #expectedMask do
        if requiredVisible[i] then
            expectedMask[i] = { 255, 255, 255, 255 }
        elseif requiredHidden[i] then
            expectedMask[i] = { 0, 0, 0, 0 }
        end
    end

    t.assertPixelsEqual(support.FIXTURE_RT, support.FIXTURE_RT, actualMask, expectedMask, label, 0)
end

---@param t ss.RenderHarness.Context
---@param beforePixels integer[][]
---@param afterPixels integer[][]
---@param label string
---@param contract table
function support.AssertVisibilityGainContract(t, beforePixels, afterPixels, label, contract)
    local tolerance = math.max(0, math.floor(tonumber(contract.tolerance) or 4))
    local requiredGain = contract.requiredGain or support.NewBoolMask(false)
    local forbiddenGain = contract.forbiddenGain or support.NewBoolMask(false)
    local beforeMask = support.VisibilityMask(beforePixels, tolerance)
    local afterMask = support.VisibilityMask(afterPixels, tolerance)
    local actualGain = support.BuildExpected { 0, 0, 0, 0 }

    for i = 1, #actualGain do
        local beforeVisible = pixelIsVisible(beforeMask[i], 0)
        local afterVisible = pixelIsVisible(afterMask[i], 0)
        actualGain[i] = (not beforeVisible and afterVisible)
            and { 255, 255, 255, 255 }
            or { 0, 0, 0, 0 }
    end

    local expectedGain = clonePixels(actualGain)
    for i = 1, #expectedGain do
        if requiredGain[i] then
            expectedGain[i] = { 255, 255, 255, 255 }
        elseif forbiddenGain[i] then
            expectedGain[i] = { 0, 0, 0, 0 }
        end
    end

    t.assertPixelsEqual(support.FIXTURE_RT, support.FIXTURE_RT, actualGain, expectedGain, label, 0)
end

---@param distance number?
---@param projPosZ number?
---@return number[]
function support.BuildWorldPosProjPosZ(distance, projPosZ)
    local eye = EyePos()
    local d = tonumber(distance) or 32
    return { eye.x - d, eye.y, eye.z, projPosZ or support.PROJ_POS_Z }
end

---@param role ss.TRI_TYPE?
---@param projPosW number?
---@return number[]
function support.BuildProjPosWMeshRole(role, projPosW)
    local encodedRole = support.ROLE_BASE
    if role ~= nil then
        encodedRole = role / ss.TRI_MAX ---@type number
    end

    return { projPosW or support.PROJ_POS_W, encodedRole, 0, 0 }
end

---@param lift number?
---@param proxyU number?
---@param proxyV number?
---@param eyeHeight number?
---@return number[]
function support.BuildCoreEyeUV(lift, proxyU, proxyV, eyeHeight)
    return {
        proxyU or support.PROXY_U,
        proxyV or support.PROXY_V,
        (lift or 0) + (eyeHeight or 1),
        0,
    }
end

---@param t ss.RenderHarness.Context
---@param spec ss.InkmeshTestCaseSpec
function support.RunCase(t, spec)
    local actual = spec.capture(spec.opts)
    if spec.transformActual then
        actual = spec.transformActual(actual)
    end
    t.assertPixelsEqual(
        support.FIXTURE_RT,
        support.FIXTURE_RT,
        actual,
        spec.expected,
        spec.label,
        spec.tolerance or 4
    )
end

---@param cases ss.RenderHarness.Case[]
---@param spec ss.InkmeshSuiteCaseSpec
function support.AppendCoreCase(cases, spec)
    cases[#cases + 1] = {
        name = spec.name,
        run = function(t)
            ss.InkmeshTestSupport.RunCase(t, {
                name = spec.name,
                label = spec.label,
                expected = spec.expected,
                tolerance = spec.tolerance,
                transformActual = spec.transformActual,
                capture = function(opts)
                    return ss.InkmeshTestFixtures.CaptureCoreDebug(opts)
                end,
                opts = spec.opts,
            })
        end,
    }
end

---@param cases ss.RenderHarness.Case[]
---@param spec ss.InkmeshSuiteCaseSpec
function support.AppendDisplayCase(cases, spec)
    cases[#cases + 1] = {
        name = spec.name,
        run = function(t)
            ss.InkmeshTestSupport.RunCase(t, {
                name = spec.name,
                label = spec.label,
                expected = spec.expected,
                tolerance = spec.tolerance,
                transformActual = spec.transformActual,
                capture = function(opts)
                    return ss.InkmeshTestFixtures.CaptureDisplayDebug(opts)
                end,
                opts = spec.opts,
            })
        end,
    }
end

---@param cases ss.RenderHarness.Case[]
---@param spec ss.InkmeshSuiteCaseSpec
function support.AppendDisplayRealVSCase(cases, spec)
    cases[#cases + 1] = {
        name = spec.name,
        run = function(t)
            ss.InkmeshTestSupport.RunCase(t, {
                name = spec.name,
                label = spec.label,
                expected = spec.expected,
                tolerance = spec.tolerance,
                transformActual = spec.transformActual,
                capture = function(opts)
                    return ss.InkmeshTestFixtures.CaptureDisplayRealVS(opts)
                end,
                opts = spec.opts,
            })
        end,
    }
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
