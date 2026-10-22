sampler FrameBuffer : register(s0);
sampler DepthBuffer : register(s1);
const float2 s0Size : register(c4);
const float4 c0 : register(c0);
const float4 HDRParams : register(c30);
static const float g_TonemapScale = HDRParams.x;
static const float g_WriteDepth   = c0.x; // 1: view depth in alpha (scene_copy.vmt), 0: zero alpha (gbuf_inkcolor_init.vmt)

float4 main(float2 uv : TEXCOORD0) : COLOR0 {
    // DX9 pixel centers are at integer screen coordinates. The unit quad
    // starts at the viewport origin; sample the corresponding texel center.
    uv += s0Size * 0.5;
    float3 color = tex2D(FrameBuffer, uv).rgb / g_TonemapScale;
    return float4(color, tex2D(DepthBuffer, uv).r * g_WriteDepth);
}
