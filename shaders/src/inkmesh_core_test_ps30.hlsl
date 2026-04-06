#include "inkmesh_core.hlsl"

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

float4 main(const PS_INPUT i) : COLOR0 {
    float traceKind;
    float traceSteps;
    float traceRayFraction;
    float3 boxProxyUV = float3(i.inkUV_worldBumpUV.xy, i.inkBinormalMeshLift.w);
    float boxEnterFraction;
    float boxExitFraction;
    float3 inkUV = TracePaintInterfaceCore(
        i.worldBinormalTangentX.xyz,
        boxProxyUV,
        i.surfaceClipRange,
        traceKind,
        traceSteps,
        traceRayFraction,
        boxEnterFraction,
        boxExitFraction);
    int debugMode = (int)round(g_Unused);
    if (debugMode == 1) {
        return float4(DebugTraceKindColor(traceKind), 1.0);
    }
    if (debugMode == 2) {
        return float4(EncodeTraceHit(inkUV), 1.0);
    }
    if (debugMode == 3) {
        return float4(saturate(traceRayFraction), traceSteps / 16.0, saturate(boxEnterFraction), 1.0);
    }
    if (debugMode == 4) {
        return float4(TO_UNSIGNED(FetchHeight(i.inkUV_worldBumpUV.xy)), FetchDepth(i.inkUV_worldBumpUV.xy), 0.0, 1.0);
    }
    return float4(1.0, 0.0, 0.0, 1.0);
}
