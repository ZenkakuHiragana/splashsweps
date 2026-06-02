
sampler FrameBuffer : register(s0);
sampler DepthBuffer : register(s1);
const float4 HDRParams : register(c30);
static const float g_TonemapScale = HDRParams.x;
float4 main(float2 uv : TEXCOORD0) : COLOR0 {
    return float4(
        tex2D(FrameBuffer, uv).rgb / g_TonemapScale,
        tex2D(DepthBuffer, uv).r);
}
