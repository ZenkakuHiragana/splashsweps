// Ink Mesh Vertex Shader for SplashSWEPs
#include "inkmesh_common.hlsl"

struct VS_INPUT {
    float3 pos    : POSITION;
    float3 normal : NORMAL0;
    float4 color  : COLOR0;
    VertexInfo vi;
};

struct VS_OUTPUT {
    float4 clipPos : POSITION0;
    VertexInfo vi;
};

static const float DEPTH_BIAS = 2.0e-5; // Depth bias in normalized device coordinates
const float4x4 cModelViewProj : register(c4);
const float4   cEyePosWaterZ  : register(c2); // xyz: eye position
VS_OUTPUT main(const VS_INPUT v) {
    float4 clipPos = mul(float4(v.pos, 1.0), cModelViewProj);
    clipPos.z -= DEPTH_BIAS * clipPos.w;

    VS_OUTPUT w;
    w.clipPos               = clipPos;
    w.vi                    = v.vi;
    w.vi.clipPos            = clipPos;
    w.vi.worldPos.xyz       = v.pos;
    w.vi.worldPos.w         = v.color.a;
    w.vi.worldNormal_dU.xyz = v.normal;

    w.vi.surfaceClipRange   = v.vi.surfaceClipRange.yxwz;
    w.vi.inkTangent_U.xyz   = v.vi.inkBinormal_V.xyz; // Intentionally swapped
    w.vi.inkBinormal_V.xyz  = v.vi.inkTangent_U.xyz;  // Intentionally swapped
    w.vi.surfaceClipRange  *= 0.5;
    w.vi.inkTangent_U      *= 0.5;
    w.vi.inkBinormal_V     *= 0.5;
    return w;
}
