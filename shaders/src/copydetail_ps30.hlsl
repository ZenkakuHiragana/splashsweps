// Copy detail images into their atlas, repeating the one-texel border.
sampler BaseTexture : register(s0);
float4 main(float2 uv : TEXCOORD0) : COLOR0 {
    // frac wraps the border; LOD 0 resamples the source into the common grid size.
    return tex2Dlod(BaseTexture, float4(frac(uv), 0, 0));
}
