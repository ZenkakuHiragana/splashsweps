sampler GBufInkColor     : register(s0);
sampler GBufInkColorBlur : register(s1);
sampler GBufReflection   : register(s2);
sampler GBufEnvmap       : register(s3);
sampler SSRResult        : register(s4);

const float4 c0        : register(c0);
const float2 g_FbSize  : register(c4);
const float4 HDRParams : register(c30);

static const float g_BlurTexelPx  = c0.x; // One over frame buffer pixels per texel of GBufInkColorBlur
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

    // SSRResult stores (hitUV * confidence, blur width in pixels at roughness = 100% * confidence, confidence).
    // Hardware linear filtering interpolates valid hits without pulling UV toward a miss at 0.
    float4 env = tex2Dlod(GBufEnvmap, uv); // rgb: envmap sample, a: roughness
    float4 ssr = tex2Dlod(SSRResult, uv);
    float3 reflectedColor = 0.0;
    if (ssr.a > 0.0) {
        // Roughness approaches the full blur, which is limited near the reflecting surface
        float  blur    = env.a * saturate(ssr.z / ssr.a * g_BlurTexelPx);
        float4 hitUV   = { saturate(ssr.xy / ssr.a), 0.0, 0.0 };
        reflectedColor = lerp(
            tex2Dlod(GBufInkColor,     hitUV).rgb,
            tex2Dlod(GBufInkColorBlur, hitUV).rgb, blur);
    }
    reflection *= lerp(env.rgb, reflectedColor, ssr.a);
    reflection *= g_TonemapScale;
    return float4(surface.rgb + reflection, 1.0);
}
