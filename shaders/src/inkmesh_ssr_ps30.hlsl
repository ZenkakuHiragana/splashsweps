struct PS_INPUT {
    float4 screenPos : VPOS;
};

sampler ForwardColor      : register(s0);
sampler ReflectionParams  : register(s1);
sampler EnvmapParams      : register(s2);
sampler SceneColorDepth   : register(s3);
sampler SSRFilter         : register(s4);

const float2 s0Size    : register(c4);
const float4 HDRParams : register(c30);

static const float2 g_FbSize       = s0Size;
static const float  g_TonemapScale = HDRParams.x;

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
