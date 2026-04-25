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
    float3 coreEyeUV = i.worldBinormalTangentX.xyz;
    float boxEnterFraction;
    float boxExitFraction;
    float3 inkUV = TracePaintInterfaceCore(
        coreEyeUV,
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
    if (debugMode == 5) {
        return float4(saturate(boxEnterFraction), saturate(boxExitFraction), 0.0, 1.0);
    }
    if (debugMode == 6) {
        float3 eyeUV;
        float3 rayDir;
        float3 proxyUV = float3(i.inkUV_worldBumpUV.xy, i.inkBinormalMeshLift.w);
        float3 eyeWorld = c3.w > 0.5 ? c3.xyz : g_EyePos.xyz;
        float3x3 tangentSpaceInk = {
            i.inkTangentXYZWorldZ.xyz,
            i.inkBinormalMeshLift.xyz,
            i.worldNormalTangentY.xyz / HEIGHT_TO_HAMMER_UNITS,
        };
        BuildTraceRay(proxyUV, i.worldPos_projPosZ.xyz, tangentSpaceInk, eyeWorld, eyeUV, rayDir);
        if (c2.x > 0.5) {
            return float4(EncodeTraceHit(eyeUV), 1.0);
        }
        if (c2.y > 0.5) {
            return float4(TO_UNSIGNED(rayDir), 1.0);
        }
        if (c2.z > 0.5) {
            float field = EvaluateInterfaceField(coreEyeUV);
            if (c3.x > 0.5) {
                return float4(TO_UNSIGNED(field), TO_UNSIGNED(field), TO_UNSIGNED(field), 1.0);
            }
            return float4(TO_UNSIGNED(field), 0.0, 0.0, 1.0);
        }

        float steps = traceSteps / 16.0;
        return float4(steps, steps, steps, 1.0);
    }
    if (debugMode == 7) {
        float traceKind2;
        float traceSteps2;
        float traceRayFraction2;
        float boxEnterFraction2;
        float boxExitFraction2;
        float3 proxyUV = float3(i.inkUV_worldBumpUV.xy, i.inkBinormalMeshLift.w);
        float3 eyeWorld = c3.w > 0.5 ? c3.xyz : g_EyePos.xyz;
        float3x3 tangentSpaceInk = {
            i.inkTangentXYZWorldZ.xyz,
            i.inkBinormalMeshLift.xyz,
            i.worldNormalTangentY.xyz / HEIGHT_TO_HAMMER_UNITS,
        };
        float3 hitUV = TraceInterface(
            proxyUV,
            i.worldPos_projPosZ.xyz,
            tangentSpaceInk,
            i.surfaceClipRange,
            eyeWorld,
            traceKind2,
            traceSteps2,
            traceRayFraction2,
            boxEnterFraction2,
            boxExitFraction2);
        if (c2.x > 0.5) {
            return float4(DebugTraceKindColor(traceKind2), 1.0);
        }
        if (c2.y > 0.5) {
            return float4(EncodeTraceHit(hitUV), 1.0);
        }
        return float4(saturate(traceRayFraction2), traceSteps2 / 16.0, saturate(boxEnterFraction2), 1.0);
    }
    return float4(1.0, 0.0, 0.0, 1.0);
}
