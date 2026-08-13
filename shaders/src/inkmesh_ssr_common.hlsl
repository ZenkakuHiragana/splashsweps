#include "inkmesh_oct.hlsl"

#define TO_SIGNED(x) ((x) * 2.0 - 1.0)
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-16)))

struct PS_INPUT {
    float4 screenPos : VPOS;
};

sampler ForwardColor      : register(s0);
sampler ForwardNormals    : register(s1);
sampler ReflectionParams  : register(s2);
sampler EnvmapParams      : register(s3);
sampler SceneColorDepth   : register(s4);
sampler SSRSource         : register(s5);

const float2 s0Size    : register(c4);
const float4 SSRPassParams : register(c0);
const float4 c11       : register(c11);
const float4 c12       : register(c12);
const float4 c13       : register(c13);
const float4 c14       : register(c14);
const float4 HDRParams : register(c30);

static const float  HEIGHT_TO_HU        = 24.0;
static const float  DepthWriteConstant  = 4000.0;
static const float2 g_FbSize            = s0Size;
static const float2 g_RenderSizeRcp     = SSRPassParams.xy;
static const float  g_TraceScale        = SSRPassParams.z;
static const float3 g_ViewRight         = c11.xyz;
static const float3 g_ViewUp            = c12.xyz;
static const float3 g_ViewForward       = c13.xyz;
static const float3 g_ViewOrigin        = c14.xyz;
static const float  g_TonemapScale      = HDRParams.x;

float ScreenEdgeFade(float2 uv) {
    float edge = min(min(uv.x, uv.y), 1.0 - max(uv.x, uv.y));
    return smoothstep(0.0, 0.0625, edge);
}

// Solves X = float4(x, y, z, det) such that v = x*a + y*b + z*c.
float4 DecomposeBasis(float3 a, float3 b, float3 c, float3 v) {
    float3 bCrossC = cross(b, c);
    float3 cCrossA = cross(c, a);
    float3 aCrossB = cross(a, b);
    float det      = dot(a, bCrossC);
    float invDet   = SAFERCP(det);
    return float4(
        dot(v, bCrossC) * invDet,
        dot(v, cCrossA) * invDet,
        dot(v, aCrossB) * invDet,
        det);
}

float3 ReconstructWorldPosition(float2 uv, float viewDepth) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return g_ViewOrigin
        + (g_ViewForward + g_ViewRight * ndc.x + g_ViewUp * ndc.y) * viewDepth;
}

float SampleSceneDepth(float2 uv) {
    return tex2Dlod(SceneColorDepth, float4(uv, 0.0, 0.0)).a * DepthWriteConstant;
}

float3 SampleInkAwareSSRColor(float2 uv, float3 fallback) {
    float4 ink = tex2Dlod(ForwardColor, float4(uv, 0.0, 0.0));
    return lerp(fallback, ink.rgb, step(0.5, ink.a));
}

float3 SampleRefinedInkAwareSSRColor(
    float2 uv, float3 fallback, bool fallbackNeedsSample)
{
    float4 ink = tex2Dlod(ForwardColor, float4(uv, 0.0, 0.0));
    [branch]
    if (ink.a >= 0.5) return ink.rgb;
    [branch]
    if (fallbackNeedsSample) {
        return tex2Dlod(SSRSource, float4(uv, 0.0, 0.0)).rgb;
    }
    return fallback;
}

float ComputeSSRThickness(float depth, float rayDepthSpan, float roughness) {
    static const float SSR_FOV_Y           = radians(75.0);
    static const float SSR_TAN_HALF_FOV    = tan(SSR_FOV_Y * 0.5);
    static const float SSR_THICKNESS_MIN   = 8.0;
    static const float SSR_THICKNESS_MAX   = 32.0;
    static const float SSR_RAY_SPAN_SCALE  = 0.25;
    static const float SSR_ROUGHNESS_SCALE = 4.0;
    float pixelSizeHU = 2.0 * depth * SSR_TAN_HALF_FOV * g_FbSize.y;
    float roughnessScale = lerp(1.0, SSR_ROUGHNESS_SCALE, roughness);
    return clamp(
        max(pixelSizeHU * roughnessScale, rayDepthSpan * SSR_RAY_SPAN_SCALE),
        SSR_THICKNESS_MIN, SSR_THICKNESS_MAX);
}

// -1: clear, 0: hit candidate, +1: occluded.
float ClassifySSRSegment(float rayMin, float rayMax, float sceneDepth, float thickness) {
    float clear = 1.0 - step(sceneDepth, rayMax);
    float behind = 1.0 - step(rayMin, sceneDepth + thickness);
    return behind - clear;
}

float4 SampleScreenSpaceReflection(
    float2 screenUV,
    float3 worldPos,
    float viewDepth,
    float3 viewDir,
    float3 geometryNormal,
    float3 worldSpaceNormal,
    float roughness,
    float height)
{
    static const int   SSR_MAX_STEPS         = 64;
    static const int   SSR_BINARY_STEPS      = 2;
    static const float SSR_STEP_PIXEL_RCP    = rcp(8.0);
    static const float SSR_INITIAL_BIAS_HU   = 2.0;
    static const float SSR_STITCH_GAP_MIN_HU = 16.0;
    float3 P = worldPos;
    float  W = max(viewDepth, 1.0e-3);
    float3 viewAway = -viewDir;
    float  viewDist = distance(g_ViewOrigin, P);
    float2 fbPixels = rcp(g_FbSize) * g_TraceScale;

    float3x3 screenSpaceAxesInWorld = {
        ddx(P) * fbPixels.x,
        ddy(P) * fbPixels.y,
        viewAway,
    };
    float3 clipWPerScreenSpaceAxis = {
        ddx(W) * fbPixels.x,
        ddy(W) * fbPixels.y,
        W / viewDist,
    };

    float4 screenSpaceOffset = DecomposeBasis(
        screenSpaceAxesInWorld[0],
        screenSpaceAxesInWorld[1],
        screenSpaceAxesInWorld[2],
        geometryNormal * (height * HEIGHT_TO_HU + SSR_INITIAL_BIAS_HU));
    float4 screenSpaceRayDirection = DecomposeBasis(
        screenSpaceAxesInWorld[0],
        screenSpaceAxesInWorld[1],
        screenSpaceAxesInWorld[2],
        reflect(viewAway, worldSpaceNormal));

    float3 rayStartUVQ = {
        screenUV + screenSpaceOffset.xy,
        rcp(max(W + dot(screenSpaceOffset.xyz, clipWPerScreenSpaceAxis), 1.0e-6)),
    };
    float3 rayDirectionUVQ = {
        screenSpaceRayDirection.xy,
        -rayStartUVQ.z * rayStartUVQ.z
            * dot(screenSpaceRayDirection.xyz, clipWPerScreenSpaceAxis),
    };

    float2 axisInvalid   = step(abs(rayDirectionUVQ.xy), 1.0e-8);
    float  qLimitInvalid = step(-rayDirectionUVQ.z, 1.0e-8);
    float2 exitEdges     = step(0.0, rayDirectionUVQ.xy);
    float2 tEdges        = lerp(
        (exitEdges - rayStartUVQ.xy) * SAFERCP(rayDirectionUVQ.xy),
        1.0e20,
        axisInvalid);
    float tQ = lerp(
        (1.0e-6 - rayStartUVQ.z) * SAFERCP(rayDirectionUVQ.z),
        1.0e20,
        qLimitInvalid);
    float tExit = min(min(tEdges.x, tEdges.y), tQ);
    float3 rayEndUVQ = rayStartUVQ + rayDirectionUVQ * tExit;
    float rayLengthPx = distance(rayStartUVQ.xy / g_FbSize, rayEndUVQ.xy / g_FbSize);
    float numSteps = clamp(ceil(rayLengthPx * SSR_STEP_PIXEL_RCP), 1.0, SSR_MAX_STEPS);

    float4 prevUVQC          = { rayStartUVQ, -1.0 };
    float  prevFbDepth       = 1.0e20;
    float3 lastClearRay      = rayStartUVQ;
    float3 lastClearColor    = 0.0;
    float  lastClearDistance = 0.0;
    float4 stitchCandidate   = 0.0;
    bool   rayArmed          = height * HEIGHT_TO_HU + SSR_INITIAL_BIAS_HU >= 0.0;

    [loop]
    for (int j = 1; j <= SSR_MAX_STEPS; j++) {
        if ((float)j > numSteps) break;

        float t = (float)j * rcp(numSteps);
        float3 uvq = lerp(rayStartUVQ, rayEndUVQ, t);
        if (ScreenEdgeFade(uvq.xy) <= 0.0) break;

        float4 fb = tex2Dlod(SSRSource, float4(uvq.xy, 0.0, 0.0));
        float fbDepth = fb.a * DepthWriteConstant;
        if (fbDepth <= 1.0e-3) continue;

        float prevRayDepth    = rcp(max(prevUVQC.z, 1.0e-6));
        float currentRayDepth = rcp(max(uvq.z, 1.0e-6));
        float rayMin          = min(prevRayDepth, currentRayDepth);
        float rayMax          = max(prevRayDepth, currentRayDepth);
        float rayDepthSpan    = rayMax - rayMin;
        float thickness       = ComputeSSRThickness(fbDepth, rayDepthSpan, roughness);
        float classification  = ClassifySSRSegment(rayMin, rayMax, fbDepth, thickness);
        if (rayArmed && prevUVQC.w < 0.0 && abs(classification) < 1.0e-3) {
            bool hitRefined = false;
            [unroll]
            for (int k = 0; k < SSR_BINARY_STEPS; k++) {
                float3 midUVQ = lerp(prevUVQC.xyz, uvq, 0.5);
                float fbMidDepth = SampleSceneDepth(midUVQ.xy);
                if (fbMidDepth < rcp(midUVQ.z)) {
                    uvq = midUVQ;
                    hitRefined = true;
                }
                else {
                    prevUVQC.xyz = midUVQ;
                }
            }
            return float4(
                SampleRefinedInkAwareSSRColor(uvq.xy, fb.rgb, hitRefined),
                ScreenEdgeFade(uvq.xy));
        }

        float depthJump = fbDepth - prevFbDepth;
        float gapThreshold = max(thickness, SSR_STITCH_GAP_MIN_HU);
        float foundStitchGap
            = (rayArmed ? 1.0 : 0.0)
            * (1.0 - step(prevUVQC.w, 0.0))
            * step(0.0, classification)
            * step(gapThreshold, depthJump);
        if (foundStitchGap > 0.0) {
            bool stitchRefined = false;
            [unroll]
            for (int k = 0; k < SSR_BINARY_STEPS; k++) {
                float3 midUVQ = lerp(prevUVQC.xyz, uvq, 0.5);
                float midFbDepth = SampleSceneDepth(midUVQ.xy);
                if (midFbDepth - prevFbDepth > gapThreshold) {
                    uvq = midUVQ;
                    currentRayDepth = rcp(max(uvq.z, 1.0e-6));
                    fbDepth = midFbDepth;
                    stitchRefined = true;
                }
                else {
                    prevUVQC.xyz = midUVQ;
                }
            }
            float3 stitchColor = SampleRefinedInkAwareSSRColor(
                uvq.xy, fb.rgb, stitchRefined);
            float currentDistanceToDepth = abs(fbDepth - currentRayDepth);
            float stitchWeight = lastClearDistance
                * rcp(max(lastClearDistance + currentDistanceToDepth, 1.0e-3));
            float3 stitchedColor = lerp(
                SampleInkAwareSSRColor(lastClearRay.xy, lastClearColor),
                stitchColor,
                stitchWeight);
            float stitchAlpha = lerp(
                ScreenEdgeFade(lastClearRay.xy),
                ScreenEdgeFade(uvq.xy),
                stitchWeight);
            stitchCandidate = float4(stitchedColor, stitchAlpha);
        }

        prevUVQC = float4(uvq, classification);
        prevFbDepth = fbDepth;
        if (classification < 0.0) {
            rayArmed = true;
            lastClearRay = uvq;
            lastClearColor = fb.rgb;
            lastClearDistance = fbDepth - currentRayDepth;
        }
    }

    return stitchCandidate;
}

