---@class ss
local ss = SplashSWEPs
if not ss then return end

local REPORT_DIR = "splashsweps/render-tests"
local HOOK_NAME = "SplashSWEPs: Render harness"
local RT_FLAGS = 1 + 256 + 512 + 1024 + 32768 + 8388608
local RT_FORMAT = IMAGE_FORMAT_RGBA8888
local RT_SIZE_MODE = RT_SIZE_NO_CHANGE
local DEFAULT_RT_DEPTH = MATERIAL_RT_DEPTH_NONE
local DEFAULT_RT_KEY = "main"
local DEFAULT_RT_WIDTH = 8
local DEFAULT_RT_HEIGHT = 8
local DEFAULT_CLEAR = { 0, 0, 0, 0 }
local MAX_MISMATCH_SAMPLES = 32

local copyMaterial = Material "splashsweps/shaders/copy"
local paramEchoMaterial = Material "splashsweps/shaders/render_test_param_echo"
local unlitGenericMaterial = CreateMaterial(
    "splashsweps_render_test_unlitgeneric_fill",
    "UnlitGeneric",
    {
        ["$basetexture"] = "color/white",
        ["$vertexalpha"] = "1",
        ["$vertexcolor"] = "1",
    }
)
unlitGenericMaterial:Recompute()

---@class ss.RenderHarness
---@field State ss.RenderHarness.State
---@field EnsureRT fun(key: string, width: integer, height: integer, depth: integer?, flags: integer?, format: integer?): ITexture
---@field CaptureRT fun(width: integer, height: integer, draw: fun(rt: ITexture), key: string?, clear: number[]|Color?, depth: integer?, flags: integer?): integer[][]
---@field ComparePixelMaps fun(width: integer, height: integer, actual: integer[][], expected: integer[][], tolerance: integer?): ss.RenderHarness.Comparison
---@field NewPixelMap fun(width: integer, height: integer, fill: number[]|Color?): integer[][]
---@field ClearTestPrefix fun(prefix: string)
---@field RegisterCase fun(name: string, fn: fun(t: ss.RenderHarness.Context))
---@field RegisterCases fun(cases: ss.RenderHarness.Case[]): string[]
---@field RegisterSuite fun(id: string, cases: ss.RenderHarness.Case[]): string[]
---@field ScheduleTests fun(requested: string[])

---@class ss.RenderHarness.Case
---@field name string
---@field run fun(t: ss.RenderHarness.Context)

---@class ss.RenderHarness.Definition
---@field name string
---@field run fun(t: ss.RenderHarness.Context)

---@class ss.RenderHarness.CaptureOptions
---@field width integer?
---@field height integer?
---@field draw fun(rt: ITexture)
---@field key string?
---@field clear number[]|Color?
---@field depth integer?
---@field flags integer?

---@class ss.RenderHarness.Context
---@field newExpected fun(width: integer?, height: integer?, fill: number[]|Color?): integer[][]
---@field setPixel fun(pixels: integer[][], width: integer, x: integer, y: integer, color: number[]|Color)
---@field fillRect fun(pixels: integer[][], width: integer, height: integer, x: integer, y: integer, w: integer, h: integer, color: number[]|Color)
---@field capture fun(opts: ss.RenderHarness.CaptureOptions): integer[][]
---@field assertPixelsEqual fun(width: integer, height: integer, actual: integer[][], expected: integer[][], label: string?, tolerance: integer?)
---@field note fun(text: string)
---@field drawCopy fun(source: ITexture, channel: integer?, width: integer?, height: integer?)

---@class ss.RenderHarness.Mismatch
---@field x integer
---@field y integer
---@field expected integer[]
---@field actual integer[]
---@field delta integer[]

---@class ss.RenderHarness.Comparison
---@field ok boolean
---@field mismatchCount integer
---@field mismatches ss.RenderHarness.Mismatch[]
---@field summary string

---@class ss.RenderHarness.Assertion
---@field label string
---@field ok boolean
---@field width integer
---@field height integer
---@field tolerance integer
---@field mismatchCount integer
---@field mismatches ss.RenderHarness.Mismatch[]
---@field summary string
---@field expected integer[][]?
---@field actual integer[][]?

---@class ss.RenderHarness.TestReport
---@field name string
---@field assertions ss.RenderHarness.Assertion[]
---@field notes string[]
---@field status "passed"|"failed"
---@field duration_ms number?
---@field error string?

---@class ss.RenderHarness.Report
---@field generatedAt string
---@field captureYFlip boolean?
---@field tests ss.RenderHarness.TestReport[]
---@field total integer
---@field passed integer
---@field failed integer

---@class ss.RenderHarness.State
---@field tests table<string, ss.RenderHarness.Definition>
---@field rtCache table<string, ITexture>
---@field pending string[]?
---@field captureYFlip boolean?
---@field lastReportPath string?
---@field suites table<string, string[]>
---@field suiteOrder string[]

---@type ss.RenderHarness
ss.RenderHarness = ss.RenderHarness or {}
---@type ss.RenderHarness.State
local state = ss.RenderHarness.State or {
    tests = {},
    rtCache = {},
    pending = nil,
    captureYFlip = nil,
    lastReportPath = nil,
    suites = {},
    suiteOrder = {},
}
state.tests = state.tests or {}
state.rtCache = state.rtCache or {}
state.suites = state.suites or {}
state.suiteOrder = state.suiteOrder or {}
ss.RenderHarness.State = state

local function clamp255(x)
    return math.Clamp(math.floor(tonumber(x) or 0), 0, 255)
end

---@param color number[]|Color
---@return integer[]
local function normalizeColor(color)
    return {
        clamp255(color[1] or color.r or 0),
        clamp255(color[2] or color.g or 0),
        clamp255(color[3] or color.b or 0),
        clamp255(color[4] or color.a or 255),
    }
end

---@param color integer[]
---@return string
local function formatColor(color)
    return string.format("rgba(%d,%d,%d,%d)", color[1], color[2], color[3], color[4])
end

---@param width integer
---@param x integer
---@param y integer
---@return integer
local function pixelIndex(width, x, y)
    return y * width + x + 1
end

---@param width integer
---@param height integer
---@param fill number[]|Color?
---@return integer[][]
local function newPixelMap(width, height, fill)
    local pixels = {} ---@type integer[][]
    local c = normalizeColor(fill or DEFAULT_CLEAR)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            pixels[pixelIndex(width, x, y)] = { c[1], c[2], c[3], c[4] }
        end
    end
    return pixels
end

---@param pixels integer[][]
---@param width integer
---@param height integer
---@return integer[][]
local function clonePixelMap(pixels, width, height)
    local copy = {} ---@type integer[][]
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local p = pixels[pixelIndex(width, x, y)]
            copy[pixelIndex(width, x, y)] = { p[1], p[2], p[3], p[4] }
        end
    end
    return copy
end

---@param pixels integer[][]
---@param width integer
---@param x integer
---@param y integer
---@param color number[]|Color
local function setPixel(pixels, width, x, y, color)
    pixels[pixelIndex(width, x, y)] = normalizeColor(color)
end

---@param pixels integer[][]
---@param width integer
---@param height integer
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param color number[]|Color
local function fillRect(pixels, width, height, x, y, w, h, color)
    local c = normalizeColor(color)
    for py = y, math.min(y + h - 1, height - 1) do
        for px = x, math.min(x + w - 1, width - 1) do
            if px >= 0 and py >= 0 then
                pixels[pixelIndex(width, px, py)] = { c[1], c[2], c[3], c[4] }
            end
        end
    end
end

---@param width integer
---@param height integer
---@param pixels integer[][]
---@return integer[][]
local function flipY(width, height, pixels)
    local flipped = {} ---@type integer[][]
    for y = 0, height - 1 do
        local targetY = height - y - 1
        for x = 0, width - 1 do
            local p = pixels[pixelIndex(width, x, y)]
            flipped[pixelIndex(width, x, targetY)] = { p[1], p[2], p[3], p[4] }
        end
    end
    return flipped
end

---@param key string
---@param width integer
---@param height integer
---@param depth integer?
---@param flags integer?
---@param format integer?
---@return ITexture
local function ensureRT(key, width, height, depth, flags, format)
    depth = depth or DEFAULT_RT_DEPTH
    flags = flags or RT_FLAGS
    format = format or RT_FORMAT
    local cacheKey = string.format("%s:%dx%d:%d:%d:%d", key, width, height, depth, flags, format)
    if state.rtCache[cacheKey] then return state.rtCache[cacheKey] end

    local rt = GetRenderTargetEx(
        string.format("splashsweps_render_test_%s_%dx%d", key, width, height),
        width,
        height,
        RT_SIZE_MODE,
        depth,
        flags,
        0,
        format
    )
    state.rtCache[cacheKey] = rt
    return rt
end

ss.RenderHarness.EnsureRT = ensureRT

---@param width integer
---@param height integer
---@return integer[][]
local function readPixelsRaw(width, height)
    local pixels = {} ---@type integer[][]
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local r, g, b, a = render.ReadPixel(x, y)
            pixels[pixelIndex(width, x, y)] = {
                clamp255(r),
                clamp255(g),
                clamp255(b),
                clamp255(a == nil and 255 or a),
            }
        end
    end
    return pixels
end

---@return boolean
local function detectCaptureYFlip()
    local width, height = 2, 2
    local rt = ensureRT("probe", width, height)
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 0)

    local ok, result = xpcall(function()
        cam.Start2D()
        surface.SetDrawColor(255, 0, 0, 255)
        surface.DrawRect(0, 0, 1, 1)
        surface.SetDrawColor(0, 255, 0, 255)
        surface.DrawRect(1, 0, 1, 1)
        surface.SetDrawColor(0, 0, 255, 255)
        surface.DrawRect(0, 1, 1, 1)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawRect(1, 1, 1, 1)
        render.CapturePixels()
        return readPixelsRaw(width, height)
    end, debug.traceback)

    cam.End2D()
    render.PopRenderTarget()
    if not ok then error(result, 0) end

    local lowerLeft = result[pixelIndex(width, 0, 0)]
    if lowerLeft[1] == 255 and lowerLeft[2] == 0 and lowerLeft[3] == 0 then
        return false
    end

    return lowerLeft[1] == 0 and lowerLeft[2] == 0 and lowerLeft[3] == 255
end

---@param rt ITexture
---@param draw fun(rt: ITexture)
---@param clear number[]|Color?
---@param clearDepth boolean?
---@return integer[][]
local function renderToTarget(rt, draw, clear, clearDepth)
    local c = normalizeColor(clear or DEFAULT_CLEAR)
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    if clearDepth then
        render.ClearDepth()
    end
    render.Clear(c[1], c[2], c[3], c[4])

    cam.Start2D()
    local ok, result = xpcall(function()
        draw(rt)
        render.CapturePixels()
        return readPixelsRaw(rt:Width(), rt:Height())
    end, debug.traceback)
    cam.End2D()

    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then error(result, 0) end
    return result
end

---@param width integer
---@param height integer
---@param draw fun(rt: ITexture)
---@param key string?
---@param clear number[]|Color?
---@param depth integer?
---@param flags integer?
---@return integer[][]
local function captureRT(width, height, draw, key, clear, depth, flags)
    if state.captureYFlip == nil then
        state.captureYFlip = detectCaptureYFlip()
    end

    local rt = ensureRT(key or DEFAULT_RT_KEY, width, height, depth, flags)
    local result = renderToTarget(rt, draw, clear, depth ~= MATERIAL_RT_DEPTH_NONE)

    return state.captureYFlip and flipY(width, height, result) or result
end

ss.RenderHarness.CaptureRT = captureRT

---@param width integer
---@param height integer
---@param actual integer[][]
---@param expected integer[][]
---@param tolerance integer?
---@return ss.RenderHarness.Comparison
local function comparePixelMaps(width, height, actual, expected, tolerance)
    tolerance = math.max(0, math.floor(tonumber(tolerance) or 0))
    local mismatches = {} ---@type ss.RenderHarness.Mismatch[]
    local mismatchCount = 0
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local a = actual[pixelIndex(width, x, y)]
            local e = expected[pixelIndex(width, x, y)]
            local dr = math.abs(a[1] - e[1])
            local dg = math.abs(a[2] - e[2])
            local db = math.abs(a[3] - e[3])
            local da = math.abs(a[4] - e[4])
            if dr > tolerance or dg > tolerance or db > tolerance or da > tolerance then
                mismatchCount = mismatchCount + 1
                if #mismatches < MAX_MISMATCH_SAMPLES then
                    mismatches[#mismatches + 1] = { ---@class ss.RenderHarness.Mismatch
                        x = x,
                        y = y,
                        expected = { e[1], e[2], e[3], e[4] },
                        actual = { a[1], a[2], a[3], a[4] },
                        delta = { dr, dg, db, da },
                    }
                end
            end
        end
    end

    local summary = "pixel maps match"
    if mismatchCount > 0 then
        local first = mismatches[1]
        summary = string.format(
            "%d/%d pixels mismatched; first at (%d,%d): expected %s actual %s",
            mismatchCount,
            width * height,
            first.x,
            first.y,
            formatColor(first.expected),
            formatColor(first.actual)
        )
    end

    ---@class ss.RenderHarness.Comparison
    local cmp = {
        ok = mismatchCount == 0,
        mismatchCount = mismatchCount,
        mismatches = mismatches,
        summary = summary,
    }
    return cmp
end

ss.RenderHarness.ComparePixelMaps = comparePixelMaps
ss.RenderHarness.NewPixelMap = newPixelMap

---@param prefix string
function ss.RenderHarness.ClearTestPrefix(prefix)
    ss.assert(isstring(prefix) and prefix ~= "", "Render harness prefix must be a non-empty string")
    local names = {} ---@type string[]
    for name in pairs(state.tests) do
        if name:sub(1, #prefix) == prefix then
            names[#names + 1] = name
        end
    end
    for _, name in ipairs(names) do
        state.tests[name] = nil
    end

    local pending = {} ---@type string[]
    for _, name in ipairs(state.pending or {}) do
        if name:sub(1, #prefix) ~= prefix then
            pending[#pending + 1] = name
        end
    end
    state.pending = pending
end

local function drawFullscreenQuad(material, width, height, tint)
    local c = normalizeColor(tint or { 255, 255, 255, 255 })
    render.SetMaterial(material)
    mesh.Begin(MATERIAL_QUADS, 1)
    mesh.Position(0, 0, 0)
    mesh.TexCoord(0, 0, 0)
    mesh.TexCoord(1, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
    mesh.AdvanceVertex()
    mesh.Position(0, height, 0)
    mesh.TexCoord(0, 0, 1)
    mesh.TexCoord(1, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
    mesh.AdvanceVertex()
    mesh.Position(width, height, 0)
    mesh.TexCoord(0, 1, 1)
    mesh.TexCoord(1, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
    mesh.AdvanceVertex()
    mesh.Position(width, 0, 0)
    mesh.TexCoord(0, 1, 0)
    mesh.TexCoord(1, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
    mesh.AdvanceVertex()
    mesh.End()
end

---@param name string
---@param fn fun(t: ss.RenderHarness.Context)
function ss.RenderHarness.RegisterCase(name, fn)
    ss.assert(isstring(name) and name ~= "", "Render harness case name must be a non-empty string")
    ss.assert(isfunction(fn), "Render harness case body must be a function")
    state.tests[name] = { name = name, run = fn }
end

---@param cases ss.RenderHarness.Case[]
---@return string[]
function ss.RenderHarness.RegisterCases(cases)
    ss.assert(istable(cases), "Render harness cases must be a table")
    local names = {} ---@type string[]
    for _, case in ipairs(cases) do
        ss.assert(istable(case), "Render harness case must be a table")
        ss.assert(isstring(case.name) and case.name ~= "", "Render harness case name must be a non-empty string")
        ss.assert(isfunction(case.run), "Render harness case body must be a function")
        ss.RenderHarness.RegisterCase(case.name, case.run)
        names[#names + 1] = case.name
    end
    return names
end

---@param dest string[]
---@param seen table<string, boolean>
---@param name string
local function appendUniqueName(dest, seen, name)
    if seen[name] then return end
    seen[name] = true
    dest[#dest + 1] = name
end

---@param requested string[]
---@return string[]
local function mergePendingTests(requested)
    local merged = {}
    local seen = {}
    for _, name in ipairs(state.pending or {}) do
        appendUniqueName(merged, seen, name)
    end
    for _, name in ipairs(requested) do
        appendUniqueName(merged, seen, name)
    end
    return merged
end

---@param names string[]?
local function removeNamedTests(names)
    if not names then return end
    local removed = {} ---@type true[]
    for _, name in ipairs(names) do
        state.tests[name] = nil
        removed[name] = true
    end

    local pending = {} ---@type string[]
    for _, name in ipairs(state.pending or {}) do
        if not removed[name] then
            pending[#pending + 1] = name
        end
    end
    state.pending = pending
end

---@return string[]
local function collectSuiteNames()
    local merged = {}
    local seen = {}
    for _, id in ipairs(state.suiteOrder) do
        for _, name in ipairs(state.suites[id] or {}) do
            appendUniqueName(merged, seen, name)
        end
    end
    return merged
end

---@param requested string[]
function ss.RenderHarness.ScheduleTests(requested)
    state.pending = mergePendingTests(requested)
end

---@param id string
---@param cases ss.RenderHarness.Case[]
---@return string[]
function ss.RenderHarness.RegisterSuite(id, cases)
    ss.assert(isstring(id) and id ~= "", "Render harness suite id must be a non-empty string")
    if not state.suites[id] then
        state.suiteOrder[#state.suiteOrder + 1] = id
    end

    removeNamedTests(state.suites[id])
    local names = ss.RenderHarness.RegisterCases(cases)
    state.suites[id] = names
    ss.RenderHarness.ScheduleTests(collectSuiteNames())
    return names
end

---@param report ss.RenderHarness.Report
---@return string
local function writeReport(report)
    file.CreateDir("splashsweps")
    file.CreateDir(REPORT_DIR)
    local path = string.format("%s/report.json", REPORT_DIR)
    file.Write(path, util.TableToJSON(report, true) or "{}")
    state.lastReportPath = path
    return path
end

---@param testReport ss.RenderHarness.TestReport
---@return ss.RenderHarness.Context
local function makeContext(testReport)
    local ctx = {} ---@class ss.RenderHarness.Context

    ---@param width integer?
    ---@param height integer?
    ---@param fill number[]|Color?
    ---@return integer[][]
    function ctx.newExpected(width, height, fill)
        return newPixelMap(width or DEFAULT_RT_WIDTH, height or DEFAULT_RT_HEIGHT, fill)
    end

    ctx.setPixel = setPixel
    ctx.fillRect = fillRect

    ---@param opts ss.RenderHarness.CaptureOptions
    ---@return integer[][]
    function ctx.capture(opts)
        local width = opts.width or DEFAULT_RT_WIDTH
        local height = opts.height or DEFAULT_RT_HEIGHT
        return captureRT(
            width,
            height,
            opts.draw,
            opts.key,
            opts.clear,
            opts.depth,
            opts.flags
        )
    end

    ---@param width integer
    ---@param height integer
    ---@param actual integer[][]
    ---@param expected integer[][]
    ---@param label string?
    ---@param tolerance integer?
    function ctx.assertPixelsEqual(width, height, actual, expected, label, tolerance)
        local comparison = comparePixelMaps(width, height, actual, expected, tolerance)
        local assertion = { ---@class ss.RenderHarness.Assertion
            label = label or "pixel comparison",
            ok = comparison.ok,
            width = width,
            height = height,
            tolerance = tolerance or 0,
            mismatchCount = comparison.mismatchCount,
            mismatches = comparison.mismatches,
            summary = comparison.summary,
        }
        if not comparison.ok then
            assertion.expected = clonePixelMap(expected, width, height)
            assertion.actual = clonePixelMap(actual, width, height)
        end
        testReport.assertions[#testReport.assertions + 1] = assertion
        if not comparison.ok then
            error(string.format("%s: %s", assertion.label, assertion.summary), 0)
        end
    end

    ---@param text string
    function ctx.note(text)
        testReport.notes[#testReport.notes + 1] = text
    end

    function ctx.drawCopy(source, channel, width, height)
        copyMaterial:SetTexture("$basetexture", source)
        copyMaterial:SetInt("$c0_x", channel or 3)
        copyMaterial:SetInt("$c0_y", 0)
        drawFullscreenQuad(
            copyMaterial,
            width or source:Width(),
            height or source:Height()
        )
    end

    return ctx
end

local function runPending()
    local names = state.pending
    if not names then return end
    state.pending = nil

    ---@type ss.RenderHarness.Report
    local report = {
        generatedAt = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ")),
        captureYFlip = state.captureYFlip,
        tests = {}, ---@type ss.RenderHarness.TestReport[]
        total = #names,
        passed = 0,
        failed = 0,
    }

    MsgN(string.format("[SplashSWEPs] Running %d render harness case(s)...", #names))
    for _, name in ipairs(names) do
        local def = state.tests[name]
        local started = SysTime()
        local testReport = { ---@class ss.RenderHarness.TestReport
            name = name,
            assertions = {}, ---@type ss.RenderHarness.Assertion[]
            notes = {}, ---@type string[]
            status = "passed",
        }

        local ok, err = xpcall(function()
            def.run(makeContext(testReport))
        end, debug.traceback)

        testReport.duration_ms = math.Round((SysTime() - started) * 1000, 3)
        if ok then
            report.passed = report.passed + 1
            MsgN(string.format("[SplashSWEPs] PASS %s (%.3f ms)", name, testReport.duration_ms))
        else
            testReport.status = "failed"
            testReport.error = tostring(err)
            report.failed = report.failed + 1
            MsgN(string.format("[SplashSWEPs] FAIL %s (%.3f ms)", name, testReport.duration_ms))
            MsgN("[SplashSWEPs]   " .. testReport.error)
            for _, assertion in ipairs(testReport.assertions) do
                if not assertion.ok then
                    MsgN(string.format("[SplashSWEPs]   %s", assertion.summary))
                    for _, mismatch in ipairs(assertion.mismatches or {}) do
                        MsgN(string.format(
                            "[SplashSWEPs]     (%d,%d) expected %s actual %s",
                            mismatch.x,
                            mismatch.y,
                            formatColor(mismatch.expected),
                            formatColor(mismatch.actual)
                        ))
                    end
                    break
                end
            end
        end

        report.tests[#report.tests + 1] = testReport
    end

    report.captureYFlip = state.captureYFlip
    local path = writeReport(report)
    MsgN(string.format(
        "[SplashSWEPs] Render harness complete: %d passed, %d failed. Report: data/%s",
        report.passed,
        report.failed,
        path
    ))
end

hook.Add("HUDPaint", HOOK_NAME, runPending)

---@type ss.RenderHarness.Case[]
local baseCases = {
    {
        name = "sanity.unlitgeneric_color_fill",
        run = function(t)
            local width, height = 4, 4
            local color = { 255, 255, 255, 255 }
            local expected = t.newExpected(width, height, color)

            local actual = t.capture {
                key = "sanity_unlitgeneric_color_fill",
                width = width,
                height = height,
                clear = { 0, 0, 0, 0 },
                draw = function()
                    surface.SetMaterial(unlitGenericMaterial)
                    surface.SetDrawColor(color[1], color[2], color[3], color[4])
                    surface.DrawTexturedRect(0, 0, width, height)
                end,
            }

            t.assertPixelsEqual(width, height, actual, expected, "UnlitGeneric color fill")
        end,
    },
    {
        name = "sanity.rgba_roundtrip",
        run = function(t)
            local width, height = 4, 4
            local expected = t.newExpected(width, height, { 0, 0, 0, 0 })
            t.fillRect(expected, width, height, 0, 0, 2, 2, { 255, 0, 0, 255 })
            t.fillRect(expected, width, height, 2, 0, 2, 2, { 0, 255, 0, 128 })
            t.fillRect(expected, width, height, 0, 2, 2, 2, { 0, 0, 255, 64 })
            t.fillRect(expected, width, height, 2, 2, 2, 2, { 255, 255, 0, 32 })

            local actual = t.capture {
                key = "sanity_rgba_roundtrip",
                width = width,
                height = height,
                clear = { 0, 0, 0, 0 },
                draw = function()
                    render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                    surface.SetDrawColor(255, 0, 0, 255)
                    surface.DrawRect(0, 0, 2, 2)
                    surface.SetDrawColor(0, 255, 0, 128)
                    surface.DrawRect(2, 0, 2, 2)
                    surface.SetDrawColor(0, 0, 255, 64)
                    surface.DrawRect(0, 2, 2, 2)
                    surface.SetDrawColor(255, 255, 0, 32)
                    surface.DrawRect(2, 2, 2, 2)
                    render.OverrideBlend(false)
                end,
            }

            t.assertPixelsEqual(width, height, actual, expected, "RGBA roundtrip")
        end,
    },
    {
        name = "shader.copy_blue_to_alpha",
        run = function(t)
            local width, height = 4, 4
            local sourceRT = ensureRT("copy_source", width, height)

            captureRT(width, height, function()
                surface.SetDrawColor(10, 20, 30, 40)
                surface.DrawRect(0, 0, 2, 2)
                surface.SetDrawColor(60, 70, 80, 90)
                surface.DrawRect(2, 0, 2, 2)
                surface.SetDrawColor(110, 120, 130, 140)
                surface.DrawRect(0, 2, 2, 2)
                surface.SetDrawColor(160, 170, 180, 190)
                surface.DrawRect(2, 2, 2, 2)
            end, "copy_source", { 0, 0, 0, 0 })

            local passthrough = t.capture {
                key = "copy_passthrough",
                width = width,
                height = height,
                clear = { 0, 0, 0, 0 },
                draw = function()
                    t.drawCopy(sourceRT, 3, width, height)
                end,
            }

            local expected = t.newExpected(width, height, { 0, 0, 0, 0 })
            for y = 0, height - 1 do
                for x = 0, width - 1 do
                    local src = passthrough[pixelIndex(width, x, y)]
                    t.setPixel(expected, width, x, y, { src[1], src[2], src[3], src[3] })
                end
            end

            local actual = t.capture {
                key = "copy_dest",
                width = width,
                height = height,
                clear = { 0, 0, 0, 0 },
                draw = function()
                    t.drawCopy(sourceRT, 2, width, height)
                end,
            }

            t.assertPixelsEqual(width, height, actual, expected, "Copy shader blue->alpha")
        end,
    },
    {
        name = "shader.param_echo_c0_rgba",
        run = function(t)
            local width, height = 4, 4
            local expected = t.newExpected(width, height, { 0, 255, 0, 255 })

            paramEchoMaterial:SetFloat("$c0_x", 0)
            paramEchoMaterial:SetFloat("$c0_y", 1)
            paramEchoMaterial:SetFloat("$c0_z", 0)
            paramEchoMaterial:SetFloat("$c0_w", 1)
            paramEchoMaterial:Recompute()

            local actual = t.capture {
                key = "shader_param_echo_c0_rgba",
                width = width,
                height = height,
                clear = { 0, 0, 0, 0 },
                draw = function()
                    surface.SetMaterial(paramEchoMaterial)
                    surface.SetDrawColor(255, 255, 255, 255)
                    render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                    surface.DrawTexturedRect(0, 0, width, height)
                    render.OverrideBlend(false)
                end,
            }

            t.assertPixelsEqual(width, height, actual, expected, "Screenspace_General c0 echo")
        end,
    },
}

ss.RenderHarness.RegisterSuite("base", baseCases)
