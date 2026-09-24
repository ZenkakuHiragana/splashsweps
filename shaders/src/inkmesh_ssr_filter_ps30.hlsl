sampler SSRResult : register(s0);
const float2 s0Size : register(c4);
float4 main(float4 pos : VPOS) : COLOR0 {
    float2 uv = pos.xy * s0Size;
    float2 d = s0Size * 0.5;
    return (tex2D(SSRResult, uv + float2(-d.x, -d.y))
          + tex2D(SSRResult, uv + float2( d.x, -d.y))
          + tex2D(SSRResult, uv + float2(-d.x,  d.y))
          + tex2D(SSRResult, uv + float2( d.x,  d.y))) * 0.25;
}
