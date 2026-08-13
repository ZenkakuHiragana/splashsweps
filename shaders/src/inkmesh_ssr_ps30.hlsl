#include "inkmesh_oct.hlsl"

struct PS_INPUT {
    float4 screenPos : VPOS;
};

sampler ForwardColor      : register(s0);
sampler ForwardNormals    : register(s1);
sampler ReflectionParams  : register(s2);
sampler EnvmapParams      : register(s3);
sampler SceneColorDepth   : register(s4);
sampler SSRFilter         : register(s5);

const float2 s0Size    : register(c4);
const float4 c11       : register(c11);
const float4 c12       : register(c12);
const float4 c13       : register(c13);
const float4 c14       : register(c14);
const float4 HDRParams : register(c30);

static const float DepthWriteConstant = 4000.0;
static const float2 g_FbSize = s0Size;
static const float3 g_ViewRight = c11.xyz;
static const float3 g_ViewUp = c12.xyz;
static const float3 g_ViewForward = c13.xyz;
static const float3 g_ViewOrigin = c14.xyz;
static const float g_TonemapScale = HDRParams.x;

float3 ReconstructWorldPosition(float2 uv, float viewDepth) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return g_ViewOrigin
        + (g_ViewForward + g_ViewRight * ndc.x + g_ViewUp * ndc.y) * viewDepth;
}

float4 main(const PS_INPUT i) : COLOR0 {
    float2 uv = i.screenPos.xy * g_FbSize;
    float4 surface = tex2Dlod(ForwardColor, float4(uv, 0.0, 0.0));
    if (surface.a < 0.5) {
        float3 sceneColor = tex2Dlod(SceneColorDepth, float4(uv, 0.0, 0.0)).rgb;
        return float4(sceneColor * g_TonemapScale, 1.0);
    }

    float4 reflectionParams = tex2Dlod(ReflectionParams, float4(uv, 0.0, 0.0));
    if (dot(reflectionParams.rgb, reflectionParams.rgb) <= 0.0) {
        return float4(surface.rgb * g_TonemapScale, 1.0);
    }

    float4 envmapParams = tex2Dlod(EnvmapParams, float4(uv, 0.0, 0.0));
    float4 ssr = tex2Dlod(SSRFilter, float4(uv, 0.0, 0.0));
    float3 reflection = (envmapParams.rgb * (1.0 - ssr.a) + ssr.rgb)
        * reflectionParams.rgb;
    return float4((surface.rgb + reflection) * g_TonemapScale, 1.0);
}
