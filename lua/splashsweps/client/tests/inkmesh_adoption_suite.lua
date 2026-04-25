---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshAdoptionSuite
---@field BuildCases fun(): ss.RenderHarness.Case[]
ss.InkmeshAdoptionSuite = ss.InkmeshAdoptionSuite or {}
local suite = ss.InkmeshAdoptionSuite

local support = ss.InkmeshTestSupport
if not support then return end

---@return ss.RenderHarness.Case[]
function suite.BuildCases()
    local cases = {} ---@type ss.RenderHarness.Case[]
    local color = support.COLORS
    local visibleExpected = support.BuildExpected { 255, 255, 255, 255 }
    local hiddenExpected = support.BuildExpected { 0, 0, 0, 0 }
    local visibleSplitExpected = support.BuildExpectedVerticalSplit({ 255, 255, 255, 255 }, { 0, 0, 0, 0 }, 6)

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.reason.visible_hit",
        label = "inkmesh adoption reason visible hit",
        expected = support.BuildExpected(color.display_visible),
        opts = {
            name = "inkmesh_adoption_reason_visible_hit",
            debugMode = 12,
            role = ss.TRI_BASE,
            heightAlpha = 255,
            depthAlpha = 255,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.reason.box_miss",
        label = "inkmesh adoption reason box miss",
        expected = support.BuildExpected(color.trace_box_miss),
        opts = {
            name = "inkmesh_adoption_reason_box_miss",
            debugMode = 12,
            role = ss.TRI_BASE,
            heightAlpha = 128,
            depthAlpha = 255,
            clipRange = { 0.0, 0.0, 0.1, 0.1 },
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.reason.no_hit",
        label = "inkmesh adoption reason no hit",
        expected = support.BuildExpected(color.trace_no_hit),
        opts = {
            name = "inkmesh_adoption_reason_no_hit",
            debugMode = 12,
            role = ss.TRI_BASE,
            heightAlpha = 0,
            depthAlpha = 255,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(1, 1),
            worldNormalTangentY = { 0, 0, 0, 0 },
            inkTangentXYZWorldZ = { 0, 0, 0, 0 },
            inkBinormalMeshLift = { 0.5, 0, 0, 0.25 },
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.reason.empty_ink",
        label = "inkmesh adoption reason empty ink",
        expected = support.BuildExpected(color.display_empty_ink),
        opts = {
            name = "inkmesh_adoption_reason_empty_ink",
            debugMode = 12,
            role = ss.TRI_BASE,
            heightAlpha = 255,
            depthAlpha = 255,
            indexColor = { 0, 0, 0, 255 },
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.reason.negative_thickness",
        label = "inkmesh adoption reason negative thickness",
        expected = support.BuildExpected(color.display_negative_thickness),
        opts = {
            name = "inkmesh_adoption_reason_negative_thickness",
            debugMode = 12,
            role = ss.TRI_BASE,
            heightAlpha = 64,
            depthAlpha = 0,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.visibility.base_full_hit",
        label = "inkmesh adoption visibility base full hit",
        expected = visibleExpected,
        transformActual = support.VisibilityMask,
        opts = {
            name = "inkmesh_adoption_visibility_base_full_hit",
            debugMode = 0,
            role = ss.TRI_BASE,
            heightAlpha = 255,
            depthAlpha = 255,
            wallAlbedoFill = { 255, 255, 255, 255 },
            wallBumpFill = { 128, 128, 255, 255 },
            lightmapFill = { 255, 255, 255, 255 },
            c1_x = 0,
            c1_y = 0,
            c1_w = 0,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.visibility.base_box_miss_hidden",
        label = "inkmesh adoption visibility base box miss hidden",
        expected = hiddenExpected,
        transformActual = support.VisibilityMask,
        opts = {
            name = "inkmesh_adoption_visibility_base_box_miss_hidden",
            debugMode = 0,
            role = ss.TRI_BASE,
            heightAlpha = 128,
            depthAlpha = 255,
            clipRange = { 0.0, 0.0, 0.1, 0.1 },
            wallAlbedoFill = { 255, 255, 255, 255 },
            wallBumpFill = { 128, 128, 255, 255 },
            lightmapFill = { 255, 255, 255, 255 },
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.visibility.base_no_hit_hidden",
        label = "inkmesh adoption visibility base no hit hidden",
        expected = hiddenExpected,
        transformActual = support.VisibilityMask,
        opts = {
            name = "inkmesh_adoption_visibility_base_no_hit_hidden",
            debugMode = 0,
            role = ss.TRI_BASE,
            heightAlpha = 0,
            depthAlpha = 255,
            wallAlbedoFill = { 255, 255, 255, 255 },
            wallBumpFill = { 128, 128, 255, 255 },
            lightmapFill = { 255, 255, 255, 255 },
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(1, 1),
            worldNormalTangentY = { 0, 0, 0, 0 },
            inkTangentXYZWorldZ = { 0, 0, 0, 0 },
            inkBinormalMeshLift = { 0.5, 0, 0, 0.25 },
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.visibility.base_empty_ink_hidden",
        label = "inkmesh adoption visibility base empty ink hidden",
        expected = hiddenExpected,
        transformActual = support.VisibilityMask,
        opts = {
            name = "inkmesh_adoption_visibility_base_empty_ink_hidden",
            debugMode = 0,
            role = ss.TRI_BASE,
            heightAlpha = 255,
            depthAlpha = 255,
            indexColor = { 0, 0, 0, 255 },
            wallAlbedoFill = { 255, 255, 255, 255 },
            wallBumpFill = { 128, 128, 255, 255 },
            lightmapFill = { 255, 255, 255, 255 },
            c1_x = 0,
            c1_y = 0,
            c1_w = 0,
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            eyeNormalDistance = 32,
        },
    })

    support.AppendDisplayCase(cases, {
        name = "inkmesh.adoption.visibility.base_partial_hit_no_leak",
        label = "inkmesh adoption visibility base partial hit no leak",
        expected = visibleSplitExpected,
        transformActual = support.VisibilityMask,
        opts = {
            name = "inkmesh_adoption_visibility_base_partial_hit_no_leak",
            debugMode = 0,
            role = ss.TRI_BASE,
            heightAlpha = 191,
            depthAlpha = 255,
            wallAlbedoFill = { 255, 255, 255, 255 },
            wallBumpFill = { 128, 128, 255, 255 },
            lightmapFill = { 255, 255, 255, 255 },
            vertices = support.BuildHorizontalProxyGradient(0.125, 0.375),
            worldPosProjPosZ = support.BuildWorldPosProjPosZ(32, 1),
            inkTangentXYZWorldZ = { 1 / 128, 0, 0, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            projPosWMeshRole = { 1, ss.TRI_BASE / ss.TRI_MAX, 0, 0 },
        },
    })

    return cases
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
