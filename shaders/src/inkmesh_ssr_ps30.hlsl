sampler GBufInkColor    : register(s0);
sampler GBufReflection  : register(s1);
sampler GBufEnvmap      : register(s2);
sampler SSRResult       : register(s3);

const float2 g_FbSize  : register(c4);
const float4 HDRParams : register(c30);

static const float g_TonemapScale = HDRParams.x;
float4 main(float4 pos : VPOS) : COLOR0 {
    float4 uv = { pos.xy * g_FbSize, 0.0, 0.0 };
    float4 surface = tex2Dlod(GBufInkColor, uv);
    clip(surface.a - 0.5);

    surface.rgb *= g_TonemapScale;
    float3 reflection = tex2Dlod(GBufReflection, uv).rgb;
    if (dot(reflection, reflection) <= 0.0) {
        return float4(surface.rgb, 1.0);
    }

    // SSRResult stores (hitUV * confidence, 0, confidence). Hardware linear
    // filtering interpolates valid hits without pulling UV toward a miss at 0.
    float3 env = tex2Dlod(GBufEnvmap, uv).rgb;
    float4 ssr = tex2Dlod(SSRResult, uv);
    float3 reflectedColor = 0.0;
    if (ssr.a > 0.0) {
        float2 hitUV = saturate(ssr.xy / ssr.a);
        reflectedColor = tex2Dlod(GBufInkColor, float4(hitUV, 0.0, 0.0)).rgb;
    }
    reflection *= lerp(env, reflectedColor, ssr.a);
    reflection *= g_TonemapScale;
    return float4(surface.rgb + reflection, 1.0);
}
