struct PS_INPUT {
    float4 screenPos : VPOS;
};

sampler SSRResult : register(s0);
const float2 s0Size : register(c4);

float4 main(const PS_INPUT i) : COLOR0 {
    float2 uv = i.screenPos.xy * s0Size;
    float2 d = s0Size * 0.5;
    return (
        tex2D(SSRResult, uv + float2(-d.x, -d.y))
        + tex2D(SSRResult, uv + float2( d.x, -d.y))
        + tex2D(SSRResult, uv + float2(-d.x,  d.y))
        + tex2D(SSRResult, uv + float2( d.x,  d.y))) * 0.25;
}
