sampler FrameBuffer : register(s0);
sampler DepthBuffer : register(s1);
const float2 s0Size : register(c4);
const float4 HDRParams : register(c30);
static const float g_TonemapScale = HDRParams.x;

struct PS_OUTPUT {
    float4 sceneColorDepth : COLOR0;
    float4 inkColor        : COLOR1;
};

PS_OUTPUT main(float2 uv : TEXCOORD0) {
    // DX9 pixel centers are at integer screen coordinates. The unit quad
    // starts at the viewport origin; sample the corresponding texel center.
    uv += s0Size * 0.5;
    float3 color = tex2D(FrameBuffer, uv).rgb / g_TonemapScale;
    PS_OUTPUT output = {
        float4(color, tex2D(DepthBuffer, uv).r),
        float4(color, 0.0), // Background, not a painted surface.
    };
    return output;
}
