---@class ss
local ss = SplashSWEPs
if not ss then return end

---@class ss.InkmeshTestCoreSuite
---@field BuildCases fun(): ss.RenderHarness.Case[]
ss.InkmeshTestCoreSuite = ss.InkmeshTestCoreSuite or {}
local suite = ss.InkmeshTestCoreSuite

local support = ss.InkmeshTestSupport
if not support then return end

---@return ss.RenderHarness.Case[]
function suite.BuildCases()
    local cases = {} ---@type ss.RenderHarness.Case[]
    local color = support.COLORS

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.hit_start",
        label = "inkmesh core trace kind hit-start",
        expected = support.BuildExpected(color.trace_hit_start),
        opts = {
            name = "inkmesh_core_tracekind_hit_start",
            debugMode = 1,
            heightAlpha = 255,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(0),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.hit_start_epsilon_window",
        label = "inkmesh core trace kind hit-start epsilon window",
        expected = support.BuildExpected(color.trace_hit_start),
        opts = {
            name = "inkmesh_core_tracekind_hit_start_epsilon_window",
            debugMode = 1,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, support.PROXY_V, support.MidHeightSigned + 0.00005, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.hit_crossing",
        label = "inkmesh core trace kind hit-crossing",
        expected = support.BuildExpected(color.trace_hit_crossing),
        opts = {
            name = "inkmesh_core_tracekind_hit_crossing",
            debugMode = 1,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.hit_crossing_threshold_outside",
        label = "inkmesh core trace kind hit-crossing threshold outside",
        expected = support.BuildExpected(color.trace_hit_crossing),
        opts = {
            name = "inkmesh_core_tracekind_hit_crossing_threshold_outside",
            debugMode = 1,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, support.PROXY_V, support.MidHeightSigned + 0.0002, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.box_miss_u",
        label = "inkmesh core trace kind box-miss u",
        expected = support.BuildExpected(color.trace_box_miss),
        opts = {
            name = "inkmesh_core_tracekind_box_miss_u",
            debugMode = 1,
            heightAlpha = 128,
            clipRange = { 0.0, 0.0, 0.1, 0.1 },
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.box_miss_v",
        label = "inkmesh core trace kind box-miss v",
        expected = support.BuildExpected(color.trace_box_miss),
        opts = {
            name = "inkmesh_core_tracekind_box_miss_v",
            debugMode = 1,
            heightAlpha = 128,
            clipRange = { 0.0, 0.0, 0.5, 0.1 },
            proxyV = 0.75,
            worldPosProjPosZ = { support.PROXY_U, 0.75, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.no_hit_visible",
        label = "inkmesh core trace kind no-hit",
        expected = support.BuildExpected(color.trace_no_hit),
        opts = {
            name = "inkmesh_core_tracekind_no_hit",
            debugMode = 1,
            heightAlpha = 0,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, 0.75, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0.25 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.tracekind.no_hit_below_surface",
        label = "inkmesh core trace kind no-hit below surface",
        expected = support.BuildExpected(color.trace_no_hit),
        opts = {
            name = "inkmesh_core_tracekind_no_hit_below_surface",
            debugMode = 1,
            heightAlpha = 255,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, 0.75, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0.25 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.build_trace_ray.eye_uv_identity",
        label = "inkmesh core build trace ray eye UV from world delta",
        expected = support.BuildExpectedUnit(0.5, 0.25, 0.5),
        opts = {
            name = "inkmesh_core_build_trace_ray_eye_uv_identity",
            debugMode = 6,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { 0.25, 0.25, 0, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            worldNormalTangentY = { 0, 0, 0, 0 },
            inkTangentXYZWorldZ = { 1, 0, 0, 0 },
            c2_x = 1,
            c3_x = 0.5,
            c3_y = 0,
            c3_z = 0,
            c3_w = 1,
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.build_trace_ray.ray_dir_points_to_proxy",
        label = "inkmesh core build trace ray direction from eye UV",
        expected = support.BuildExpectedSigned(-0.25, 0, 0),
        opts = {
            name = "inkmesh_core_build_trace_ray_direction_to_proxy",
            debugMode = 6,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { 0.25, 0.25, 0, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            worldNormalTangentY = { 0, 0, 0, 0 },
            inkTangentXYZWorldZ = { 1, 0, 0, 0 },
            c2_y = 1,
            c3_x = 0.5,
            c3_y = 0,
            c3_z = 0,
            c3_w = 1,
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.evaluate_interface_field.positive_inside",
        label = "inkmesh core evaluate interface field positive inside",
        expected = support.BuildExpectedSignedGray(0.5),
        opts = {
            name = "inkmesh_core_evaluate_interface_field_positive_inside",
            debugMode = 6,
            heightAlpha = 255,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, support.PROXY_V, 0.5, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            c2_z = 1,
            c3_x = 1,
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.evaluate_interface_field.zero_on_surface",
        label = "inkmesh core evaluate interface field zero on surface",
        expected = support.BuildExpectedGray(0.5),
        opts = {
            name = "inkmesh_core_evaluate_interface_field_zero_on_surface",
            debugMode = 6,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, support.PROXY_V, support.MidHeightSigned, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            c2_z = 1,
            c3_x = 1,
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.evaluate_interface_field.negative_outside",
        label = "inkmesh core evaluate interface field negative outside",
        expected = support.BuildExpectedSignedGray(-0.5),
        opts = {
            name = "inkmesh_core_evaluate_interface_field_negative_outside",
            debugMode = 6,
            heightAlpha = 0,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, support.PROXY_V, -0.5, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0 },
            c2_z = 1,
            c3_x = 1,
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.hit_uv_encoding.center",
        label = "inkmesh core hit UV encoding center",
        expected = support.BuildExpectedUnit(0.25, 0.25, support.MidHeightUnit),
        opts = {
            name = "inkmesh_core_hit_uv_center",
            debugMode = 2,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            worldNormalTangentY = { 1, 0, 0, 0 },
            inkTangentXYZWorldZ = { 0, 1, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.hit_uv_encoding.near_max_u",
        label = "inkmesh core hit UV encoding near max u",
        expected = support.BuildExpectedUnit(0.4375, 0.25, support.MidHeightUnit),
        opts = {
            name = "inkmesh_core_hit_uv_near_max_u",
            debugMode = 2,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            proxyU = 0.4375,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75, 0.4375, 0.25),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.hit_uv_encoding.box_miss_clamped_max",
        label = "inkmesh core hit UV encoding box-miss clamp",
        expected = support.BuildExpectedUnit(0.5, 0.25, 0.625),
        opts = {
            name = "inkmesh_core_hit_uv_box_miss_clamped_max",
            debugMode = 2,
            heightAlpha = 0,
            clipRange = support.CLIP_FULL,
            proxyU = 0.75,
            worldPosProjPosZ = { 0.75, 0.25, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0.25 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.trace_fraction_and_steps",
        label = "inkmesh core trace fraction and steps",
        expected = support.BuildExpected(color.trace_hit_fraction),
        opts = {
            name = "inkmesh_core_trace_fraction_steps",
            debugMode = 3,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            worldNormalTangentY = { 1, 0, 0, 0 },
            inkTangentXYZWorldZ = { 0, 1, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.step_count.min_clamp",
        label = "inkmesh core step count min clamp",
        expected = support.BuildExpectedUnit(0.125, 0.125, 0.125),
        opts = {
            name = "inkmesh_core_step_count_min_clamp",
            debugMode = 6,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.step_count.max_clamp",
        label = "inkmesh core step count max clamp",
        expected = support.BuildExpectedUnit(1, 1, 1),
        opts = {
            name = "inkmesh_core_step_count_max_clamp",
            debugMode = 6,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            proxyU = 0.5,
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75, 0.0, 0.25),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.box_fraction.enter_half_exit_full",
        label = "inkmesh core box fraction enter half exit full",
        expected = support.BuildExpectedUnit(0.5, 1.0, 0.0),
        opts = {
            name = "inkmesh_core_box_fraction_enter_half_exit_full",
            debugMode = 5,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { -0.25, 0.25, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.box_fraction.enter_quarter_exit_three_quarters",
        label = "inkmesh core box fraction enter quarter exit three quarters",
        expected = support.BuildExpectedUnit(0.25, 0.75, 0.0),
        opts = {
            name = "inkmesh_core_box_fraction_enter_quarter_exit_three_quarters",
            debugMode = 5,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            proxyU = 0.75,
            worldPosProjPosZ = { -0.25, 0.25, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.height_depth_fetch.max",
        label = "inkmesh core height/depth fetch max",
        expected = support.BuildExpectedUnit(1, 1, 0),
        opts = {
            name = "inkmesh_core_height_depth_fetch_max",
            debugMode = 4,
            heightAlpha = 255,
            depthAlpha = 255,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(0),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.height_depth_fetch.zero",
        label = "inkmesh core height/depth fetch zero",
        expected = support.BuildExpectedUnit(0, 0, 0),
        opts = {
            name = "inkmesh_core_height_depth_fetch_zero",
            debugMode = 4,
            heightAlpha = 0,
            depthAlpha = 0,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = support.BuildCoreEyeUV(0),
            inkBinormalMeshLift = { 0, 0, 0, 0 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.trace_interface.status_matches_box_miss",
        label = "inkmesh core trace interface status box miss",
        expected = support.BuildExpected(color.trace_box_miss),
        opts = {
            name = "inkmesh_core_trace_interface_status_box_miss",
            debugMode = 7,
            c2_x = 1,
            heightAlpha = 128,
            clipRange = { 0.0, 0.0, 0.1, 0.1 },
            worldPosProjPosZ = support.BuildCoreEyeUV(-0.75),
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.trace_interface.status_matches_no_hit",
        label = "inkmesh core trace interface status no hit",
        expected = support.BuildExpected(color.trace_no_hit),
        opts = {
            name = "inkmesh_core_trace_interface_status_no_hit",
            debugMode = 7,
            c2_x = 1,
            heightAlpha = 0,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { support.PROXY_U, 0.75, 0.25, 0 },
            inkBinormalMeshLift = { 0, 0, 0, 0.25 },
        },
    })

    support.AppendCoreCase(cases, {
        name = "inkmesh.core.trace_interface.hit_uv_matches_core_path",
        label = "inkmesh core trace interface hit UV",
        expected = support.BuildExpectedUnit(0.25, 0.25, support.MidHeightUnit),
        opts = {
            name = "inkmesh_core_trace_interface_hit_uv",
            debugMode = 7,
            c2_y = 1,
            heightAlpha = 128,
            clipRange = support.CLIP_FULL,
            worldPosProjPosZ = { 0, 0, 0, 0 },
            inkBinormalMeshLift = { 0, 0, 0, -0.75 },
            worldNormalTangentY = { 0, 0, 32, 0 },
            inkTangentXYZWorldZ = { 0, 0, 0, 0 },
            c3_x = 0,
            c3_y = 0,
            c3_z = 1,
            c3_w = 1,
        },
    })

    return cases
end

if ss.RegisterInkmeshTestSuites then
    ss.RegisterInkmeshTestSuites()
end
