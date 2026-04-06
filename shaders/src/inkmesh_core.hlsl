
// Data texture layout
#define ID_COLOR_ALPHA        0
#define ID_TINT_GEOMETRYPAINT 1
#define ID_EDGE               2
#define ID_HEIGHT_MAXLAYERS   3
#define ID_MATERIAL_REFRACT   4
#define ID_MISC               5
#define ID_DETAILS_BUMPBLEND  6
#define ID_OTHERS             7

#define TRACE_FALLBACK     0.0
#define TRACE_HIT_START    1.0
#define TRACE_HIT_CROSSING 2.0
#define TRACE_BOX_MISS     3.0
#define TRACE_NO_HIT       4.0
#define MESH_ROLE_CEIL     0
#define MESH_ROLE_DEPTH    1
#define MESH_ROLE_BASE     2
#define MESH_ROLE_SIDE_IN  3
#define MESH_ROLE_SIDE_OUT 4
#define MESH_ROLE_MAX      4.0

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// [-1.0, +1.0] --> [0.0, 1.0]
#define TO_UNSIGNED(x) saturate((x) * 0.5 + 0.5)

// Safe rcp that avoids division by zero
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-21)))

// Shared pixel shader bindings for inkmesh shaders.
sampler InkMap             : register(s0);
sampler InkDataSampler     : register(s1);
sampler DepthSampler       : register(s2);
sampler FrameBuffer        : register(s3);
sampler InkDetailSampler   : register(s4);
sampler WallAlbedoSampler  : register(s5);
sampler WallBumpmapSampler : register(s6);
sampler LightmapSampler    : register(s7);

const float4 c0            : register(c0);
const float4 c1            : register(c1);
const float4 c2            : register(c2);
const float4 c3            : register(c3);
const float2 RcpRTSize     : register(c4);
const float2 RcpDataRTSize : register(c5);
const float2 RcpDepthSize  : register(c6);
const float2 RcpFbSize     : register(c7);
const float4 c8            : register(c8);
const float4 c9            : register(c9);
const float4 g_EyePos      : register(c10);
const float2x4 BaseTextureTransform : register(c11);
const float2x4 BumpTextureTransform : register(c15);
const float4 HDRParams     : register(c30);

static const float HEIGHT_TO_HAMMER_UNITS = 32.0;
static const float LOD_DISTANCE = 4096.0;
static const float4 GROUND_PROPERTIES[8] = {
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 1.0,  0.0 },
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 0.75, 0.5 },
    { 0.0, 0.0, 0.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 0.0, 0.0,  0.0 },
};

#define g_SunDirection      c0.xyz
#define g_Unused            c0.w
#define g_HasBumpedLightmap c1.x
#define g_NeedsFrameBuffer  c1.y
#define g_ScreenScale       c1.y
#define g_HammerUnitsToUV   c1.z
#define g_Simplified        c1.w

#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w

struct PS_INPUT {
    float2   screenPos             : VPOS;
    float4   surfaceClipRange      : TEXCOORD0;
    float4   lightmapUV1And2       : TEXCOORD1;
    float4   lightmapUV3_projXY    : TEXCOORD2;
    float4   inkUV_worldBumpUV     : TEXCOORD3;
    float4   worldPos_projPosZ     : TEXCOORD4;
    float4   worldBinormalTangentX : TEXCOORD5;
    float4   worldNormalTangentY   : TEXCOORD6;
    float4   inkTangentXYZWorldZ   : TEXCOORD7;
    float4   inkBinormalMeshLift   : TEXCOORD8;
    float4   projPosW_meshRole     : TEXCOORD9;
};

// Samples only height value to apply parallax effect to the ink
float FetchHeight(float2 uv) {
    return TO_SIGNED(tex2Dlod(InkMap, float4(uv, 0.0, 0.0)).a);
}

float FetchDepth(float2 uv) {
    return tex2Dlod(InkMap, float4(uv.x + 0.5, uv.y, 0.0, 0.0)).a;
}

float EvaluateInterfaceField(float3 samplePos) {
    return FetchHeight(samplePos.xy) - samplePos.z;
}

float3 DebugTraceKindColor(float traceKind) {
    if (traceKind < 0.5) return float3(1.0, 0.0, 0.0);
    if (traceKind < 1.5) return float3(0.0, 1.0, 0.0);
    if (traceKind < 2.5) return float3(0.0, 0.5, 1.0);
    if (traceKind < 3.5) return float3(1.0, 1.0, 0.0);
    if (traceKind < 4.5) return float3(1.0, 0.0, 1.0);
    return float3(1.0, 0.0, 0.0);
}

bool IsTraceHit(float traceKind) {
    return traceKind > 0.5 && traceKind < 2.5;
}

float3 DebugTexelFraction(float2 uv, float2 rcpRTSize) {
    float2 texelCoord = uv / rcpRTSize;
    float2 texelFrac = frac(texelCoord);
    float2 texelEdgeDistance = min(texelFrac, 1.0 - texelFrac);
    float edgeLine = 1.0 - saturate(min(texelEdgeDistance.x, texelEdgeDistance.y) * 8.0);
    return float3(texelFrac, edgeLine);
}

float3 DebugSnapDelta(float2 uv, float2 pixelUV, float2 rcpRTSize) {
    float2 delta = abs((uv - pixelUV) / rcpRTSize) * 2.0;
    return saturate(float3(delta.x, delta.y, max(delta.x, delta.y)));
}

float3 DebugHeightDepth(float height, float hitHeight, float depth) {
    return float3(TO_UNSIGNED(height), TO_UNSIGNED(hitHeight), saturate(depth));
}

float3 DebugInkIDs(float id1, float id2, float idBlend) {
    return float3(id1 * (1.0 / 255.0), id2 * (1.0 / 255.0), idBlend);
}

float2 SolveScreenOffset(float2 du, float2 dv, float2 uvOffset) {
    float det = du.x * dv.y - dv.x * du.y;
    det = rcp(det + (det < 0 ? -1.0e-7 : 1.0e-7));
    return float2(
        dot(float2( dv.y, -dv.x), uvOffset) * det,
        dot(float2(-du.y,  du.x), uvOffset) * det);
}

float2 EncodeSignedUnitFloat2(float2 v) {
    return saturate(v * 0.5 + 0.5);
}

float3 EncodeTraceHit(float3 inkUV) {
    return float3(saturate(inkUV.xy), TO_UNSIGNED(inkUV.z));
}

float TraceLinearFraction(float a, float b) {
    return saturate(-a * SAFERCP(b - a));
}

float3 TracePaintInterfaceCore(
    float3 eyeUV,
    float3 proxyUV,
    float4 surfaceClipRange,
    out float traceKind,
    out float traceSteps,
    out float traceRayFraction,
    out float boxEnterFraction,
    out float boxExitFraction) {
    const float PIXELS_PER_STEP_RCP = rcp(16.0);
    const float MIN_STEPS = 2.0;
    const float MAX_STEPS = 16.0;
    const int NUM_REFINEMENT_STEPS = 2;
    float3 boxMin        = float3(surfaceClipRange.xy, -1.0 - 1.0e-5);
    float3 boxMax        = float3(surfaceClipRange.zw,  1.0 + 1.0e-5);
    float3 rayDir        = proxyUV - eyeUV;
    float3 rayDirInv     = SAFERCP(rayDir);
    float3 fractionMin   = (boxMin - eyeUV) * rayDirInv;
    float3 fractionMax   = (boxMax - eyeUV) * rayDirInv;
    float3 fractionNear  = min(fractionMin, fractionMax);
    float3 fractionFar   = max(fractionMin, fractionMax);
    float  fractionEnter = max(max(fractionNear.x, fractionNear.y), fractionNear.z);
    float  fractionExit  = min(min(fractionFar.x, fractionFar.y), fractionFar.z);
    float  fractionStart = max(fractionEnter, 0.0);
    float  fractionEnd   = fractionExit;
    boxEnterFraction = fractionStart;
    boxExitFraction = fractionEnd;
    if (fractionEnd <= fractionStart) {
        traceKind = TRACE_BOX_MISS;
        traceSteps = 0.0;
        traceRayFraction = fractionStart;
        return clamp(proxyUV,
            float3(surfaceClipRange.xy, boxMin.z),
            float3(surfaceClipRange.zw, boxMax.z));
    }
    float3 rayMarchingStart = eyeUV + rayDir * fractionStart;
    float3 rayMarchingEnd   = eyeUV + rayDir * fractionEnd;
    float  pixelPerUV       = rcp(max(min(length(ddx(proxyUV.xy)), length(ddy(proxyUV.xy))), 1.0e-8));
    float  numSteps         = distance(rayMarchingStart.xy, rayMarchingEnd.xy);
    numSteps *= PIXELS_PER_STEP_RCP * pixelPerUV;
    numSteps = clamp(round(numSteps), MIN_STEPS, MAX_STEPS);
    traceSteps = numSteps;
    float3 previousRay   = rayMarchingStart;
    float  previousField = EvaluateInterfaceField(previousRay);
    float  previousRayFraction = fractionStart;
    if (abs(previousField) < 1.0e-4) {
        traceKind = TRACE_HIT_START;
        traceRayFraction = previousRayFraction;
        return clamp(previousRay,
            float3(surfaceClipRange.xy, boxMin.z),
            float3(surfaceClipRange.zw, boxMax.z));
    }
    [unroll]
    for (int j = 1; j <= MAX_STEPS; j++) {
        if (j > (int)numSteps) break;
        float fraction = (float)j / numSteps;
        float currentRayFraction = lerp(fractionStart, fractionEnd, fraction);
        float3 currentRay = lerp(rayMarchingStart, rayMarchingEnd, fraction);
        float currentField = EvaluateInterfaceField(currentRay);
        if (previousField * currentField <= 0.0) {
            float3 a = previousRay;
            float3 b = currentRay;
            float fa = previousField;
            float fb = currentField;
            [unroll]
            for (int k = 0; k < NUM_REFINEMENT_STEPS; k++) {
                float3 mid = lerp(a, b, 0.5);
                float fm = EvaluateInterfaceField(mid);
                if (fa * fm <= 0.0) {
                    b = mid;
                    fb = fm;
                }
                else {
                    a = mid;
                    fa = fm;
                }
            }

            float hitFraction = TraceLinearFraction(fa, fb);
            float3 inkUV = lerp(a, b, hitFraction);
            traceKind = TRACE_HIT_CROSSING;
            traceRayFraction = lerp(previousRayFraction, currentRayFraction, hitFraction);
            return clamp(inkUV,
                float3(surfaceClipRange.xy, boxMin.z),
                float3(surfaceClipRange.zw, boxMax.z));
        }

        previousRay = currentRay;
        previousField = currentField;
        previousRayFraction = currentRayFraction;
    }
    traceKind = TRACE_NO_HIT;
    traceRayFraction = fractionEnd;
    return clamp(previousRay,
        float3(surfaceClipRange.xy, boxMin.z),
        float3(surfaceClipRange.zw, boxMax.z));
}

float3 TracePaintInterface(const PS_INPUT i, out float traceKind, out float traceSteps, out float traceRayFraction) {
    float3 worldPos = i.worldPos_projPosZ.xyz;
    float3 proxyUV  = float3(i.inkUV_worldBumpUV.xy, i.inkBinormalMeshLift.w);
    float3x3 tangentSpaceInk = {
        i.inkTangentXYZWorldZ.xyz,
        i.inkBinormalMeshLift.xyz,
        i.worldNormalTangentY.xyz / HEIGHT_TO_HAMMER_UNITS,
    };
    float3 eyeUV = proxyUV + mul(tangentSpaceInk, g_EyePos.xyz - worldPos);
    float boxEnterFraction, boxExitFraction;
    return TracePaintInterfaceCore(
        eyeUV,
        proxyUV,
        i.surfaceClipRange,
        traceKind,
        traceSteps,
        traceRayFraction,
        boxEnterFraction,
        boxExitFraction);
}
