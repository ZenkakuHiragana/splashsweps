#include "inkmesh_common.hlsl"

sampler SceneColorDepth : register(s0);
sampler GBufInkColor    : register(s1);
sampler GBufInkNormals  : register(s2);
sampler GBufReflection  : register(s3);
sampler GBufEnvmap      : register(s4);

static const int   MAX_STEPS         = 64;       // Maximum screen-space samples
static const int   BINARY_STEPS      = 2;        // Binary search refinement steps
static const float STEP_PIXEL_RCP    = rcp(8.0); // Target screen-space distance between samples
static const float INITIAL_BIAS_HU   = 2.0;      // Ray start offset in Hammer units to skip the source surface
static const float STITCH_GAP_MIN_HU = 16.0;
static const float FOV_Y             = radians(75.0);
static const float TAN_HALF_FOV      = tan(FOV_Y * 0.5);
static const float THICKNESS_MIN     = 8.0;  // Minimum accepted screen-depth thickness in Hammer units
static const float THICKNESS_MAX     = 32.0; // Accepted thickness at the far end of the ray
static const float RAY_SPAN_SCALE    = 0.25; // Scale factor for jumping depth between steps
static const float ROUGHNESS_SCALE   = 4.0;  // Scale factor for roughness

static const float2 g_FbSize      = s0Size;            // One over frame buffer size
static const float2 g_RenderSize  = s0Size * 2.0;      // RT size = always 0.5x resolution of the frame buffer
static const float2 g_RenderPx    = rcp(g_RenderSize); // Render target resolution in px
static const float3 g_ViewRight   = c11.xyz;
static const float3 g_ViewUp      = c12.xyz;
static const float3 g_ViewForward = c13.xyz;
static const float3 g_ViewOrigin  = c14.xyz;

float3 ReconstructWorldPosition(float2 uv, float viewDepth) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return g_ViewOrigin + (g_ViewForward + g_ViewRight * ndc.x + g_ViewUp * ndc.y) * viewDepth;
}

float3 InkAwareColor(float2 uv, float3 frameBufferColor) {
    float4 ink = tex2Dlod(GBufInkColor, float4(uv, 0.0, 0.0));
    return lerp(frameBufferColor, ink.rgb, step(0.5, ink.a));
}

float ComputeSSRThickness(float depth, float rayDepthSpan, float roughness) {
    float pixelSizeHU = 2.0 * depth * TAN_HALF_FOV * g_FbSize.y;
    float roughnessScale = lerp(1.0, ROUGHNESS_SCALE, roughness);
    return clamp(
        max(pixelSizeHU * roughnessScale, rayDepthSpan * RAY_SPAN_SCALE),
        THICKNESS_MIN, THICKNESS_MAX);
}

// -1 -> clear:         ray is in front of the depth shell
//  0 -> hit candidate: ray overlaps the depth shell
// +1 -> occluded:      ray is behind the depth shell
float ClassifySSRSegment(float rayMin, float rayMax, float sceneDepth, float thickness) {
    float sceneMin = sceneDepth;
    float sceneMax = sceneDepth + thickness;

    // 1 when ray is strictly in front of the shell.
    // rayMin    rayMax    sceneMin    sceneMax
    //   *---------*          +===========+
    float clear = 1.0 - step(sceneMin, rayMax);

    // 1 when ray is strictly behind the shell.
    // sceneMin    sceneMax   rayMin    rayMax
    //    +===========+         *---------*
    float behind = 1.0 - step(rayMin, sceneMax);
    return behind - clear;
}

float4 SampleScreenSpaceReflection(
    float2 screenUV,
    float3 worldPos,
    float  viewDepth,
    float3 viewDir,
    float3 geometryNormal,
    float3 worldSpaceNormal,
    float roughness,
    float height)
{
    float3 P = worldPos;
    float  W = max(viewDepth, 1.0e-3);
    float3 viewAway = -viewDir;
    float  viewDist = distance(g_ViewOrigin, P);

    // Represents the world position movement amount in world coordinates:
    //   x: ∂P/∂u -- per 1.0 horizontal UV movement on the frame buffer
    //   y: ∂P/∂v -- per 1.0 vertical UV movement on the frame buffer
    //   z: ∂P/∂r -- per 1.0 Hammer Unit along view direction
    float3x3 screenSpaceAxesInWorld = { ddx(P) * g_RenderPx.x, ddy(P) * g_RenderPx.y, viewAway };

    // Difference of clipPos.w along the screen space coordinates (u, v, r)
    //   x: ∂W/∂u,  y: ∂W/∂v,  z: ∂W/∂r
    float3 clipWPerScreenSpaceAxis = { ddx(W) * g_RenderPx.x, ddy(W) * g_RenderPx.y, W / viewDist };

    // Surface displacement by the height map in screen space coordinates (u, v, r)
    // (u, v) .. Frame buffer UV, r .. Depth in Hammer units
    // screenSpaceOffset = ds = (du, dv, dr)
    float4 screenSpaceOffset = DecomposeBasis(
        screenSpaceAxesInWorld[0],
        screenSpaceAxesInWorld[1],
        screenSpaceAxesInWorld[2],
        geometryNormal * (height * HEIGHT_TO_HU + INITIAL_BIAS_HU));

    // Reflection ray direction in screen space coordinates
    //   The point on the reflection ray R = P + reflect(...) * t, where t is a parameter
    //   screenSpaceRayDirection = dR/dt = (dRu/dt, dRv/dt, dRr/dt)
    float4 screenSpaceRayDirection = DecomposeBasis(
        screenSpaceAxesInWorld[0],
        screenSpaceAxesInWorld[1],
        screenSpaceAxesInWorld[2],
        reflect(viewAway, worldSpaceNormal));

    // UVQ coordinate:
    //   xy: framebuffer UV
    //   z : reciprocal clip.w, q = 1 / w
    //
    // This is the marching coordinate. A linear segment in UVQ gives
    // evenly spaced screen-space samples and a reciprocal-depth value
    // that can be converted back to clip.w for depth comparison.
    float3 rayStartUVQ = {
        screenUV + screenSpaceOffset.xy,
        // W + dW = W + ∂W/∂u * du + ∂W/∂v * dv + ∂W/∂r * dr = W + dot(∂W, ds)
        rcp(max(W + dot(screenSpaceOffset.xyz, clipWPerScreenSpaceAxis), 1.0e-6)),
    };

    // dQ/dt = -1/W² * dW/dt = -Q² * dW/dt
    // dW/dt = ∂W/∂u * dQu/dt
    //       + ∂W/∂v * dQv/dt
    //       + ∂W/∂r * dQr/dt = dot(∂W, dQ/dt)
    float3 rayDirectionUVQ = {
        screenSpaceRayDirection.xy,
        -rayStartUVQ.z * rayStartUVQ.z * dot(screenSpaceRayDirection.xyz, clipWPerScreenSpaceAxis),
    };

    // Building the ray
    float2 axisInvalid   = step(abs(rayDirectionUVQ.xy), 1.0e-8);
    float  qLimitInvalid = step(-rayDirectionUVQ.z, 1.0e-8);
    float2 exitEdges     = step(0.0, rayDirectionUVQ.xy);
    float2 tEdges        = lerp((exitEdges - rayStartUVQ.xy) * SAFERCP(rayDirectionUVQ.xy), 1.0e20, axisInvalid);
    float  tQ            = lerp((1.0e-6 - rayStartUVQ.z) * SAFERCP(rayDirectionUVQ.z), 1.0e20, qLimitInvalid);
    float  tExit         = min(min(tEdges.x, tEdges.y), tQ);
    float3 rayEndUVQ     = rayStartUVQ + rayDirectionUVQ * tExit;
    float  rayLengthPx   = distance(rayStartUVQ.xy / g_FbSize, rayEndUVQ.xy / g_FbSize);
    float  numSteps      = clamp(ceil(rayLengthPx * STEP_PIXEL_RCP), 1.0, MAX_STEPS);

    // Temporary variables used in the loop
    float4 prevUVQC          = { rayStartUVQ, -1.0 }; // UVQ + Classify result
    float  prevFbDepth       = 1.0e20;
    float3 lastClearRay      = rayStartUVQ; // Last ray that was in front of the depth
    float3 lastClearColor    = 0.0;
    float  lastClearDistance = 0.0;
    float4 stitchCandidate   = 0.0;
    bool   rayArmed          = height * HEIGHT_TO_HU + INITIAL_BIAS_HU >= 0.0;

    [loop]
    for (int j = 1; j <= MAX_STEPS; j++) {
        if ((float)j > numSteps) break;

        float t = (float)j * rcp(numSteps);
        float3 uvq = lerp(rayStartUVQ, rayEndUVQ, t);
        if (ScreenEdgeFade(uvq.xy) <= 0.0) break;

        float4 fb = tex2Dlod(SceneColorDepth, float4(uvq.xy, 0.0, 0.0));
        float fbDepth = fb.a * DEPTHWRITE_TO_HU;
        if (fbDepth <= 1.0e-3) continue; // Seems like the ray is on the viewmodel, skipping...

        float prevRayDepth    = rcp(max(prevUVQC.z, 1.0e-6));
        float currentRayDepth = rcp(max(uvq.z, 1.0e-6));
        float rayMin          = min(prevRayDepth, currentRayDepth);
        float rayMax          = max(prevRayDepth, currentRayDepth);
        float rayDepthSpan    = rayMax - rayMin;
        float thickness       = ComputeSSRThickness(fbDepth, rayDepthSpan, roughness);
        float classification  = ClassifySSRSegment(rayMin, rayMax, fbDepth, thickness);
        if (rayArmed && prevUVQC.w < 0.0 && abs(classification) < 1.0e-3) {
            [unroll]
            for (int k = 0; k < BINARY_STEPS; k++) {
                float3 midUVQ     = lerp(prevUVQC.xyz, uvq, 0.5);
                float4 midFb      = tex2Dlod(SceneColorDepth, float4(midUVQ.xy, 0.0, 0.0));
                float  midFbDepth = midFb.a * DEPTHWRITE_TO_HU;

                // fbDepth
                //  *   * uvq
                //  |  /
                //  | * midUVQ
                //   X
                //  / \
                // *   * previous fbDepth
                // prevUVQ
                if (midFbDepth < rcp(midUVQ.z)) {
                    uvq = midUVQ;
                    fb = midFb;
                }
                else {
                    prevUVQC.xyz = midUVQ;
                }
            }
            return float4(InkAwareColor(uvq.xy, fb.rgb), ScreenEdgeFade(uvq.xy));
        }

        float depthJump = fbDepth - prevFbDepth;
        float gapThreshold = max(thickness, STITCH_GAP_MIN_HU);
        float foundStitchGap
            = (rayArmed ? 1.0 : 0.0)
            * (1.0 - step(prevUVQC.w, 0.0))  // previously occluded
            * step(0.0, classification)      // and now occluded or hit candidate
            * step(gapThreshold, depthJump); // and depth jumps
        if (foundStitchGap > 0.0) {
            [unroll]
            for (int k = 0; k < BINARY_STEPS; k++) {
                float3 midUVQ     = lerp(prevUVQC.xyz, uvq, 0.5);
                float4 midFb      = tex2Dlod(SceneColorDepth, float4(midUVQ.xy, 0.0, 0.0));
                float  midFbDepth = midFb.a * DEPTHWRITE_TO_HU;
                if (midFbDepth - prevFbDepth > gapThreshold) {
                    uvq = midUVQ;
                    currentRayDepth = rcp(max(uvq.z, 1.0e-6));
                    fb = midFb;
                    fbDepth = midFbDepth;
                }
                else {
                    prevUVQC.xyz = midUVQ;
                }
            }
            float3 color1 = InkAwareColor(lastClearRay.xy, lastClearColor);
            float3 color2 = InkAwareColor(uvq.xy, fb.rgb);
            float  currentDistanceToDepth = abs(fbDepth - currentRayDepth);
            float  stitchWeight  = lastClearDistance * rcp(max(lastClearDistance + currentDistanceToDepth, 1.0e-3));
            float3 stitchedColor = lerp(color1, color2, stitchWeight);
            float  stitchAlpha   = lerp(ScreenEdgeFade(lastClearRay.xy), ScreenEdgeFade(uvq.xy), stitchWeight);
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

float4 main(float4 i : VPOS) : COLOR0 {
    float4 uv = { i.xy * g_RenderSize, 0.0, 0.0 };
    float4 surface = tex2Dlod(GBufInkColor, uv);
    if (surface.a < 0.5) return 0.0;

    float4 reflectionParams = tex2Dlod(GBufReflection, uv);
    if (dot(reflectionParams.rgb, reflectionParams.rgb) <= 0.0) return 0.0;

    float4 scene          = tex2Dlod(SceneColorDepth, uv);
    float4 normals        = tex2Dlod(GBufInkNormals,  uv);
    float4 envmapParams   = tex2Dlod(GBufEnvmap,      uv);
    float  viewDepth      = scene.a * DEPTHWRITE_TO_HU;
    float3 worldPos       = ReconstructWorldPosition(uv.xy, viewDepth);
    float3 worldNormal    = DecodeOctahedralUnitVector(normals.xy);
    float3 geometryNormal = DecodeOctahedralUnitVector(normals.zw);
    float3 viewDir        = normalize(g_ViewOrigin - worldPos);
    float4 ssr = SampleScreenSpaceReflection(
        uv.xy, worldPos, viewDepth, viewDir, geometryNormal,
        worldNormal, envmapParams.a, reflectionParams.a);
    return float4(ssr.rgb * ssr.a, ssr.a);
}
