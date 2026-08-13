#include "inkmesh_ssr_common.hlsl"

float4 main(const PS_INPUT i) : COLOR0 {
    float2 uv = i.screenPos.xy * g_RenderSizeRcp;
    float4 surface = tex2Dlod(ForwardColor, float4(uv, 0.0, 0.0));
    if (surface.a < 0.5) return 0.0;

    float4 reflectionParams = tex2Dlod(ReflectionParams, float4(uv, 0.0, 0.0));
    if (dot(reflectionParams.rgb, reflectionParams.rgb) <= 0.0) return 0.0;

    float4 scene = tex2Dlod(SceneColorDepth, float4(uv, 0.0, 0.0));
    float4 normals = tex2Dlod(ForwardNormals, float4(uv, 0.0, 0.0));
    float4 envmapParams = tex2Dlod(EnvmapParams, float4(uv, 0.0, 0.0));
    float viewDepth = scene.a * DepthWriteConstant;
    float3 worldPos = ReconstructWorldPosition(uv, viewDepth);
    float3 viewDir = normalize(g_ViewOrigin - worldPos);
    float3 worldNormal = DecodeOctahedralUnitVector(normals.xy);
    float3 geometryNormal = DecodeOctahedralUnitVector(normals.zw);
    float4 ssr = SampleScreenSpaceReflection(
        uv, worldPos, viewDepth, viewDir, geometryNormal,
        worldNormal, envmapParams.a, reflectionParams.a);
    return float4(ssr.rgb * ssr.a, ssr.a);
}
