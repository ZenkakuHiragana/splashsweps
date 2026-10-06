// Copy detail images into their atlas, repeating the one-texel border.
sampler BaseTexture : register(s0);
const float2 c0 : register(c0);
static const bool TransposeUV     = c0.x > 0.5; // if the texture is rotated in the atlas
static const bool TransposeNormal = c0.y > 0.5; // if R and G represent normal vector
float4 main(float2 uv : TEXCOORD0) : COLOR0 {
    // frac wraps the border; LOD 0 copies the original texels.
    float4 detail = tex2Dlod(BaseTexture,
        float4(frac(TransposeUV ? uv.yx : uv.xy), 0, 0));
    if (TransposeUV && TransposeNormal) detail.rg = detail.gr;
    return detail;
}
