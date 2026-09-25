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
static const float DEPTH_GAP_MIN_HU  = 16.0;     // Minimum depth jump that counts as crossing a depth gap
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

// Prepares the inverse of the basis (a, b, c), so that
// mul(MakeBasisInverse(a, b, c), v) solves v = x*a + y*b + z*c for (x, y, z).
// Prepare once and apply to several vectors when the basis is shared.
float3x3 MakeBasisInverse(float3 a, float3 b, float3 c) {
    float3 bCrossC = cross(b, c);
    float3 cCrossA = cross(c, a);
    float3 aCrossB = cross(a, b);
    float invDet   = SAFERCP(dot(a, bCrossC));
    return float3x3(
        bCrossC * invDet,
        cCrossA * invDet,
        aCrossB * invDet);
}

float3 ReconstructWorldPosition(float2 uv, float viewDepth) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return g_ViewOrigin + (g_ViewForward + g_ViewRight * ndc.x + g_ViewUp * ndc.y) * viewDepth;
}

float ComputeSSRThickness(float depth, float rayDepthSpan, float roughness) {
    float pixelSizeHU = 2.0 * depth * TAN_HALF_FOV * g_FbSize.y;
    float roughnessScale = lerp(1.0, ROUGHNESS_SCALE, roughness);
    float thickness = max(pixelSizeHU * roughnessScale, rayDepthSpan * RAY_SPAN_SCALE);
    return clamp(thickness, THICKNESS_MIN, THICKNESS_MAX);
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

// The three classification values produced by ClassifySSRSegment.
bool SegmentIsClear(float c)        { return c < 0.0; }
bool SegmentIsOccluded(float c)     { return c > 0.0; }
bool SegmentIsHitCandidate(float c) { return abs(c) < 1.0e-3; }

// Bisects [inFront, behind] down to where the reflection ray crosses the scene surface:
// 'behind' converges to the first sample behind the surface,
// 'inFront' to the last sample in front of it.
// The scene sample at 'behind' is carried along,
// so the caller keeps color and depth at the crossing point.
void RefineSurfaceCrossing(inout float3 inFront, inout float3 behind, inout float4 behindSample) {
    [unroll]
    for (int k = 0; k < BINARY_STEPS; k++) {
        float3 midUVQ    = lerp(inFront, behind, 0.5);
        float4 midSample = tex2Dlod(SceneColorDepth, float4(midUVQ.xy, 0.0, 0.0));
        if (midSample.a * DEPTHWRITE_TO_HU < rcp(midUVQ.z)) {
            behind = midUVQ;
            behindSample = midSample;
        }
        else {
            inFront = midUVQ;
        }
    }
}

// Bisects [beforeGap, pastGap] down to the edge of a depth gap (a silhouette or
// a crack between surfaces): 'pastGap' converges to the first sample that
// already sees the far side of the gap. Its scene sample is carried along.
void RefineGapEdge(
    inout float3 beforeGap,
    inout float3 pastGap,
    inout float4 pastSample,
    float previousDepth,
    float gapThreshold)
{
    [unroll]
    for (int k = 0; k < BINARY_STEPS; k++) {
        float3 midUVQ    = lerp(beforeGap, pastGap, 0.5);
        float4 midSample = tex2Dlod(SceneColorDepth, float4(midUVQ.xy, 0.0, 0.0));
        if (midSample.a * DEPTHWRITE_TO_HU - previousDepth > gapThreshold) {
            pastGap = midUVQ;
            pastSample = midSample;
        }
        else {
            beforeGap = midUVQ;
        }
    }
}

// Marches the reflection ray in UVQ space and resolves the reflection hit of one pixel.
// A hit is either the surface crossing found by the march (returned immediately)
// or a depth-gap bridge recorded along the way (returned when the march ends without a crossing).
// xy: selected framebuffer UV, a: confidence (screen-edge fade).
// The caller premultiplies UV by confidence for valid-only interpolation.
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

    // Inverse of the screen space basis (u, v, r) -> world, prepared once and
    // applied to the two vectors below:
    //   mul(worldToUVR, v) = (du, dv, dr) such that
    //   v = du*∂P/∂u + dv*∂P/∂v + dr*∂P/∂r
    float3x3 worldToUVR = MakeBasisInverse(
        screenSpaceAxesInWorld[0],
        screenSpaceAxesInWorld[1],
        screenSpaceAxesInWorld[2]);

    // Surface displacement by the height map in screen space coordinates (u, v, r)
    // (u, v) .. Frame buffer UV, r .. Depth in Hammer units
    // screenSpaceOffset = ds = (du, dv, dr)
    float3 screenSpaceOffset = mul(worldToUVR, geometryNormal * (height * HEIGHT_TO_HU + INITIAL_BIAS_HU));

    // Reflection ray direction in screen space coordinates
    //   The point on the reflection ray R = P + reflect(...) * t, where t is a parameter
    //   screenSpaceRayDirection = dR/dt = (dRu/dt, dRv/dt, dRr/dt)
    float3 screenSpaceRayDirection = mul(worldToUVR, reflect(viewAway, worldSpaceNormal));

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
        rcp(max(W + dot(screenSpaceOffset, clipWPerScreenSpaceAxis), 1.0e-6)),
    };

    // dQ/dt = -1/W² * dW/dt = -Q² * dW/dt
    // dW/dt = ∂W/∂u * dQu/dt
    //       + ∂W/∂v * dQv/dt
    //       + ∂W/∂r * dQr/dt = dot(∂W, dQ/dt)
    float3 rayDirectionUVQ = {
        screenSpaceRayDirection.xy,
        -rayStartUVQ.z * rayStartUVQ.z * dot(screenSpaceRayDirection, clipWPerScreenSpaceAxis),
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

    // March state. 'sceneSample' is always the scene sample at 'uvq'; every
    // refinement below carries the sample along when it moves the point.
    float3 previousUVQ    = rayStartUVQ; // Previous sample position in UVQ
    float  previousClass  = -1.0;        // Its classification; the biased start is assumed clear
    float  previousDepth  = 1.0e20;      // Scene depth at the previous sample
    float3 lastClearUVQ   = rayStartUVQ; // Near anchor of the depth-gap bridge
    float  lastClearance  = 0.0;         // Ray-to-surface clearance at the anchor
    float4 bridgedHit     = 0.0;         // Fallback hit bridged across a depth gap

    // A ray starting inside its own depth shell (dug ink) must reach clear
    // space once before any hit is accepted, so it cannot hit its own surface.
    bool canAcceptHit = height * HEIGHT_TO_HU + INITIAL_BIAS_HU >= 0.0;

    [loop]
    for (int j = 1; j <= MAX_STEPS; j++) {
        if ((float)j > numSteps) break;

        float t = (float)j * rcp(numSteps);
        float3 uvq = lerp(rayStartUVQ, rayEndUVQ, t);
        if (ScreenEdgeFade(uvq.xy) <= 0.0) break;

        float4 sceneSample = tex2Dlod(SceneColorDepth, float4(uvq.xy, 0.0, 0.0));
        float sceneSampleDepth = sceneSample.a * DEPTHWRITE_TO_HU;
        if (sceneSampleDepth <= 1.0e-3) continue; // Seems like the ray is on the viewmodel, skipping...

        float previousRayDepth = rcp(max(previousUVQ.z, 1.0e-6));
        float rayDepth         = rcp(max(uvq.z, 1.0e-6));
        float rayMin           = min(previousRayDepth, rayDepth);
        float rayMax           = max(previousRayDepth, rayDepth);
        float rayDepthSpan     = rayMax - rayMin;
        float thickness        = ComputeSSRThickness(sceneSampleDepth, rayDepthSpan, roughness);
        float classification   = ClassifySSRSegment(rayMin, rayMax, sceneSampleDepth, thickness);

        // Hard hit: the segment has just left clear space and now touches the
        // depth shell, so the surface crossing itself is the reflection hit.
        if (canAcceptHit && SegmentIsClear(previousClass) && SegmentIsHitCandidate(classification)) {
            RefineSurfaceCrossing(previousUVQ, uvq, sceneSample);
            return float4(uvq.xy, 0.0, ScreenEdgeFade(uvq.xy));
        }

        // Depth-gap bridge (fallback hit): retain the endpoint with the larger
        // inverse-clearance weight. Do not interpolate UV across the occluder.
        // A later surface crossing still takes precedence over this fallback.
        float depthJump    = sceneSampleDepth - previousDepth;
        float gapThreshold = max(thickness, DEPTH_GAP_MIN_HU);
        bool crossedDepthGap = canAcceptHit
            && SegmentIsOccluded(previousClass) // previously occluded
            && !SegmentIsClear(classification)  // and now occluded or hit candidate
            && depthJump >= gapThreshold;       // and depth jumps
        if (crossedDepthGap) {
            RefineGapEdge(previousUVQ, uvq, sceneSample, previousDepth, gapThreshold);
            sceneSampleDepth = sceneSample.a * DEPTHWRITE_TO_HU;
            float  rayDepthAtGap = rcp(max(uvq.z, 1.0e-6));
            float  gapClearance  = abs(sceneSampleDepth - rayDepthAtGap);
            float  farSideWeight = lastClearance * rcp(max(lastClearance + gapClearance, 1.0e-3));
            float2 hitUV = farSideWeight >= 0.5 ? uvq.xy : lastClearUVQ.xy;
            bridgedHit = float4(hitUV, 0.0, ScreenEdgeFade(hitUV));
        }

        previousUVQ   = uvq;
        previousClass = classification;
        previousDepth = sceneSampleDepth;
        if (SegmentIsClear(classification)) {
            canAcceptHit   = true;
            lastClearUVQ   = uvq;
            lastClearance  = sceneSampleDepth - rcp(max(uvq.z, 1.0e-6));
        }
    }

    return bridgedHit;
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
    return float4(ssr.xy * ssr.a, 0.0, ssr.a);
}
